#!/usr/bin/tclsh8.6
# Test Case 12: N4 (db integrity) / W2 (wirelen cache invalidation) /
#               P7 (report_path -limit / -max_depth) / G8 (report_design)
# Small structural design (one flop for sync tracing, one high-fanout buffer
# chain). Verifies the four new features without running the slow placement
# optimizers.
source ../../../mylittleda.tcl
puts "=========================================="
puts "Test 12: N4 / W2 / P7 / G8"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lib ../../../liberty_files/std_cell.lib
read_netlist ../inputs/feat_design.v
set_top_design feat_top
build_design
update_wire_db
build_net_conn

# ---------------------------------------------------------------------------
# G8 report_design
# ---------------------------------------------------------------------------
puts "=========================================="
puts "G8 report_design non-reg checks"
puts "=========================================="
# report_design must run after build_design. Capture its output to assert the
# expected counts. The design has 1 module, 5 leaf instances (1 flop + 4
# buffers) and 2 hierarchical instances (the assign statements become
# pseudo-hierarchical instances during read_netlist), 8 top ports, 2 assigns.
proc _capture_stdout {cmd} {
  rename puts _cap_puts_orig
  upvar 1 _capf _capf
  set _capf [open /tmp/test12_cap.out w]
  proc puts {args} {
    global _capf _cap_puts_orig
    set nl 0
    if {[lindex $args 0] eq "-nonewline"} { set nl 1; set args [lrange $args 1 end] }
    if {[llength $args] == 2} { set args [lrange $args 1 end] }
    set s [join $args]
    if {$nl} { _cap_puts_orig -nonewline $_capf $s } else { _cap_puts_orig $_capf $s }
  }
  uplevel 1 $cmd
  close $_capf
  # Destroy the capture puts (it exists now). A leftover _cap_puts_gone from a
  # previous call is removed first so the rename target is free.
  catch { rename _cap_puts_gone {} }
  rename puts _cap_puts_gone
  rename _cap_puts_orig puts
  return [split [exec cat /tmp/test12_cap.out] \n]
}
proc _g8val {lines key} {
  foreach l $lines {
    if {[string first $key $l] >= 0} {
      set t [lindex [split $l ":"] end]
      return [string trim $t]
    }
  }
  return ""
}

set g8 [_capture_stdout {report_design}]
set nleaf [_g8val $g8 "leaf instances"]
set nhier [_g8val $g8 "hier instances"]
set nports [_g8val $g8 "top ports"]
set nassigns [_g8val $g8 "assigns"]
# leaf instances = 1 flop + 4 buffers = 5
if {$nleaf == 5} {
  puts "PASS: report_design leaf instances = 5 (1 flop + 4 buffers)"
} else {
  puts "FAIL: report_design leaf instances expected 5, got '$nleaf'"
}
# hier instances = the 2 assign pseudo-instances (q, hi_net)
if {$nhier == 2} {
  puts "PASS: report_design hier instances = 2 (the two assigns)"
} else {
  puts "FAIL: report_design hier instances expected 2, got '$nhier'"
}
# top ports = clk, d, q, hi_in, o0, o1, o2, o3 = 8
if {$nports == 8} {
  puts "PASS: report_design top ports = 8"
} else {
  puts "FAIL: report_design top ports expected 8, got '$nports'"
}
# assigns = q = q_net, hi_net = hi_in  -> 2
if {$nassigns == 2} {
  puts "PASS: report_design assigns = 2"
} else {
  puts "FAIL: report_design assigns expected 2, got '$nassigns'"
}

# G8 high-fanout: set a threshold of 2, so hi_net (4 receivers) is high-fanout.
set_max_fanout 2
set g8b [_capture_stdout {report_design}]
set nhi [_g8val $g8b "high-fanout nets"]
# value parsing: "1 (threshold maxfanout=2)" -> first token is the count
set nhi_cnt [lindex $nhi 0]
if {$nhi_cnt == 1} {
  puts "PASS: report_design high-fanout nets = 1 (hi_net has 4 receivers > maxfanout 2)"
} else {
  puts "FAIL: report_design high-fanout nets expected 1, got '$nhi'"
}

