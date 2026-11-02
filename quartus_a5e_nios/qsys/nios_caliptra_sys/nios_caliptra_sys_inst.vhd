	component nios_caliptra_sys is
		port (
			caliptra_apb_waitrequest   : in  std_logic                     := 'X';             -- waitrequest
			caliptra_apb_readdata      : in  std_logic_vector(31 downto 0) := (others => 'X'); -- readdata
			caliptra_apb_readdatavalid : in  std_logic                     := 'X';             -- readdatavalid
			caliptra_apb_burstcount    : out std_logic_vector(0 downto 0);                     -- burstcount
			caliptra_apb_writedata     : out std_logic_vector(31 downto 0);                    -- writedata
			caliptra_apb_address       : out std_logic_vector(17 downto 0);                    -- address
			caliptra_apb_write         : out std_logic;                                        -- write
			caliptra_apb_read          : out std_logic;                                        -- read
			caliptra_apb_byteenable    : out std_logic_vector(3 downto 0);                     -- byteenable
			caliptra_apb_debugaccess   : out std_logic;                                        -- debugaccess
			clk_clk                    : in  std_logic                     := 'X';             -- clk
			reset_reset_n              : in  std_logic                     := 'X';             -- reset_n
			ctrl_pio_export            : out std_logic_vector(31 downto 0);                    -- export
			magic_pio_export           : out std_logic_vector(31 downto 0);                    -- export
			status_pio_export          : in  std_logic_vector(31 downto 0) := (others => 'X')  -- export
		);
	end component nios_caliptra_sys;

	u0 : component nios_caliptra_sys
		port map (
			caliptra_apb_waitrequest   => CONNECTED_TO_caliptra_apb_waitrequest,   -- caliptra_apb.waitrequest
			caliptra_apb_readdata      => CONNECTED_TO_caliptra_apb_readdata,      --             .readdata
			caliptra_apb_readdatavalid => CONNECTED_TO_caliptra_apb_readdatavalid, --             .readdatavalid
			caliptra_apb_burstcount    => CONNECTED_TO_caliptra_apb_burstcount,    --             .burstcount
			caliptra_apb_writedata     => CONNECTED_TO_caliptra_apb_writedata,     --             .writedata
			caliptra_apb_address       => CONNECTED_TO_caliptra_apb_address,       --             .address
			caliptra_apb_write         => CONNECTED_TO_caliptra_apb_write,         --             .write
			caliptra_apb_read          => CONNECTED_TO_caliptra_apb_read,          --             .read
			caliptra_apb_byteenable    => CONNECTED_TO_caliptra_apb_byteenable,    --             .byteenable
			caliptra_apb_debugaccess   => CONNECTED_TO_caliptra_apb_debugaccess,   --             .debugaccess
			clk_clk                    => CONNECTED_TO_clk_clk,                    --          clk.clk
			reset_reset_n              => CONNECTED_TO_reset_reset_n,              --        reset.reset_n
			ctrl_pio_export            => CONNECTED_TO_ctrl_pio_export,            --     ctrl_pio.export
			magic_pio_export           => CONNECTED_TO_magic_pio_export,           --    magic_pio.export
			status_pio_export          => CONNECTED_TO_status_pio_export           --   status_pio.export
		);

