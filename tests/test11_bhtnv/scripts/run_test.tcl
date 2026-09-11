#!/usr/bin/tclsh8.6
source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 11: bhtnv block (SRAM + std cells, hier_placement)"
puts "=========================================="
puts ""

# Lighter testcase extracted from cpu_syn.v: the bhtnv_h_832_242_406 block
# (branch-prediction history table) plus the modules it instantiates. It has
# one SRAM macro (DP128X64M4 at phtable/x0_id0) and a few thousand std cells,
# so it exercises hier_placement at a realistic size without the full 100k+
# design read time.

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef

read_netlist ../inputs/bhtnv_design.v
set_top_design bhtnv_h_832_242_406
build_design

# Report the scale of the block.
global instindex
puts "Info : test11 instindex = $instindex"

# Floorplan sized to the block area (the SRAM is 20x40; give core room).
make_floorplan 200 200 0 0

# Place the SRAM macro leaf (DP128X64M4) inside the phtable sub-block.
place_instance {phtable/x0_id0} 100 100 N

add_halo 2 2
set_site_height 0.3
unplace_stdcell
set targetutilz 35

# Build connectivity so hier_placement can use net connectivity for intra-
# cluster ordering (the multi-seed trials also score by wire length).
update_wire_db
build_net_conn

# --- hier_placement timing: serial ---
set t0 [clock milliseconds]
hier_placement
set t1 [clock milliseconds]
puts "Info : test11 hier_placement (serial) took [expr {$t1-$t0}] ms"

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
  puts "PASS: hier_placement placed all $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (serial)"
} else {
  puts "FAIL: hier_placement placed $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (serial)"
}

# --- hier_placement timing: multithread (multi-seed trials) ---
unplace_stdcell
set_multithread_on 4
set t2 [clock milliseconds]
hier_placement
set t3 [clock milliseconds]
puts "Info : test11 hier_placement (MT 4 trials) took [expr {$t3-$t2}] ms"

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
  puts "PASS: hier_placement placed all $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (MT)"
} else {
  puts "FAIL: hier_placement placed $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core (MT)"
}

# --- placeOpt: iterative wire-length optimizer on the placed layout ---
# Runs after hier_placement so the optimizer starts from a legal placement
# and reduces total wire length by moving the cells of the longest nets
# toward their centroid. Default 3 iterations; verify the placement stays
# legal (no blockage hits, no out-of-core) afterward.
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
