#!/usr/bin/env python
# SPDX-License-Identifier: MIT
"""Cocotb tests for the KR260 SFP 10G AXI-Stream paths."""

import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSource, AxiStreamSink
from cocotbext.eth import XgmiiFrame

sys.path.insert(0, os.path.dirname(__file__))
from baser import BaseRSerdesSource, BaseRSerdesSink


class SfpCoreTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk, 8, unit="ns").start())
        cocotb.start_soon(Clock(dut.s_clk_fifo_tx, 8, unit="ns").start())
        cocotb.start_soon(Clock(dut.m_clk_fifo_rx, 8, unit="ns").start())

        cocotb.start_soon(Clock(dut.sfp_mgt_refclk_p, 6.4, unit="ns").start())

        # The SIM model exposes the 10GBASE-R serial-side data path here.
        ch = dut.core_inst.sfp_mac.sfp_mac_inst.ch[0].ch_inst
        gt = ch.gt.gt_inst
        cocotb.start_soon(Clock(gt.tx_clk, 3.102, unit="ns").start())
        cocotb.start_soon(Clock(gt.rx_clk, 3.102, unit="ns").start())

        self.serdes_rx = BaseRSerdesSource(
            data=gt.serdes_rx_data,
            data_valid=gt.serdes_rx_data_valid,
            hdr=gt.serdes_rx_hdr,
            hdr_valid=gt.serdes_rx_hdr_valid,
            clock=gt.rx_clk,
            slip=gt.serdes_rx_bitslip,
            reverse=True,
            gbx_cfg=(66, [64, 65]),
        )
        self.serdes_tx = BaseRSerdesSink(
            data=gt.serdes_tx_data,
            data_valid=gt.serdes_tx_data_valid,
            hdr=gt.serdes_tx_hdr,
            hdr_valid=gt.serdes_tx_hdr_valid,
            gbx_sync=gt.serdes_tx_gbx_sync,
            clock=gt.tx_clk,
            reverse=True,
            gbx_cfg=(66, [64, 65]),
        )

        self.tx_axis = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis_fifo_tx"),
            dut.s_clk_fifo_tx,
            dut.s_rst_fifo_tx,
        )
        self.rx_axis = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "m_axis_fifo_rx"),
            dut.m_clk_fifo_rx,
            dut.m_rst_fifo_rx,
        )

    async def reset_and_wait_link(self):
        dut = self.dut
        dut.rst.value = 1
        dut.s_rst_fifo_tx.value = 1
        dut.m_rst_fifo_rx.value = 1
        for _ in range(10):
            await RisingEdge(dut.clk)
        dut.rst.value = 0
        dut.s_rst_fifo_tx.value = 0
        dut.m_rst_fifo_rx.value = 0

        # Allow the simulated GT and 10GBASE-R block lock to settle.
        for _ in range(1200):
            await RisingEdge(dut.clk)


@cocotb.test()
async def test_tx_axis_to_sfp(dut):
    """Send one frame on the TX AXI-Stream input and observe SFP TX SerDes."""
    tb = SfpCoreTB(dut)
    await tb.reset_and_wait_link()

    payload = bytes((i * 7 + 3) & 0xFF for i in range(96))
    await tb.tx_axis.send(AxiStreamFrame(payload))

    frame = await with_timeout(tb.serdes_tx.recv(), 100, "us")
    assert frame.get_payload() == payload
    assert frame.check_fcs()


@cocotb.test()
async def test_rx_sfp_to_axis(dut):
    """Send one frame into SFP RX SerDes and observe the RX AXI-Stream output."""
    tb = SfpCoreTB(dut)
    await tb.reset_and_wait_link()

    payload = bytes((255 - i * 5) & 0xFF for i in range(96))
    await tb.serdes_rx.send(XgmiiFrame.from_payload(payload))

    frame = await with_timeout(tb.rx_axis.recv(), 100, "us")
    assert bytes(frame.tdata) == payload
