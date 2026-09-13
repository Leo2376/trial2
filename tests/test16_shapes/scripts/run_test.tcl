#!/usr/bin/tclsh8.6
# Test Case 16: Wire shape model (RT1/RT2/RT3)
# Verifies the per-net shape data model: add_shape (path/via), report_shapes,
# clear_shapes, delete_shape, db persistence (v3 with _netshapes), delete_net
# dropping shapes, and the report_design routed-nets line. Builds on the
# path_design netlist so the net keys resolve exactly like report_net.
source ../../../mylittleda.tcl
puts "=========================================="
puts "Test 16: Wire shape model (RT1/RT2/RT3)"
puts "=========================================="
puts ""
add_lef ../../../lef_files/std_cell.lef
read_netlist ../inputs/path_design.v
set_top_design path_top
build_design
update_wire_db
build_net_conn

# ---------------------------------------------------------------------------
# RT2 add_shape + report_shapes
# ---------------------------------------------------------------------------
puts "=========================================="
puts "RT2 add_shape / report_shapes"
puts "=========================================="
# Two paths on different layers + a via at the bend (Manhattan L).
add_shape n_buf path m2 1.0 2.0 5.0 2.0
add_shape n_buf via  via23 5.0 2.0
add_shape n_buf path m3 5.0 2.0 5.0 8.0

# Capture report_shapes to count the shape lines.
proc _capture_stdout {cmd} {
  rename puts _cap_puts_orig
  upvar 1 _capf _capf
  set _capf [open /tmp/test16_cap.out w]
  proc puts {args} {
    global _capf _cap_puts_orig
    set nl 0
    if {[lindex $args 0] eq "-nonewline"} { set nl 1; set args [lrange $args 1 end] }
    if {[llength $args] == 2} { set args [lrange $args 1 end] }
    set s [join $args]
    if {$nl} { _cap_puts_orig -nonewline $_capf $s } else { _cap_puts_orig $_capf $s }
  }
  uplevel 1 $cmd
  close $_capf
  catch { rename _cap_puts_gone {} }
  rename puts _cap_puts_gone
  rename _cap_puts_orig puts
  return [split [exec cat /tmp/test16_cap.out] \n]
}
set rs [_capture_stdout {report_shapes n_buf}]
set nlines 0
foreach l $rs {
  if {[regexp {^\s+\[[0-9]+\] (path|via)} $l]} { incr nlines }
}
# Should report 3 shapes (2 path + 1 via) and a shapes: 3 line.
set shcount ""
foreach l $rs {
  if {[regexp {shapes:\s+([0-9]+)} $l -> c]} { set shcount $c }
}
if {$nlines == 3 && $shcount == 3} {
  puts "PASS: report_shapes listed 3 shape lines, count=3"
} else {
  puts "FAIL: report_shapes expected 3 lines/count=3, got lines=$nlines count=$shcount"
}

# A net with no shapes reports (no shapes).
set rs2 [_capture_stdout {report_shapes n_or}]
set none 0
foreach l $rs2 { if {[string first "(no shapes)" $l] >= 0} { set none 1 } }
if {$none} {
  puts "PASS: report_shapes reports (no shapes) for an unrouted net"
} else {
  puts "FAIL: report_shapes should report (no shapes) for n_or"
}

# ---------------------------------------------------------------------------
# RT2 validation: bad layer / via / kind / coords / unknown net
# ---------------------------------------------------------------------------
puts "=========================================="
puts "RT2 add_shape validation"
puts "=========================================="
# Capture each error output to assert the Error line.
set e1 [_capture_stdout {add_shape n_buf path m1 0 0 1 1}]
set e1ok 0
foreach l $e1 { if {[string first "unknown path layer" $l] >= 0} { set e1ok 1 } }
if {$e1ok} { puts "PASS: bad path layer m1 rejected" } else { puts "FAIL: bad layer m1 not rejected" }

set e2 [_capture_stdout {add_shape n_buf via via99 0 0}]
set e2ok 0
foreach l $e2 { if {[string first "unknown via type" $l] >= 0} { set e2ok 1 } }
if {$e2ok} { puts "PASS: bad via type via99 rejected" } else { puts "FAIL: bad via via99 not rejected" }

set e3 [_capture_stdout {add_shape n_buf ring 0 0 1 1}]
set e3ok 0
foreach l $e3 { if {[string first "kind must be 'path' or 'via'" $l] >= 0} { set e3ok 1 } }
if {$e3ok} { puts "PASS: bad kind 'ring' rejected" } else { puts "FAIL: bad kind not rejected" }

