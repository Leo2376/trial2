#!/usr/bin/tclsh8.6
# Test Case 8: write_db / restore_db (N2/N3)
# Based on test3 (medium_design.v): loads the design fully (read_netlist ->
# set_top_design -> build_design -> build_net_conn), runs write_db, then in a
# fresh tclsh session runs restore_db and checks that every query command
# (get_cells, get_nets, all_connected, report_net, report_pin, get_lib_cells)
# returns identical results to the original session. The saved file must
# contain 100% of the database (instances, wires, positions, the net
# connectivity map, LEF library, ports, assigns) so restore_db is a strict
# faster substitute for the parse/build path.
source ../../../mylittleda.tcl
puts "=========================================="
puts "Test 8: write_db / restore_db"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef
read_netlist ../inputs/medium_design.v
set_top_design medium_cpu
build_design
build_net_conn

set repo   [file normalize ../../..]
set lefdir [file join $repo lef_files]
set dbfile [file normalize ../outputs/medium_design_test8.db]

# Query script shared by both sessions: run a fixed list of query commands and
# write their stdout (captured by redirecting puts) to the file in $::qout.
# This runs inside the engine namespace so the queries see the restored state.
set qscript /tmp/test8_query.tcl
set qf [open $qscript w]
puts $qf {rename puts _puts_orig}
puts $qf {set _qf [open $::qout w]}
# Redirect every puts to the capture file, honouring -nonewline and an explicit
# channel (engine banner lines from a sourced engine are not re-emitted here
# since the engine is already loaded before this script runs).
puts $qf {proc puts {args} {
  global _qf _puts_orig
  set nl 0
  if {[lindex $args 0] eq "-nonewline"} { set nl 1; set args [lrange $args 1 end] }
  if {[llength $args] == 2} { set args [lrange $args 1 end] }
  set s [join $args]
  if {$nl} { _puts_orig -nonewline $_qf $s } else { _puts_orig $_qf $s }
}}
puts $qf {proc _emit {cmd} { global _qf _puts_orig; set rc [catch {uplevel 1 $cmd} res]; if {$rc} { _puts_orig $_qf $res } }}
puts $qf {proc _emit_ret {cmd} { global _qf _puts_orig; set rc [catch {uplevel 1 $cmd} res]; if {$rc} { _puts_orig $_qf $res } else { _puts_orig $_qf $res } }}
puts $qf {set sep ===========================================================}
foreach q {
  {get_cells *}
  {get_cells * -hier}
  {get_nets *}
  {get_nets * -hier}
  {all_connected alu_result}
  {report_net alu_result}
  {report_pin alu/and0/Z}
  {report_pin alu/result}
  {get_lib_cells AN2*}
} {
  puts $qf "_puts_orig \$_qf \$sep"
  puts $qf "_puts_orig \$_qf {CMD: $q}"
  if { [regexp {^get_(cell|net|lib_cell)} $q] } {
    puts $qf "_emit_ret {$q}"
  } else {
    puts $qf "_emit {$q}"
  }
}
puts $qf {close $_qf}
puts $qf {rename puts _puts_gone}
puts $qf {rename _puts_orig puts}
puts $qf {exit}
close $qf

# Session 1: the full parse/build path, capture the same queries as the
# reference (golden) output.
set s1 [open /tmp/test8_s1.tcl w]
puts $s1 "source [file join $repo mylittleda.tcl]"
puts $s1 "add_lef [file join $lefdir std_cell.lef]"
puts $s1 "add_lef [file join $lefdir sram.lef]"
puts $s1 "read_netlist [file normalize ../inputs/medium_design.v]"
puts $s1 "set_top_design medium_cpu"
puts $s1 "build_design"
puts $s1 "build_net_conn"
puts $s1 "set ::qout /tmp/test8_q1.out"
puts $s1 "source $qscript"
puts $s1 "exit"
close $s1
set rc [catch {exec tclsh8.6 /tmp/test8_s1.tcl >& /tmp/test8_s1.log} res]
puts "Info : session 1 (full build) rc=$rc"

# write_db from the current (already built) session.
write_db $dbfile
puts "Info : wrote db to $dbfile"

# Session 2: restore_db only (no read_netlist / build_design / build_net_conn),
# capture the same queries.
set s2 [open /tmp/test8_s2.tcl w]
puts $s2 "source [file join $repo mylittleda.tcl]"
puts $s2 "restore_db $dbfile"
puts $s2 "set ::qout /tmp/test8_q2.out"
puts $s2 "source $qscript"
puts $s2 "exit"
close $s2
set rc [catch {exec tclsh8.6 /tmp/test8_s2.tcl >& /tmp/test8_s2.log} res]
puts "Info : session 2 (restore_db) rc=$rc"

# Compare the two captured query outputs: they must be identical.
set f1 [open /tmp/test8_q1.out r]
set d1 [read $f1]
close $f1
set f2 [open /tmp/test8_q2.out r]
set d2 [read $f2]
close $f2
if { $d1 eq $d2 } {
  puts "PASS : restore_db reproduces full-build query output"
  puts "       (get_cells/get_nets/all_connected/report_net/report_pin/get_lib_cells)"
} else {
  puts "FAIL : restored query output differs from full-build output"
  puts "  session 1: /tmp/test8_q1.out"
  puts "  session 2: /tmp/test8_q2.out"
  set l1 [split $d1 \n]
  set l2 [split $d2 \n]
  for {set i 0} {$i < [llength $l1] && $i < [llength $l2]} {incr i} {
    if { [lindex $l1 $i] ne [lindex $l2 $i] } {
      puts "  first diff at line [expr {$i+1}]:"
      puts "    s1: [lindex $l1 $i]"
      puts "    s2: [lindex $l2 $i]"
      break
    }
  }
}

# Confirm the restore skipped the slow path: netconnbuilt must be set and the
# top name present without re-parsing.
set s3 [open /tmp/test8_s3.tcl w]
puts $s3 "source [file join $repo mylittleda.tcl]"
puts $s3 "restore_db $dbfile"
puts $s3 "puts \"CHK netconnbuilt=\$netconnbuilt top=\$topname insts=\$instindex\""
puts $s3 "exit"
close $s3
set rc [catch {exec tclsh8.6 /tmp/test8_s3.tcl >& /tmp/test8_s3.log} res]
puts "Info : $res"
exit
