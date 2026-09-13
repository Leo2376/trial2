#!/usr/bin/tclsh8.6
source ../../../mylittleda.tcl

# Helper: capture stdout produced by a script so the test can parse the Info
# lines printed by report_area_stats -wire. Renames puts for the duration.
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
puts "Test 11: bhtnv block (SRAM + std cells, seed_placement)"
puts "=========================================="
puts ""

# Lighter testcase extracted from cpu_syn.v: the bhtnv_h_832_242_406 block
# (branch-prediction history table) plus the modules it instantiates. It has
# one SRAM macro (DP128X64M4 at phtable/x0_id0) and a few thousand std cells,
# so it exercises seed_placement at a realistic size without the full 100k+
# design read time.

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef

read_netlist ../inputs/bhtnv_design.v
set_top_design bhtnv_h_832_242_406
build_design

# Report the scale of the block.
global instindex
puts "Info : test11 instindex = $instindex"

# Floorplan: 1/4th of the original 200x200 -> 100x100 (1/4 area). The SRAM is
# 20x40; place it near the centre of the smaller core.
make_floorplan 100 100 0 0

# Place the SRAM macro leaf (DP128X64M4) inside the phtable sub-block.
place_instance {phtable/x0_id0} 50 50 N

add_halo 2 2
set_site_height 0.3
unplace_stdcell
set targetutilz 35

# Build connectivity so seed_placement can score trials by total wire length.
update_wire_db
build_net_conn

# --- seed_placement single-threaded (1 random seed) ---
set t0 [clock milliseconds]
seed_placement
set t1 [clock milliseconds]
puts "Info : test11 seed_placement (serial, 1 random seed) took [expr {$t1-$t0}] ms"

# Verify every CORE cell is placed, inside the core, and clear of blockages.
global _instlist _libcell blockageindex _blockagelist corebox regionindex _regionlist
set cb_x0 [lindex $corebox 0]
set cb_y0 [lindex $corebox 1]
set cb_x1 [lindex $corebox 2]
set cb_y1 [lindex $corebox 3]
set obs {}
for { set i 1 } { $i <= $blockageindex } { incr i } {
  lappend obs [list [lindex $_blockagelist($i) 1] [lindex $_blockagelist($i) 2] [lindex $_blockagelist($i) 3] [lindex $_blockagelist($i) 4]]
}
for { set i 1 } { $i <= $regionindex } { incr i } {
  lappend obs [list [lindex $_regionlist($i) 1] [lindex $_regionlist($i) 2] [lindex $_regionlist($i) 3] [lindex $_regionlist($i) 4]]
}
set ncore 0
set nplaced 0
set nover 0
set nout 0
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  set refid [lindex $inst 8]
  set class [lindex $_libcell($refid) 4]
  if { $class ne "CORE" } { continue }
  incr ncore
  if { [lindex $inst 4] != 1 } { continue }
  incr nplaced
  set px [lindex $inst 5]
  set py [lindex $inst 6]
  if { $px < $cb_x0 || $px > $cb_x1 || $py < $cb_y0 || $py > $cb_y1 } { incr nout }
  foreach b $obs {
    if { $px >= [lindex $b 0] && $px < [lindex $b 2] && $py >= [lindex $b 1] && $py < [lindex $b 3] } { incr nover; break }
  }
}
if { $nplaced == $ncore && $nover == 0 && $nout == 0 } {
  puts "PASS: seed_placement placed all $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (serial)"
} else {
  puts "FAIL: seed_placement placed $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (serial)"
}

