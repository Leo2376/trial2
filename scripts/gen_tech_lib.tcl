#!/usr/bin/tclsh8.6
# Generator for the technology Liberty (.lib) file used by mylittleda.tcl.
#
# It walks the LEF files given on the command line, extracts every MACRO with
# its pin names and directions, and emits a single Liberty library. The only
# technology-specific timing intent captured here is the set of synchronous
# (clock) pins of sequential cells: the std-cell flop clock pin `CP` and the
# SRAM clock pin `CLK`. Those pins are tagged with `clock : true;` so the
# `add_lib` parser in mylittleda.tcl can recover them without any timing
# tables. All timing values are the scalar 0.1 (units: ns / pf / uW) to keep
# the file minimal and syntactically valid.
#
# Usage:  tclsh scripts/gen_tech_lib.tcl <lef...>  >  liberty_files/n7_tech.lib

# Pin names that identify a synchronous (clock) endpoint of a sequential cell.
set SYNC_PIN_NAMES {CP CLK}

if {$argv eq ""} {
    puts stderr "Error: no LEF files given"
    puts stderr "Usage: gen_tech_lib.tcl <lef...>"
    exit 1
}

set cells {}          ;# ordered list of cell names
array set cellpins {} ;# cell -> list of {pin direction}
array set cellclass {} ;# cell -> class (CORE/BLOCK/PAD)

foreach lef $argv {
    set fh [open $lef r]
    set macro ""
    set class "CORE"
    set pins {}
    set curpin ""
    set curdir ""
    while {[gets $fh line] >= 0} {
        set w [regexp -all -inline -- {\S+} $line]
        set a1 [lindex $w 0]
        set a2 [lindex $w 1]
        set a3 [lindex $w 2]
        set a4 [lindex $w 3]

        if {$a1 eq "MACRO"} {
            set macro $a2
            set class "CORE"
            set pins {}
            set curpin ""
            set curdir ""
            continue
        }
        if {$a1 eq "END" && $a2 eq $macro && $macro ne ""} {
            if {$curpin ne ""} { lappend pins [list $curpin $curdir] }
            set cellpins($macro) $pins
            set cellclass($macro) $class
            lappend cells $macro
            set macro ""
            set pins {}
            set curpin ""
            continue
        }
        if {$macro eq ""} { continue }
        if {$a1 eq "CLASS"} { set class $a2 }
        if {$a1 eq "PIN"} {
            if {$curpin ne ""} { lappend pins [list $curpin $curdir] }
            set curpin $a2
            set curdir "INPUT"
        }
        if {$a1 eq "DIRECTION" && $curpin ne ""} { set curdir $a2 }
    }
    close $fh
}

puts "library (n7_tech) {"
puts "  delay_model : table_lookup ;"
puts "  time_unit : \"1ns\" ;"
puts "  voltage_unit : \"1V\" ;"
puts "  current_unit : \"1mA\" ;"
puts "  pulling_resistance_unit : \"1kohm\" ;"
puts "  capacitive_load_unit (0.1, pf) ;"
puts "  leakage_power_unit : \"0.1uW\" ;"
puts ""

foreach cell $cells {
    set cl $cellclass($cell)
    puts "  cell ($cell) {"
    if {$cl eq "BLOCK"} {
        puts "    memory : \"true\" ;"
    }
    puts "    area : 0.1 ;"
    puts "    leakage_power : 0.1 ;"
    foreach pp $cellpins($cell) {
        set pn [lindex $pp 0]
        set pd [lindex $pp 1]
        set sync [expr {[lsearch -exact $SYNC_PIN_NAMES $pn] >= 0}]
        if {$pn ne ""} {
            puts "    pin ($pn) {"
            if {$pd eq "INPUT"}   { puts "      direction : input ;" }
            if {$pd eq "OUTPUT"}  { puts "      direction : output ;" }
            if {$pd eq "INOUT"}   { puts "      direction : inout ;" }
            if {$sync} {
                puts "      clock : true ;"
                puts "      capacitance : 0.1 ;"
            } else {
                puts "      capacitance : 0.1 ;"
                puts "      function : \"0\" ;"
            }
            puts "    }"
        }
    }
    puts "  }"
    puts ""
}
puts "}"
