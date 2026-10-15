set project_dir [file normalize [file dirname [info script]]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir INTEGRATION_GAO.gprj]
    set_option -top_module top -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0 -oreg_in_iob 0 -reg_in_iob 0 -output_base_name INTEGRATION_GAO
    run all
    puts "Current-top GAO bitstream: [file join $project_dir impl pnr ao_0.fs]"
} message]} {
    puts stderr "Integration GAO build failed: $message"
    exit 1
}
exit 0
