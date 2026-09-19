<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The design draws an animated black & white hypnotic spiral on a 640x480 @ 60 Hz VGA display
(25.175 MHz pixel clock). It is a "Fermat spiral": the radius squared grows linearly with the angle.

For every pixel:

1. The pixel position is centred on the screen, giving |dx| and |dy|.
2. `r2 = dx^2 + dy^2` is computed with two small multipliers. Rings of constant `r2` are perfectly round circles.
3. A smooth 8-bit angle (0..255 for a full turn) is computed with a tiny 5-bit division per octant:
   `smaller / larger` is a good approximation of the angle, and the octant and quadrant bits are mirrored so the
   angle grows continuously around the circle.
4. `phase = r2/32 + arms * angle -/+ time`. The number of arms is any integer, because 256 * k wraps to 0.
5. The top bit of `phase` selects black or white. R, G and B are all driven with the same value.

A frame counter, incremented on every VSync, moves the phase by 4 units per frame so the rings flow outward
(or inward) and the arms appear to spin.

The datapath is pipelined in 3 stages; HSync, VSync and blanking are delayed by the same 3 clocks.

Inputs:

| Pin | Function |
|-----|----------|
| ui[0] | Reverse the flow direction |
| ui[1] | Tighter rings |
| ui[3:2] | Twist: 00 = 4 spiral arms (default), 01 = 1 arm, 10 = 8 arms, 11 = pure circles |
| ui[4] | Invert black / white |
| ui[5] | Soft grayscale shading instead of hard black / white |

## How to test

Connect a VGA monitor through a Tiny VGA PMOD (see below), run the design at 25.175 MHz and pulse reset.
With all inputs low you should see round rings flowing outward and twisting into a 4-arm spiral. Toggle the
input switches to change the look.

A cocotb testbench is included (`test/test.py`). It checks that HSync/VSync behave, that the output is pure
black and white, that blanking is black, and that `ui[4]` inverts the picture. Run it with `make` in the `test` folder.

## External hardware

- Tiny VGA PMOD (or any 2-bit-per-channel resistor DAC) on the dedicated outputs `uo[7:0]`.
- A VGA monitor.
