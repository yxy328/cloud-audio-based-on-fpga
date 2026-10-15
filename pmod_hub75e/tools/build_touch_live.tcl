# Run with: gw_sh tools/build_touch_live.tcl
# Direct CLK_IN sample clock; no HUB75, ROM, UI, or USER_KEY-dependent reset.
set workspace_dir [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $workspace_dir debug touch_live]
set project_file [file join $project_dir HUB75E_LIVE.gprj]
set gao_config [file join $project_dir Touch_LIVE.gao]
set gao_netlist [file join $project_dir impl gao gao.v]
if {![file exists $project_file] || ![file exists $gao_config]} {
    puts stderr "Touch live project or GAO configuration is missing in $project_dir"
    exit 1
}
cd $project_dir
if {[file exists $gao_netlist] &&
    [file mtime $gao_config] > [file mtime $gao_netlist]} {
    file delete $gao_netlist
}
if {[catch {
    open_project $project_file
    set_option -top_module TOP_TOUCH_LIVE -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0
    run all
    puts "Direct 50 MHz live touch bitstream: [file join $project_dir impl pnr ao_0.fs]"
    puts "Load it together with: $gao_config"
} message]} {
    puts stderr "Gowin touch live build failed: $message"
    exit 1
}
exit 0
