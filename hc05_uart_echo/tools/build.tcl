set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir HC05_UART_ECHO.gprj]
    set_option -top_module hc05_uart_echo_top -output_base_name HC05_UART_ECHO -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0 -use_ready_as_gpio 1 -use_done_as_gpio 1
    run all
    puts "Bitstream: [file join $project_dir impl pnr HC05_UART_ECHO.fs]"
} message]} {
    puts stderr "Gowin build failed: $message"
    exit 1
}
exit 0
