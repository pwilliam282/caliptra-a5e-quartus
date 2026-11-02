create_clock -name clk -period 20.000 [get_ports clk]
create_clock -name altera_reserved_tck -period 40.000 [get_ports -nowarn altera_reserved_tck]
set_clock_groups -asynchronous -group {clk} -group {altera_reserved_tck}
set_false_path -from [get_ports reset_n]