set e4 [_capture_stdout {add_shape n_buf path m2 a b 1 1}]
set e4ok 0
foreach l $e4 { if {[string first "coordinates must be numbers" $l] >= 0} { set e4ok 1 } }
if {$e4ok} { puts "PASS: non-numeric coordinates rejected" } else { puts "FAIL: non-numeric coords not rejected" }

set e5 [_capture_stdout {add_shape no_such_net path m2 0 0 1 1}]
set e5ok 0
foreach l $e5 { if {[string first "net no_such_net not found" $l] >= 0} { set e5ok 1 } }
if {$e5ok} { puts "PASS: unknown net rejected" } else { puts "FAIL: unknown net not rejected" }

# ---------------------------------------------------------------------------
# RT2 delete_shape / clear_shapes
# ---------------------------------------------------------------------------
puts "=========================================="
puts "RT2 delete_shape / clear_shapes"
puts "=========================================="
# delete_shape index 1 (the via) leaves 2 shapes.
add_shape n_inv path m2 0 0 3 3
add_shape n_inv via  via34 3 3
add_shape n_inv path m4 3 3 6 6
set rs3 [_capture_stdout {report_shapes n_inv}]
set sc3 ""
foreach l $rs3 { if {[regexp {shapes:\s+([0-9]+)} $l -> c]} { set sc3 $c } }
if {$sc3 == 3} {
  puts "PASS: n_inv has 3 shapes before delete"
} else {
  puts "FAIL: n_inv should have 3 shapes, got $sc3"
}
set d1 [_capture_stdout {delete_shape n_inv 1}]
set rs4 [_capture_stdout {report_shapes n_inv}]
set sc4 ""
foreach l $rs4 { if {[regexp {shapes:\s+([0-9]+)} $l -> c]} { set sc4 $c } }
if {$sc4 == 2} {
  puts "PASS: delete_shape removed the via, 2 shapes remain"
} else {
  puts "FAIL: delete_shape left $sc4 shapes (expected 2)"
}
# Out-of-range index rejected.
set d2 [_capture_stdout {delete_shape n_inv 99}]
set d2ok 0
foreach l $d2 { if {[string first "out of range" $l] >= 0} { set d2ok 1 } }
if {$d2ok} { puts "PASS: out-of-range delete_shape index rejected" } else { puts "FAIL: out-of-range index not rejected" }

# clear_shapes empties the net.
clear_shapes n_inv
set rs5 [_capture_stdout {report_shapes n_inv}]
set cleared 0
foreach l $rs5 { if {[string first "(no shapes)" $l] >= 0} { set cleared 1 } }
if {$cleared} { puts "PASS: clear_shapes emptied n_inv" } else { puts "FAIL: clear_shapes did not empty n_inv" }

# After clear, the _netshapes entry is gone so it no longer counts as routed.
global _netshapes
if {![info exists _netshapes(n_inv)]} {
  puts "PASS: clear_shapes dropped the _netshapes(n_inv) entry"
} else {
  puts "FAIL: clear_shapes left a _netshapes(n_inv) entry"
}

# ---------------------------------------------------------------------------
# RT3 db persistence (write_db v3 + restore_db)
# ---------------------------------------------------------------------------
puts "=========================================="
puts "RT3 write_db / restore_db (v3 _netshapes)"
puts "=========================================="
set dbfile [file normalize ../outputs/path_test16.db]
file mkdir ../outputs
write_db $dbfile

