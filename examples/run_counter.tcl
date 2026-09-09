#!/usr/bin/tclsh
# Example script for simple_counter.v
# Follows the same pattern as cpu.tcl

source ../mylittleda.tcl

# Load required LEF files
add_lef ../lef_files/std_cell.lef

# Read netlist and set top design
read_netlist simple_counter.v
set_top_design simple_counter
build_design

# Create floorplan
make_floorplan 100 100 0 0

# Place instances manually (optional)
place_instance ff0 10 10 N
place_instance ff1 20 10 N
place_instance ff2 30 10 N
place_instance ff3 40 10 N

# Add halo and set site height
add_halo 1 1
set_site_height 0.3

# Make automatic placement
unplace_stdcell
set targetutilz 50
make_placement

# Redraw to see the layout
redraw

# Export outputs
export_def simple_counter.def
make_lef simple_counter.lef
make_lib simple_counter.lib

# Report
report_hierarchy_tree
report_area_stats

puts "Counter design completed!"
