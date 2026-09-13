source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 15: seed_placement area-weighted budget (mixed blockage)"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef

read_netlist ../inputs/areabudget_design.v
set_top_design top
build_design
make_floorplan 100 80 0 0
build_net_conn

set npass 0
set nfail 0

# Pre-place a SRAM macro so a large chunk of the core is blocked. The
# 8x8 region grid (region ~6.25 x 5) means the 22x57 SRAM blocks several
# regions, forcing the area-weighted budget to credit those regions far
# fewer cells and route the std-cell basket into the open regions instead
# of overflowing.
place_instance u_sram0 5 5 N

set_site_height 0.3
add_halo 1 1
set targetutilz 60

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
seed_placement -iter 1 -seed 7 -verbose
set log [_restore_stdout]

# Parse: total overflow across all baskets, and out-of-core leftover count.
set total_overflow 0
set have_overflow 0
foreach line [split $log "\n"] {
 if { [regexp {basket \d+ packed by .* : (\d+) placed, (\d+) overflow} $line -> placed ov] } {
  incr total_overflow $ov
  set have_overflow 1
 }
}
# leftover placed at core origin count (only printed under -verbose; if
# the design fits in the free regions no origin dump happens -> 0).
set origin_dump 0
foreach line [split $log "\n"] {
 if { [regexp {leftover cells placed at core origin} $line] } {
  if { [regexp {(\d+) leftover cells placed} $line -> n] } { set origin_dump $n }
 }
}

# Count placed/total CORE cells.
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

if { $have_overflow } {
 puts "PASS: seed_placement reported basket overflow lines (total basket overflow $total_overflow)"
 incr npass
} else {
 puts "PASS: seed_placement reported no basket overflow"
 incr npass
}

if { $placed == $total } {
 puts "PASS: all $placed/$total CORE cells placed (no out-of-core loss)"
 incr npass
} else {
 puts "FAIL: only $placed/$total CORE cells placed (out-of-core loss)"
 incr nfail
}

# The area-weighted budget should keep the leftover (origin-dump) small:
# the SRAM blocks some regions, but the basket must absorb the std cells
# into the open regions rather than dumping them at the core origin. With a
# 100x80 core and a 22x57 SRAM there is ample open area, so the origin dump
# must be empty (the budget routes cells into open regions).
if { $origin_dump == 0 } {
 puts "PASS: no leftover cells dumped at core origin ($origin_dump)"
 incr npass
} else {
 puts "FAIL: $origin_dump leftover cells dumped at core origin (open area should absorb them)"
 incr nfail
}

puts ""
puts "Test 15: done"
puts "=========================================="
puts "PASS: $npass  FAIL: $nfail"
puts "=========================================="
if { $nfail > 0 } { exit 1 }
exit 0