# The db must carry a v3 header.
set fp [open $dbfile r]
set lines [split [read $fp] \n]
close $fp
set hdr2 [lindex $lines 1]
if {[regexp {# version 3} $hdr2]} {
  puts "PASS: db has v3 header ($hdr2)"
} else {
  puts "FAIL: db header unexpected: '$hdr2'"
}
# The db must contain an _netshapes array line for n_buf.
set has_shapes 0
foreach l $lines { if {[regexp {_netshapes} $l]} { set has_shapes 1 } }
if {$has_shapes} {
  puts "PASS: db persists the _netshapes array"
} else {
  puts "FAIL: db missing _netshapes array line"
}

# restore_db into a fresh session and check the shapes survived.
set s_r [open /tmp/test16_restore.tcl w]
puts $s_r "source ../../../mylittleda.tcl"
puts $s_r "restore_db $dbfile"
puts $s_r "report_shapes n_buf"
puts $s_r "exit"
close $s_r
set rout [exec tclsh8.6 /tmp/test16_restore.tcl 2>@1]
set rcount ""
foreach l [split $rout \n] { if {[regexp {shapes:\s+([0-9]+)} $l -> c]} { set rcount $c } }
if {[string first "db integrity verified (v3 checksum ok)" $rout] >= 0 && $rcount == 3} {
  puts "PASS: restore_db verifies v3 checksum and n_buf has 3 shapes"
} else {
  puts "FAIL: restore_db/shape restore unexpected (count=$rcount): $rout"
}

# A v2 db (no _netshapes) must still restore, with _netshapes empty.
set fv [open /tmp/test16_v2.db w]
puts $fv "# mylittleda db"
puts $fv "# version 2"
# Drop the version header to v2 and strip any _netshapes line; keep checksum
# recompute by re-summing body line lengths.
set body {}
set sum 0
foreach l [lrange $lines 2 end] {
  if {$l eq ""} { continue }
  if {[regexp {^C } $l]} { continue }
  if {[regexp {_netshapes} $l]} { continue }
  lappend body $l
  incr sum [string length $l]
}
foreach l $body { puts $fv $l }
puts $fv "C $sum"
close $fv
set s_v [open /tmp/test16_restore_v2.tcl w]
puts $s_v "source ../../../mylittleda.tcl"
puts $s_v "restore_db /tmp/test16_v2.db"
puts $s_v "global _netshapes"
puts $s_v "puts \"CHK v2 ns=\[array size _netshapes\]\""
puts $s_v "exit"
close $s_v
set vout [exec tclsh8.6 /tmp/test16_restore_v2.tcl 2>@1]
if {[string first "CHK v2 ns=0" $vout] >= 0} {
  puts "PASS: v2 db restores with empty _netshapes (no shapes)"
} else {
  puts "FAIL: v2 db restore unexpected: $vout"
}

# ---------------------------------------------------------------------------
# delete_net drops shapes; report_design routed-nets line
# ---------------------------------------------------------------------------
puts "=========================================="
puts "RT1 delete_net / report_design routed line"
puts "=========================================="
# n_buf currently has 3 shapes. report_design should report 1 routed net.
set g8 [_capture_stdout {report_design}]
set nrouted ""
foreach l $g8 { if {[regexp {routed nets\s+:\s+([0-9]+)} $l -> c]} { set nrouted $c } }
if {$nrouted == 1} {
  puts "PASS: report_design routed nets = 1 (n_buf)"
} else {
  puts "FAIL: report_design routed nets expected 1, got '$nrouted'"
}

# Deleting n_buf drops its shapes too.
delete_net n_buf
global _netshapes
if {![info exists _netshapes(n_buf)]} {
  puts "PASS: delete_net dropped _netshapes(n_buf)"
} else {
  puts "FAIL: delete_net left _netshapes(n_buf)"
}
set g8b [_capture_stdout {report_design}]
set nrouted2 ""
foreach l $g8b { if {[regexp {routed nets\s+:\s+([0-9]+)} $l -> c]} { set nrouted2 $c } }
if {$nrouted2 == 0} {
  puts "PASS: report_design routed nets = 0 after delete_net"
} else {
  puts "FAIL: report_design routed nets expected 0 after delete, got '$nrouted2'"
}

# ---------------------------------------------------------------------------
# H2 help: Routing area lists the new commands
# ---------------------------------------------------------------------------
puts "=========================================="
puts "H2 help Routing area"
puts "=========================================="
set hh [_capture_stdout {help}]
set area 0
set cmds 0
set inrouting 0
foreach l $hh {
  if {[regexp {^Routing :} $l]} { set area 1; set inrouting 1; continue }
  if {$inrouting} {
    # A blank line ends the Routing command block.
    if {[string trim $l] eq ""} { set inrouting 0; continue }
    if {[regexp {^\s+add_shape} $l]} { incr cmds }
    if {[regexp {^\s+report_shapes} $l]} { incr cmds }
    if {[regexp {^\s+clear_shapes} $l]} { incr cmds }
    if {[regexp {^\s+delete_shape} $l]} { incr cmds }
  }
}
if {$area && $cmds == 4} {
  puts "PASS: help lists the Routing area with 4 commands"
} else {
  puts "FAIL: help Routing area missing (area=$area cmds=$cmds)"
}

puts "=========================================="
puts "Test 16: done"
puts "=========================================="
exit
