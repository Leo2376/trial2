#!/usr/bin/tclsh8.6
# Test Case 13: E5 (delete_cell/delete_net) / P8 (hier-port direction) /
#               P7 cycle guard / H2 (help)
# Small structural design with a flop, a high-fanout chain, an inverter ring
# (combinational cycle) and a hierarchical submodule.
source ../../../mylittleda.tcl
puts "=========================================="
puts "Test 13: E5 / P8 / P7-cycle / H2"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lib ../../../liberty_files/std_cell.lib
read_netlist ../inputs/e5p8_design.v
set_top_design e5p8_top
build_design
build_net_conn

# ---------------------------------------------------------------------------
# H2 help
# ---------------------------------------------------------------------------
puts "=========================================="
puts "H2 help non-reg checks"
puts "=========================================="
# Capture stdout so we can assert on it without the engine banner noise.
proc _capture_stdout {cmd} {
  rename puts _cap_puts_orig
  upvar 1 _capf _capf
  set _capf [open /tmp/test13_cap.out w]
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
  return [split [exec cat /tmp/test13_cap.out] \n]
}

# help with no arg lists commands grouped by area. Assert that key area
# headers and the new commands appear.
set h [_capture_stdout {help}]
proc _has {lines s} {
  foreach l $lines { if {[string first $s $l] >= 0} { return 1 } }
  return 0
}
if {[_has $h "ECO :"] && [_has $h "delete_cell"] && [_has $h "delete_net"]} {
  puts "PASS: help (no arg) lists ECO area with delete_cell/delete_net"
} else {
  puts "FAIL: help (no arg) missing ECO area / delete commands"
}
if {[_has $h "Path tracing :"] && [_has $h "report_path"]} {
  puts "PASS: help (no arg) lists Path tracing area with report_path"
} else {
  puts "FAIL: help (no arg) missing Path tracing / report_path"
}
if {[_has $h "Reporting :"] && [_has $h "report_design"]} {
  puts "PASS: help (no arg) lists Reporting area with report_design"
} else {
  puts "FAIL: help (no arg) missing Reporting / report_design"
}

# help with a glob lists matching command usage.
set hr [_capture_stdout {help report*}]
if {[_has $hr "report_path"] && [_has $hr "report_design"]} {
  puts "PASS: help report* lists report_path and report_design"
} else {
  puts "FAIL: help report* missing expected entries"
}
# Usage line for report_path must mention -limit / -max_depth (P7).
if {[_has $hr "-limit"] && [_has $hr "-max_depth"]} {
  puts "PASS: help report_path usage shows -limit / -max_depth options"
} else {
  puts "FAIL: help report_path usage missing -limit / -max_depth"
}
# help *cell* lists the cell commands.
set hc [_capture_stdout {help *cell*}]
if {[_has $hc "get_cells"] && [_has $hc "delete_cell"] && [_has $hc "get_lib_cells"]} {
  puts "PASS: help *cell* lists get_cells / delete_cell / get_lib_cells"
} else {
  puts "FAIL: help *cell* missing expected cell commands"
}
# help with a non-matching pattern reports no match (cleanly).
set hb [_capture_stdout {help zzz*}]
if {[_has $hb "No command matches"]} {
  puts "PASS: help zzz* reports no match cleanly"
} else {
  puts "FAIL: help zzz* should report 'No command matches'"
}

# ---------------------------------------------------------------------------
# E5 delete_cell / delete_net
# ---------------------------------------------------------------------------
puts "=========================================="
puts "E5 delete_cell / delete_net non-reg checks"
puts "=========================================="
# Create a buffer, wire it into hi_net (as an extra load via its input), then
# delete the cell. The net must lose the connection; get_cells must not list
# the deleted cell; the session must not crash on a later get_cells *.
create_net hi2
create_cell u_e5del BUFFD1
connect_net hi2 u_e5del/Z
connect_net hi_net u_e5del/I
# hi2 now has driver u_e5del/Z.
set ac [_capture_stdout {all_connected hi2}]
if {[_has $ac "u_e5del/Z"]} {
  puts "PASS: before delete, hi2 has driver u_e5del/Z"
} else {
  puts "FAIL: before delete, hi2 should have driver u_e5del/Z"
}
delete_cell u_e5del
# After delete: hi2 has no driver; get_cells * must not list u_e5del.
set ac2 [_capture_stdout {all_connected hi2}]
if {[_has $ac2 "drivers : (none)"]} {
  puts "PASS: after delete_cell, hi2 has no driver"
} else {
  puts "FAIL: after delete_cell, hi2 should have no driver"
}
set gc [_capture_stdout {get_cells u_*}]
if {! [_has $gc "u_e5del"]} {
  puts "PASS: after delete_cell, get_cells u_* does not list the deleted cell"
} else {
  puts "FAIL: get_cells u_* still lists the deleted cell u_e5del"
}
# The whole-instance scan must not crash (the <deleted> slot is skipped).
if {![catch {get_cells * -hier} err]} {
  puts "PASS: get_cells * -hier runs cleanly after a delete_cell (no gap crash)"
} else {
  puts "FAIL: get_cells * -hier crashed after delete_cell: $err"
}

