# Run with: gw_sh tools/build.tcl
# Keep project/file paths relative to this script, regardless of shell cwd.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
# Gowin may reuse an existing analyzer netlist after external .gao edits.
# Invalidate only that generated file when the configuration is newer.
set gao_config [file join $project_dir src HUB75E.gao]
set gao_netlist [file join $project_dir impl gao gao.v]
if {[file exists $gao_config] && [file exists $gao_netlist] &&
    [file mtime $gao_config] > [file mtime $gao_netlist]} {
    file delete $gao_netlist
}
if {[catch {
    open_project [file join $project_dir HUB75E.gprj]
    set_option -top_module TOP -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0
    run all
    puts "GAO debug bitstream: [file join $project_dir impl pnr ao_0.fs]"
    puts "Load it together with: $gao_config"
} message]} {
    puts stderr "Gowin build failed: $message"
    exit 1
}
exit 0
