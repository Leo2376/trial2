#!/usr/bin/tclsh8.6
# Test Case 10: report_net wire-length estimation (W1)
# report_net prints an estimated Manhattan wire length (deltaX + deltaY) from
# the bounding box of the placed driver and receiver instance pins, plus the
# bounding-box corners. Unplaced / hierarchical / port / assign pins have no
# coordinate and are skipped; a net with fewer than 2 placed pins reports the
# estimation as unavailable.
source ../../../mylittleda.tcl

# Helper: capture the stdout produced by a script (any `puts` inside the
# script) into a string, so the test can parse the Info lines printed by
# report_area_stats -wire. Renames puts for the duration of the script.
proc capture_stdout { script } {
  rename puts _orig_puts
  set ::_cap_buf ""
  proc puts { args } {
    if { [llength $args] >= 2 && [lindex $args 0] eq "-nonewline" } {
      append ::_cap_buf [lindex $args 1]
    } elseif { [llength $args] >= 1 } {
      append ::_cap_buf [lindex $args 0]
      append ::_cap_buf "\n"
    }
  }
  uplevel 1 $script
  set data $::_cap_buf
  rename puts {}
  rename _orig_puts puts
  return $data
}

puts "=========================================="
puts "Test 10: report_net wire-length estimation"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
read_netlist ../inputs/wlen_design.v
set_top_design wlen_top
build_design

make_floorplan 100 100 0 0
# Place the three cells at known coordinates so the wire length is
# deterministic. g_and (n_and driver) at (5, 5); g_inv (n_and receiver, n_inv
# driver) at (25, 15); g_buf (n_inv receiver, n_buf driver) at (60, 15).
place_instance g_and 5 5 N
place_instance g_inv 25 15 N
place_instance g_buf 60 15 N

update_wire_db
build_net_conn

set pass 1

# n_and: driver g_and (5, 5), receiver g_inv (25, 15).
# bounding box (5, 5) - (25, 15) => deltaX 20 + deltaY 10 = 30.
puts "-- n_and --"
report_net n_and

# Capture the wire-length line and check it.
set wl [report_net_wirelen n_and]
if { $wl eq "" } {
  puts "FAIL: n_and returned no wire length"
  set pass 0
} elseif { $wl != 30 } {
  puts "FAIL: n_and wire length expected 30, got $wl"
  set pass 0
} else {
  puts "PASS: n_and estimated wire length is $wl (20 + 10)"
}

# n_inv: driver g_inv (25, 15), receiver g_buf (60, 15).
# bounding box (25, 15) - (60, 15) => deltaX 35 + deltaY 0 = 35.
puts "-- n_inv --"
report_net n_inv
set wl2 [report_net_wirelen n_inv]
if { $wl2 eq "" } {
  puts "FAIL: n_inv returned no wire length"
  set pass 0
} elseif { $wl2 != 35 } {
  puts "FAIL: n_inv wire length expected 35, got $wl2"
  set pass 0
} else {
  puts "PASS: n_inv estimated wire length is $wl2 (35 + 0)"
}

# n_buf: driver g_buf (60, 15), receiver assign out_y (unplaced).
# Only 1 placed pin => estimation unavailable.
puts "-- n_buf (1 placed pin) --"
report_net n_buf
set wl3 [report_net_wirelen n_buf]
if { $wl3 ne "" } {
  puts "FAIL: n_buf should be unavailable (1 placed pin), got $wl3"
  set pass 0
} else {
  puts "PASS: n_buf wire length is unavailable (fewer than 2 placed pins)"
}

# report_area_stats -wire: prints the accumulated estimated wire length over
# all nets. n_and (30) + n_inv (35) = 65 are the only estimable nets; the 4
# remaining nets (in_a, in_b, n_buf, out_y) have fewer than 2 placed pins and
# are reported as unknown/unestimable. The total must be 65.
puts "-- report_area_stats -wire --"
set out [capture_stdout { report_area_stats -wire }]
set total -1
set unknown -1
foreach line [split $out "\n"] {
  if { [regexp {total estimated wire length ([^ ]+)} $line -> t] } { set total $t }
  if { [regexp {unknown/unestimable nets ([0-9]+)} $line -> u] } { set unknown $u }
}
if { $total != 65 } {
  puts "FAIL: accumulated wire length expected 65, got $total"
  set pass 0
} else {
  puts "PASS: report_area_stats -wire total is $total (n_and 30 + n_inv 35)"
}
if { $unknown != 4 } {
  puts "FAIL: unknown nets expected 4, got $unknown"
  set pass 0
} else {
  puts "PASS: report_area_stats -wire reports $unknown unknown/unestimable nets"
}

# Cache check: report_area_stats -wire populates the per-net cache, so a
# second report_area_stats -wire must still report 65 (cache reuse).
set out2 [capture_stdout { report_area_stats -wire }]
set total2 -1
foreach line [split $out2 "\n"] {
  if { [regexp {total estimated wire length ([^ ]+)} $line -> t] } { set total2 $t }
}
if { $total2 != 65 } {
  puts "FAIL: cached accumulated wire length expected 65, got $total2"
  set pass 0
} else {
  puts "PASS: cached report_area_stats -wire total is $total2"
}

if { $pass } {
  puts "=========================================="
  puts "Test 10: PASS"
} else {
  puts "=========================================="
  puts "Test 10: FAIL"
}

exit
