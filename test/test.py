# SPDX-License-Identifier: Apache-2.0
#
# Simple cocotb tests for the hypnotic spiral VGA project.
# uo_out = {hsync, B0, G0, R0, vsync, B1, G1, R1}

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

LINE = 800  # pixel clocks per VGA line (640 visible + 160 blanking)


def start_clock(dut):
    clock = Clock(dut.clk, 40, units="ns")  # ~25 MHz pixel clock
    cocotb.start_soon(clock.start())


async def reset(dut, ui_in=0):
    dut.ena.value = 1
    dut.ui_in.value = ui_in
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1


async def capture(dut, n=LINE):
    """Sample uo_out on n clock edges. Returns (hsync, vsync, color) lists."""
    hs, vs, col = [], [], []
    for _ in range(n):
        await RisingEdge(dut.clk)
        val = dut.uo_out.value
        assert val.is_resolvable, f"uo_out contains X/Z bits: {val}"
        v = int(val)
        hs.append((v >> 7) & 1)
        vs.append((v >> 3) & 1)
        col.append(v & 0x77)  # the six colour bits (R,G,B x 2)
    return hs, vs, col


@cocotb.test()
async def test_sync_and_pixels(dut):
    dut._log.info("Two VGA lines with default switches")
    start_clock(dut)
    await reset(dut)

    hs, vs, col = await capture(dut, 2 * LINE)

    # HSync is active low and pulses once per 800 clocks
    falling = sum(1 for i in range(1, len(hs)) if hs[i - 1] == 1 and hs[i] == 0)
    assert 1 <= falling <= 2, f"unexpected number of HSync pulses: {falling}"

    # VSync stays idle (high) during the first lines of a frame
    assert all(vs), "VSync should be idle during the first lines"

    # Black & white only: R = G = B, so every sample is 0x00 or 0x77
    assert all(c in (0x00, 0x77) for c in col), "found a non black/white pixel"

    # Blanking (HSync low) must be black
    assert all(c == 0 for c, h in zip(col, hs) if h == 0), "colour during HSync"

    # The pattern must actually contain both black and white
    assert 0x00 in col and 0x77 in col, "no black/white variation on the line"


@cocotb.test()
async def test_invert_switch(dut):
    dut._log.info("ui_in[4] must invert every visible pixel")
    start_clock(dut)

    await reset(dut, ui_in=0x00)
    _, _, normal = await capture(dut)

    await reset(dut, ui_in=0x10)
    _, _, inverted = await capture(dut)

    diffs = [a ^ b for a, b in zip(normal, inverted)]
    assert all(d in (0x00, 0x77) for d in diffs), "inversion is not complementary"
    assert sum(1 for d in diffs if d == 0x77) >= 600, "too few pixels inverted"
