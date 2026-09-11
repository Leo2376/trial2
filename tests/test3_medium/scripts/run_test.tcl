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
add_lib ../../../liberty_files/n7_tech.lib
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

report_hierarchy_tree

exit
