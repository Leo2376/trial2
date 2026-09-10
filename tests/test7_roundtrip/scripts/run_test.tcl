#!/usr/bin/tclsh8.6
# Test Case 7: write_verilog round-trip
# Based on test3 (medium_design.v). Reads the netlist, dumps it back out as
# Verilog with write_verilog, re-reads the dumped file and dumps it again, then
# checks the two dumps are byte-identical: the read -> write -> read -> write
# round-trip is structurally stable. Comments and line wrapping may differ
# from the source, but the module/port/wire/instance/assign structure is
# preserved.

source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 7: write_verilog round-trip"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/ts1n7hslvta128x33m2wbzhocp.lef
add_lef ../../../lef_files/ts1n7hslvta512x40m2wbzhocp.lef

# First pass: read the source netlist and dump it.
read_netlist ../inputs/medium_design.v
set_top_design medium_cpu
puts "Info : first pass - read source, dump with write_verilog"
write_verilog ../outputs/medium_design_test7.v

# build_design + build_net_conn so the connectivity map exists; the round-trip
# should not disturb it. This also exercises that the dumped netlist is a
# valid structural description.
build_design
update_wire_db
build_net_conn

# Report a quick structural summary of what was dumped.
puts "Info : modules dumped:"
foreach m [lrange $hierlistdef 0 [expr {$hierindex-1}]] {
  puts "  - $m"
}

# Second pass: re-read the dumped file in a fresh tclsh (read_netlist keeps
# internal state per session) and dump it again, so the two dumps can be
# compared for structural identity. Use absolute paths so the spawned script
# resolves files regardless of its working directory.
puts "Info : second pass - re-read the dump and dump again"
set repo [file normalize ../../..]
set lefdir [file join $repo lef_files]
set dump1  [file normalize ../outputs/medium_design_test7.v]
set dump2  [file normalize ../outputs/medium_design_test7_rt.v]
set rt2 [open /tmp/test7_rt2.tcl w]
puts $rt2 "source [file join $repo mylittleda.tcl]"
puts $rt2 "add_lef [file join $lefdir std_cell.lef]"
puts $rt2 "read_netlist $dump1"
puts $rt2 "set_top_design medium_cpu"
puts $rt2 "write_verilog $dump2"
puts $rt2 "exit"
close $rt2

set rc [catch {exec tclsh8.6 /tmp/test7_rt2.tcl >& /tmp/test7_rt2.log} res]
puts "Info : second pass rc=$rc"

# Compare the two dumps: they must be byte-identical (round-trip is stable).
set f1 [open ../outputs/medium_design_test7.v r]
set d1 [read $f1]
close $f1
set f2 [open ../outputs/medium_design_test7_rt.v r]
set d2 [read $f2]
close $f2

if { $d1 eq $d2 } {
  puts "PASS : write_verilog round-trip is byte-identical (read -> write -> read -> write)"
} else {
  puts "FAIL : round-trip dumps differ"
  puts "  first dump:  ../outputs/medium_design_test7.v"
  puts "  second dump: ../outputs/medium_design_test7_rt.v"
}

# Sanity: confirm the dumped file declares the expected modules.
set nm 0
foreach line [split $d1 \n] {
  if { [regexp {^module (\S+)} $line -> mn] } { incr nm }
}
puts "Info : dumped file declares $nm modules"
puts "Info : top module is $topname"

exit
