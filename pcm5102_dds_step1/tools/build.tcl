# Build the independent single-voice DDS project.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir DDS_STEP1.gprj]
    set_option -top_module top -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0 -output_base_name DDS_STEP1 -gen_verilog_sim_netlist 1 -show_init_in_vo 1
    run all
    puts "Bitstream: [file join $project_dir impl pnr DDS_STEP1.fs]"
} message]} {
    puts stderr "DDS step 1 build failed: $message"
    exit 1
}
exit 0
