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


set hier_dontshow { assign }
report_hierarchy_tree

exit