# G8 guard: report_design before build_design must error cleanly (it needs
# level 2). Re-source in a fresh session to drop state.
set s_g [open /tmp/test12_g8g.tcl w]
puts $s_g "source ../../../mylittleda.tcl"
puts $s_g "add_lef ../../../lef_files/std_cell.lef"
puts $s_g "read_netlist ../inputs/feat_design.v"
puts $s_g "report_design"
puts $s_g "exit"
close $s_g
set g8g [exec tclsh8.6 /tmp/test12_g8g.tcl 2>@1]
if {[string first "no top design" $g8g] >= 0} {
  puts "PASS: report_design refuses to run before set_top_design/build_design"
} else {
  puts "FAIL: report_design should have refused before build_design"
}

# ---------------------------------------------------------------------------
# P7 report_path -limit / -max_depth
# ---------------------------------------------------------------------------
puts "=========================================="
puts "P7 report_path -limit / -max_depth non-reg checks"
puts "=========================================="
# Forward trace from clk should reach the flop CP sync endpoint. add_lib loaded
# the sync pins, so one sync endpoint is expected.
report_path -from clk
# -limit 0 means unlimited; with a real limit the count is capped (here only 1
# endpoint exists, so the message reports 1 and the (limited to N) note).
report_path -from clk -limit 1
# -max_depth 0 should behave as unlimited (find the endpoint). A depth of 1
# from clk: clk -> feat_ff/CP is one hop, so depth 1 still reaches it.
report_path -from clk -max_depth 1
# -max_depth 0 with -to: bogus option handling. A non-integer -limit must error.
report_path -from clk -limit abc
report_path -from clk -max_depth xyz

# Bad option is rejected.
report_path -from clk -bogus

