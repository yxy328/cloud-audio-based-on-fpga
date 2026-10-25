set project_dir [file normalize [file join [file dirname [info script]] ..]]
set previous_dir [pwd]
cd $project_dir
if {[catch {
    set frozen_config [file join $project_dir .. build_inputs PCM5102_UNIFIED_process_config.json]
    if {[file exists $frozen_config]} {
        file mkdir [file join $project_dir impl]
        file copy -force $frozen_config [file join $project_dir impl PCM5102_UNIFIED_process_config.json]
    }
    open_project [file join $project_dir PCM5102_UNIFIED.gprj]
    set_option -top_module top_unified -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_mspi_as_gpio 1 -use_jtag_as_gpio 0 -output_base_name PCM5102_UNIFIED -gen_verilog_sim_netlist 1 -show_init_in_vo 1
    set_option -resource_sharing 1 -retiming 1 -global_freq 50 -enable_dsrm 1
    # 2026-10-25: the slider now owns its own I2C pins (K10/L10) instead of
    # sharing H4/G4 with the APDS-9960. At Logic 21860 / CLS 11317 (~99%)
    # place 1 routes but misses setup on 4 endpoints (Fmax 49.813MHz), while
    # place 2 gives 0 unrouted, 0 setup/hold violations and Fmax 50.119MHz.
    # place 0 leaves 200+ unrouted nets. Re-check this option after any change.
    set_option -place_option 2 -route_option 0 -route_maxfan 23
    run all
    puts "Audio take bitstream: [file join $project_dir impl pnr PCM5102_UNIFIED.fs]"
} message options]} {
    cd $previous_dir
    return -options $options $message
}
cd $previous_dir
