/*
 * Smooth black & white hypnotic spiral for Tiny Tapeout VGA (640x480 @ 60 Hz)
 *
 * Needs hvsync_generator.v (from the TT VGA template) next to this file.
 *
 * How it works (a "Fermat spiral": radius^2 grows linearly with the angle):
 *   1. Centre the pixel coordinates on the screen        -> |dx|, |dy|
 *   2. r2 = dx^2 + dy^2                                   -> perfectly round rings
 *   3. Smooth 8-bit angle (5-bit division per octant)     -> spiral arms, no facets
 *   4. phase = r2/16 + arms*angle -/+ time                -> flowing spiral
 *   5. phase MSB -> black / white
 *
 * The datapath is pipelined in 3 stages so it meets 25 MHz timing.
 * hsync / vsync / blanking are delayed by the same 3 clocks.
 *
 * Controls (ui_in):
 *   ui_in[0] : reverse flow direction
 *   ui_in[1] : tighter rings
 *   ui_in[2] : 3 spiral arms instead of 1
 *   ui_in[3] : pure concentric circles (no spiral)
 *   ui_in[4] : invert black/white
 *   ui_in[5] : soft grayscale shading instead of hard black/white
 */

`default_nettype none

module tt_um_vga_hypno_spiral (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // 25.175 MHz pixel clock
    input  wire       rst_n     // active-low reset
);

  // ---------------------------------------------------------------- VGA
  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;

  hvsync_generator hvsync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // ---------------------------------------------------- Frame / time counter
  reg [11:0] frame;
  reg        vsync_q;

  always @(posedge clk) begin
    if (~rst_n) begin
      frame   <= 12'd0;
      vsync_q <= 1'b0;
    end else begin
      vsync_q <= vsync;
      if (vsync && !vsync_q) frame <= frame + 12'd1;  // once per frame
    end
  end

  wire [7:0] t8 = {frame[5:0], 2'b00};  // 4 phase units per frame (~1 cycle/s)

  // ======================================================== Stage 0 (comb)
  // Centre the coordinates and take absolute values
  wire signed [10:0] dx = $signed({1'b0, pix_x}) - 11'sd320;
  wire signed [10:0] dy = $signed({1'b0, pix_y}) - 11'sd240;

  wire [8:0] ax0 = dx[10] ? (9'd0 - dx[8:0]) : dx[8:0];  // |dx|
  wire [8:0] ay0 = dy[10] ? (9'd0 - dy[8:0]) : dy[8:0];  // |dy|

  // Quadrants numbered in angular order:
  // Q1(dx>=0,dy>=0)=0  Q2(dx<0,dy>=0)=1  Q3(dx<0,dy<0)=2  Q4(dx>=0,dy<0)=3
  reg [1:0] quad0;
  always @* begin
    case ({dy[10], dx[10]})
      2'b00:   quad0 = 2'd0;
      2'b01:   quad0 = 2'd1;
      2'b11:   quad0 = 2'd2;
      default: quad0 = 2'd3;
    endcase
  end

  // ----------------------------------------------------- Pipeline reg A
  reg [8:0] ax_a, ay_a;
  reg [1:0] quad_a;
  reg       hs_a, vs_a, act_a;

  always @(posedge clk) begin
    ax_a   <= ax0;
    ay_a   <= ay0;
    quad_a <= quad0;
    hs_a   <= hsync;
    vs_a   <= vsync;
    act_a  <= video_active;
  end

  // ======================================================== Stage 1 (comb)
  // Radius squared -> perfectly round rings
  wire [17:0] ax2 = ax_a * ax_a;
  wire [17:0] ay2 = ay_a * ay_a;
  wire [18:0] r2  = {1'b0, ax2} + {1'b0, ay2};

  // Smooth angle: within each octant, angle ~ smaller/larger (5-bit fraction)
  wire       swap = (ay_a > ax_a);
  wire [8:0] num  = swap ? ax_a : ay_a;  // smaller
  wire [8:0] den  = swap ? ay_a : ax_a;  // larger

  // 5-bit restoring division: floor(32 * num / den), num <= den
  function [4:0] frac5(input [8:0] n, input [8:0] d);
    reg [9:0] rem;
    reg [4:0] qq;
    integer i;
    begin
      rem = {1'b0, n};
      for (i = 4; i >= 0; i = i - 1) begin
        rem = rem << 1;
        if (rem >= {1'b0, d}) begin
          qq[i] = 1'b1;
          rem   = rem - {1'b0, d};
        end else begin
          qq[i] = 1'b0;
        end
      end
      frac5 = qq;
    end
  endfunction

  wire [4:0] qf   = frac5(num, den);              // 0..31
  wire [5:0] th64 = swap ? (6'd63 - {1'b0, qf})   // angle inside the quadrant
                         : {1'b0, qf};            // 0..63
  // Mirror odd quadrants so the angle grows continuously around the circle
  wire [7:0] theta = {quad_a, quad_a[0] ? ~th64 : th64};  // 0..255 full turn

  // ----------------------------------------------------- Pipeline reg B
  reg [8:0] r2_b;
  reg [7:0] theta_b;
  reg       hs_b, vs_b, act_b;

  always @(posedge clk) begin
    r2_b    <= r2[12:4];
    theta_b <= theta;
    hs_b    <= hs_a;
    vs_b    <= vs_a;
    act_b   <= act_a;
  end

  // ======================================================== Stage 2 (comb)
  wire [7:0] ring = ui_in[1] ? r2_b[7:0] : r2_b[8:1];

  // Any integer number of arms wraps seamlessly (256 * k = 0 mod 256)
  wire [7:0] arm_term = ui_in[3] ? 8'd0 :
                        ui_in[2] ? (theta_b + {theta_b[6:0], 1'b0}) :  // 3 arms
                                   theta_b;                            // 1 arm

  wire [7:0] p_raw = ring + arm_term + (ui_in[0] ? t8 : (8'd0 - t8));
  wire [7:0] p     = ui_in[4] ? ~p_raw : p_raw;

  wire [1:0] shade = ui_in[5] ? (p[7] ? ~p[6:5] : p[6:5])  // soft gray
                              : {2{p[7]}};                 // hard black/white

  // ----------------------------------------------------- Pipeline reg C
  reg [1:0] gray_c;
  reg       hs_c, vs_c;

  always @(posedge clk) begin
    gray_c <= act_b ? shade : 2'b00;
    hs_c   <= hs_b;
    vs_c   <= vs_b;
  end

  // Tiny Tapeout VGA PMOD pinout: R = G = B  -> black & white
  assign uo_out  = {hs_c, gray_c[0], gray_c[0], gray_c[0],
                    vs_c, gray_c[1], gray_c[1], gray_c[1]};
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  wire _unused = &{ena, ui_in[7:6], uio_in, 1'b0};

endmodule
