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

  logic ready_for_fuses, ready_for_fw_push, ready_for_runtime;
  // ---- SoC window decode (18-bit, Nios base 0x0004_0000) ----
  //   0x00000-0x1BFFF  soc_fw_store   FW bundle ROM (read-only, 112 KiB)
  //   0x1F000-0x1FFFF  soc_fuse_ctrl  fuse controller MMIO
  //   0x20000-0x3FFFF  Caliptra APB   (mbox_csr 0x20000, soc_ifc 0x30000) via avmm_to_apb
  // Caliptra 1.x decodes only 0x2xxxx/0x3xxxx, so the low half is free for SoC IP.
  logic sel_cptra, sel_fuse, sel_fw;
  assign sel_cptra = cl_address[17];
  assign sel_fuse  = !cl_address[17] && (cl_address[16:12] == 5'h1F);
  assign sel_fw    = !cl_address[17] && !sel_fuse;
  logic [31:0] br_readdata, fuse_rdata, fw_rdata;
  logic br_readdatavalid, br_waitrequest;
  logic loc_rv, loc_rv_fuse;
  always_ff @(posedge clk or negedge reset_n)
    if (!reset_n) begin loc_rv <= 1'b0; loc_rv_fuse <= 1'b0; end
    else begin loc_rv <= cl_read && !sel_cptra; loc_rv_fuse <= sel_fuse; end
  assign cl_waitrequest   = sel_cptra ? br_waitrequest : 1'b0;   // local slaves: zero wait
  assign cl_readdatavalid = br_readdatavalid | loc_rv;
  assign cl_readdata      = loc_rv ? (loc_rv_fuse ? fuse_rdata : fw_rdata) : br_readdata;

  soc_fw_store #(.DEPTH(28672), .FW_INIT_FILE("../fw/caliptra-fw-bundle.hex")) u_fw_store (
    .clk, .rd(cl_read && sel_fw), .waddr(cl_address[16:2] < 15'd28672 ? cl_address[16:2] : 15'd0),
    .rdata(fw_rdata));

  // ---- Avalon -> APB (Nios path) + fuse controller APB path, muxed ----
  logic [31:0] PADDR, PWDATA, PAUSER, PRDATA; logic [2:0] PPROT;
  logic PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
  logic [31:0] n_PADDR, n_PWDATA, f_PADDR, f_PWDATA;
  logic n_PSEL, n_PENABLE, n_PWRITE, f_PSEL, f_PENABLE, f_PWRITE, fuse_busy;
  avmm_to_apb #(.AW(18), .PAUSER_VAL(32'h1)) u_bridge (
    .clk, .rst_n(reset_n),
    .avs_address(cl_address), .avs_read(cl_read && sel_cptra), .avs_write(cl_write && sel_cptra),
    .avs_writedata(cl_writedata), .avs_byteenable(cl_byteenable),
    .avs_readdata(br_readdata), .avs_readdatavalid(br_readdatavalid),
    .avs_waitrequest(br_waitrequest), .avs_response(cl_response),
    .PADDR(n_PADDR), .PPROT, .PSEL(n_PSEL), .PENABLE(n_PENABLE), .PWRITE(n_PWRITE),
    .PWDATA(n_PWDATA), .PAUSER, .PREADY, .PSLVERR, .PRDATA);

  soc_fuse_ctrl #(.FUSE_IMAGE_FILE("../fw/fuse_image.hex"), .FW_BYTES(32'd109000)) u_fuse_ctrl (
    .clk, .rst_n(reset_n), .ready_for_fuses,
    .mmio_read(cl_read && sel_fuse), .mmio_write(cl_write && sel_fuse),
    .mmio_addr(cl_address[11:0]), .mmio_wdata(cl_writedata), .mmio_rdata(fuse_rdata),
    .busy(fuse_busy), .PADDR(f_PADDR), .PWDATA(f_PWDATA),
    .PSEL(f_PSEL), .PENABLE(f_PENABLE), .PWRITE(f_PWRITE), .PREADY, .PSLVERR);

  // Fuse controller owns APB while pushing fuses (Nios only polls fuse_ctrl STATUS meanwhile).
  assign PADDR   = fuse_busy ? f_PADDR   : n_PADDR;
  assign PWDATA  = fuse_busy ? f_PWDATA  : n_PWDATA;
  assign PSEL    = fuse_busy ? f_PSEL    : n_PSEL;
  assign PENABLE = fuse_busy ? f_PENABLE : n_PENABLE;
  assign PWRITE  = fuse_busy ? f_PWRITE  : n_PWRITE;

  // ---- Host controls (ctrl PIO, reset value 0 => Caliptra held in reset) ----
  // ctrl[0] cptra_pwrgood, ctrl[1] cptra_rst_b, ctrl[2] BootFSM_BrkPoint
  logic cptra_pwrgood, cptra_rst_b;
  assign cptra_pwrgood = ctrl_out[0] & reset_n;
  assign cptra_rst_b   = ctrl_out[1] & reset_n;

  logic mailbox_data_avail, mailbox_flow_done, cptra_error_fatal, cptra_error_non_fatal, etrng_req;
  logic [63:0] generic_output_wires;
  assign status_in = {generic_output_wires[23:0],
                      etrng_req, cptra_error_non_fatal, cptra_error_fatal, mailbox_flow_done,
                      mailbox_data_avail, ready_for_runtime, ready_for_fw_push, ready_for_fuses};

  // Arbitrary TEST obfuscation key (placeholder strap) - NEVER use in production
  localparam logic [255:0] TEST_OBF_KEY =
    256'h31358e8a_f34d6a45_1c1b3b72_e5f5ffd6_d1bf4e16_cf1f2ce9_3dc4fd37_b2c3b8d5;

  caliptra_passive_top #(.ROM_INIT_FILE("../fw/caliptra-rom.hex")) u_caliptra (
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
