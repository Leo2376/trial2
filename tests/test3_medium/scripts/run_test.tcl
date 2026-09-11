#!/usr/bin/tclsh8.6
# Test Case 3: Medium Design
# Medium complexity design with hierarchy, multiple blocks

source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 3: Medium Design"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef
read_netlist ../inputs/medium_design.v

set_top_design medium_cpu
build_design

make_floorplan 200 200 0 0

add_halo 1 1
set_site_height 0.3

unplace_stdcell
set targetutilz 40

make_placement

make_lef ../outputs/medium_design_test3.lef
export_def ../outputs/medium_design_test3.def
export_dc_floorplan ../outputs/medium_design_test3.dc_floorplan.tcl
make_lib ../outputs/medium_design_test3.lib

# Build the net connectivity map and load the liberty sync (clock) pins so
# trace_clock (R2) can trace the clock tree to leaf sync endpoints.
update_wire_db
build_net_conn
add_lib ../../../liberty_files/std_cell.lib
puts "=========================================="
puts "trace_clock non-reg checks (R2)"
puts "=========================================="
# trace_clock traces a tree from a net/pin down through combinational logic
# to all leaf sync load pins (flop CP / SRAM CK via _libsyncpin). The clk net
# fans out through the rf and ctrl hierarchical instances to 4 flop CP pins
# (rf/reg_ff, ctrl/pc_ff0..2): expect 4 sync endpoints.
trace_clock clk
# A pin root works the same: rf/clk is on the clk net, so the same tree.
trace_clock rf/clk
# A net with no clock path forward reports 0 endpoints without error.
trace_clock alu_result

puts "=========================================="
puts "report_path -from non-reg checks (P4)"
puts "=========================================="
# P4: forward-only report_path (no -to) traces from -from across all branches
# and stops each branch at the first sync load pin. From clk the same 4 flop
# CP endpoints as trace_clock are reached, each as its own path block.
report_path -from clk
# A net with no clock path forward reports 0 sync endpoints reached without
# error.
report_path -from alu_result

puts "=========================================="
puts "set_max_fanout / fix_max_fanout non-reg checks (O1/O2)"
puts "=========================================="
# O1+O2 buffer insertion. alu_result has a single logical driver set and 3
# receivers (assign data_out, alu/result, rf/data_in). With set_max_fanout 2,
# fix_max_fanout -cell BUFFD1 splits the 3 receivers across 2
# buffers: alu_result keeps the 2 buffer inputs as its receivers (<=2), and a
# new net per buffer (alu_result_b1, alu_result_b2) carries the moved receivers,
# each driven by a buffer Z output. show the before/after fanout.
set_max_fanout 2
report_net alu_result
fix_max_fanout -cell BUFFD1
# After: alu_result now has 2 receivers (the 2 buffer inputs), each <= maxfanout.
report_net alu_result
# The new buffer nets exist and each has at most maxfanout receivers.
get_net alu_result_b*
report_net alu_result_b1
report_net alu_result_b2
# The inserted buffer instances are visible to get_cell.
get_cell alu_result___*

# Non-regression check for hier_placement (hierarchy-aware placer): the
# medium design has 3 hierarchy clusters (rf, ctrl, alu). Re-unplace and run
# the hierarchy-clustering placement engine, then verify all CORE cells are
# placed inside the core with no blockage overlap.
puts "=========================================="
puts "hier_placement non-reg check"
puts "=========================================="
unplace_stdcell
hier_placement
global instindex _instlist _libcell blockageindex _blockagelist corebox regionindex _regionlist
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
  puts "PASS: hier_placement placed all $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core"
} else {
  puts "FAIL: hier_placement placed $nplaced/$ncore CORE cells, $nover blockage hits, $nout out-of-core"
}

report_hierarchy_tree

exit
