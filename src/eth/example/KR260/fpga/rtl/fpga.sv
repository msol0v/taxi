// SPDX-License-Identifier: MIT
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA top-level module
 */
module fpga #
(
    // simulation (set to avoid vendor primitives)
    parameter logic SIM = 1'b0,
    // vendor ("GENERIC", "XILINX", "ALTERA")
    parameter string VENDOR = "XILINX",
    // device family
    parameter string FAMILY = "zynquplus",
    // MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1,
    parameter MAC_DATA_W = 32
)
(
    /*
     * Clock: 25MHz
     */
    input  wire logic        clk_25mhz,

    /*
     * GPIO
     */
    output wire logic [1:0]  led,
    output wire logic [1:0]  sfp_led,

    /*
     * Ethernet: SFP+
     */
    input  wire logic        sfp_rx_p,
    input  wire logic        sfp_rx_n,
    output wire logic        sfp_tx_p,
    output wire logic        sfp_tx_n,
    input  wire logic        sfp_mgt_refclk_p,
    input  wire logic        sfp_mgt_refclk_n,

    output wire logic        sfp_tx_disable,
    input  wire logic        sfp_tx_fault,
    input  wire logic        sfp_rx_los,
    input  wire logic        sfp_mod_abs,
    inout  wire logic        sfp_i2c_scl,
    inout  wire logic        sfp_i2c_sda
);

// Clock and reset

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk_125mhz_int;
wire rst_125mhz_int;

// Internal 62.5 MHz clock
wire clk_62mhz_mmcm_out;
wire clk_62mhz_int;

// Internal 312.5 MHz clock
wire clk_312mhz_mmcm_out;
wire clk_312mhz_int;
wire rst_312mhz_int;

wire mmcm_rst = 1'b0;
wire mmcm_locked;
wire mmcm_clkfb;

// MMCM instance
MMCME4_BASE #(
    // 25 MHz input
    .CLKIN1_PERIOD(40),
    .REF_JITTER1(0.010),
    // 25 MHz input / 1 = 25 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(1),
    // 25 MHz PFD * 50 = 1250 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(50),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(10),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 90 degrees
    .CLKOUT1_DIVIDE(10),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    // 1250 MHz / 20 = 62.5 MHz, 0 degrees
    .CLKOUT2_DIVIDE(20),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    // 1250 MHz / 4 = 312.5 MHz, 0 degrees
    .CLKOUT3_DIVIDE(4),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT3_PHASE(0),
    // Not used
    .CLKOUT4_DIVIDE(1),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0),
    .CLKOUT4_CASCADE("FALSE"),
    // Not used
    .CLKOUT5_DIVIDE(1),
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT5_PHASE(0),
    // Not used
    .CLKOUT6_DIVIDE(1),
    .CLKOUT6_DUTY_CYCLE(0.5),
    .CLKOUT6_PHASE(0),

    // optimized bandwidth
    .BANDWIDTH("OPTIMIZED"),
    // don't wait for lock during startup
    .STARTUP_WAIT("FALSE")
)
clk_mmcm_inst (
    // 25 MHz input
    .CLKIN1(clk_25mhz),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    // 62.5 MHz, 0 degrees
    .CLKOUT2(clk_62mhz_mmcm_out),
    .CLKOUT2B(),
    // 312.5 MHz, 0 degrees
    .CLKOUT3(clk_312mhz_mmcm_out),
    .CLKOUT3B(),
    // Not used
    .CLKOUT4(),
    // Not used
    .CLKOUT5(),
    // Not used
    .CLKOUT6(),
    // reset input
    .RST(mmcm_rst),
    // don't power down
    .PWRDWN(1'b0),
    // locked output
    .LOCKED(mmcm_locked)
);

BUFG
clk_125mhz_bufg_inst (
    .I(clk_125mhz_mmcm_out),
    .O(clk_125mhz_int)
);

BUFG
clk_62mhz_bufg_inst (
    .I(clk_62mhz_mmcm_out),
    .O(clk_62mhz_int)
);

BUFG
clk_312mhz_bufg_inst (
    .I(clk_312mhz_mmcm_out),
    .O(clk_312mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
    .out(rst_125mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_312mhz_inst (
    .clk(clk_312mhz_int),
    .rst(~mmcm_locked),
    .out(rst_312mhz_int)
);

// GPIO
wire sfp_tx_fault_int;
wire sfp_rx_los_int;
wire sfp_mod_abs_int;

wire sfp_i2c_scl_i;
wire sfp_i2c_scl_o;
wire sfp_i2c_scl_t;
wire sfp_i2c_sda_i;
wire sfp_i2c_sda_o;
wire sfp_i2c_sda_t;

reg sfp_i2c_scl_o_reg;
reg sfp_i2c_scl_t_reg;
reg sfp_i2c_sda_o_reg;
reg sfp_i2c_sda_t_reg;

always @(posedge clk_125mhz_int) begin
    sfp_i2c_scl_o_reg <= sfp_i2c_scl_o;
    sfp_i2c_scl_t_reg <= sfp_i2c_scl_t;
    sfp_i2c_sda_o_reg <= sfp_i2c_sda_o;
    sfp_i2c_sda_t_reg <= sfp_i2c_sda_t;
end

taxi_sync_signal #(
    .WIDTH(5),
    .N(2)
)
sync_signal_inst (
    .clk(clk_125mhz_int),
    .in({sfp_tx_fault, sfp_rx_los, sfp_mod_abs, sfp_i2c_scl, sfp_i2c_sda}),
    .out({sfp_tx_fault_int, sfp_rx_los_int, sfp_mod_abs_int, sfp_i2c_scl_i, sfp_i2c_sda_i})
);

assign sfp_i2c_scl = sfp_i2c_scl_t_reg ? 1'bz : sfp_i2c_scl_o_reg;
assign sfp_i2c_sda = sfp_i2c_sda_t_reg ? 1'bz : sfp_i2c_sda_o_reg;

fpga_core #(
    .SIM(SIM),
    .VENDOR(VENDOR),
    .FAMILY(FAMILY),
    .CFG_LOW_LATENCY(CFG_LOW_LATENCY),
    .COMBINED_MAC_PCS(COMBINED_MAC_PCS),
    .MAC_DATA_W(MAC_DATA_W)
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk(clk_125mhz_int),
    .rst(rst_125mhz_int),

    /*
     * GPIO
     */
    .led(led),
    .sfp_led(sfp_led),

    /*
     * Ethernet: SFP+
     */
    .sfp_rx_p(sfp_rx_p),
    .sfp_rx_n(sfp_rx_n),
    .sfp_tx_p(sfp_tx_p),
    .sfp_tx_n(sfp_tx_n),
    .sfp_mgt_refclk_p(sfp_mgt_refclk_p),
    .sfp_mgt_refclk_n(sfp_mgt_refclk_n),

    .sfp_tx_disable(sfp_tx_disable),
    .sfp_tx_fault(sfp_tx_fault_int),
    .sfp_rx_los(sfp_rx_los_int),
    .sfp_mod_abs(sfp_mod_abs_int),

    .sfp_i2c_scl_i(sfp_i2c_scl_i),
    .sfp_i2c_scl_o(sfp_i2c_scl_o),
    .sfp_i2c_scl_t(sfp_i2c_scl_t),
    .sfp_i2c_sda_i(sfp_i2c_sda_i),
    .sfp_i2c_sda_o(sfp_i2c_sda_o),
    .sfp_i2c_sda_t(sfp_i2c_sda_t)
);

endmodule

`resetall
