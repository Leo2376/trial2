#!/usr/bin/tclsh
# Backward-compatible shim. The unified engine now lives in mylittleda.tcl,
# which supports both GUI and nogui modes via the _gui_mode flag.
# Sourcing this file runs the tool in nogui (batch) mode, matching the
# previous behavior of the standalone mylittleda_nogui.tcl.
set _gui_mode 0
source [file join [file dirname [info script]] mylittleda.tcl]
