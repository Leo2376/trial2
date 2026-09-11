#!/usr/bin/tclsh8.6
# Test Case 6: Liberty (.lib) import and sync-pin recovery
# Verifies that add_lib parses the technology liberty file and stores, per
# library cell, the set of synchronous (clock) pins. Flop clock pin is CP and
# SRAM clock pin is CLK. get_sync_pins is used to query the stored attribute.

source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 6: Liberty sync-pin import"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
add_lef ../../../lef_files/sram.lef
add_lib ../../../liberty_files/n7_tech.lib

puts "=========================================="
puts "sync pin queries"
puts "=========================================="

set ff_pins [get_sync_pins DFQD0]
puts "DFQD0 sync pins : $ff_pins"

set ram_pins [get_sync_pins TS1N7HSLVTA128X33M2WBZHOCP]
puts "TS1N7HSLVTA128X33M2WBZHOCP sync pins : $ram_pins"

set comb_pins [get_sync_pins AN2D1]
puts "AN2D1 sync pins (should be empty) : $comb_pins"

puts "=========================================="
puts "sync pin checks"
puts "=========================================="

set pass 1

if { [lsearch -exact $ff_pins CP] < 0 } {
  puts "FAIL: flop DFQD0 missing CP sync pin"
  set pass 0
} else {
  puts "PASS: flop DFQD0 has CP sync pin"
}

if { [lsearch -exact $ram_pins CLK] < 0 } {
  puts "FAIL: SRAM TS1N7HSLVTA128X33M2 missing CLK sync pin"
  set pass 0
} else {
  puts "PASS: SRAM TS1N7HSLVTA128X33M2 has CLK sync pin"
}

if { $comb_pins ne "" } {
  puts "FAIL: combinational AN2D1 has sync pins"
  set pass 0
} else {
  puts "PASS: combinational AN2D1 has no sync pins"
}

if { $pass } {
  puts "=========================================="
  puts "Test 6: PASS"
} else {
  puts "=========================================="
  puts "Test 6: FAIL"
}

exit
