# Default entry point: the single unified project. Builds without programming hardware.
if {[catch {
    source [file join [file dirname [info script]] build_unified.tcl]
} message]} {
    puts stderr "Unified build failed: $message"
    exit 1
}
exit 0
