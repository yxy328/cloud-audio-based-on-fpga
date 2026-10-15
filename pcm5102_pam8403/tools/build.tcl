# Invoke with gw_sh tools/build.tcl; builds the standalone audio project.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir PCM5102_PAM8403.gprj]
    set_option -top_module top -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0 -output_base_name PCM5102_PAM8403 -gen_verilog_sim_netlist 1 -show_init_in_vo 1
    run all
    puts "Bitstream: [file join $project_dir impl pnr PCM5102_PAM8403.fs]"
} message]} {
    puts stderr "Gowin build failed: $message"
    exit 1
}
exit 0
