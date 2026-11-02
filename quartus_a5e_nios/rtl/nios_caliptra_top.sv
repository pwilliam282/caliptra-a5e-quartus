// nios_caliptra_top.sv - Nios V/m host + Caliptra 1.x (passive) on Agilex 5 E (A5EC065BB32AE6S).
// Nios data master -> PD mm_bridge (exported) -> avmm_to_apb -> Caliptra APB (constant PAUSER=1).
// TEST KEY ONLY on cptra_obf_key. Pinout TBD (all non-clock I/O virtual for the compile study).
module nios_caliptra_top (
  input  logic       clk,        // single clock for Nios + Caliptra (e.g. 50-100 MHz board osc)
  input  logic       reset_n,    // board reset / push-button, active low
  output logic [7:0] led         // host_magic[7:0] (Nios writes 0xCA when HW_REV_ID read OK)
);
  // ---- Platform Designer system ----
  logic [17:0] cl_address; logic cl_read, cl_write, cl_waitrequest, cl_readdatavalid;
  logic [31:0] cl_writedata, cl_readdata; logic [3:0] cl_byteenable; logic [1:0] cl_response;
  logic [31:0] ctrl_out, status_in, magic_out;

  nios_caliptra_sys u_sys (
    .clk_clk                      (clk),
    .reset_reset_n                (reset_n),
    .caliptra_apb_address         (cl_address),
    .caliptra_apb_read            (cl_read),
    .caliptra_apb_write           (cl_write),
    .caliptra_apb_writedata       (cl_writedata),
    .caliptra_apb_byteenable      (cl_byteenable),
    .caliptra_apb_readdata        (cl_readdata),
    .caliptra_apb_readdatavalid   (cl_readdatavalid),
    .caliptra_apb_waitrequest     (cl_waitrequest),
    .caliptra_apb_burstcount      (),
    .caliptra_apb_debugaccess     (),
    .ctrl_pio_export              (ctrl_out),
    .status_pio_export            (status_in),
    .magic_pio_export             (magic_out)
  );

  // ---- Avalon -> APB ----
  logic [31:0] PADDR, PWDATA, PAUSER, PRDATA; logic [2:0] PPROT;
  logic PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
  avmm_to_apb #(.AW(18), .PAUSER_VAL(32'h1)) u_bridge (
    .clk, .rst_n(reset_n),
    .avs_address(cl_address), .avs_read(cl_read), .avs_write(cl_write),
    .avs_writedata(cl_writedata), .avs_byteenable(cl_byteenable),
    .avs_readdata(cl_readdata), .avs_readdatavalid(cl_readdatavalid),
    .avs_waitrequest(cl_waitrequest), .avs_response(cl_response),
    .PADDR, .PPROT, .PSEL, .PENABLE, .PWRITE, .PWDATA, .PAUSER, .PREADY, .PSLVERR, .PRDATA);

  // ---- Host controls (ctrl PIO, reset value 0 => Caliptra held in reset) ----
  // ctrl[0] cptra_pwrgood, ctrl[1] cptra_rst_b, ctrl[2] BootFSM_BrkPoint
  logic cptra_pwrgood, cptra_rst_b;
  assign cptra_pwrgood = ctrl_out[0] & reset_n;
  assign cptra_rst_b   = ctrl_out[1] & reset_n;

  logic ready_for_fuses, ready_for_fw_push, ready_for_runtime;
  logic mailbox_data_avail, mailbox_flow_done, cptra_error_fatal, cptra_error_non_fatal, etrng_req;
  logic [63:0] generic_output_wires;
  assign status_in = {generic_output_wires[23:0],
                      etrng_req, cptra_error_non_fatal, cptra_error_fatal, mailbox_flow_done,
                      mailbox_data_avail, ready_for_runtime, ready_for_fw_push, ready_for_fuses};

  // Arbitrary TEST obfuscation key (placeholder strap) - NEVER use in production
  localparam logic [255:0] TEST_OBF_KEY =
    256'h31358e8a_f34d6a45_1c1b3b72_e5f5ffd6_d1bf4e16_cf1f2ce9_3dc4fd37_b2c3b8d5;

  caliptra_passive_top u_caliptra (
    .clk, .cptra_pwrgood, .cptra_rst_b,
    .cptra_obf_key(TEST_OBF_KEY),
    .security_state_device_lifecycle(2'b00),   // DEVICE_UNPROVISIONED
    .security_state_debug_locked(1'b0),
    .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0), .jtag_trst_n(1'b0),
    .jtag_tdo(), .jtag_tdoEn(),
    .PADDR, .PPROT, .PSEL, .PENABLE, .PWRITE, .PWDATA, .PAUSER, .PREADY, .PSLVERR, .PRDATA,
    .ready_for_fuses, .ready_for_fw_push, .ready_for_runtime,
    .mailbox_data_avail, .mailbox_flow_done,
    .cptra_error_fatal, .cptra_error_non_fatal,
    .BootFSM_BrkPoint(ctrl_out[2]),
    .generic_input_wires({32'h0, magic_out}),
    .generic_output_wires,
    .etrng_req, .itrng_data(4'h0), .itrng_valid(1'b0),
    .scan_mode(1'b0));

  assign led = magic_out[7:0];
endmodule
