
source mylittleda.tcl

# Load comprehensive standard cell library
add_lef lef_files/std_cell.lef

# Load RAM macros (SRAM with expanded bussed pins)
add_lef lef_files/ts1n7hslvta128x33m2wbzhocp.lef
add_lef lef_files/ts1n7hslvta128x33m4wbzhocp.lef
add_lef lef_files/ts1n7hslvta512x40m2wbzhocp.lef
add_lef lef_files/ts1n7hslvta512x40m4wbzhocp.lef
add_lef lef_files/tsdn7lvta128x64m4wbzhocp.lef

# Load I/O library
add_lef lef_files/tphn7_18gpio_15lm.lef

read_netlist cpu_syn.v
set_top_design cpucore5nvstrb_nl2
build_design

make_floorplan 500 400 0 0

place_instance  {core0/w0/cmem1/itagmem_0/x0_id0}  250 220 N
place_instance  {core0/w0/cmem1/itagmem_1/x0_id0}  280 220 N
place_instance  {core0/w0/cmem1/itagmem_2/x0_id0}  310 220 N
place_instance  {core0/w0/cmem1/itagmem_3/x0_id0}  340 220 N

place_instance  {core0/w0/cmem1/idatamemh_0/x0_id0} 250 260 N
place_instance  {core0/w0/cmem1/idatameml_0/x0_id0} 250 330 N
place_instance  {core0/w0/cmem1/idatamemh_1/x0_id0} 280 260 N
place_instance  {core0/w0/cmem1/idatameml_1/x0_id0} 280 330 N
place_instance  {core0/w0/cmem1/idatamemh_2/x0_id0} 310 260 N
place_instance  {core0/w0/cmem1/idatameml_2/x0_id0} 310 330 N
place_instance  {core0/w0/cmem1/idatamemh_3/x0_id0} 340 260 N
place_instance  {core0/w0/cmem1/idatameml_3/x0_id0} 340 330 N

place_instance  {core0/w0/cmem1/dtagcmem_0/x0_id0} 380 220 N
place_instance  {core0/w0/cmem1/dtagcmem_1/x0_id0} 410 220 N
place_instance  {core0/w0/cmem1/dtagcmem_2/x0_id0} 440 220 N
place_instance  {core0/w0/cmem1/dtagcmem_3/x0_id0} 470 220 N

place_instance  {core0/w0/cmem1/ddatamemh_0/x0_id0} 380 260 N 
place_instance  {core0/w0/cmem1/ddatameml_0/x0_id0} 380 330 N 
place_instance  {core0/w0/cmem1/ddatamemh_1/x0_id0} 410 260 N 
place_instance  {core0/w0/cmem1/ddatameml_1/x0_id0} 410 330 N 
place_instance  {core0/w0/cmem1/ddatamemh_2/x0_id0} 440 260 N 
place_instance  {core0/w0/cmem1/ddatameml_2/x0_id0} 440 330 N 
place_instance  {core0/w0/cmem1/ddatamemh_3/x0_id0} 470 260 N 
place_instance  {core0/w0/cmem1/ddatameml_3/x0_id0} 470 330 N

place_instance {core0/w0/nv_c0/c0/bht0/phtable/x0_id0}  1  10 N
 
add_halo 2 2
set_site_height 0.3
unplace_stdcell

set targetutilz 35

make_placement

redraw

make_lef cpu_syn.lef
export_def cpu_syn.def
export_dc_floorplan cpu_syn.dc_floorplan.tcl
make_lib cpu_syn.lib

set hier_dontshow { SNPS_CLOCK  grnand2_tech68_ }
report_hierarchy_tree

#report_net_connection core0/w0/nv_c0/c0/piped/fptoint_i/n2424