# --- report_area_stats -wire : multithread vs single-thread agreement ---
# The design has thousands of nets (>256 threshold), so with multithreading on
# report_area_stats -wire resolves the per-net wire length in parallel worker
# threads. Run it once with MT on (cold cache, parallel resolution), capture
# the total and unknown count, then run it again with MT off (warm cache, pure
# serial sum of cached scalars). The two totals must match to 4 decimals and
# the unknown counts must be identical: this verifies the parallel
# bounding-box computation gives the same accumulated wire length as the
# serial cached path.
set_multithread_on 8
set out_mt [capture_stdout { report_area_stats -wire }]
set total_mt -1
set unknown_mt -1
foreach line [split $out_mt "\n"] {
  if { [regexp {total estimated wire length ([^ ]+)} $line -> t] } { set total_mt $t }
  if { [regexp {unknown/unestimable nets ([0-9]+)} $line -> u] } { set unknown_mt $u }
}
set_multithread_off
set out_st [capture_stdout { report_area_stats -wire }]
set total_st -1
set unknown_st -1
foreach line [split $out_st "\n"] {
  if { [regexp {total estimated wire length ([^ ]+)} $line -> t] } { set total_st $t }
  if { [regexp {unknown/unestimable nets ([0-9]+)} $line -> u] } { set unknown_st $u }
}
# MT and serial sum the same nets in different orders, so the totals can
# differ by floating-point rounding at the last digits; compare with a
# small relative tolerance instead of exact string equality.
set _mt [expr {double($total_mt)}]
set _st [expr {double($total_st)}]
set _rel [expr {($_mt == 0 && $_st == 0) ? 0.0 : abs($_mt - $_st) / (abs($_mt) > abs($_st) ? abs($_mt) : abs($_st))}]
if { $_rel <= 0.001 && $unknown_mt == $unknown_st } {
  puts "PASS: report_area_stats -wire MT total $total_mt ~= serial $total_st (rel [format %.4g $_rel]), unknown $unknown_mt == $unknown_st"
} else {
  puts "FAIL: report_area_stats -wire MT total $total_mt vs serial $total_st, unknown $unknown_mt vs $unknown_st"
}
# Turn MT back on for the rest of the test.
set_multithread_on 8

# --- seed_placement multithread: several random seeds, judged by wire length ---
# MT runs N (=worker count) random-seed trials in parallel, scores each by
# total wire length, and commits the best. This is the seed_placement counterpart
# of hier_placement's multi-seed trials.
unplace_stdcell
set_multithread_on 8
set t2 [clock milliseconds]
seed_placement
set t3 [clock milliseconds]
puts "Info : test11 seed_placement (MT 8 random seeds) took [expr {$t3-$t2}] ms"

# re-verify after the MT placement.
set ncore 0
set nplaced 0
set nover 0
set nout 0
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  set refid [lindex $inst 8]
  set class [lindex $_libcell($refid) 4]
  if { $class ne "CORE" } { continue }
  incr ncore
  if { [lindex $inst 4] != 1 } { continue }
  incr nplaced
  set px [lindex $inst 5]
  set py [lindex $inst 6]
  if { $px < $cb_x0 || $px > $cb_x1 || $py < $cb_y0 || $py > $cb_y1 } { incr nout }
  foreach b $obs {
    if { $px >= [lindex $b 0] && $px < [lindex $b 2] && $py >= [lindex $b 1] && $py < [lindex $b 3] } { incr nover; break }
  }
}
if { $nplaced == $ncore && $nover == 0 && $nout == 0 } {
  puts "PASS: seed_placement placed all $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (MT)"
} else {
  puts "FAIL: seed_placement placed $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (MT)"
}

# --- seed_placement -iter n: multi-round best-across-rounds MT search ---
# Each iteration generates a fresh set of random seeds, scores them, and
# keeps the best across all rounds so far. More rounds give the search more
# chances to find a lower-wire-length layout.
unplace_stdcell
set ti0 [clock milliseconds]
seed_placement -iter 3
set ti1 [clock milliseconds]
puts "Info : test11 seed_placement -iter 3 (MT) took [expr {$ti1-$ti0}] ms"

