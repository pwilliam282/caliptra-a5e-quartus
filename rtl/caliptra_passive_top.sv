// caliptra_passive_top.sv
// Caliptra 1.x (caliptra-rtl v1.1, 5f85fb4) passive-mode wrapper for Intel Cyclone 10 GX study.
// 1.x is inherently "passive": SoC boots itself, talks to Caliptra over APB mailbox. No AXI DMA,
// no subsystem straps, no Adams Bridge (PQC) in this version.
// Memories (mailbox 128 KiB+ECC, ROM 48 KiB, VeeR ICCM/DCCM 128 KiB each + ICache) are instantiated
// here as inferred RAMs -> intended to map to M20K. TEST KEY ONLY on cptra_obf_key.
`include "config_defines.svh"
`include "caliptra_macros.svh"

module caliptra_passive_top
  import soc_ifc_pkg::*;
  import caliptra_top_tb_pkg::*;
#(parameter ROM_INIT_FILE = "")(
  input  logic         clk, cptra_pwrgood, cptra_rst_b,
  input  logic [255:0] cptra_obf_key,
  input  logic [1:0]   security_state_device_lifecycle,
  input  logic         security_state_debug_locked,
  input  logic jtag_tck, jtag_tms, jtag_tdi, jtag_trst_n,
  output logic jtag_tdo, jtag_tdoEn,
  // SoC APB subordinate (mailbox / soc_ifc) -> Nios V via APB bridge in Platform Designer
  input  logic [`CALIPTRA_APB_ADDR_WIDTH-1:0] PADDR,
  input  logic [2:0]  PPROT,
  input  logic        PSEL, PENABLE, PWRITE,
  input  logic [`CALIPTRA_APB_DATA_WIDTH-1:0] PWDATA,
  input  logic [`CALIPTRA_APB_USER_WIDTH-1:0] PAUSER,
  output logic        PREADY, PSLVERR,
  output logic [`CALIPTRA_APB_DATA_WIDTH-1:0] PRDATA,
  output logic ready_for_fuses, ready_for_fw_push, ready_for_runtime,
  output logic mailbox_data_avail, mailbox_flow_done,
  output logic cptra_error_fatal, cptra_error_non_fatal,
  input  logic BootFSM_BrkPoint,
  input  logic [63:0] generic_input_wires,
  output logic [63:0] generic_output_wires,
  output logic       etrng_req,
  input  logic [3:0] itrng_data,
  input  logic       itrng_valid,
  input  logic scan_mode
);
  el2_mem_if el2_mem_export ();
  logic mbox_sram_cs, mbox_sram_we;
  logic [MBOX_ADDR_W-1:0]         mbox_sram_addr;
  logic [MBOX_DATA_AND_ECC_W-1:0] mbox_sram_wdata, mbox_sram_rdata;
  logic imem_cs;
  logic [`CALIPTRA_IMEM_ADDR_WIDTH-1:0] imem_addr;
  logic [`CALIPTRA_IMEM_DATA_WIDTH-1:0] imem_rdata;

  security_state_t security_state;
  assign security_state.device_lifecycle = device_lifecycle_e'(security_state_device_lifecycle);
  assign security_state.debug_locked     = security_state_debug_locked;

  caliptra_top u_caliptra (
    .clk, .cptra_pwrgood, .cptra_rst_b, .cptra_obf_key,
    .jtag_tck, .jtag_tms, .jtag_tdi, .jtag_trst_n, .jtag_tdo, .jtag_tdoEn,
    .PADDR, .PPROT, .PSEL, .PENABLE, .PWRITE, .PWDATA, .PAUSER, .PREADY, .PSLVERR, .PRDATA,
    // QSPI (UART only if CALIPTRA_INTERNAL_UART) debug-only peripherals in 1.x: tie off
    .qspi_clk_o(), .qspi_cs_no(), .qspi_d_i('0), .qspi_d_o(), .qspi_d_en_o(),
    .el2_mem_export(el2_mem_export.veer_sram_src),
    .mbox_sram_cs, .mbox_sram_we, .mbox_sram_addr, .mbox_sram_wdata, .mbox_sram_rdata,
    .imem_cs, .imem_addr, .imem_rdata,
    .ready_for_fuses, .ready_for_fw_push, .ready_for_runtime,
    .mailbox_data_avail, .mailbox_flow_done, .BootFSM_BrkPoint,
    .cptra_error_fatal, .cptra_error_non_fatal,
    .etrng_req, .itrng_data, .itrng_valid,
    .generic_input_wires, .generic_output_wires,
    .security_state, .scan_mode);

  // Mailbox SRAM 128 KiB data + 7b ECC (32768 x 39)
  caliptra_sram #(.DATA_WIDTH(MBOX_DATA_AND_ECC_W), .DEPTH(MBOX_DEPTH)) u_mbox_ram (
    .clk_i(clk), .cs_i(mbox_sram_cs), .we_i(mbox_sram_we), .addr_i(mbox_sram_addr),
    .wdata_i(mbox_sram_wdata), .rdata_o(mbox_sram_rdata));

  // ROM 48 KiB (6144 x 64)
  caliptra_rom_m20k #(.DEPTH(`CALIPTRA_IMEM_DEPTH), .DW(`CALIPTRA_IMEM_DATA_WIDTH),
                      .AW(`CALIPTRA_IMEM_ADDR_WIDTH), .INIT_FILE(ROM_INIT_FILE)) u_rom (
    .clk(clk), .cs(imem_cs), .addr(imem_addr), .rdata(imem_rdata));

  // VeeR ICCM/DCCM/ICache (reuses upstream TB export module; error injection tied off)
  veer_sram_error_injection_mode_t no_inj;
  assign no_inj = '0;
  caliptra_veer_sram_export u_veer_sram (.sram_error_injection_mode(no_inj),
                                         .el2_mem_export(el2_mem_export.veer_sram_sink));
endmodule

module caliptra_rom_m20k #(parameter int DEPTH=6144, DW=64, AW=13, parameter INIT_FILE="") (
  input logic clk, input logic cs, input logic [AW-1:0] addr, output logic [DW-1:0] rdata);
  logic [DW-1:0] mem [DEPTH];
  initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  always_ff @(posedge clk) if (cs) rdata <= mem[addr];
endmodule
