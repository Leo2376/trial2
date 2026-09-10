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

set hier_dontshow { SNPS_CLOCK grnand2_tech68_ }
report_hierarchy_tree

exit
