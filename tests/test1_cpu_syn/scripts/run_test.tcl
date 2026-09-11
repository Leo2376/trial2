source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 1: CPU Synthesis (Large Design)"
puts "=========================================="
puts ""

# Load LEF libraries
puts "Loading LEF libraries..."
add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/ts1n7hslvta128x33m2wbzhocp.lef
add_lef ../../../lef_files/ts1n7hslvta512x40m4wbzhocp.lef
add_lef ../../../lef_files/tsdn7lvta128x64m4wbzhocp.lef


read_netlist ../inputs/cpu_syn.v
set_top_design cpucore5nvstrb_nl2
build_design

make_floorplan 500 400 0 0

place_instance {core0/w0/cmem1/itagmem_0/x0_id0} 250 220 N
place_instance {core0/w0/cmem1/itagmem_1/x0_id0} 280 220 N
place_instance {core0/w0/cmem1/itagmem_2/x0_id0} 310 220 N
place_instance {core0/w0/cmem1/itagmem_3/x0_id0} 340 220 N

place_instance {core0/w0/cmem1/idatamemh_0/x0_id0} 250 260 N
place_instance {core0/w0/cmem1/idatameml_0/x0_id0} 250 330 N
place_instance {core0/w0/cmem1/idatamemh_1/x0_id0} 280 260 N
place_instance {core0/w0/cmem1/idatameml_1/x0_id0} 280 330 N
place_instance {core0/w0/cmem1/idatamemh_2/x0_id0} 310 260 N
place_instance {core0/w0/cmem1/idatameml_2/x0_id0} 310 330 N
place_instance {core0/w0/cmem1/idatamemh_3/x0_id0} 340 260 N
place_instance {core0/w0/cmem1/idatameml_3/x0_id0} 340 330 N

place_instance {core0/w0/cmem1/dtagcmem_0/x0_id0} 380 220 N
place_instance {core0/w0/cmem1/dtagcmem_1/x0_id0} 410 220 N
place_instance {core0/w0/cmem1/dtagcmem_2/x0_id0} 440 220 N
place_instance {core0/w0/cmem1/dtagcmem_3/x0_id0} 470 220 N

place_instance {core0/w0/cmem1/ddatamemh_0/x0_id0} 380 260 N
place_instance {core0/w0/cmem1/ddatameml_0/x0_id0} 380 330 N
place_instance {core0/w0/cmem1/ddatamemh_1/x0_id0} 410 260 N
place_instance {core0/w0/cmem1/ddatameml_1/x0_id0} 410 330 N
place_instance {core0/w0/cmem1/ddatamemh_2/x0_id0} 440 260 N
place_instance {core0/w0/cmem1/ddatameml_2/x0_id0} 440 330 N
place_instance {core0/w0/cmem1/ddatamemh_3/x0_id0} 470 260 N
place_instance {core0/w0/cmem1/ddatameml_3/x0_id0} 470 330 N

place_instance {core0/w0/nv_c0/c0/bht0/phtable/x0_id0} 1 10 N

add_halo 2 2
set_site_height 0.3

unplace_stdcell
set targetutilz 35

make_placement

make_lef ../outputs/cpu_syn_test1.lef
export_def ../outputs/cpu_syn_test1.def
export_dc_floorplan ../outputs/cpu_syn_test1.dc_floorplan.tcl
make_lib ../outputs/cpu_syn_test1.lib

# Build connectivity so report_path can trace nets/pins.
update_wire_db
build_net_conn

report_path -from core0/w0/nv_c0/c0/iu0/r_reg_M__ADDRESS__49_/Q  -to  core0/w0/nv_c0/c0/iu0/n20719

puts "=========================================="
puts "report_path -net / -layout non-reg checks (P5/P6)"
puts "=========================================="
# P6 -net: also print the logical nets crossed (by default the Net column is
# blank). Expect the crossed nets n84 and n20719 to appear.
report_path -from core0/w0/nv_c0/c0/iu0/r_reg_M__ADDRESS__49_/Q -to core0/w0/nv_c0/c0/iu0/n20719 -net
# P5 -layout: add an (x, y) column for placed crossed cells/pins. Cells are
# placed by make_placement above, so coordinates must appear for the pins.
report_path -from core0/w0/nv_c0/c0/iu0/r_reg_M__ADDRESS__49_/Q -to core0/w0/nv_c0/c0/iu0/n20719 -layout
# Both options together.
report_path -from core0/w0/nv_c0/c0/iu0/r_reg_M__ADDRESS__49_/Q -to core0/w0/nv_c0/c0/iu0/n20719 -net -layout

puts "=========================================="
puts "get_lib_cell non-reg checks"
puts "=========================================="

# get_lib_cell queries the loaded library (cataloglist), not the netlist, so
# it works once a LEF is imported. Exact name, prefix wildcard and substring
# wildcard are all supported.
get_lib_cell BUFFD10BWP300H8P64PDLVT
get_lib_cell BUFF*
get_lib_cell *DFF*

puts "=========================================="
puts "get_cell / all_connected non-reg checks"
puts "=========================================="

