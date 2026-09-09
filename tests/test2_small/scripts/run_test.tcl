source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 2: Small Design"
puts "=========================================="
puts ""

# Load LEF libraries
puts "Loading LEF libraries..."
add_lef ../../../lef_files/std_cell.lef

read_netlist ../inputs/simple_counter.v
set_top_design counter_wrapper
build_design

make_floorplan 50 50 0 0

place_instance {sc/ff0} 10 10 N
place_instance {sc/ff1} 20 10 N
place_instance {sc/ff2} 30 10 N
place_instance {sc/ff3} 40 10 N

add_halo 1 1
set_site_height 0.3

unplace_stdcell
set targetutilz 50

make_placement

make_lef ../outputs/simple_counter_test2.lef
export_def ../outputs/simple_counter_test2.def
export_dc_floorplan ../outputs/simple_counter_test2.dc_floorplan.tcl
make_lib ../outputs/simple_counter_test2.lib

report_hierarchy_tree

exit
