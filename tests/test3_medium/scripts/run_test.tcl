#!/usr/bin/tclsh8.6
# Test Case 3: Medium Design
# Medium complexity design with hierarchy, multiple blocks

source ../../../mylittleda_nogui.tcl

puts "=========================================="
puts "Test 3: Medium Design"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/ts1n7hslvta128x33m2wbzhocp.lef
add_lef ../../../lef_files/ts1n7hslvta512x40m2wbzhocp.lef
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

report_hierarchy_tree

exit
