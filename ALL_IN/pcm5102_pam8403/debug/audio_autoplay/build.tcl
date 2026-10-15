set project_dir [file normalize [file dirname [info script]]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir AUDIO_AUTOPLAY.gprj]
    # Keep output registers in fabric so GAO can route the I2S output nets.
    set_option -top_module top -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0 -oreg_in_iob 0 -reg_in_iob 0
    run all
    puts "GAO bitstream: [file join $project_dir impl pnr ao_0.fs]"
} message]} {
    puts stderr "Audio GAO build failed: $message"
    exit 1
}
exit 0