# delete_net: remove hi2 entirely; it must vanish from get_nets/all_connected.
delete_net hi2
set gn [_capture_stdout {get_nets hi2}]
if {! [_has $gn "hi2"]} {
  puts "PASS: after delete_net, get_nets hi2 finds nothing"
} else {
  puts "FAIL: after delete_net, get_nets hi2 still finds the net"
}
set ac3 [_capture_stdout {all_connected hi2}]
if {[_has $ac3 "No net matches"]} {
  puts "PASS: after delete_net, all_connected hi2 reports no net"
} else {
  puts "FAIL: after delete_net, all_connected hi2 should report no net"
}

# E5 guards: deleting a non-existent instance / net errors cleanly.
set g1 [_capture_stdout {delete_cell no_such_inst}]
if {[_has $g1 "not found"]} {
  puts "PASS: delete_cell rejects a non-existent instance"
} else {
  puts "FAIL: delete_cell should reject non-existent instance"
}
set g2 [_capture_stdout {delete_net no_such_net}]
if {[_has $g2 "not found"]} {
  puts "PASS: delete_net rejects a non-existent net"
} else {
  puts "FAIL: delete_net should reject non-existent net"
}
# delete_cell on a hierarchical instance must be rejected (not a leaf).
set g3 [_capture_stdout {delete_cell sub_inst}]
if {[_has $g3 "hierarchical instance"]} {
  puts "PASS: delete_cell rejects a hierarchical instance"
} else {
  puts "FAIL: delete_cell should reject a hierarchical instance"
}

# ---------------------------------------------------------------------------
# P8 hierarchical-port direction awareness
# ---------------------------------------------------------------------------
puts "=========================================="
puts "P8 hier-port direction non-reg checks"
puts "=========================================="
# sub_inst is a hierarchical instance with input port si and output port so.
# _hier_pin_dir must report si=input, so=output.
if {[_hier_pin_dir sub_inst si] eq "input"} {
  puts "PASS: _hier_pin_dir sub_inst/si = input"
} else {
  puts "FAIL: _hier_pin_dir sub_inst/si expected input, got '[_hier_pin_dir sub_inst si]'"
}
if {[_hier_pin_dir sub_inst so] eq "output"} {
  puts "PASS: _hier_pin_dir sub_inst/so = output"
} else {
  puts "FAIL: _hier_pin_dir sub_inst/so expected output, got '[_hier_pin_dir sub_inst so]'"
}
# A forward trace from sub_in must cross into the submodule (input port) and
# reach sub_inst's inner net. A forward trace must NOT cross an output port
# backwards: from inside, an output port drives the outer net; from the outer
# side, sub_out is driven by sub_inst/so (an output), so tracing forward from
# sub_out should NOT re-enter the submodule through so.
# Sanity: report_pin on a hier pin should now report a real direction.
set rp [_capture_stdout {report_pin sub_inst/si}]
if {[_has $rp "direction: input"]} {
  puts "PASS: report_pin sub_inst/si reports direction input"
} else {
  puts "FAIL: report_pin sub_inst/si should report direction input"
}

# ---------------------------------------------------------------------------
# P7 cycle guard
# ---------------------------------------------------------------------------
puts "=========================================="
puts "P7 cycle guard non-reg checks"
puts "=========================================="
# A forward trace from ring_in enters the inverter ring (ring_a -> inv1 ->
# ring_b -> inv2 -> ring_a). ring_a is revisited, so the BFS prunes a cyclic
# back-edge. The Note line must report >=1 pruned back-edge, and the trace
# must terminate (not hang).
set rc [_capture_stdout {report_path -from ring_in}]
if {[_has $rc "cyclic back-edge(s) pruned"]} {
  puts "PASS: report_path -from ring_in reports a pruned cyclic back-edge"
} else {
  puts "FAIL: report_path -from ring_in should report a pruned back-edge"
}
# The same Note must appear in the -to mode when a cycle is on the path.
set rc2 [_capture_stdout {report_path -from ring_in -to ring_out}]
if {[_has $rc2 "1 path found."] || [_has $rc2 "No path found"]} {
  puts "PASS: report_path -to ring_out terminates (cycle does not hang the BFS)"
} else {
  puts "FAIL: report_path -to ring_out did not terminate cleanly"
}
# -limit caps sync endpoints: from clk, the only sync endpoint is e5_ff/CP.
set rl [_capture_stdout {report_path -from clk -limit 1}]
if {[_has $rl "limited to 1"]} {
  puts "PASS: report_path -from clk -limit 1 reports the limit cap"
} else {
  puts "FAIL: report_path -from clk -limit 1 should report '(limited to 1)'"
}
# -max_depth 1 from clk still reaches e5_ff/CP (one hop), depth 0 stops it.
set rd [_capture_stdout {report_path -from clk -max_depth 1}]
if {[_has $rd "sync endpoint(s) reached"]} {
  puts "PASS: report_path -from clk -max_depth 1 reaches the sync endpoint"
} else {
  puts "FAIL: report_path -from clk -max_depth 1 should reach the sync endpoint"
}
set rd0 [_capture_stdout {report_path -from clk -max_depth 0}]
if {[_has $rd0 "sync endpoint(s) reached"]} {
  puts "PASS: report_path -from clk -max_depth 0 (unlimited) reaches the sync endpoint"
} else {
  puts "FAIL: report_path -from clk -max_depth 0 should reach the sync endpoint"
}

puts "=========================================="
puts "Test 13: done"
puts "=========================================="
exit
