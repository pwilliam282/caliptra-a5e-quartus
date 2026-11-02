# Regenerate (inside Quartus Pro 25.3 Docker; delete ip/ and the .qsys first or PD appends _0/_1 suffixes): cd qsys && qsys-script --script=nios_caliptra_sys.tcl --quartus-project=none
#             then qsys-generate nios_caliptra_sys.qsys --synthesis=VERILOG --output-directory=nios_caliptra_sys --family="Agilex 5" --part=A5EC065BB32AE6S
package require -exact qsys 25.3
create_system nios_caliptra_sys
set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5EC065BB32AE6S

add_instance clk clock_source
set_instance_parameter_value clk clockFrequency 50000000.0
set_instance_parameter_value clk resetSynchronousEdges DEASSERT

add_instance cpu intel_niosv_m
set_instance_parameter_value cpu resetSlave "ram.s1"
set_instance_parameter_value cpu resetOffset 0
set_instance_parameter_value cpu enableDebug 1

add_instance ram intel_onchip_memory
set_instance_parameter_value ram memorySize 65536.0
set_instance_parameter_value ram dataWidth 32
set_instance_parameter_value ram initMemContent 1
set_instance_parameter_value ram useNonDefaultInitFile 1
set_instance_parameter_value ram initializationFileName "onchip_mem.hex"

add_instance jtag_uart altera_avalon_jtag_uart

add_instance ctrl_pio altera_avalon_pio
set_instance_parameter_value ctrl_pio direction Output
set_instance_parameter_value ctrl_pio width 32
set_instance_parameter_value ctrl_pio resetValue 0.0

add_instance status_pio altera_avalon_pio
set_instance_parameter_value status_pio direction Input
set_instance_parameter_value status_pio width 32

add_instance magic_pio altera_avalon_pio
set_instance_parameter_value magic_pio direction Output
set_instance_parameter_value magic_pio width 32
set_instance_parameter_value magic_pio resetValue 0.0

# 256 KiB window -> exported Avalon master -> rtl/avmm_to_apb.sv -> Caliptra APB
add_instance caliptra_win altera_avalon_mm_bridge
set_instance_parameter_value caliptra_win DATA_WIDTH 32
set_instance_parameter_value caliptra_win ADDRESS_WIDTH 18
set_instance_parameter_value caliptra_win ADDRESS_UNITS SYMBOLS
set_instance_parameter_value caliptra_win MAX_BURST_SIZE 1
set_instance_parameter_value caliptra_win MAX_PENDING_RESPONSES 1
set_instance_parameter_value caliptra_win PIPELINE_COMMAND 1
set_instance_parameter_value caliptra_win PIPELINE_RESPONSE 1

# clocks / resets
foreach i {cpu ram jtag_uart ctrl_pio status_pio magic_pio caliptra_win} {
  foreach c [get_instance_interfaces $i] {
    set cls [get_instance_interface_property $i $c CLASS_NAME]
    if {[string equal $cls clock_sink]} { add_connection clk.clk $i.$c }
    if {[string equal $cls reset_sink]} { add_connection clk.clk_reset $i.$c }
  }
}

# data manager map
proc dm {slave base} {
  add_connection cpu.data_manager $slave
  set_connection_parameter_value cpu.data_manager/$slave baseAddress $base
}
dm ram.s1                          0x00000000
dm caliptra_win.s0                 0x00040000
dm jtag_uart.avalon_jtag_slave     0x00080000
dm ctrl_pio.s1                     0x00080010
dm status_pio.s1                   0x00080020
dm magic_pio.s1                    0x00080030
dm cpu.timer_sw_agent              0x00080040
dm cpu.dm_agent                    0x00090000
add_connection cpu.instruction_manager ram.s1
set_connection_parameter_value cpu.instruction_manager/ram.s1 baseAddress 0x00000000
add_connection cpu.instruction_manager cpu.dm_agent
set_connection_parameter_value cpu.instruction_manager/cpu.dm_agent baseAddress 0x00090000

add_connection cpu.platform_irq_rx jtag_uart.irq
set_connection_parameter_value cpu.platform_irq_rx/jtag_uart.irq irqNumber 0

# exports
set_interface_property clk EXPORT_OF clk.clk_in
set_interface_property reset EXPORT_OF clk.clk_in_reset
set_interface_property caliptra_apb EXPORT_OF caliptra_win.m0
set_interface_property ctrl_pio EXPORT_OF ctrl_pio.external_connection
set_interface_property status_pio EXPORT_OF status_pio.external_connection
set_interface_property magic_pio EXPORT_OF magic_pio.external_connection

save_system nios_caliptra_sys.qsys
