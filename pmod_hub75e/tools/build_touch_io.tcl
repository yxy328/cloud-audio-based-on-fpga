# Run with: gw_sh tools/build_touch_io.tcl
# Keep this diagnostic build and all outputs isolated from the main project.
set workspace_dir [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $workspace_dir debug touch_io]
cd $project_dir
set gao_config [file join $project_dir Touch_IO.gao]
set gao_netlist [file join $project_dir impl gao gao.v]
if {[file exists $gao_config] && [file exists $gao_netlist] &&
    [file mtime $gao_config] > [file mtime $gao_netlist]} {
    file delete $gao_netlist
}
if {[catch {
    open_project [file join $project_dir HUB75E_IO.gprj]
    set_option -top_module TOP -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0
    run all
    puts "Touch I/O debug bitstream: [file join $project_dir impl pnr ao_0.fs]"
    puts "Load it together with: $gao_config"
} message]} {
    puts stderr "Gowin touch I/O build failed: $message"
    exit 1
}
exit 0

