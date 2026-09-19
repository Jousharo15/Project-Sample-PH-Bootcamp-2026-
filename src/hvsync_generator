/*
 * VGA 640x480 @ 60 Hz timing generator (25.175 MHz pixel clock)
 * Sync pulses are active low.
 */

`default_nettype none

module hvsync_generator (
    input  wire       clk,
    input  wire       reset,
    output reg        hsync,
    output reg        vsync,
    output wire       display_on,
    output reg  [9:0] hpos,
    output reg  [9:0] vpos
);

  // Horizontal timing (pixels)
  localparam H_DISPLAY = 640;
  localparam H_FRONT   = 16;
  localparam H_SYNC    = 96;
  localparam H_BACK    = 48;
  localparam H_TOTAL   = H_DISPLAY + H_FRONT + H_SYNC + H_BACK;  // 800

  // Vertical timing (lines)
  localparam V_DISPLAY = 480;
  localparam V_BOTTOM  = 10;
  localparam V_SYNC    = 2;
  localparam V_TOP     = 33;
  localparam V_TOTAL   = V_DISPLAY + V_BOTTOM + V_SYNC + V_TOP;  // 525

  wire hmaxxed = (hpos == H_TOTAL - 1);
  wire vmaxxed = (vpos == V_TOTAL - 1);

  always @(posedge clk) begin
    if (reset) begin
      hpos  <= 10'd0;
      vpos  <= 10'd0;
      hsync <= 1'b1;
      vsync <= 1'b1;
    end else begin
      // Position counters
      if (hmaxxed) begin
        hpos <= 10'd0;
        vpos <= vmaxxed ? 10'd0 : vpos + 10'd1;
      end else begin
        hpos <= hpos + 10'd1;
      end

      // Sync pulses (active low)
      hsync <= ~(hpos >= H_DISPLAY + H_FRONT - 1 &&
                 hpos <  H_DISPLAY + H_FRONT + H_SYNC - 1);
      vsync <= ~(vpos >= V_DISPLAY + V_BOTTOM &&
                 vpos <  V_DISPLAY + V_BOTTOM + V_SYNC);
    end
  end

  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

endmodule
