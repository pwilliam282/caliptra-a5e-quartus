	nios_caliptra_sys u0 (
		.caliptra_apb_waitrequest   (_connected_to_caliptra_apb_waitrequest_),   //   input,   width = 1, caliptra_apb.waitrequest
		.caliptra_apb_readdata      (_connected_to_caliptra_apb_readdata_),      //   input,  width = 32,             .readdata
		.caliptra_apb_readdatavalid (_connected_to_caliptra_apb_readdatavalid_), //   input,   width = 1,             .readdatavalid
		.caliptra_apb_burstcount    (_connected_to_caliptra_apb_burstcount_),    //  output,   width = 1,             .burstcount
		.caliptra_apb_writedata     (_connected_to_caliptra_apb_writedata_),     //  output,  width = 32,             .writedata
		.caliptra_apb_address       (_connected_to_caliptra_apb_address_),       //  output,  width = 18,             .address
		.caliptra_apb_write         (_connected_to_caliptra_apb_write_),         //  output,   width = 1,             .write
		.caliptra_apb_read          (_connected_to_caliptra_apb_read_),          //  output,   width = 1,             .read
		.caliptra_apb_byteenable    (_connected_to_caliptra_apb_byteenable_),    //  output,   width = 4,             .byteenable
		.caliptra_apb_debugaccess   (_connected_to_caliptra_apb_debugaccess_),   //  output,   width = 1,             .debugaccess
		.clk_clk                    (_connected_to_clk_clk_),                    //   input,   width = 1,          clk.clk
		.reset_reset_n              (_connected_to_reset_reset_n_),              //   input,   width = 1,        reset.reset_n
		.ctrl_pio_export            (_connected_to_ctrl_pio_export_),            //  output,  width = 32,     ctrl_pio.export
		.magic_pio_export           (_connected_to_magic_pio_export_),           //  output,  width = 32,    magic_pio.export
		.status_pio_export          (_connected_to_status_pio_export_)           //   input,  width = 32,   status_pio.export
	);

