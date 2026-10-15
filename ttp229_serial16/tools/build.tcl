# Builds a fixed 16-key test. Does not program the board.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir TTP229_SERIAL16.gprj]
    set_option -top_module ttp229_serial16_top -output_base_name TTP229_SERIAL16 -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0 -use_ready_as_gpio 1 -use_done_as_gpio 1 -gen_verilog_sim_netlist 1 -show_init_in_vo 1
    run all
    puts "Bitstream: [file join $project_dir impl pnr TTP229_SERIAL16.fs]"
} message]} {
    puts stderr "Gowin build failed: $message"
    exit 1
}
exit 0
