# Builds a distinct event-record/replay image; never programs hardware.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir PCM5102_EVENT_TAKE.gprj]
    set_option -top_module top_take -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_mspi_as_gpio 1 -use_jtag_as_gpio 0 -output_base_name PCM5102_EVENT_TAKE -gen_verilog_sim_netlist 1 -show_init_in_vo 1
    set_option -resource_sharing 1 -retiming 1 -disable_io_insertion 0 -global_freq 50
    run all
    puts "Event bitstream: [file join $project_dir impl pnr PCM5102_EVENT_TAKE.fs]"
} message]} {
    puts stderr "Event recording build failed: $message"
    exit 1
}
exit 0
