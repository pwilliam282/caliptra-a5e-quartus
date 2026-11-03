// tb_nios_top_fw.sv - simulates the REAL quartus_a5e_nios/rtl/nios_caliptra_top.sv (window decode,
// soc_fw_store, soc_fuse_ctrl, avmm_to_apb, caliptra_passive_top + 1.x ROM) with a behavioral
// stand-in for the Platform Designer system (nios_caliptra_sys) that executes the same
// sequence as sw/app/main.c over the Avalon window. TEST KEYS/ENTROPY ONLY.
`timescale 1ns/1ps
module nios_caliptra_sys (
  input  logic clk_clk, reset_reset_n,
  output logic [17:0] caliptra_apb_address, output logic caliptra_apb_read, caliptra_apb_write,
  output logic [31:0] caliptra_apb_writedata, output logic [3:0] caliptra_apb_byteenable,
  input  logic [31:0] caliptra_apb_readdata, input logic caliptra_apb_readdatavalid, caliptra_apb_waitrequest,
  output logic [0:0] caliptra_apb_burstcount, output logic caliptra_apb_debugaccess,
  output logic [31:0] ctrl_pio_export, input logic [31:0] status_pio_export, output logic [31:0] magic_pio_export);
  wire clk = clk_clk;
  initial begin caliptra_apb_read=0; caliptra_apb_write=0; caliptra_apb_byteenable=4'hf;
    ctrl_pio_export=0; magic_pio_export=0; end
  bit busy=0;
  // Avalon host: drive/sample at negedge (no race with posedge NBA updates); a request is
  // accepted on the first posedge where waitrequest is low, like the Nios mm interconnect.
  task automatic wr(input [17:0] a, input [31:0] d);
    while (busy) @(negedge clk); busy=1;
    @(negedge clk); caliptra_apb_address=a; caliptra_apb_writedata=d; caliptra_apb_write=1;
    #1; while (caliptra_apb_waitrequest) @(negedge clk) ;
    @(negedge clk); caliptra_apb_write=0; busy=0;
  endtask
  task automatic rd(input [17:0] a, output [31:0] d);
    while (busy) @(negedge clk); busy=1;
    @(negedge clk); caliptra_apb_address=a; caliptra_apb_read=1;
    #1; while (caliptra_apb_waitrequest) @(negedge clk) ;
    @(negedge clk); caliptra_apb_read=0;
    while (!caliptra_apb_readdatavalid) @(negedge clk);
    d = caliptra_apb_readdata; busy=0;
  endtask
  // TRNG service, called from the polling loops exactly like trng_service() in main.c
  int trng_reqs=0;
  task automatic trng_svc();
    if (status_pio_export[7]) begin
      for (int i=0;i<12;i++) wr(18'h30078+4*i, $urandom);
      wr(18'h300ac, 2); trng_reqs++; $display("[%0d] TRNG request %0d serviced", cyc, trng_reqs);
      while (status_pio_export[7]) @(posedge clk);
    end
  endtask
  task automatic wait_st(input int b); while (!status_pio_export[b]) begin trng_svc(); @(posedge clk); end endtask
  longint cyc=0; always @(posedge clk) cyc++;
  initial begin
    logic [31:0] d, n; int words; longint maxc = 16_000_000;
    void'($value$plusargs("max_cycles=%d", maxc));
    fork begin wait (cyc>=maxc); $display("TB_NIOS_TOP TIMEOUT magic=%h trng=%0d", magic_pio_export, trng_reqs); $finish; end join_none
    fork begin wait (status_pio_export[5]); rd(18'h30000, d); rd(18'h30008, n); $display("TB_NIOS_TOP FAIL fatal at %0d HW_ERR_FATAL=%h ... FW_ERR_FATAL=%h", cyc, d, n); $finish; end join_none
    wait (reset_reset_n); repeat (5) @(posedge clk);
    magic_pio_export = 1; ctrl_pio_export = 1; repeat (20) @(posedge clk); ctrl_pio_export = 3;
    wait_st(0); magic_pio_export = 2;
    rd(18'h300d4, d); $display("[%0d] HW_REV_ID=%h", cyc, d);
    wr(18'h30048, 1); wr(18'h3005c, 1); wr(18'h30110, 32'd100_000_000); wr(18'h30114, 0);  // WDT_CFG (debug-locked ROM arms WDT1) magic_pio_export = 3;
    rd(18'h1f000, d); $display("[%0d] FUSE_CTRL ID=%h", cyc, d); if (d!=32'h46555345) $display("ERROR id");
    wr(18'h1f004, 1);
    do rd(18'h1f008, d); while (d[0] || !(d[1]|d[2]));
    rd(18'h1f00c, n); $display("[%0d] FUSE_CTRL STATUS=%h COUNT=%0d", cyc, d, n);
    if (d[2]) begin $display("TB_NIOS_TOP FAIL fuse err"); $finish; end
    rd(18'h30200, d); $display("  readback FUSE_UDS_SEED_0 (expect 0 - write-only to SoC) = %h", d);
    rd(18'h300b0, d); $display("[%0d] FUSE_WR_DONE=%h", cyc, d); magic_pio_export = 4;
    wait_st(1); magic_pio_export = 5; $display("[%0d] ready_for_fw_push trng=%0d", cyc, trng_reqs);
    rd(18'h1f010, n);
    do begin trng_svc(); rd(18'h20000, d); end while (d[0]);
    rd(18'h20004, d); $display("  MBOX_USER=%h", d);
    wr(18'h20008, 32'h46574C44); wr(18'h2000c, n);
    words = (n+3)/4;
    for (int i=0;i<words;i++) begin rd(4*i, d); wr(18'h20010, d); if ((i&255)==0) trng_svc(); end
    wr(18'h20018, 1); magic_pio_export = 6; $display("[%0d] FIRMWARE_LOAD %0d bytes from soc_fw_store", cyc, n);
    do begin repeat (1000) @(posedge clk); trng_svc(); rd(18'h2001c, d); end while (d[3:0]==0);
    $display("[%0d] MBOX_STATUS=%0d", cyc, d[3:0]); wr(18'h20018, 0);
    if (d[3:0]!=2) begin $display("TB_NIOS_TOP FAIL mbox"); $finish; end
    magic_pio_export = 7;
    wait_st(2); $display("[%0d] ready_for_runtime", cyc);
    magic_pio_export = 32'hCA11F00D; $display("TB_NIOS_TOP PASS cyc=%0d trng=%0d", cyc, trng_reqs); $finish;
  end
endmodule

module tb_nios_top_fw;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  initial begin repeat (5) @(posedge clk); rst_n=1; end
  logic [7:0] led;
  nios_caliptra_top dut (.clk, .reset_n(rst_n), .led);
  always @(posedge dut.etrng_req) $display("[tb] etrng_req rise status=%h", dut.status_in);
  // Caliptra ROM/FW log on generic_output_wires[7:0] (bit8 toggles per char)
  logic [8:0] prev_o; bit prev_v=0;
  always @(posedge clk) if (dut.cptra_rst_b) begin
    if (!prev_v) begin prev_o <= dut.generic_output_wires[8:0]; prev_v <= 1; end
    else if (dut.generic_output_wires[8:0] != prev_o) begin prev_o <= dut.generic_output_wires[8:0];
      $write("%c", dut.generic_output_wires[7:0]); $fflush; end
  end
endmodule
