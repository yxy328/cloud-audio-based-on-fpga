set project_dir [file normalize [file join [file dirname [info script]] ..]]
set previous_dir [pwd]
cd $project_dir
if {[catch {
    set frozen_config [file join $project_dir .. build_inputs PCM5102_AUDIO_TAKE_process_config.json]
    if {[file exists $frozen_config]} {
        file mkdir [file join $project_dir impl]
        file copy -force $frozen_config [file join $project_dir impl PCM5102_AUDIO_TAKE_process_config.json]
    }
    open_project [file join $project_dir PCM5102_AUDIO_TAKE.gprj]
    set_option -top_module top_audio_take -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_mspi_as_gpio 1 -use_jtag_as_gpio 0 -output_base_name PCM5102_AUDIO_TAKE -gen_verilog_sim_netlist 1 -show_init_in_vo 1
    set_option -resource_sharing 1 -retiming 1 -global_freq 50
    run all
    puts "Audio take bitstream: [file join $project_dir impl pnr PCM5102_AUDIO_TAKE.fs]"
} message options]} {
    cd $previous_dir
    return -options $options $message
}
cd $previous_dir
