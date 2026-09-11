#!/usr/bin/tclsh
source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 4: Hierarchical Design (RAM + Std Cells)"
puts "=========================================="
puts ""

# Load LEF libraries
puts "Loading LEF libraries..."
add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef

read_netlist ../inputs/hierarchical_design.v
set_top_design hierarchical_top
build_design

make_floorplan 300 300 0 0

place_instance ram_hier/itag/itag_ram_0 100 130 N
place_instance ram_hier/itag/itag_ram_1 120 130 N
place_instance ram_hier/idata/idata_ram_h 100 160 N
place_instance ram_hier/idata/idata_ram_l 120 160 N

add_halo 1 1
set_site_height 0.3

unplace_stdcell
set targetutilz 45

make_placement

make_lef ../outputs/hierarchical_test4.lef
export_def ../outputs/hierarchical_test4.def
export_dc_floorplan ../outputs/hierarchical_test4.dc_floorplan.tcl
make_lib ../outputs/hierarchical_test4.lib


# Non-regression check for hier_placement (hierarchy-aware placer): re-unplace
# the std cells, run the hierarchy-clustering placement engine, and verify
# every CORE cell ends up placed inside the core with no blockage overlap.
puts "=========================================="
puts "hier_placement non-reg check"
puts "=========================================="
unplace_stdcell
hier_placement

# Verify all CORE cells are placed, inside the core box, and clear of every
# blockage/region box (the placed macros + their halos).
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

set hier_dontshow { assign }
report_hierarchy_tree

exit