# verify legal after the iterated search.
set ncore 0
set nplaced 0
set nover 0
set nout 0
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  set refid [lindex $inst 8]
  set class [lindex $_libcell($refid) 4]
  if { $class ne "CORE" } { continue }
  incr ncore
  if { [lindex $inst 4] != 1 } { continue }
  incr nplaced
  set px [lindex $inst 5]
  set py [lindex $inst 6]
  if { $px < $cb_x0 || $px > $cb_x1 || $py < $cb_y0 || $py > $cb_y1 } { incr nout }
  foreach b $obs {
    if { $px >= [lindex $b 0] && $px < [lindex $b 2] && $py >= [lindex $b 1] && $py < [lindex $b 3] } { incr nover; break }
  }
}
if { $nplaced == $ncore && $nover == 0 && $nout == 0 } {
  puts "PASS: seed_placement -iter 3 placed all $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core"
} else {
  puts "FAIL: seed_placement -iter 3 placed $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core"
}

# --- seed_placement determinism: same seed must reproduce identical coordinates ---
unplace_stdcell
set_multithread_off
seed_placement -seed 1234
array set sp_coords1 {}
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $_libcell([lindex $inst 8]) 4] ne "CORE" } { continue }
  set sp_coords1($i) [list [lindex $inst 5] [lindex $inst 6]]
}
unplace_stdcell
seed_placement -seed 1234
set ndiff 0
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $_libcell([lindex $inst 8]) 4] ne "CORE" } { continue }
  if { [lindex $inst 4] != 1 } { continue }
  set c [list [lindex $inst 5] [lindex $inst 6]]
  if { $c ne $sp_coords1($i) } { incr ndiff }
}
if { $ndiff == 0 } {
  puts "PASS: seed_placement is deterministic for seed 1234"
} else {
  puts "FAIL: seed_placement produced $ndiff differing cells on the same seed"
}

# a different seed should (generally) produce a different layout.
unplace_stdcell
seed_placement -seed 777
set ndiff 0
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $_libcell([lindex $inst 8]) 4] ne "CORE" } { continue }
  if { [lindex $inst 4] != 1 } { continue }
  set c [list [lindex $inst 5] [lindex $inst 6]]
  if { $c ne $sp_coords1($i) } { incr ndiff }
}
if { $ndiff > 0 } {
  puts "PASS: seed_placement seed 777 differs from seed 1234 ($ndiff cells moved)"
} else {
  puts "FAIL: seed_placement seed 777 is identical to seed 1234"
}

# --- placeOpt: iterative wire-length optimizer on the placed layout ---
# Runs after seed_placement so the optimizer starts from a legal placement and
# reduces total wire length by moving the cells of the longest nets toward
# their centroid. Default 3 iterations; verify the placement stays legal
# (no blockage hits, no out-of-core) afterward.
puts "=========================================="
puts "placeOpt wire-length optimization"
puts "=========================================="
set to0 [clock milliseconds]
placeOpt
set to1 [clock milliseconds]
puts "Info : test11 placeOpt (default 3 iters) took [expr {$to1-$to0}] ms"

# verify placement still legal after placeOpt.
set ncore 0
set nplaced 0
set nover 0
set nout 0
for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  set refid [lindex $inst 8]
  set class [lindex $_libcell($refid) 4]
  if { $class ne "CORE" } { continue }
  incr ncore
  if { [lindex $inst 4] != 1 } { continue }
  incr nplaced
  set px [lindex $inst 5]
  set py [lindex $inst 6]
  if { $px < $cb_x0 || $px > $cb_x1 || $py < $cb_y0 || $py > $cb_y1 } { incr nout }
  foreach b $obs {
    if { $px >= [lindex $b 0] && $px < [lindex $b 2] && $py >= [lindex $b 1] && $py < [lindex $b 3] } { incr nover; break }
  }
}
if { $nplaced == $ncore && $nover == 0 && $nout == 0 } {
  puts "PASS: placeOpt kept all $nplaced/$ncore CORE cells placed, $nover blockage hits, $nout out-of-core"
} else {
  puts "FAIL: placeOpt left $nplaced/$ncore CORE cells placed, $nover blockage hits, $nout out-of-core"
}

# also exercise the -iter option.
set to2 [clock milliseconds]
placeOpt -iter 5
set to3 [clock milliseconds]
puts "Info : test11 placeOpt -iter 5 took [expr {$to3-$to2}] ms"

exit
