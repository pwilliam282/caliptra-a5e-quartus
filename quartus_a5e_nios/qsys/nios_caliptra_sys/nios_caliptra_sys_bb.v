module nios_caliptra_sys (
		input  wire        caliptra_apb_waitrequest,   // caliptra_apb.waitrequest
		input  wire [31:0] caliptra_apb_readdata,      //             .readdata
		input  wire        caliptra_apb_readdatavalid, //             .readdatavalid
		output wire [0:0]  caliptra_apb_burstcount,    //             .burstcount
		output wire [31:0] caliptra_apb_writedata,     //             .writedata
		output wire [17:0] caliptra_apb_address,       //             .address
		output wire        caliptra_apb_write,         //             .write
		output wire        caliptra_apb_read,          //             .read
		output wire [3:0]  caliptra_apb_byteenable,    //             .byteenable
		output wire        caliptra_apb_debugaccess,   //             .debugaccess
		input  wire        clk_clk,                    //          clk.clk
		input  wire        reset_reset_n,              //        reset.reset_n
		output wire [31:0] ctrl_pio_export,            //     ctrl_pio.export
		output wire [31:0] magic_pio_export,           //    magic_pio.export
		input  wire [31:0] status_pio_export           //   status_pio.export
	);
endmodule

