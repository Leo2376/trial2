#!/usr/bin/tclsh8.6
# Test Case 5: Path Tracing (report_path)
# Based on test3_medium. Exercises report_path connectivity queries on a
# small structural design whose cells/pins exist in std_cell.lef.
source ../../../mylittleda.tcl
puts "=========================================="
puts "Test 5: Path Tracing"
puts "=========================================="
puts ""
add_lef ../../../lef_files/std_cell.lef
read_netlist ../inputs/path_design.v
set_top_design path_top
build_design
update_wire_db

puts "=========================================="
puts "report_path queries"
puts "=========================================="
# Top-input to top-output path through the leaf cells.
report_path -from in_a -to out_y
# Net-to-pin path (driver net to a sink pin).
report_path -from n_and -to out_y
# Pin-to-pin path.
report_path -from g_and/Y -to g_buf/Y

exit
