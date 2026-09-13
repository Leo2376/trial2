source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 14: seed_placement expandparent anchor (top-residual fix)"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef

read_netlist ../inputs/expand_design.v
set_top_design top
build_design
make_floorplan 50 50 0 0
build_net_conn

set npass 0
set nfail 0

# Run seed_placement and capture the "free CORE cells, N top-residual" line.
# With the expandparent fix, the top-residual should be only the legitimate
# flat top-level cells (4 INVD1 + 1 DFQD0 = 5), NOT the ~34 direct-resident
# cells of big_mod (i0..i31 + bf0) that leak when big_mod is expanded.

proc _capture_stdout { } {
 catch { rename _cap_puts {} }
 rename puts _cap_puts
 proc puts { args } {
  if { [llength $args] >= 2 && [lindex $args 0] eq "-nonewline" } {
   set s [lindex $args 1]
  } else {
   set s [lindex $args 0]
  }
  global _caplog
  append _caplog $s "\n"
  return
 }
 global _caplog
 set _caplog ""
}

proc _restore_stdout { } {
 catch { rename puts {} }
 rename _cap_puts puts
 global _caplog
 return $_caplog
}

_capture_stdout
seed_placement -iter 1 -seed 1
set log [_restore_stdout]

# Parse the free-CORE / top-residual line.
set resid -1
set nfree -1
foreach line [split $log "\n"] {
 if { [regexp {Info : seed_placement, (\d+) free CORE cells, (\d+) top-residual} $line -> nf nr] } {
  set nfree $nf
  set resid $nr
  break
 }
}

# Count legitimate flat top-level CORE cells (those whose parent path is -1/empty).
# A CORE leaf cell is one whose refid resolves to a CORE lib cell. Field 4 is
# the placed flag, not a leaf flag, so do not filter on it (after seed_placement
# everything is placed).
global instindex _instlist _libcell
set legit_flat 0
for { set i 1 } { $i <= $instindex } { incr i } {
 set inst $_instlist($i)
 set refid [lindex $inst 8]
 if { ! [info exists _libcell($refid)] } { continue }
 if { [lindex $_libcell($refid) 4] ne "CORE" } { continue }
 set fp [lindex $inst 7]
 if { $fp eq "-1" || $fp eq "" } { incr legit_flat }
}

if { $nfree >= 0 } {
 puts "PASS: seed_placement ran, $nfree free CORE cells, top-residual $resid"
 incr npass
} else {
 puts "FAIL: did not find the free CORE / top-residual line in seed_placement output"
 incr nfail
}

# The legitimate flat cells are 4 INVD1 + 1 DFQD0 = 5.
if { $legit_flat == 5 } {
 puts "PASS: legitimate flat top-level cells = $legit_flat (4 INVD1 + 1 DFQD0)"
 incr npass
} else {
 puts "FAIL: expected 5 legitimate flat top-level cells, got $legit_flat"
 incr nfail
}

# Core assertion: top-residual must NOT include big_mod's direct-resident
# cells (the 32 inverters i0..i31 + flop bf0 = 34 cells). With the fix the
# residual equals the legitimate flat count; without the fix it is ~5 + 34.
# Allow a small margin (<= legit_flat) so any extra flat cell stays within it.
if { $resid >= 0 && $resid <= $legit_flat } {
 puts "PASS: top-residual $resid <= legitimate flat $legit_flat (big_mod direct-resident cells anchored, not leaked)"
 incr npass
} else {
 puts "FAIL: top-residual $resid > legitimate flat $legit_flat (big_mod direct-resident cells leaked to top-residual)"
 incr nfail
}

# Sanity: all free CORE cells were placed (no out-of-core / leftover dump).
# Field 4 is the placed flag (1 = placed), field 5/6 are x/y.
global instindex _instlist _libcell
set placed 0
set total 0
for { set i 1 } { $i <= $instindex } { incr i } {
 set inst $_instlist($i)
 set refid [lindex $inst 8]
 if { ! [info exists _libcell($refid)] } { continue }
 if { [lindex $_libcell($refid) 4] ne "CORE" } { continue }
 incr total
 if { [lindex $inst 4] == 1 } { incr placed }
}
if { $placed == $total } {
 puts "PASS: all $placed/$total CORE cells placed"
 incr npass
} else {
 puts "FAIL: only $placed/$total CORE cells placed"
 incr nfail
}

# Determinism: rerun with same seed, residual must be identical.
_capture_stdout
seed_placement -iter 1 -seed 1
set log2 [_restore_stdout]
# Determinism: unplace stdcells first (seed_placement only counts cells
# whose placed flag is 0, so a bare re-run would see 0 free cells), then
# rerun with the same seed and confirm the top-residual is identical.
unplace_stdcell
_capture_stdout
seed_placement -iter 1 -seed 1
set log2 [_restore_stdout]
set resid2 -1
foreach line [split $log2 "\n"] {
 if { [regexp {Info : seed_placement, (\d+) free CORE cells, (\d+) top-residual} $line -> nf nr] } {
  set resid2 $nr
  break
 }
}
if { $resid2 == $resid } {
 puts "PASS: seed_placement top-residual is deterministic after unplace ($resid == $resid2)"
 incr npass
} else {
 puts "FAIL: seed_placement top-residual differs after unplace ($resid != $resid2)"
 incr nfail
}

puts ""
puts "Test 14: done"
puts "=========================================="
puts "PASS: $npass  FAIL: $nfail"
puts "=========================================="
if { $nfail > 0 } { exit 1 }
exit 0