# ---------------------------------------------------------------------------
# N4 write_db / restore_db integrity
# ---------------------------------------------------------------------------
puts "=========================================="
puts "N4 write_db / restore_db integrity non-reg checks"
puts "=========================================="
set dbfile [file normalize ../outputs/feat_test12.db]
file mkdir ../outputs
write_db $dbfile
# The db must carry a v2 header and a trailing "C <sum>" checksum line.
set fp [open $dbfile r]
set lines [split [read $fp] \n]
close $fp
set hdr1 [lindex $lines 0]
set hdr2 [lindex $lines 1]
set last [lindex $lines [expr {[llength $lines] - 2}]]
if {$hdr1 eq "# mylittleda db" && [regexp {# version 2} $hdr2]} {
  puts "PASS: db has v2 header ($hdr2)"
} else {
  puts "FAIL: db header unexpected: '$hdr1' / '$hdr2'"
}
if {[regexp {^C [0-9]+$} $last]} {
  puts "PASS: db has trailing checksum line: $last"
} else {
  puts "FAIL: db missing trailing checksum line, last='$last'"
}

# restore_db of a valid file succeeds and verifies the checksum.
set s_r [open /tmp/test12_restore.tcl w]
puts $s_r "source ../../../mylittleda.tcl"
puts $s_r "restore_db $dbfile"
puts $s_r "puts \"CHK top=\$topname insts=\$instindex\""
puts $s_r "exit"
close $s_r
set rout [exec tclsh8.6 /tmp/test12_restore.tcl 2>@1]
if {[string first "db integrity verified (v2 checksum ok)" $rout] >= 0 && [string first "CHK top=feat_top insts=5" $rout] >= 0} {
  puts "PASS: restore_db verifies v2 checksum and restores top=feat_top insts=5"
} else {
  puts "FAIL: restore_db output unexpected: $rout"
}

# Truncated db (drop the checksum line): restore_db must report a clear error.
exec head -n -1 $dbfile > /tmp/test12_trunc.db
set s_t [open /tmp/test12_restore_trunc.tcl w]
puts $s_t "source ../../../mylittleda.tcl"
puts $s_t "restore_db /tmp/test12_trunc.db"
puts $s_t "exit"
close $s_t
set tout [exec tclsh8.6 /tmp/test12_restore_trunc.tcl 2>@1]
if {[string first "db checksum missing (file truncated)" $tout] >= 0} {
  puts "PASS: restore_db detects truncated db (checksum missing)"
} else {
  puts "FAIL: restore_db should report checksum missing, got: $tout"
}

# Corrupted db (edit a body line): restore_db must report a checksum mismatch.
file copy -force $dbfile /tmp/test12_corrupt.db
set fc [open /tmp/test12_corrupt.db r+]
set content [read $fc]
# Replace the first scalar line's value to change its length without breaking
# the Tcl list grammar: prepend a marker to the topname value.
set content [string map {feat_top feat_top_CORRUPTED} $content]
seek $fc 0
puts -nonewline $fc $content
close $fc
set s_c [open /tmp/test12_restore_corrupt.tcl w]
puts $s_c "source ../../../mylittleda.tcl"
puts $s_c "restore_db /tmp/test12_corrupt.db"
puts $s_c "exit"
close $s_c
set cout [exec tclsh8.6 /tmp/test12_restore_corrupt.tcl 2>@1]
if {[string first "db checksum mismatch" $cout] >= 0} {
  puts "PASS: restore_db detects corrupted db (checksum mismatch)"
} else {
  puts "FAIL: restore_db should report checksum mismatch, got: $cout"
}

# A v1 db (no checksum) must still restore, with a warning.
set fv [open /tmp/test12_v1.db w]
puts $fv "# mylittleda db"
puts $fv "# version 1"
foreach l [lrange $lines 2 end-2] {
  if {$l ne ""} { puts $fv $l }
}
close $fv
set s_v [open /tmp/test12_restore_v1.tcl w]
puts $s_v "source ../../../mylittleda.tcl"
puts $s_v "restore_db /tmp/test12_v1.db"
puts $s_v "puts \"CHK v1 top=\$topname\""
puts $s_v "exit"
close $s_v
set vout [exec tclsh8.6 /tmp/test12_restore_v1.tcl 2>@1]
if {[string first "db version 1 has no integrity checksum" $vout] >= 0 && [string first "CHK v1 top=feat_top" $vout] >= 0} {
  puts "PASS: restore_db accepts v1 db with a no-checksum warning"
} else {
  puts "FAIL: restore_db v1 handling unexpected: $vout"
}

# ---------------------------------------------------------------------------
# W2 wirelen cache invalidation on placement change
# ---------------------------------------------------------------------------
puts "=========================================="
puts "W2 wirelen cache invalidation non-reg checks"
puts "=========================================="
# Make a floorplan and place the flop so a net has a real wire length, then
# move a cell and confirm the cached length is recomputed (not stale). We use
# report_net_wirelen before/after a place_instance move on a placed cell.
make_floorplan 50 40 0 0
place_instance feat_ff 5 5 N
place_instance b0 10 5 N
build_net_conn
set w0 [report_net_wirelen hi_net]
# hi_net connects hi_in (port, no coord) to b0/I etc; with b0 placed it may
# still be "" if fewer than 2 placed pins. Instead measure q_net which links
# feat_ff/Q (placed) to the q port (no coord) -> likely "". Use a net that
# spans two placed cells: none here directly, so instead assert the cache
# mechanism: after a placement move, the cache is cleared and a subsequent
# query recomputes from scratch. We force a known cache entry then move.
global _wirelen_cache
# Prime the cache for hi_net.
report_net_wirelen hi_net
set cached_before [info exists _wirelen_cache(hi_net)]
# Move a placed cell: this must invalidate the whole cache.
place_instance b0 12 7 N
set cached_after [info exists _wirelen_cache(hi_net)]
if {$cached_before && ! $cached_after} {
  puts "PASS: place_instance invalidated _wirelen_cache (entry dropped on move)"
} else {
  puts "FAIL: place_instance should invalidate cache (before=$cached_before after=$cached_after)"
}
# Recompute: the entry comes back (proving the cache is rebuilt, not broken).
report_net_wirelen hi_net
set cached_recomputed [info exists _wirelen_cache(hi_net)]
if {$cached_recomputed} {
  puts "PASS: wirelen cache rebuilt after re-query following invalidation"
} else {
  puts "FAIL: wirelen cache not rebuilt after re-query"
}

# unplace_stdcell must also invalidate the cache.
report_net_wirelen hi_net
unplace_stdcell
set cached_unplace [info exists _wirelen_cache(hi_net)]
if {! $cached_unplace} {
  puts "PASS: unplace_stdcell invalidated _wirelen_cache"
} else {
  puts "FAIL: unplace_stdcell should invalidate cache"
}

puts "=========================================="
puts "Test 12: done"
puts "=========================================="
exit