# get_cell without -hier stays within one scope (direct children only):
#   *             -> top-level instances only (197)
#   <scope>/*     -> direct children of <scope> only
# get_cell -hier matches across the whole hierarchy (legacy behaviour).
get_cell *
get_cell * -hier
get_cell core0/w0/nv_c0/c0/*
get_cell core0/w0/nv_c0/c0/iu0/*

# get_net mirrors get_cell's scope semantics but for nets. Without -hier it
# reports only the nets of the single scope implied by the pattern; with
# -hier it matches across the whole hierarchy. get_net now reports just the
# net name per match (a getter, like get_cell/get_lib_cell); the driver /
# receiver detail lives in report_net. Expect a single net for the exact
# reference (use report_net to see driver U28571/ZN).
get_net *
get_net * -hier
get_net core0/w0/nv_c0/c0/*
get_net core0/w0/nv_c0/c0/iu0/*
get_net core0/w0/nv_c0/c0/iu0/n20719

# all_connected on a full hierarchical net reports only that scope's net,
# not same-named nets reused in sibling submodules. Expect a single driver:
# core0/w0/nv_c0/c0/iu0/U28571/ZN
all_connected core0/w0/nv_c0/c0/iu0/n20719

# all_connected on a top input-port net: the port drives the net and the
# core0 instance input pin is the receiver. Bus-concatenation pins must not
# misalign the parser (core0/nv_dbgo_halted must NOT appear here). Expect
# driver: nv_entropy_valid (port), receiver: core0/nv_entropy_valid.
all_connected nv_entropy_valid

# all_connected is scoped like get_net (no -hier): a bare name matches only the
# top-level net, not same-named nets reused in submodules. all_connected n77
# must report a single top-level net n77 (driver U18/Z), not the 38 cross-scope
# n77 nets. A hierarchical reference scopes to that module.
all_connected n77
all_connected core0/w0/nv_c0/c0/bht0/n77
puts "=========================================="
puts "report_net / report_pin non-reg checks (G4)"
puts "=========================================="
# report_net reports a single scoped net: drivers, receivers and the full
# connected-pin list. It is scoped like get_net/all_connected (no -hier), so a
# full hierarchical reference reports only that scope's net.
#   core0/w0/nv_c0/c0/iu0/n20719 has a single driver U28571/ZN and one receiver
#   U28630/A1 (must NOT collapse same-named nets from sibling scopes).
report_net core0/w0/nv_c0/c0/iu0/n20719
# A top input-port net: driver is the port, receiver is the core0 input pin.
# Bus-concatenation pins must not misalign the parser.
report_net nv_entropy_valid
# report_net is scoped like get_net (no -hier): a bare name matches only the
# top-level net, not same-named nets reused in submodules.
report_net n77
report_net core0/w0/nv_c0/c0/bht0/n77
# A net that does not exist reports an error.
report_net core0/w0/nv_c0/c0/iu0/no_such_net
# report_pin reports a single instance pin: its direction, the net it is on,
# and that net's drivers/receivers. Leaf-cell pin directions come from LEF.
#   core0/w0/nv_c0/c0/iu0/U28571/ZN is the OUTPUT driver of n20719.
report_pin core0/w0/nv_c0/c0/iu0/U28571/ZN
#   core0/w0/nv_c0/c0/iu0/U28630/A1 is an INPUT receiver on n20719.
report_pin core0/w0/nv_c0/c0/iu0/U28630/A1
# Hierarchical-instance pin directions come from the module port declaration.
#   core0/nv_entropy_valid is an INPUT pin of the core0 hierarchical instance
#   on the nv_entropy_valid net.
report_pin core0/nv_entropy_valid

puts "=========================================="
puts "ECO non-reg checks (E1-E4)"
puts "=========================================="

# E1-E4 ECO flow: create a new net, create a buffer in the same scope, move a
# receiver from an existing net to the new net through the buffer, then verify
# with get_net/all_connected. Uses net core0/w0/nv_c0/c0/iu0/n20719 which has a
# single driver U28571/ZN and one receiver U28630/A1 before the ECO.
#
# E1 create_net: new net n_eco in scope core0/w0/nv_c0/c0/iu0.
create_net core0/w0/nv_c0/c0/iu0/n_eco

# E2 create_cell: instantiate a buffer in the same scope.
create_cell core0/w0/nv_c0/c0/iu0/u_eco_buf BUFFD10BWP300H8P64PDLVT

# E3 disconnect_net: detach the receiver pin from the old net.
disconnect_net core0/w0/nv_c0/c0/iu0/n20719 core0/w0/nv_c0/c0/iu0/U28630/A1

# E4 connect_net: buffer output drives the new net, buffer input loads the old
# net, and the moved receiver now loads the new net.
connect_net core0/w0/nv_c0/c0/iu0/n_eco core0/w0/nv_c0/c0/iu0/u_eco_buf/Z
connect_net core0/w0/nv_c0/c0/iu0/n20719 core0/w0/nv_c0/c0/iu0/u_eco_buf/I
connect_net core0/w0/nv_c0/c0/iu0/n_eco core0/w0/nv_c0/c0/iu0/U28630/A1

# Verify: old net now has driver U28571/ZN and receiver u_eco_buf/I.
all_connected core0/w0/nv_c0/c0/iu0/n20719
# Verify: new net now has driver u_eco_buf/Z and receiver U28630/A1.
all_connected core0/w0/nv_c0/c0/iu0/n_eco
# Verify: the new net and cell are visible to the query commands.
get_net core0/w0/nv_c0/c0/iu0/n_eco
get_cell core0/w0/nv_c0/c0/iu0/u_*

set hier_dontshow { SNPS_CLOCK grnand2_tech68_ }
report_hierarchy_tree

exit
