# Run with: gw_sh tools/build_touch_high.tcl
# Keep the active-high comparison and all outputs in debug/touch_high.
set workspace_dir [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $workspace_dir debug touch_high]
cd $project_dir
set gao_config [file join $project_dir Touch_HIGH.gao]
set gao_netlist [file join $project_dir impl gao gao.v]
if {[file exists $gao_config] && [file exists $gao_netlist] &&
    [file mtime $gao_config] > [file mtime $gao_netlist]} {
    file delete $gao_netlist
}
if {[catch {
    open_project [file join $project_dir HUB75E_HIGH.gprj]
    set_option -top_module TOP_TTP_HIGH -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0
    run all
    puts "Active-high touch debug bitstream: [file join $project_dir impl pnr ao_0.fs]"
    puts "Load it together with: $gao_config"
} message]} {
    puts stderr "Gowin active-high touch build failed: $message"
    exit 1
}
exit 0
