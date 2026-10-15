# Run with gw_sh tools/build.tcl. Never programs hardware.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
set gao_config [file join $project_dir src TTP229_GPIO.gao]
set gao_netlist [file join $project_dir impl gao gao.v]
if {[file exists $gao_config] && [file exists $gao_netlist] &&
    [file mtime $gao_config] > [file mtime $gao_netlist]} {
    file delete $gao_netlist
}
if {[catch {
    open_project [file join $project_dir TTP229_GPIO.gprj]
    set_option -top_module ttp229_gpio_top -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0
    run all
    puts "Standalone bitstream: [file join $project_dir impl pnr ao_0.fs]"
    puts "Matching GAO configuration: $gao_config"
} message]} {
    puts stderr "Gowin build failed: $message"
    exit 1
}
exit 0
