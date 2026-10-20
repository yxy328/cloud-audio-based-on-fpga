# Re-run placement/timing against the existing event-target netlist only.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    open_project [file join $project_dir PCM5102_EVENT_TAKE.gprj]
    set_option -top_module top_take -output_base_name PCM5102_EVENT_TAKE -use_mspi_as_gpio 1 -use_cpu_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 0
    run pnr
} message]} {
    puts stderr "Event placement failed: $message"
    exit 1
}
exit 0
