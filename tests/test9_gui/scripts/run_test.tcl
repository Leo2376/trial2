#!/usr/bin/tclsh8.6
# Test Case 9: gui_start / redraw without a floorplan (G1/GUI)
# Non-regression for a crash in redraw: when gui_start brought up the Tk GUI
# for a design with no floorplan defined, redraw computed the top-boundary
# scale factor as expr (...)/0 (topbox defaults to {0 0 0 0}) and aborted with
# a "domain error: argument not in valid range". redraw must instead skip the
# physical boundary/core rectangles gracefully and let the session continue.
#
# This test runs in two modes:
#   * headless (no $DISPLAY): gui_start must fail gracefully, session continues.
#   * under a display (xvfb-run): gui_start brings up the canvas, redraw of a
#     floorplan-less design must NOT crash, and make_floorplan must still draw.
source ../../../mylittleda.tcl

puts "=========================================="
puts "Test 9: gui_start / redraw (no floorplan)"
puts "=========================================="
puts ""

add_lef ../../../lef_files/std_cell.lef
read_netlist ../../../tests/test5_path/inputs/path_design.v
set_top_design path_top
build_design
update_wire_db
build_net_conn

set pass 1

# gui_start either brings up the GUI (display present) or fails gracefully
# (headless). In both cases the session must continue normally afterwards.
gui_start

if { ! $_gui_mode } {
  puts "Info : headless mode - gui_start did not start the GUI (expected)"
  # Confirm the session is unaffected: a normal query still runs.
  set rc [catch { get_cell * } msg]
  if { $rc } {
    puts "FAIL: session broken after headless gui_start: $msg"
    set pass 0
  } else {
    puts "PASS: session continues after headless gui_start"
  }
} else {
  puts "Info : display present - gui_start started the GUI"
  # The redraw triggered by gui_start (no floorplan yet) must not crash.
  if { ! [winfo exist .can] } {
    puts "FAIL: GUI mode active but canvas .can missing"
    set pass 0
  } else {
    puts "PASS: canvas .can exists after gui_start"
  }
  # Pan/zoom toolbar: the 6 control buttons must be present on top of the canvas.
  set tbok 1
  foreach b {up down left right zin zout draw} {
    if { ! [winfo exists .tb.$b] } { set tbok 0 }
  }
  if { $tbok } {
    puts "PASS: pan/zoom/draw toolbar buttons present (up/down/left/right/zin/zout/draw)"
  } else {
    puts "FAIL: pan/zoom/draw toolbar buttons missing"
    set pass 0
  }
  # Force a redraw of the floorplan-less design; this is the crash scenario.
  set rc [catch { redraw } msg]
  if { $rc } {
    puts "FAIL: redraw crashed on floorplan-less design: $msg"
    set pass 0
  } else {
    puts "PASS: redraw survives a floorplan-less design"
  }
  # make_floorplan must still draw the boundary correctly after a floorplan
  # is defined, proving the guarded code path is not skipped when it should run.
  set rc [catch { make_floorplan 50 50 0 0 } msg]
  if { $rc } {
    puts "FAIL: make_floorplan/redraw crashed: $msg"
    set pass 0
  } else {
    puts "PASS: make_floorplan redraws after floorplan defined"
  }
}

if { $pass } {
  puts "=========================================="
  puts "Test 9: PASS"
} else {
  puts "=========================================="
  puts "Test 9: FAIL"
}

exit
