set project_dir [file normalize [file join [file dirname [info script]] ..]]
cd $project_dir
if {[catch {
    foreach item {performance_take take_nor_store} {
        open_project [file join $project_dir PCM5102_EVENT_TAKE.gprj]
        set_option -top_module $item -disable_io_insertion 1 -output_base_name AUDIT_$item
        run syn
    }
} message]} {
    puts stderr "Resource audit failed: $message"
    exit 1
}
exit 0
