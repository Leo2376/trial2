#!/usr/bin/tclsh
package require Tcl

# GUI mode is enabled with the -gui command-line option; otherwise batch mode.
# Usage: tclsh mylittleda.tcl -gui
set _gui_mode 0
if { [lsearch -exact $argv "-gui"] >= 0 } { set _gui_mode 1 }
if { $_gui_mode } {
  package require Tk
}

set tcl_prompt1 { puts -nonewline "mylittleda> "}

puts ""
puts " *******************************************************"
puts ""
puts "       My Little EDA"
puts "       Version 2025.09 for linux64 - Sep 10, 2025"
puts "       author: Leonardo Valencia"
puts ""
puts " *******************************************************"
puts ""

set app_width  1000
set app_height 1200
set app_dimension 1000x1200

if { $_gui_mode } {
  wm title . "Layout "
  wm geometry . $app_dimension
}

if { $_gui_mode } {
  if { [winfo exist .can] == 0} {
     canvas .can -background black -height $app_height -width $app_width
     pack .can
  }
}

# Initialize path tracing functionality (will be called after Tk mainloop starts)
# The tracing UI will be added when the user first uses tracing features


array set _libcell {}
array set _libcellpindir {}
array set _libsyncpin {}
set _libcellsync [ list ]
array set _instlist {}
array set _hinstlist {}
set _assignlist [ list ]
array set _blockagelist {}
array set _regionlist {}
array set _portlist {}
array set _porttype {}
array set _portmaster {}
array set _wirelist {}
array set _wiretype {}
array set _wiremaster {}
array set _wireinst {}
array set _wirelen_cache {}
array set _instpinconn1 {}
array set _instpinconn2 {}
array set _hinstpinconn1 {}
array set _hinstpinconn2 {}
array set _wirepinconn {}
array set _bumplist {}

set topname ""
set topnameid 0

set bumpindex 0
set cellindex 0
set hierindex 0
set instindex 0
set hinstindex 0
set portindex 0
set wireindex 0
set blockageindex 0
set regionindex 0


set cataloglist [ list ]
set hierlistdef [ list ]
set hierlist [ list ]
set pathlist [ list ]
set hpathlist [ list ]
set corebox [ list 0 0 0 0 ]
set topbox [ list 0 0 0 0 ]

set instrefsearch [ list ]
set hinstrefsearch [ list ]
set wiresearch [ list ]
array set wiresearch_map {}


set scale_f 0

# GUI view state for pan/zoom. _view_scale multiplies the auto-fit scale_f
# (1.0 = fit, 2.0 = zoomed in 2x, 0.5 = zoomed out 2x). _pan_dx/_pan_dy are
# the pan offset in screen pixels added on top of the scale transform.
set _view_scale 1.0
set _pan_dx 0.0
set _pan_dy 0.0

# GUI draw mode: "detail" draws every placed cell; "fast" skips cells whose
# on-screen size is less than 1/200th of the canvas, which speeds up redraw
# on designs with many small standard cells. _smallcell_cache marks, per lib
# cell refid, whether the cell is small at the current view scale (1 = small /
# filtered, 0 = draw); it is rebuilt at the top of each redraw.
set _draw_mode detail
array set _smallcell_cache {}

set gridutil [ list ]

set utlzmap  [ list ]
set hier_dontshow [ list clk_gate ]

set siteh 0.3

# Multithreading. Off by default: the Thread extension may not be installed on
# the host, so nothing multithreaded runs until set_multithread_on is called
# (which does 'package require Thread' and reports clearly if it is missing).
# _mt_on is 1 when enabled; _mt_workers is the worker count (default 8).
set _mt_on 0
set _mt_workers 8
set _mt_thread_loaded 0
# Counter for unique per-call tsv namespaces in the parallel site scan.
set _eval_sites_seq 0
# Parallel redraw: only the CORE std-cell rectangles are computed across
# worker threads (blockages/macros/bumps stay on the main thread so they stay
# in the background and Tk canvas calls are never made off-thread). The workers
# only compute screen coordinates and return them; the main thread issues the
# .can create calls in instance order. 4 slices, fixed.
set _redraw_seq 0

set fontsize 6

set targetutilz 65

set maxfanout 0

proc _require { level } {
 variable topname
 variable topnameid
 variable instindex
 variable hierindex
 variable cellindex
 variable corebox
 if { $level >= 1 && $topname eq "" } {
  puts "Error : no top design set, call 'set_top_design' before this command"
  return -code return
 }
 if { $level >= 2 && $hierindex == 0 } {
  puts "Error : design hierarchy not built, call 'build_design' before this command"
  return -code return
 }
 if { $level >= 3 && [lindex $corebox 2] == [lindex $corebox 0] } {
  puts "Error : no floorplan defined, call 'make_floorplan' before this command"
  return -code return
 }
}

proc build_design { } {
 variable topname
 _require 1
 variable topnameidt
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable _wireinst
 
 puts -nonewline "Info : build design , buiding hierarchy for " 
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"  			


 set topnameid -1
 expand_tree $topnameid 1 0 1

 # build hpathlist
 for { set i 1} { $i<= $hinstindex } { set i [expr $i +1] } {
   if { [lindex $_hinstlist($i) 7] == "-1" } { 
    set fullpath "[lindex $_hinstlist($i) 0]"
    } else {
    set fullpath "[lindex $_hinstlist($i) 7]/[lindex $_hinstlist($i) 0]"
   }    
  lappend hpathlist $fullpath
 }
 

 puts -nonewline "Info : build design , leaf cell path for " 
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"  			

 for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  #put in cache the related reference cell id
  set refname [lindex $_instlist($i) 1]
  set refid [lsearch  -exact $cataloglist $refname]
  incr refid
  lset _instlist($i) 8 $refid


  # full path update
  set topmodulename [lindex $_instlist($i) 2] 
  set topmodule_id [ get_cell_id $topmodulename ]
  if { $topmodulename == $topname } { 
      lset _instlist($i) 7 "-1"
      set fullpath "-1"
     } else { 
      # another unsued top
      if { $topmodule_id== "-1" } {continue } 
      # otherwise ..
      incr topmodule_id
      if { [lindex $_hinstlist($topmodule_id) 7] == "-1" } {
        set fullpath "[lindex $_hinstlist($topmodule_id) 0]"
       } else {
        set fullpath "[lindex $_hinstlist($topmodule_id) 7]/[lindex $_hinstlist($topmodule_id) 0]"
       }
      lset _instlist($i) 7 $fullpath
     }
     
  if { $fullpath == "-1" } {set instpath "[lindex $_instlist($i) 0]" } else {
                            set instpath "$fullpath/[lindex $_instlist($i) 0]" }
  lappend pathlist $instpath
  

 }
 puts ""
 puts -nonewline "Info : build design , building net usage data "  
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"   
 puts ""
 

 update_wire_db
 
}

proc report_hierarchy_tree { } {
 variable topname
 variable hierindex
 variable instindex
 _require 1
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist

 puts "************************************************************"
 puts " report_hierarchy : $topname "
 puts "************************************************************"
 
 set topnameid -1
 expand_tree $topnameid 1 1 0

}


proc expand_tree { instnameid depth display update } {
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable hier_dontshow

set subblockid [ list ]

if { $instnameid == -1 } { 
        set subblockid [ find_topchild ] 
        } else {
        set subblockid [ find_child $instnameid ] 
	}
	
set depth2 [expr $depth+1]

foreach blockid $subblockid { 
		          set instname [lindex $_hinstlist($blockid) 0]
                          set refname [lindex $_hinstlist($blockid) 1]
                          set fullpath [lindex $_hinstlist($blockid) 7]			 
			  
			  if { $display  == 1 } {		            
                            set hit 0
			    for { set j 0} { $j< [llength $hier_dontshow] } { incr j } { 
                               set hier_dont [lindex $hier_dontshow $j]
                               set ll [ expr [string length $hier_dont] -1 ]
			       set lcell [string range $refname 0 $ll ]
			       if { [string first $hier_dont $lcell] >= 0 } { set hit 1 }
                               }
			       
			    if {$hit == 0}  { 
				 for { set i 1} { $i<= $depth } { incr i } { puts -nonewline "  " }
			         puts "$instname      ( $refname )    ( $fullpath )"
				 }
			    }

			    
			  if { $update == 1 && $instnameid>=0 } {
			    set fatherpath    [lindex $_hinstlist($instnameid) 7] 
			    set blockinstname [lindex $_hinstlist($instnameid) 0]			    
			    if { $fatherpath == "-1" } { 
			         set fullname [lindex $_hinstlist($instnameid) 0] 
				 } else {
                                 set fullname "${fatherpath}/[lindex $_hinstlist($instnameid) 0]"
				 }
			    lset _hinstlist($blockid) 7 $fullname
			   }
			   
                          expand_tree $blockid $depth2 $display $update
                        }
} 

proc find_topchild { } {
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist

 set childlistid [ list ]
 set parentname  $topname
 
 for { set i 1} { $i<= $hinstindex } { set i [expr $i +1] } {
   if {  [lindex $_hinstlist($i) 2] == $parentname } { 
	  lappend childlistid [expr 0+$i]
	 }
 }
 return $childlistid
}


proc find_child { instid } {
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist

 set childlistid [ list ]
 set parentname  [lindex $_hinstlist($instid) 1]
 
 for { set i 1} { $i<= $hinstindex } { set i [expr $i +1] } {
   if {  [lindex $_hinstlist($i) 2] == $parentname } { 
	  lappend childlistid [expr 0+$i]
	 }
 }
 return $childlistid
}

proc set_top_design { name } {
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable hierlistdef
 variable _gui_mode

 if { $name eq "" } {
  puts "Error : set_top_design requires a module name"
  puts "Usage: set_top_design <module>"
  return
 }
 # A netlist must have been read first: hierlistdef holds the parsed module
 # names. Reject an unknown top so build_design does not fail later on an
 # empty / mistyped reference.
 if { [llength $hierlistdef] == 0 } {
  puts "Error : no netlist loaded, call 'read_netlist' before set_top_design"
  return
 }
 if { [lsearch -exact $hierlistdef $name] < 0 } {
  puts "Error : module $name not found in the loaded netlist"
  return
 }

 set topname $name

if { $_gui_mode } { wm title . "Layout : $name" }

 puts -nonewline "Info : top design cell is now "
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"  			
 
 puts ""
  
}
#############################################################
#
# GRAPHIC RENDER SECTION ( & RELATED ) 
#
#############################################################

# G1 (GUI) gui_start
# Bring up the Tk GUI from a session that was started in batch mode (i.e. not
# launched with -gui). Loads Tk if it is not already loaded, switches to GUI
# mode, creates the layout canvas, sets the window title (to the loaded top
# design if one is set, else a generic title) and redraws if a design has been
# built. After gui_start the session is in GUI mode: redraw and the canvas are
# available exactly as if the tool had been launched with -gui. In an
# interactive (REPL) session the window stays up while the prompt continues; in
# a scripted session the window lives for as long as the process runs.
proc gui_start { } {
 global _gui_mode app_width app_height app_dimension
 variable topname
 variable hierindex

 if { $_gui_mode } {
  puts "Info : GUI already active"
  if { [winfo exists .can] } { redraw }
  return
 }
 # Load Tk. If this fails (no display / Tk not installed) report and stay in
 # batch mode rather than aborting the session.
 if { [catch {package require Tk} err] } {
  puts "Error : cannot start GUI ($err)"
  puts "Info : a display is required (run under a physical display or xvfb-run)"
  return
 }
 set _gui_mode 1
 wm title . "Layout"
 wm geometry . $app_dimension
 if { ! [winfo exists .can] } {
  canvas .can -background black -height $app_height -width $app_width
  pack .can
 }
 _build_view_toolbar
 if { $topname ne "" } { wm title . "Layout : $topname" }
 puts "Info : GUI started"
 if { $hierindex > 0 } { redraw }
}

proc set_font_size { sz } {
 variable fontsize
 
 set $fontsize $sz
}

proc scalepx { sx } {
 variable scale_f
 global _pan_dx
 set offset_x [expr {20.0 + $_pan_dx}]
 set bl_x [expr $offset_x+$scale_f*$sx]
 return $bl_x
 }

proc scalepy { sy } {
 variable scale_f
 variable app_height
 global _pan_dy
 set wsizey $app_height
 set offset_y [expr {20.0 + $_pan_dy}]
 set bl_y [expr $offset_y+$scale_f*$sy]
 set bl_y [expr $wsizey-$bl_y]
 return $bl_y
 }


# GUI pan/zoom. Panning shifts the view by 10% of the canvas display size in
# the requested direction; zooming multiplies the current view scale by 2x
# (in) or 0.5 (out). Each helper updates the view state and redraws. The
# pan amount is 10% of app_width/app_height so the step scales with the window.
proc _view_pan { dir } {
 global _pan_dx _pan_dy app_width app_height
 set sx [expr {$app_width / 10.0}]
 set sy [expr {$app_height / 10.0}]
 switch -exact -- $dir {
  left  { set _pan_dx [expr {$_pan_dx + $sx}] }
  right { set _pan_dx [expr {$_pan_dx - $sx}] }
  up    { set _pan_dy [expr {$_pan_dy - $sy}] }
  down  { set _pan_dy [expr {$_pan_dy + $sy}] }
 }
 redraw
}

proc _view_zoom { factor } {
 global _view_scale
 set _view_scale [expr {$_view_scale * $factor}]
 redraw
}

proc _view_reset { } {
 global _view_scale _pan_dx _pan_dy
 set _view_scale 1.0
 set _pan_dx 0.0
 set _pan_dy 0.0
 redraw
}

# Toggle between detail (draw every cell) and fast (filter cells below
# 1/200th of the canvas) draw modes, then redraw. The button label is
# refreshed to show the active mode.
proc _view_toggle_draw { } {
 global _draw_mode
 if { $_draw_mode eq "detail" } {
  set _draw_mode fast
 } else {
  set _draw_mode detail
 }
 _update_draw_button
 redraw
}

proc _update_draw_button { } {
 global _draw_mode
 if { [winfo exists .tb.draw] } {
  .tb.draw configure -text "Draw: $_draw_mode"
 }
}

# Build the pan/zoom toolbar (a frame of buttons) on top of the canvas. Idempotent:
# created once, then left in place across redraws. The six buttons are arranged
# on a single row at the very top of the window.
proc _build_view_toolbar { } {
 if { [winfo exists .tb] } { return }
 frame .tb -background "#202020"
 button .tb.up    -text "\u2191" -command {_view_pan up}    -width 3
 button .tb.down  -text "\u2193" -command {_view_pan down}  -width 3
 button .tb.left  -text "\u2190" -command {_view_pan left}  -width 3
 button .tb.right -text "\u2192" -command {_view_pan right} -width 3
 button .tb.zin   -text "Zoom In 2x"  -command {_view_zoom 2.0}   -width 10
 button .tb.zout  -text "Zoom Out 2x" -command {_view_zoom 0.5}   -width 10
 button .tb.fit   -text "Fit" -command {_view_reset} -width 5
 button .tb.draw  -text "Draw: detail" -command {_view_toggle_draw} -width 12
 pack .tb -side top -fill x -before .can
 pack .tb.left -side left -padx 1 -pady 1
 pack .tb.up   -side left -padx 1 -pady 1
 pack .tb.down -side left -padx 1 -pady 1
 pack .tb.right -side left -padx 1 -pady 1
 pack .tb.zin  -side left -padx 4 -pady 1
 pack .tb.zout -side left -padx 4 -pady 1
 pack .tb.draw -side left -padx 4 -pady 1
 pack .tb.fit  -side right -padx 4 -pady 1
}


proc redraw { args } {
 variable _gui_mode
 # -verbose: print the per-stage Info messages (default is silent, so panning/
 # zooming do not spam the console).
 set verbose 0
 foreach a $args { if { $a eq "-verbose" } { set verbose 1 } }
 if { ! $_gui_mode } {
    if { $verbose } { puts "Info: REDRAW (batch mode - no GUI)" }
    return
 }
 _build_view_toolbar
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable bumpindex
 variable _bumplist
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable corebox
 variable topbox
 variable blockageindex
 variable _blockagelist
 variable regionindex
 variable _regionlist
 variable .can
 variable scale_f
 variable fontsize
 variable app_width
 variable app_height
 global _view_scale _pan_dx _pan_dy
 
 .can delete all

 if { $verbose } { puts "Info : REDRAW APR objects .." }
 
 # APR objects
 set wsizex $app_width
 set wsizey $app_height
 # Fit-to-window is computed against the base 20px margins (independent of
 # pan/zoom). _view_scale then multiplies that fit scale (1.0 = fit, 2.0 =
 # zoomed in 2x), and _pan_dx/_pan_dy shift the rendered view in screen
 # pixels by being folded into the margins used by every transform below.
 set base_off 20.0
 # Default margins with user pan folded in; the floorplan branch refines
 # offset_x/offset_y (and scale_f) below, but these defaults keep the
 # blockage/region/bump loops valid even with no floorplan.
 set offset_x [expr {$base_off + $_pan_dx}]
 set offset_y [expr {$base_off + $_pan_dy}]
 # top Boudary
 if { $verbose } { puts "Info : REDRAW top boundary .." }
 set bl_x [lindex $topbox 0]
 set bl_y [lindex $topbox 1]
 set tr_x [lindex $topbox 2]
 set tr_y [lindex $topbox 3]

 set scale_f  1
 if { $tr_x > 0 && $tr_y > 0 } {
  set scale_fx [expr ($wsizex-2.0*$base_off) / $tr_x ]
  set scale_fy [expr ($wsizey-2.0*$base_off) / $tr_y ]
  if { $scale_fx <  $scale_fy } { set scale_f $scale_fx }
  if { $scale_fx >= $scale_fy } { set scale_f $scale_fy }
  # Apply the user zoom factor (1.0 = fit-to-window).
  set scale_f [expr {$scale_f * $_view_scale}]
  # Fold the user pan into the margins used by every transform below.
  set offset_x [expr {$base_off + $_pan_dx}]
  set offset_y [expr {$base_off + $_pan_dy}]

  # Rebuild the small-cell cache for the current view scale. A lib cell is
  # "small" (filtered in fast mode) when its on-screen width AND height are
  # both less than 1/200th of the canvas. The cache is keyed by refid so the
  # per-instance loop below stays a cheap O(1) lookup.
  global _draw_mode _smallcell_cache
  array unset _smallcell_cache
  if { $_draw_mode eq "fast" } {
   set minx [expr {$wsizex / 200.0}]
   set miny [expr {$wsizey / 200.0}]
   for { set c 1 } { $c <= $cellindex } { incr c } {
    if { ! [info exists _libcell($c)] } { continue }
    set cw [lindex $_libcell($c) 1]
    set ch [lindex $_libcell($c) 2]
    if { $scale_f*$cw < $minx && $scale_f*$ch < $miny } {
     set _smallcell_cache($c) 1
    } else {
     set _smallcell_cache($c) 0
    }
   }
  }

  set bound_x [expr $offset_x+$scale_f*$tr_x]
  set bound_y [expr $offset_y+$scale_f*$tr_y]

  .can create rectangle $offset_x [expr $wsizey-$offset_y] $bound_x [expr $wsizey-$bound_y] -width 2 -outline "#b0b0b0"

 # core Boundary
 if { $verbose } { puts "Info : REDRAW top boundary .." }
  set bl_x [lindex $corebox 0]
  set bl_y [lindex $corebox 1]
  set tr_x [lindex $corebox 2]
  set tr_y [lindex $corebox 3]

  set bl_x [expr $offset_x+$scale_f*$bl_x]
  set bl_y [expr $offset_y+$scale_f*$bl_y]
  set tr_x [expr $offset_x+$scale_f*$tr_x]
  set tr_y [expr $offset_y+$scale_f*$tr_y]

  set bl_y [expr $wsizey-$bl_y]
  set tr_y [expr $wsizey-$tr_y]

  .can create rectangle $bl_x $bl_y $tr_x $tr_y -width 1 -outline "#606060" -fill "#303030"
 } else {
  if { $verbose } { puts "Info : no floorplan defined (run make_floorplan before redraw)" }
 }
 
 if { $verbose } { puts "Info : REDRAW placement blockage .." }
  for { set i 1} { $i<= $blockageindex } { set i [expr $i +1] } {
         set bl_x [lindex $_blockagelist($i) 1]
	 set bl_y [lindex $_blockagelist($i) 2]
	 set tr_x [lindex $_blockagelist($i) 3]
	 set tr_y [lindex $_blockagelist($i) 4]
	
         set bl_x [expr $offset_x+$scale_f*$bl_x]
         set bl_y [expr $offset_y+$scale_f*$bl_y]
         set tr_x [expr $offset_x+$scale_f*$tr_x]
         set tr_y [expr $offset_y+$scale_f*$tr_y]

         set bl_y [expr $wsizey-$bl_y]
         set tr_y [expr $wsizey-$tr_y]
	 
        .can create rectangle $bl_x $bl_y $tr_x $tr_y -width 1 -outline "#bb3300" -fill "#772000"
  
  }

 if { $verbose } { puts "Info : REDRAW placement regions .." }
  for { set i 1} { $i<= $regionindex } { set i [expr $i +1] } {
         set bl_x [lindex $_regionlist($i) 1]
	 set bl_y [lindex $_regionlist($i) 2]
	 set tr_x [lindex $_regionlist($i) 3]
	 set tr_y [lindex $_regionlist($i) 4]
	
         set bl_x [expr $offset_x+$scale_f*$bl_x]
         set bl_y [expr $offset_y+$scale_f*$bl_y]
         set tr_x [expr $offset_x+$scale_f*$tr_x]
         set tr_y [expr $offset_y+$scale_f*$tr_y]

         set bl_y [expr $wsizey-$bl_y]
         set tr_y [expr $wsizey-$tr_y]
	 
        .can create rectangle $bl_x $bl_y $tr_x $tr_y -width 1 -outline "#909010"
  
  }


 # cell placed 
 if { $verbose } { puts "Info : REDRAW placed instance .." }
 # Macros (BLOCK/PAD) are drawn on the main thread first so they stay in the
 # background; CORE std cells are collected and drawn afterwards (in parallel
 # when multithreading is on) so they sit on top of the macros.
 set core_list {}
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
   set inst $_instlist($i)
   if {  [lindex $inst 4] == 1 } {
         set orient [lindex $inst 9] 	 
         set refid  [lindex $inst 8] 	 
	 set szx [lindex $_libcell($refid) 1]
	 set szy [lindex $_libcell($refid) 2]
	 set class [lindex $_libcell($refid) 4]

         set outline "white" ; set blockfill "white"
         if {$class == "BLOCK"}  { set outline "#d0d0d0" ; set blockfill "#101010" }
         if {$class == "CORE" }  { set outline "#4888b8" ; set blockfill "#305074" }
         if {$class == "PAD"  }  { set outline "#339999" ; set blockfill "#305074" }

         # Fast-draw filter: small std cells (CORE) cached as below the
         # 1/200th-of-canvas threshold for the current view scale are skipped,
         # but 1 in 20 is still drawn so the floorplan does not look empty.
         # Macros (BLOCK/PAD) are always drawn regardless of mode. CORE cells
         # that survive the filter are queued for the (optionally parallel)
         # std-cell draw below, not drawn here.
         if { $class eq "CORE" } {
          if { $_draw_mode eq "fast" && [info exists _smallcell_cache($refid)] && $_smallcell_cache($refid) && ($i % 20) != 1 } { continue }
          lappend core_list [list $i [lindex $inst 5] [lindex $inst 6] $szx $szy $orient $refid]
          continue
         }
        	 
         if { $orient == "N" } {
          set bl_x [lindex $inst 5]
          set bl_y [lindex $inst 6]
          set tr_x [expr $bl_x+$szx]
          set tr_y [expr $bl_y+$szy]
          }

         if { $orient == "FN" } {
          set bl_x [lindex $inst 5]
          set bl_y [lindex $inst 6]
          set tr_x [expr $bl_x-$szx]
          set tr_y [expr $bl_y+$szy]
	  }

         if { $orient == "MY" } {
          set bl_x [lindex $inst 5]
          set bl_y [lindex $inst 6]
          set tr_x [expr $bl_x+$szx]
          set tr_y [expr $bl_y+$szy]
	  }

         if { $orient == "S" } {
          set bl_x [lindex $inst 5]
          set bl_y [lindex $inst 6]
          set tr_x [expr $bl_x+$szx]
          set tr_y [expr $bl_y-$szy]
	  }

         if { $orient == "FS" } {
          set bl_x [lindex $inst 5]
          set bl_y [lindex $inst 6]
          set tr_x [expr $bl_x-$szx]
          set tr_y [expr $bl_y-$szy]
	  }

         set bl_x [expr $offset_x+$scale_f*$bl_x]
         set bl_y [expr $offset_y+$scale_f*$bl_y]
         set tr_x [expr $offset_x+$scale_f*$tr_x]
         set tr_y [expr $offset_y+$scale_f*$tr_y]

         set bl_y [expr $wsizey-$bl_y]
         set tr_y [expr $wsizey-$tr_y]

	 
        .can create rectangle $bl_x $bl_y $tr_x $tr_y -width 1 -outline $outline


	#text
         if {$class == "BLOCK" && $szx < $szy} {
         set text [lindex $_libcell($refid) 0]
         set tx_y [expr $bl_y+($tr_y-$bl_y)/20 ]
         set tx_x [expr $tr_x-($tr_x-$bl_x)/4 ]
  
        .can create line      $bl_x $tx_y $tx_x $bl_y -width 1 -fill $outline	 
	
				 if { [expr $bl_y-$tr_y] > 300                              } { .can create text $tx_x $tx_y -text $text -fill $outline -angle 90 -justify left -anchor w -font {Helvetica -14 bold}}
 				 if { [expr $bl_y-$tr_y] >  70 && [expr $bl_y-$tr_y] <= 300 } { .can create text $tx_x $tx_y -text $text -fill $outline -angle 90 -justify left -anchor w -font {Helvetica -7 bold}}
				 if { [expr $bl_y-$tr_y] >  40 && [expr $bl_y-$tr_y] <=  70 } { .can create text $tx_x $tx_y -text $text -fill $outline -angle 90 -justify left -anchor w -font {Helvetica -5 bold}}
	                        
				
         }

         if {$class == "BLOCK" && $szx >= $szy} {
         set text [lindex $_libcell($refid) 0]
         set tx_y [expr $bl_y+($tr_y-$bl_y)/4 ]
         set tx_x [expr $bl_x+($tr_x-$bl_x)/20 ]

        .can create line      $bl_x $tx_y $tx_x $bl_y -width 1 -fill $outline	 

				 if { [expr $tr_x-$bl_x] > 300 			    } {  .can create text $tx_x $tx_y -text $text -fill $outline -angle 0 -justify left -anchor w -font {Helvetica -24 bold}}
				 if { [expr $tr_x-$bl_x] >  70 && [expr $tr_x-$bl_x] <= 300 } {  .can create text $tx_x $tx_y -text $text -fill $outline -angle 0 -justify left -anchor w -font {Helvetica -14 bold}}
				 if { [expr $tr_x-$bl_x] >  40 && [expr $tr_x-$bl_x] <=  70 } {  .can create text $tx_x $tx_y -text $text -fill $outline -angle 0 -justify left -anchor w -font {Helvetica -9 bold}}
	                        
	 }
         }
 }

 # CORE std cells: drawn after the macros so they sit on top. Computed across
 # 4 worker threads when multithreading is on (workers only compute coords; the
 # .can create calls run on the main thread in instance order), else serially.
 _redraw_core_cells $core_list $offset_x $offset_y $scale_f $wsizey "#4888b8"


 if { $verbose } { puts "Info : Bump redraw  .." }
  for { set i 1} { $i<= $bumpindex } { incr i } {

         set bl_x  [lindex $_bumplist($i) 2]
	 set bl_y  [lindex $_bumplist($i) 3]
	 
	 set cbump [lindex $_bumplist($i) 1]
	 
         .can create line  [scalepx [expr $bl_x-13-26]]  [scalepy [expr $bl_y +13   ]] \
	                   [scalepx [expr $bl_x-13   ]]  [scalepy [expr $bl_y +13+26]] \
	                   [scalepx [expr $bl_x+13   ]]  [scalepy [expr $bl_y +13+26]] \
	                   [scalepx [expr $bl_x+13+26]]  [scalepy [expr $bl_y +13   ]] \
	                   [scalepx [expr $bl_x+13+26]]  [scalepy [expr $bl_y -13   ]] \
	                   [scalepx [expr $bl_x+13   ]]  [scalepy [expr $bl_y -13-26]] \
	                   [scalepx [expr $bl_x-13   ]]  [scalepy [expr $bl_y -13-26]] \
	                   [scalepx [expr $bl_x-13-26]]  [scalepy [expr $bl_y -13   ]] \
			   [scalepx [expr $bl_x-13-26]]  [scalepy [expr $bl_y +13   ]] \
	                   -width 1 -fill $cbump
	
  }


 
 pack .can
 
}
proc add_bump { nbump bx by {cbump "yellow"} } {
 variable bumpindex 
 variable _bumplist
 incr bumpindex 
 set _bumplist($bumpindex) [list $nbump $cbump $bx $by ]
}


proc make_floorplan { widthx widthy corex corey } {
 variable topname
 _require 1
 variable corebox
 variable topbox

 puts -nonewline "Info : Initialize flooplan for design "
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts -nonewline "\033\[1;0m"  			
 puts ""
 
 set topbox [ list 0 0 $widthx $widthy ] 
 set a [ expr $widthx - $corex ]
 set b [ expr $widthy - $corey ]
 
 set corebox [ list $corex $corey $a $b ] 
 redraw
 puts ""

}

proc place_instance { cellinst posx posy orientation } {
 variable topname
 _require 2
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable corebox
 variable topbox
 variable pathlist
 
 set instid [lsearch -exact $pathlist $cellinst]
 
 incr instid

 lset _instlist($instid) 5 $posx
 lset _instlist($instid) 6 $posy
 lset _instlist($instid) 4 1
 lset _instlist($instid) 9 $orientation
   
}

proc remove_all_blockage { } {
 _require 2
 variable topname
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindexr
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable scale_f
 variable blockageindex
 variable _blockagelist
 variable utlzmap
 variable corebox
 
 set blockageindex 0
}


proc add_halo { marginx marginy } {
 variable topname
 _require 2
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable scale_f
 variable blockageindex
 variable _blockagelist
 variable utlzmap
 variable corebox
  
 # cell placed 
 puts "Info : Create Halo around hard macro .."
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
   set inst $_instlist($i)
   set orient [lindex $inst 9]     
   set refid  [lindex $inst 8]     
   set szx [lindex $_libcell($refid) 1]
   set szy [lindex $_libcell($refid) 2]
   set class [lindex $_libcell($refid) 4]
   
   if {  [lindex $inst 4] == 1 && $class=="BLOCK" } {
        	if { $orient == "N" } {
        	 set bl_x [lindex $inst 5]
        	 set bl_y [lindex $inst 6]
        	 set tr_x [expr $bl_x+$szx]
        	 set tr_y [expr $bl_y+$szy]
        	 }

        	if { $orient == "FN" } {
        	 set bl_x [lindex $inst 5]
        	 set bl_y [lindex $inst 6]
        	 set tr_x [expr $bl_x-$szx]
        	 set tr_y [expr $bl_y+$szy]
        	 }

        	if { $orient == "S" } {
        	 set bl_x [lindex $inst 5]
        	 set bl_y [lindex $inst 6]
        	 set tr_x [expr $bl_x+$szx]
        	 set tr_y [expr $bl_y-$szy]
        	 }

        	if { $orient == "FS" } {
        	 set bl_x [lindex $inst 5]
        	 set bl_y [lindex $inst 6]
        	 set tr_x [expr $bl_x-$szx]
        	 set tr_y [expr $bl_y-$szy]
        	 }

        	set bl_x [expr $bl_x-$marginx]
        	set bl_y [expr $bl_y-$marginy]
        	set tr_x [expr $tr_x+$marginx]
        	set tr_y [expr $tr_y+$marginy]
		
		set newblockage [ list $i $bl_x $bl_y $tr_x $tr_y ]
		set blockageindex [ expr $blockageindex + 1]
		
		set _blockagelist($blockageindex) $newblockage
		
           }
   }


  redraw

 puts "Info : add blockage map"

 # define empty list to store the blocked area of the design by blockages
 for { set searchx 0 } { $searchx < 100 } { set searchx [expr $searchx + 1] } {
     for { set searchy 0 } { $searchy < 100 } { set searchy [expr $searchy + 1] } {
        set sx [ expr [ lindex $corebox 0 ] + $searchx*([ lindex $corebox 2 ] - [ lindex $corebox 0 ])/100 ]
        set sy [ expr [ lindex $corebox 1 ] + $searchy*([ lindex $corebox 3 ] - [ lindex $corebox 1 ])/100 ]

        set hit 0
        for { set i 1} { $i<= $blockageindex } { set i [expr $i +1] } {
          set bl_x [lindex $_blockagelist($i) 1]
	  set bl_y [lindex $_blockagelist($i) 2]
	  set tr_x [lindex $_blockagelist($i) 3]
	  set tr_y [lindex $_blockagelist($i) 4]
	  
	 # if the search point is inside a blockagre enclosure then it is occupied
	  if { ($sx>$bl_x) && ($sx<$tr_x) && ($sy>$bl_y) && ($sy<$tr_y) } { set hit 1 }
	}       
       if {$hit == 1} { lappend utlzmap 1 } else { lappend utlzmap 0 }
 
     }
 }
 puts "" 
}

proc unplace_stdcell { } {
 variable topname
 _require 2
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist

 puts "Info : Unplace std cells .."
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
   set inst $_instlist($i)
   set orient [lindex $inst 9]     
   set refid  [lindex $inst 8]     
   set szx [lindex $_libcell($refid) 1]
   set szy [lindex $_libcell($refid) 2]
   set class [lindex $_libcell($refid) 4]
   
   if {  [lindex $inst 4] == 1 } {    
      if { $class=="BLOCK" } { } {
         if { $class=="PAD" } { } {
            lset _instlist($i) 4 0
	 }
      }
      
    }
   }
}


proc unplace_pad { } {
 variable topname
 _require 2
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
r variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist

 puts "Info : Unplace IO cells .."
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
   set inst $_instlist($i)
   set orient [lindex $inst 9]     
   set refid  [lindex $inst 8]     
   set szx [lindex $_libcell($refid) 1]
   set szy [lindex $_libcell($refid) 2]
   set class [lindex $_libcell($refid) 4]
   
   if {  [lindex $inst 4] == 1 } {     
      if { $class=="BLOCK" } { } {
           if { $class=="CORE" } { } {
              lset _instlist($i) 4 0
	   }
      }
      
    }
   }
}


proc set_site_height { height } {
 variable siteh
 set siteh $height
}

proc set_target_utilization { utilz } {
 variable targetutilz

set targetutilz $utilz
}

# set_multithread_on ?nworkers?
# Turn on internal multithreading by loading the Thread extension. If Thread is
# not installed on the host, report it clearly and stay single-threaded (no
# crash). An optional argument sets the worker count (default 8). After a
# successful call, multithreaded placement uses a pool of worker threads for
# the parallelizable stages (e.g. the placement-site utilization scan).
proc set_multithread_on { {nworkers ""} } {
 global _mt_on _mt_workers _mt_thread_loaded
 if { $_mt_on } {
  puts "Info : multithread already on ($_mt_workers workers)"
  return
 }
 if { $nworkers ne "" } {
  if { ! [string is integer -strict $nworkers] || $nworkers < 1 } {
   puts "Error : set_multithread_on requires a positive integer worker count (got '$nworkers')"
   return
  }
  set _mt_workers $nworkers
 }
 if { [catch {package require Thread} err] } {
  puts "Error : cannot enable multithread: the Thread extension is not installed ($err)"
  puts "Info : the tool stays single-threaded; install the 'thread' Tcl package to enable it"
  return
 }
 set _mt_thread_loaded 1
 set _mt_on 1
 puts "Info : multithread ON with $_mt_workers workers (Thread [package present Thread])"
}

# Turn off internal multithreading so subsequent stages run single-threaded.
# The worker count is kept so a later set_multithread_on can reuse it.
proc set_multithread_off { } {
 global _mt_on _mt_workers
 if { ! $_mt_on } {
  puts "Info : multithread already off"
  return
 }
 set _mt_on 0
 puts "Info : multithread OFF (placement now single-threaded)"
}

# Internal: scan one placement site's 20x20 utilization grid against the
# utlzmap (read-only during this scan, so parallel scans are safe). Returns the
# occupation count for that site. Factored out so it can run in a worker thread
# when multithreading is on.
proc _scan_site_utilz { psite bx by utlzmap } {
 set utlz 0
 for { set searchx 0 } { $searchx < 20 } { set searchx [expr {$searchx + 1}] } {
  for { set searchy 0 } { $searchy < 20 } { set searchy [expr {$searchy + 1}] } {
   set gx [expr {$bx + $searchx}]
   set gy [expr {$by + $searchy}]
   if { [lindex $utlzmap [expr {$gy + 100*$gx}]] == 1 } { incr utlz }
  }
 }
 return $utlz
}

# Internal: evaluate all placement-site occupation counts. site_coords is a list
# of {psite bx by} triples; utlzmap is read-only. Returns the per-site
# occupation list (in site order) and prints each site's percentage. Uses a
# worker pool when multithreading is on (Thread loaded), otherwise runs the
# scans serially. The scan is a pure read of utlzmap, so parallel execution is
# safe; results are gathered back on the main thread.
proc _eval_sites { site_coords utlzmap } {
 global _mt_on _mt_workers _mt_thread_loaded
 set msite {}
 if { $_mt_on && $_mt_thread_loaded } {
  # Use a unique shared-namespace per call so no stale results remain; the
  # Thread tsv API has no 'array unset', so we sidestep clearing entirely.
  # Each namespace must be initialised with tsv::array set before use.
  set ns site_eval[incr _eval_sites_seq]
  tsv::array set $ns counter 0
  # tsv::incr returns the post-increment value, so start at -1 so the first
  # worker-grabbed index is 0 (matches site_coords list indices).
  tsv::set $ns counter -1
  tsv::set $ns coords $site_coords
  tsv::set $ns utlzmap $utlzmap
  # Tell workers which namespace to use (avoids interpolating it into the
  # script body, so the worker script stays a clean brace-delimited string).
  tsv::array set site_eval_ns x 1
  tsv::set site_eval_ns cur $ns
  # done counter: workers increment it as they finish; the main thread waits
  # until it equals nw (thread::join does not fit this create/wait pattern).
  tsv::set site_eval_ns done 0
  set n [llength $site_coords]
  set nw [expr {$_mt_workers < $n ? $_mt_workers : $n}]
  set wscript {
   proc _wscan { bx by utlzmap } {
    set utlz 0
    for { set sx 0 } { $sx < 20 } { incr sx } {
     for { set sy 0 } { $sy < 20 } { incr sy } {
      set gx [expr {$bx + $sx}]
      set gy [expr {$by + $sy}]
      if { [lindex $utlzmap [expr {$gy + 100*$gx}]] == 1 } { incr utlz }
     }
    }
    return $utlz
   }
   set ns [tsv::get site_eval_ns cur]
   set coords [tsv::get $ns coords]
   set utzmap [tsv::get $ns utlzmap]
   while 1 {
    set i [tsv::incr $ns counter]
    if { $i >= [llength $coords] } { break }
    set trip [lindex $coords $i]
    set psite [lindex $trip 0]
    set bx [lindex $trip 1]
    set by [lindex $trip 2]
    tsv::set $ns result_$psite [_wscan $bx $by $utzmap]
   }
   tsv::incr site_eval_ns done
   thread::release
  }
  set workers {}
  for { set w 0 } { $w < $nw } { incr w } {
   lappend workers [thread::create $wscript]
  }
  # Wait for all workers to report done, then gather results in site order.
  while { [tsv::get site_eval_ns done] < $nw } { after 5 }
  foreach trip $site_coords {
   set psite [lindex $trip 0]
   set utlz [tsv::get $ns result_$psite]
   puts "Info : placement site $psite has occupation of [expr {$utlz/4}] %"
   lappend msite $utlz
  }
 } else {
  foreach trip $site_coords {
   set psite [lindex $trip 0]
   set bx [lindex $trip 1]
   set by [lindex $trip 2]
   set utlz [_scan_site_utilz $psite $bx $by $utlzmap]
   puts "Info : placement site $psite has occupation of [expr {$utlz/4}] %"
   lappend msite $utlz
  }
 }
 return $msite
}

# Internal: draw the CORE std-cell rectangles in parallel when multithreading is
# on, otherwise serially. blockages, macros (BLOCK/PAD) and bumps are NOT drawn
# here -- they are drawn on the main thread by redraw before/after this call so
# they stay in the background/foreground and Tk canvas calls are never made off
# the main thread. Workers only compute the screen coordinates of each CORE
# rectangle; the main thread issues the .can create rectangle calls in instance
# order so the layering is deterministic.
# core_list is a list of {i px py szx szy orient refid} entries (already filtered
# for the fast-draw small-cell cache); the transform params (offset_x, offset_y,
# scale_f, wsizey) are the same ones used everywhere else in redraw. The outline
# color is the CORE rectangle outline.
proc _redraw_core_cells { core_list offset_x offset_y scale_f wsizey outline } {
 global _mt_on _mt_thread_loaded _redraw_seq
 set n [llength $core_list]
 if { $n == 0 } { return }
 if { ! ($_mt_on && $_mt_thread_loaded) } {
  foreach c $core_list {
   set i [lindex $c 0]
   set px [lindex $c 1]
   set py [lindex $c 2]
   set szx [lindex $c 3]
   set szy [lindex $c 4]
   set orient [lindex $c 5]
   if { $orient == "N" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py+$szy}]
   } elseif { $orient == "FN" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px-$szx}]; set tr_y [expr {$py+$szy}]
   } elseif { $orient == "MY" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py+$szy}]
   } elseif { $orient == "S" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py-$szy}]
   } elseif { $orient == "FS" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px-$szx}]; set tr_y [expr {$py-$szy}]
   } else {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py+$szy}]
   }
   set bl_x [expr {$offset_x+$scale_f*$bl_x}]
   set bl_y [expr {$offset_y+$scale_f*$bl_y}]
   set tr_x [expr {$offset_x+$scale_f*$tr_x}]
   set tr_y [expr {$offset_y+$scale_f*$tr_y}]
   set bl_y [expr {$wsizey-$bl_y}]
   set tr_y [expr {$wsizey-$tr_y}]
   .can create rectangle $bl_x $bl_y $tr_x $tr_y -width 1 -outline $outline
  }
  return
 }
 # Parallel: 4 slices. Workers compute coords and stash them per index; the
 # main thread draws in instance order. Shared state via a unique tsv namespace.
 set ns rdraw[incr _redraw_seq]
 tsv::array set $ns counter 0
 tsv::set $ns counter -1
 tsv::set $ns corelist $core_list
 tsv::set $ns offx $offset_x
 tsv::set $ns offy $offset_y
 tsv::set $ns sf $scale_f
 tsv::set $ns wsy $wsizey
 tsv::array set rdraw_ns x 1
 tsv::set rdraw_ns cur $ns
 tsv::set rdraw_ns done 0
 set nw 4
 if { $nw > $n } { set nw $n }
 set wscript {
  set ns [tsv::get rdraw_ns cur]
  set corelist [tsv::get $ns corelist]
  set offx [tsv::get $ns offx]
  set offy [tsv::get $ns offy]
  set sf [tsv::get $ns sf]
  set wsy [tsv::get $ns wsy]
  set n [llength $corelist]
  while 1 {
   set i [tsv::incr $ns counter]
   if { $i >= $n } { break }
   set c [lindex $corelist $i]
   set idx [lindex $c 0]
   set px [lindex $c 1]
   set py [lindex $c 2]
   set szx [lindex $c 3]
   set szy [lindex $c 4]
   set orient [lindex $c 5]
   if { $orient == "N" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py+$szy}]
   } elseif { $orient == "FN" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px-$szx}]; set tr_y [expr {$py+$szy}]
   } elseif { $orient == "MY" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py+$szy}]
   } elseif { $orient == "S" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py-$szy}]
   } elseif { $orient == "FS" } {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px-$szx}]; set tr_y [expr {$py-$szy}]
   } else {
    set bl_x $px; set bl_y $py; set tr_x [expr {$px+$szx}]; set tr_y [expr {$py+$szy}]
   }
   set bl_x [expr {$offx+$sf*$bl_x}]
   set bl_y [expr {$offy+$sf*$bl_y}]
   set tr_x [expr {$offx+$sf*$tr_x}]
   set tr_y [expr {$offy+$sf*$tr_y}]
   set bl_y [expr {$wsy-$bl_y}]
   set tr_y [expr {$wsy-$tr_y}]
   tsv::set $ns crd_$idx [list $bl_x $bl_y $tr_x $tr_y]
  }
  tsv::incr rdraw_ns done
  thread::release
 }
 set workers {}
 for { set w 0 } { $w < $nw } { incr w } {
  lappend workers [thread::create $wscript]
 }
 while { [tsv::get rdraw_ns done] < $nw } { after 5 }
 # Draw in instance order so layering is deterministic regardless of which
 # worker computed which slice.
 foreach c $core_list {
  set idx [lindex $c 0]
  set crd [tsv::get $ns crd_$idx]
  .can create rectangle [lindex $crd 0] [lindex $crd 1] [lindex $crd 2] [lindex $crd 3] -width 1 -outline $outline
 }
}

proc make_placement { {opt "-full"} } {
 variable topname
 global _mt_on _mt_thread_loaded _mt_workers
 _require 3
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable targetutilz
 variable regionindex
 variable _regionlist

 set pregion 0

 # Announce the threading mode so the user can tell from the log whether
 # make_placement is running the parallel site scan (MT on) or serially.
 if { $_mt_on && $_mt_thread_loaded } {
  puts "Info : make_placement with multithread ON ($_mt_workers workers)"
 } else {
  puts "Info : make_placement single-threaded"
 }

 if { $opt == "-full" } { 
 puts "Info : Make Full placement ..."
 }

 if { $opt == "-region_only" } { 
 puts "Info : Make placement for regions only ... "
 set pregion 1
 }
 
 puts "Info : Using site heigh of $siteh um "
 puts " "
 
  set localinst 0
  for { set i 1} { $i <= $regionindex } { incr i } {
   set tr_x [ lindex $_regionlist($i) 3]
   set bl_x [ lindex $_regionlist($i) 1]
   set tr_y [ lindex $_regionlist($i) 4]
   set bl_y [ lindex $_regionlist($i) 2]
   
   set utilstepn [ expr   100.0 / ( [ lindex $_regionlist($i) 5] ) ]
   
   set px $bl_x
   set py $bl_y
   set lcell [ lindex $_regionlist($i) 6]
   
   puts "Info : make_placement, Start with Region placement [ lindex $_regionlist($i) 0] , target [ lindex $_regionlist($i) 5] % utilization"
   puts "Info : make_placement, bounding box $bl_x $bl_y $tr_x $tr_y  "
   
   for {set j 0} {$j < [llength $lcell] } {incr j} {
       set currentinst [lindex $lcell $j]
       set inst $_instlist($currentinst)
       set orient [lindex $inst 9]     
       set refid  [lindex $inst 8]     
       set szx [lindex $_libcell($refid) 1]
        
       lset _instlist($currentinst) 4 1
       lset _instlist($currentinst) 5 $px
       lset _instlist($currentinst) 6 $py
       set px [expr $px + $szx * $utilstepn ]
       if {$px> $tr_x} {set px $bl_x; set py [expr $py + $siteh ]}
       if {$py> $tr_y} { break }
       incr localinst
     }
   puts "Info : make_placement, Region placement [ lindex $_regionlist($i) 0] , Placed $localinst / $instindex cells "
    }


if { $pregion == 0 } {
 set msite [ list ]
 puts "Info : make_placement, placement sites evaluation "
 # Build the 25 site (bx,by) coordinate pairs once, then evaluate them.
 # _eval_sites scans each site's 20x20 grid against utlzmap (read-only),
 # using a worker pool when multithreading is on, otherwise serially. It
 # returns the per-site occupation list and prints each site's percentage.
 set site_coords {}
 for { set psite 0 } { $psite < 25 } { set psite [expr $psite + 1] } {
  set bx [expr {($psite % 5) * 20}]
  set by [expr {($psite / 5) * 20}]
  lappend site_coords [list $psite $bx $by]
 }
 set msite [_eval_sites $site_coords $utlzmap]

 set currentinst 0

 for { set npass 1 } { $npass < 10 } { set npass [expr $npass + 1] } {

 set utilstepn [ expr   100.0* $npass / ($targetutilz*1.0) ]
 set floor [expr ($npass-1)*10]
 set ceilling [expr ($npass-1)*10+10]
 

 puts "Info : make_placement, Pass $npass , target [expr 100.0/$utilstepn] % utilization"
 
 for { set psite 0 } { $psite < 25 } { set psite [expr $psite + 1] } {
  if { $psite == 0 } { set bx 0  ;  set by 0  }
  if { $psite == 1 } { set bx 20 ;  set by 0  }
  if { $psite == 2 } { set bx 40 ;  set by 0  }
  if { $psite == 3 } { set bx 60 ;  set by 0  }
  if { $psite == 4 } { set bx 80 ;  set by 0  }
  if { $psite == 5 } { set bx 0  ;  set by 20  }
  if { $psite == 6 } { set bx 20 ;  set by 20  }
  if { $psite == 7 } { set bx 40 ;  set by 20  }
  if { $psite == 8 } { set bx 60 ;  set by 20  }
  if { $psite == 9 } { set bx 80 ;  set by 20  }
  if { $psite == 10 } { set bx 0  ;  set by 40  }
  if { $psite == 11 } { set bx 20 ;  set by 40  }
  if { $psite == 12 } { set bx 40 ;  set by 40  }
  if { $psite == 13 } { set bx 60 ;  set by 40  }
  if { $psite == 14 } { set bx 80 ;  set by 40  }
  if { $psite == 15 } { set bx 0  ;  set by 60  }
  if { $psite == 16 } { set bx 20 ;  set by 60  }
  if { $psite == 17 } { set bx 40 ;  set by 60  }
  if { $psite == 18 } { set bx 60 ;  set by 60  }
  if { $psite == 19 } { set bx 80 ;  set by 60  }
  if { $psite == 20 } { set bx 0  ;  set by 80  }
  if { $psite == 21 } { set bx 20 ;  set by 80  }
  if { $psite == 22 } { set bx 40 ;  set by 80  }
  if { $psite == 23 } { set bx 60 ;  set by 80  }
  if { $psite == 24 } { set bx 80 ;  set by 80  }
  
  set utilz [lindex $msite $psite]
  set localinst 0
  
  set bl_x [ expr [ lindex $corebox 0 ] + $bx*([ lindex $corebox 2 ] - [ lindex $corebox 0 ])/100 ]
  set bl_y [ expr [ lindex $corebox 1 ] + $by*([ lindex $corebox 3 ] - [ lindex $corebox 1 ])/100 ]
  set tr_x [ expr [ lindex $corebox 0 ] + ($bx+20)*([ lindex $corebox 2 ] - [ lindex $corebox 0 ])/100 ]
  set tr_y [ expr [ lindex $corebox 1 ] + ($by+20)*([ lindex $corebox 3 ] - [ lindex $corebox 1 ])/100 ]

 if { [ expr $utilz / 4 ] >= $floor  && [ expr $utilz / 4 ] < $ceilling} {      
   set px $bl_x
   set py $bl_y
   puts "Info : make_placement, bounding box $bl_x $bl_y $tr_x $tr_y  "
   
   while { $py < $tr_y } {
     set px $bl_x
     while { $px < $tr_x } {
       if { $currentinst >= $instindex } { break } else { incr currentinst }
       set inst $_instlist($currentinst)
       set placed  [lindex $inst 4]
       if { $placed == 0} {
       incr localinst
       set orient [lindex $inst 9]     
       set refid  [lindex $inst 8]     
       set szx [lindex $_libcell($refid) 1]
       set class [lindex $_libcell($refid) 4]
    
        set hit 0
        for { set i 1} { $i<= $blockageindex } { set i [expr $i +1] } {
          set bbl_x [lindex $_blockagelist($i) 1]
	  set bbl_y [lindex $_blockagelist($i) 2]
	  set btr_x [lindex $_blockagelist($i) 3]
	  set btr_y [lindex $_blockagelist($i) 4]	  
	 # if the search point is inside a blockage then advance px by 2um
	  if { ($px>$bbl_x) && ($px<$btr_x) && ($py>$bbl_y) && ($py<$btr_y) } { set hit 1 ; set px [expr $px + 2] } 
	}       

        for { set i 1} { $i<= $regionindex } { set i [expr $i +1] } {
          set bbl_x [lindex $_regionlist($i) 1]
	  set bbl_y [lindex $_regionlist($i) 2]
	  set btr_x [lindex $_regionlist($i) 3]
	  set btr_y [lindex $_regionlist($i) 4]	  
	 # if the search point is inside a region then advance px by 2um
	  if { ($px>$bbl_x) && ($px<$btr_x) && ($py>$bbl_y) && ($py<$btr_y) } { set hit 1 ; set px [expr $px + 2] } 
	}       
    
       if {$class=="CORE" && $hit==0 } {
         lset _instlist($currentinst) 4 1
         lset _instlist($currentinst) 5 $px
         lset _instlist($currentinst) 6 $py
         set px [expr $px + $szx * $utilstepn ]   
        }
       }
       #placed
      }  
      set py [expr $py + $siteh ]   
     }
    }
    puts "Info : make_placement, Placed $localinst cells on placement site $psite " 
 }
 puts "Info : make_placement, Total after Pass $npass , Placed $currentinst / $instindex cells "
 puts ""
 }
 #partial pregion 0/1
 }
 
}

# Alternative placement engine: initial_placement. A row-based, blockage-aware
# placer that keeps the design within the target utilization but uses the
# available freedom to pack cells more evenly than the fixed 25-site scan of
# make_placement. Blockages and regions are honored: each row's usable spans
# are the gaps between blockages/regions that intersect that row, so no cell is
# ever placed on top of a macro/halo/region. The orientation is preserved (N).
#
# Algorithm:
#   1. Place region-bound cells first (same serial loop as make_placement) so
#      region constraints are respected.
#   2. Collect the remaining unplaced CORE instances.
#   3. Slice the core into horizontal rows of height $siteh. For each row build
#      the free spans (core bounds minus blockage/region overlaps at that row).
#   4. Distribute the free CORE cells across rows (longest-free-span first) and
#      pack each row left-to-right inside its spans, scaling the packing pitch
#      by the target utilization so density tracks $targetutilz.
#   5. When multithreading is on, the per-row packing runs across $mt_workers
#      worker threads (each owns a contiguous block of rows, with its own row
#      cursor, so no shared mutable state); workers stash (instid,px,py) in a
#      unique tsv namespace and the main thread commits _instlist in instance
#      order. Otherwise it runs serially.
#
# This is intentionally a separate command so make_placement stays available.
proc initial_placement { {opt "-full"} } {
 variable topname
 global _mt_on _mt_workers _mt_thread_loaded
 _require 3
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable targetutilz
 variable regionindex
 variable _regionlist

 set pregion 0
 if { $opt == "-region_only" } { set pregion 1 }

 # Threading mode banner.
 if { $_mt_on && $_mt_thread_loaded } {
  puts "Info : initial_placement with multithread ON ($_mt_workers workers)"
 } else {
  puts "Info : initial_placement single-threaded"
 }
 if { $opt == "-full" } { puts "Info : initial_placement (full) ..." }
 if { $opt == "-region_only" } { puts "Info : initial_placement (regions only) ..." }
 puts "Info : Using site height of $siteh um"

 # --- Step 1: region placement (serial, same as make_placement) ---
 for { set i 1 } { $i <= $regionindex } { incr i } {
  set tr_x [lindex $_regionlist($i) 3]
  set bl_x [lindex $_regionlist($i) 1]
  set tr_y [lindex $_regionlist($i) 4]
  set bl_y [lindex $_regionlist($i) 2]
  set utilstepn [expr {100.0 / [lindex $_regionlist($i) 5]}]
  set px $bl_x
  set py $bl_y
  set lcell [lindex $_regionlist($i) 6]
  puts "Info : initial_placement, region [lindex $_regionlist($i) 0] target [lindex $_regionlist($i) 5]% util"
  for { set j 0 } { $j < [llength $lcell] } { incr j } {
   set currentinst [lindex $lcell $j]
   set inst $_instlist($currentinst)
   set refid [lindex $inst 8]
   set szx [lindex $_libcell($refid) 1]
   lset _instlist($currentinst) 4 1
   lset _instlist($currentinst) 5 $px
   lset _instlist($currentinst) 6 $py
   set px [expr {$px + $szx * $utilstepn}]
   if {$px > $tr_x} { set px $bl_x; set py [expr {$py + $siteh}] }
   if {$py > $tr_y} { break }
  }
 }

 if { $pregion == 1 } { return }

 # --- Step 2: collect unplaced CORE instances ---
 set free_cells {}
 for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $inst 4] == 0 } {
   set refid [lindex $inst 8]
   set class [lindex $_libcell($refid) 4]
   if { $class eq "CORE" } {
    set szx [lindex $_libcell($refid) 1]
    lappend free_cells [list $i $szx]
   }
  }
 }
 set nfree [llength $free_cells]
 puts "Info : initial_placement, $nfree free CORE cells to place"
 if { $nfree == 0 } {
  puts "Info : initial_placement, nothing to place"
  return
 }

 # --- Step 3: build rows and their free spans ---
 set cb_x0 [lindex $corebox 0]
 set cb_y0 [lindex $corebox 1]
 set cb_x1 [lindex $corebox 2]
 set cb_y1 [lindex $corebox 3]
 set core_w [expr {$cb_x1 - $cb_x0}]
 if { $siteh <= 0 } { set siteh 0.3 }
 set nrows [expr {int(($cb_y1 - $cb_y0) / $siteh)}]
 if { $nrows < 1 } { set nrows 1 }

 # Precompute blockage/region boxes for span subtractions.
 set obs {}
 for { set i 1 } { $i <= $blockageindex } { incr i } {
  lappend obs [list [lindex $_blockagelist($i) 1] [lindex $_blockagelist($i) 2] [lindex $_blockagelist($i) 3] [lindex $_blockagelist($i) 4]]
 }
 for { set i 1 } { $i <= $regionindex } { incr i } {
  lappend obs [list [lindex $_regionlist($i) 1] [lindex $_regionlist($i) 2] [lindex $_regionlist($i) 3] [lindex $_regionlist($i) 4]]
 }

 # rows: each entry is {y0 spans} where spans is a list of {x0 x1} free spans.
 set rows {}
 for { set r 0 } { $r < $nrows } { incr r } {
  set ry0 [expr {$cb_y0 + $r * $siteh}]
  set ry1 [expr {$ry0 + $siteh}]
  # free spans start as the whole core width
  set spans [list [list $cb_x0 $cb_x1]]
  foreach b $obs {
   set bx0 [lindex $b 0]; set by0 [lindex $b 1]; set bx1 [lindex $b 2]; set by1 [lindex $b 3]
   if { $by1 <= $ry0 || $by0 >= $ry1 } { continue }
   set nsp {}
   foreach sp $spans {
    set sx0 [lindex $sp 0]; set sx1 [lindex $sp 1]
    if { $bx1 <= $sx0 || $bx0 >= $sx1 } { lappend nsp $sp; continue }
    if { $bx0 > $sx0 } { lappend nsp [list $sx0 $bx0] }
    if { $bx1 < $sx1 } { lappend nsp [list $bx1 $sx1] }
   }
   set spans $nsp
  }
  set rowlen 0
  foreach sp $spans { set rowlen [expr {$rowlen + [lindex $sp 1] - [lindex $sp 0]}] }
  lappend rows [list $ry0 $spans $rowlen]
 }

 # --- Step 4: distribute cells to rows and pack ---
 # Target utilization drives the packing pitch: a row's capacity is its free
 # length / (targetutilz/100). Distribute cells to the longest rows first.
 set row_order {}
 for { set r 0 } { $r < $nrows } { incr r } { lappend row_order $r }
 # sort rows by free span length (longest first) via a key list so the
 # round-robin distribution below prefers rows with the most room.
 set keyed {}
 for { set r 0 } { $r < $nrows } { incr r } {
  lappend keyed [list [lindex [lindex $rows $r] 2] $r]
 }
 set keyed [lsort -real -decreasing -index 0 $keyed]
 set row_order {}
 foreach k $keyed { lappend row_order [lindex $k 1] }
 # simple round-robin by cell count into rows (keeps rows balanced)
 set row_cells {}
 for { set r 0 } { $r < $nrows } { incr r } { lappend row_cells {} }
 set ri 0
 foreach c $free_cells {
  set idx [lindex $row_order $ri]
  lset row_cells $idx [linsert [lindex $row_cells $idx] end $c]
  set ri [expr {($ri + 1) % $nrows}]
 }

 # Pack each row. The pitch scales cell width by 100/targetutilz so a higher
 # target packs tighter; freedom: we cap pitch at 1.0 so cells never spread
 # beyond their natural width (no artificial gaps beyond utilization).
 set pitch [expr {100.0 / $targetutilz}]
 if { $pitch < 1.0 } { set pitch 1.0 }

 # result map: instid -> {px py}
 set result {}

 if { ! ($_mt_on && $_mt_thread_loaded) } {
  # --- Serial pack ---
  for { set r 0 } { $r < $nrows } { incr r } {
   set ry0 [lindex [lindex $rows $r] 0]
   set spans [lindex [lindex $rows $r] 1]
   set cells [lindex $row_cells $r]
   set ci 0
   set ncell [llength $cells]
   if { $ncell == 0 } { continue }
   foreach sp $spans {
    set sx0 [lindex $sp 0]; set sx1 [lindex $sp 1]
    set px $sx0
    while { $ci < $ncell && $px + [lindex [lindex $cells $ci] 1] <= $sx1 } {
     set cid [lindex [lindex $cells $ci] 0]
     lappend result [list $cid $px $ry0]
     set px [expr {$px + [lindex [lindex $cells $ci] 1] * $pitch}]
     incr ci
    }
    if { $ci >= $ncell } { break }
   }
  }
  foreach rec $result {
   set cid [lindex $rec 0]
   lset _instlist($cid) 4 1
   lset _instlist($cid) 5 [lindex $rec 1]
   lset _instlist($cid) 6 [lindex $rec 2]
  }
  puts "Info : initial_placement, placed [llength $result] / $nfree cells (serial)"
  return
 }

 # --- Parallel pack: each worker owns a contiguous block of rows ---
 set ns ipl[incr _eval_sites_seq]
 tsv::array set $ns counter 0
 tsv::set $ns counter -1
 tsv::set $ns rows $rows
 tsv::set $ns rowcells $row_cells
 tsv::set $ns pitch $pitch
 tsv::array set ipl_ns x 1
 tsv::set ipl_ns cur $ns
 tsv::set ipl_ns done 0
 set nw $_mt_workers
 if { $nw > $nrows } { set nw $nrows }
 set wscript {
  set ns [tsv::get ipl_ns cur]
  set rows [tsv::get $ns rows]
  set rowcells [tsv::get $ns rowcells]
  set pitch [tsv::get $ns pitch]
  set nrows [llength $rows]
  while 1 {
   set r [tsv::incr $ns counter]
   if { $r >= $nrows } { break }
   set ry0 [lindex [lindex $rows $r] 0]
   set spans [lindex [lindex $rows $r] 1]
   set cells [lindex $rowcells $r]
   set ci 0
   set ncell [llength $cells]
   if { $ncell == 0 } { continue }
   foreach sp $spans {
    set sx0 [lindex $sp 0]; set sx1 [lindex $sp 1]
    set px $sx0
    while { $ci < $ncell && $px + [lindex [lindex $cells $ci] 1] <= $sx1 } {
     set cid [lindex [lindex $cells $ci] 0]
     tsv::set $ns pl_$cid [list $px $ry0]
     set px [expr {$px + [lindex [lindex $cells $ci] 1] * $pitch}]
     incr ci
    }
    if { $ci >= $ncell } { break }
   }
  }
  tsv::incr ipl_ns done
  thread::release
 }
 set workers {}
 for { set w 0 } { $w < $nw } { incr w } {
  lappend workers [thread::create $wscript]
 }
 while { [tsv::get ipl_ns done] < $nw } { after 5 }
 # Gather: a cell that did not fit any of its row's spans has no pl_* key, so
 # use tsv::exists (not tsv::get, which would throw) and skip it. The leftover
 # cells are placed by a serial fallback pass below so the MT result is as
 # complete as the serial one.
 set placed 0
 set leftover {}
 # row index lookup by y0 and per-row used cursor (rightmost packed x).
 array set rowof {}
 for { set r 0 } { $r < $nrows } { incr r } {
  set rowof([format %.6f [lindex [lindex $rows $r] 0]]) $r
 }
 set rowused {}
 for { set r 0 } { $r < $nrows } { incr r } { lappend rowused 0 }
 foreach c $free_cells {
  set cid [lindex $c 0]
  if { [tsv::exists $ns pl_$cid] } {
   set pos [tsv::get $ns pl_$cid]
   set px [lindex $pos 0]; set py [lindex $pos 1]
   lset _instlist($cid) 4 1
   lset _instlist($cid) 5 $px
   lset _instlist($cid) 6 $py
   incr placed
   set r $rowof([format %.6f $py])
   set endx [expr {$px + [lindex $c 1]}]
   if { $endx > [lindex $rowused $r] } { lset rowused $r $endx }
  } else {
   lappend leftover $c
  }
 }
 # Serial fallback: pack any cells the workers could not fit into whichever
 # row still has room (resume each row's cursor after the MT-packed cells).
 # This mirrors the serial path so the final placement is as complete and
 # identical to single-thread as possible.
 foreach c $leftover {
  set cid [lindex $c 0]
  set szx [lindex $c 1]
  set done 0
  for { set r 0 } { $r < $nrows } { incr r } {
   set ry0 [lindex [lindex $rows $r] 0]
   set spans [lindex [lindex $rows $r] 1]
   set usex [lindex $rowused $r]
   foreach sp $spans {
    set sx0 [lindex $sp 0]; set sx1 [lindex $sp 1]
    set px [expr {$usex > $sx0 ? $usex : $sx0}]
    if { $px + $szx <= $sx1 } {
     lset _instlist($cid) 4 1
     lset _instlist($cid) 5 $px
     lset _instlist($cid) 6 $ry0
     lset rowused $r [expr {$px + $szx}]
     incr placed
     set done 1
     break
    }
   }
   if { $done } { break }
  }
 }
 puts "Info : initial_placement, placed $placed / $nfree cells (multithread, $nw workers)"
}

# Hierarchical placement engine: hier_placement.
#
# A research-informed ASIC placement strategy (recursive bisection / min-cut
# floorplanning, as in FengShui/mPG/APlace) that keeps hierarchy blocks
# together (coherency) instead of scattering a block's cells across the whole
# core. The core area is recursively bisected (alternating H/V cuts) into
# rectangular slots, hierarchy clusters are packed into slots sized by their
# total area (avoiding blockages/regions), and within each cluster the cells
# are recursively bisected again so connected cells stay close. Blockages and
# regions are honored everywhere: a slot that overlaps a blockage is shrunk or
# dropped so no cell is ever placed on a macro/halo/region.
#
# Multithreading is used the way that actually pays off for placement here:
# instead of parallelizing one tiny scan (where thread overhead dominates),
# each worker runs a COMPLETE placement trial from a different seed (different
# cluster ordering and bisection orientation sequence) and scores it by total
# estimated wire length. The main thread keeps the lowest-wirelength trial and
# commits it to _instlist. With MT off a single trial runs serially. This gives
# real coherency (hierarchy blocks kept together) and uses MT for a genuine
# quality search rather than a questionable speedup on a 20-cell design.
#
# Steps:
#   1. Place region-bound cells first (same serial loop as make_placement).
#   2. Collect the remaining unplaced CORE instances and group them by their
#      hierarchical parent path (_instlist field 7) into clusters; each cluster
#      records its member inst ids, total area and cell count.
#   3. Floorplan: recursively bisect the available core area into slots, assign
#      clusters to slots by area so each block gets a contiguous region.
#   4. Intra-cluster placement: recursively bisect each cluster's cells
#      (alternating H/V) and place them in a grid of sub-slots inside the
#      cluster's region, packed at the target utilization pitch.
#   5. MT: run several seeded trials in worker threads, score by wire length,
#      commit the best. Serial: run one trial.
proc hier_placement { {opt "-full"} } {
 variable topname
 global _mt_on _mt_workers _mt_thread_loaded
 _require 3
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable targetutilz
 variable regionindex
 variable _regionlist

 set pregion 0
 if { $opt == "-region_only" } { set pregion 1 }

 if { $_mt_on && $_mt_thread_loaded } {
  puts "Info : hier_placement with multithread ON ($_mt_workers seed trials)"
 } else {
  puts "Info : hier_placement single-threaded (1 seed trial)"
 }
 if { $opt == "-full" } { puts "Info : hier_placement (full) ..." }
 if { $opt == "-region_only" } { puts "Info : hier_placement (regions only) ..." }
 puts "Info : Using site height of $siteh um"

 # --- Step 1: region placement (serial, same as make_placement) ---
 for { set i 1 } { $i <= $regionindex } { incr i } {
  set tr_x [lindex $_regionlist($i) 3]
  set bl_x [lindex $_regionlist($i) 1]
  set tr_y [lindex $_regionlist($i) 4]
  set bl_y [lindex $_regionlist($i) 2]
  set utilstepn [expr {100.0 / [lindex $_regionlist($i) 5]}]
  set px $bl_x
  set py $bl_y
  set lcell [lindex $_regionlist($i) 6]
  puts "Info : hier_placement, region [lindex $_regionlist($i) 0] target [lindex $_regionlist($i) 5]% util"
  for { set j 0 } { $j < [llength $lcell] } { incr j } {
   set currentinst [lindex $lcell $j]
   set inst $_instlist($currentinst)
   set refid [lindex $inst 8]
   set szx [lindex $_libcell($refid) 1]
   lset _instlist($currentinst) 4 1
   lset _instlist($currentinst) 5 $px
   lset _instlist($currentinst) 6 $py
   set px [expr {$px + $szx * $utilstepn}]
   if {$px > $tr_x} { set px $bl_x; set py [expr {$py + $siteh}] }
   if {$py > $tr_y} { break }
  }
 }

 if { $pregion == 1 } { return }

 # --- Step 2: collect unplaced CORE instances and cluster by hierarchy ---
 set free_cells {}
 array set cellarea {}
 for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $inst 4] == 0 } {
   set refid [lindex $inst 8]
   set class [lindex $_libcell($refid) 4]
   if { $class eq "CORE" } {
    set szx [lindex $_libcell($refid) 1]
    set szy [lindex $_libcell($refid) 2]
    set area [expr {$szx * $szy}]
    set cellarea($i) [list $szx $szy $area]
    lappend free_cells $i
   }
  }
 }
 set nfree [llength $free_cells]
 puts "Info : hier_placement, $nfree free CORE cells to place"
 if { $nfree == 0 } {
  puts "Info : hier_placement, nothing to place"
  return
 }

 # Cluster by hierarchical parent path (field 7), but at a COARSE level so a
 # 100k+ cell flat-ish synthesis does not produce 100k single-cell clusters
 # (which would make bisection and the score loop nonsensical). We bucket by
 # the top two path segments of the parent path (the block-level hierarchy),
 # so a deep path like "core0/w0/cmem1/.../cell" maps to "core0/w0". Top-level
 # cells (fullpath == -1) map to "<top>". Tiny clusters (below a minimum cell
 # count) are then merged into a single "<misc>" bucket so no cluster is a
 # 1-cell fragment: the score loop and bisection only see meaningful blocks.
 array set cluster {}
 array set clusterarea {}
 array set clustern {}
 # min cluster size: a fraction of the design, but at least 4 cells so we
 # never keep single-cell clusters; cap so we don't merge everything on
 # small designs.
 set minc [expr {int($nfree / 50)}]
 if { $minc < 4 } { set minc 4 }
 if { $minc > 200 } { set minc 200 }
 foreach i $free_cells {
  set inst $_instlist($i)
  set fp [lindex $inst 7]
  if { $fp eq "-1" || $fp eq "" } {
   set key "<top>"
  } else {
   set segs [split $fp /]
   if { [llength $segs] >= 2 } {
    set key [join [lrange $segs 0 1] /]
   } else {
    set key $fp
   }
  }
  lappend cluster($key) $i
  set a [lindex $cellarea($i) 2]
  if { [info exists clusterarea($key)] } {
   set clusterarea($key) [expr {$clusterarea($key) + $a}]
   set clustern($key) [expr {$clustern($key) + 1}]
  } else {
   set clusterarea($key) $a
   set clustern($key) 1
  }
 }
 # merge clusters below minc into <misc>, keeping the big blocks coherent.
 set smallkeys {}
  set bigkeys {}
 foreach k [array names cluster] {
  if { $clustern($k) < $minc } { lappend smallkeys $k } else { lappend bigkeys $k }
 }
 if { [llength $smallkeys] > 1 } {
  set misc "<misc>"
  set cluster($misc) {}
  set clusterarea($misc) 0
  set clustern($misc) 0
  foreach k $smallkeys {
   foreach i $cluster($k) { lappend cluster($misc) $i }
   set clusterarea($misc) [expr {$clusterarea($misc) + $clusterarea($k)}]
   set clustern($misc) [expr {$clustern($misc) + $clustern($k)}]
   unset cluster($k) clusterarea($k) clustern($k)
  }
 }
 set cnames [array names cluster]
 puts "Info : hier_placement, [llength $cnames] hierarchy clusters (min cluster size $minc)"
 foreach c $cnames {
  puts "Info :   cluster $c : $clustern($c) cells, area [format %.4g $clusterarea($c)] um^2"
 }

 # Blockage + region boxes to avoid (same as initial_placement).
 set obs {}
 for { set i 1 } { $i <= $blockageindex } { incr i } {
  lappend obs [list [lindex $_blockagelist($i) 1] [lindex $_blockagelist($i) 2] [lindex $_blockagelist($i) 3] [lindex $_blockagelist($i) 4]]
 }
 for { set i 1 } { $i <= $regionindex } { incr i } {
  lappend obs [list [lindex $_regionlist($i) 1] [lindex $_regionlist($i) 2] [lindex $_regionlist($i) 3] [lindex $_regionlist($i) 4]]
 }

 set cb_x0 [lindex $corebox 0]
 set cb_y0 [lindex $corebox 1]
 set cb_x1 [lindex $corebox 2]
 set cb_y1 [lindex $corebox 3]
 if { $siteh <= 0 } { set siteh 0.3 }
 set pitch [expr {100.0 / $targetutilz}]
 if { $pitch < 1.0 } { set pitch 1.0 }

 # Build a connectivity index for intra-cluster ordering: inst id -> list of
 # connected inst ids (same net). Uses netdriver/netload if built, else empty.
 # This index only ORDERS cells within a cluster (BFS) so connected cells land
 # in the same bisection half; it is NOT a wirelength computation. To stay O(n)
 # on 100k+ cell designs we record, per net, a single anchor link (each pin
 # links to the first driver pin of that net) instead of the full O(k^2)
 # pairwise graph -- enough to bias the BFS ordering without the quadratic
 # blowup that hung large designs.
 set haveconn 0
 array set instconn {}
 global netconnbuilt netdriver netload
 if { [info exists netconnbuilt] && $netconnbuilt } {
  set haveconn 1
  # Map full instance path -> inst id (pathlist is 0-based, inst ids 1-based).
  array set pathid {}
  set pi 0
  foreach p $pathlist { set pathid($p) [expr {$pi + 1}]; incr pi }
  # Net keys can contain bit-select brackets (e.g. "alu/result[0]"), so any
  # subscript like $netload($n) or info exists netload($n) would parse the
  # brackets as command substitution. We walk both arrays via array get and
  # merge with dicts (string-keyed, no subscript parsing).
  set loaddict [array get netload]
  set driverdict [array get netdriver]
  foreach {n dval} [array get netdriver] {
   set anchor 0
   set lval {}
   if { [dict exists $loaddict $n] } { set lval [dict get $loaddict $n] }
   foreach p $dval {
    set ip [lindex $p 0]
    if { [info exists pathid($ip)] } {
     set id $pathid($ip)
     if { $anchor == 0 } { set anchor $id }
     if { $anchor != $id } { lappend instconn($id) $anchor }
    }
   }
   if { $anchor != 0 } {
    foreach p $lval {
     set ip [lindex $p 0]
     if { [info exists pathid($ip)] } {
      set id $pathid($ip)
      if { $anchor != $id } { lappend instconn($id) $anchor }
     }
    }
   }
  }
  foreach {n lval} [array get netload] {
   if { [dict exists $driverdict $n] } { continue }
   # net with loads but no driver: chain loads to the first load.
   set anchor 0
   foreach p $lval {
    set ip [lindex $p 0]
    if { [info exists pathid($ip)] } {
     set id $pathid($ip)
     if { $anchor == 0 } { set anchor $id }
     if { $anchor != $id } { lappend instconn($id) $anchor }
    }
   }
  }
 }

 # ---- Pure placement function for one seed trial. Returns a list of ----
 # ---- {instid px py} for all placed cells, and the wirelength score. ----
 # seed: integer controlling cluster ordering and bisection orientation.
 # This proc is defined inside hier_placement so it captures the local
 # arrays (cellarea, cluster, clusterarea, obs, corebox, siteh, pitch) and
 # the connectivity index. It is re-created each call (cheap) and used by
 # both the serial path and the MT workers (workers get it via tsv strings).
 proc _hp_place_trial { seed cellarea_v cluster_v clusterarea_v obs_v cb_x0 cb_y0 cb_x1 cb_y1 siteh pitch haveconn instconn_v } {
  array set cellarea $cellarea_v
  array set cluster $cluster_v
  array set clusterarea $clusterarea_v
  array set instconn $instconn_v
  set obs $obs_v

  # deterministic pseudo-random from seed (LCG)
  set rng $seed
  set rnd [list]
  # We don't need many draws; just provide a shuffle by sorting on a hash.

  # --- cluster ordering by this seed ---
  set cnames [array names cluster]
  # seed mod 2 picks sort key: 0 = area desc, 1 = area asc; different seeds
  # shuffle ties so the bisection assignment varies.
  set keymode [expr {$seed % 2}]
  set keyed {}
  foreach c $cnames {
   set ka $clusterarea($c)
   # mix the cluster name hash into the sort key so seeds differ even with
   # equal areas (different bisection leaf assignment).
   set h 0
   foreach ch [split $c {}] { set h [expr {($h*31 + [scan $ch %c 0]) & 0x7fffffff}] }
   set kh [expr {$h ^ ($seed * 2654435761)}]
   if {$keymode == 0} {
    lappend keyed [list [expr {-$ka}] $kh $c]
   } else {
    lappend keyed [list $ka $kh $c]
   }
  }
  set keyed [lsort -integer -index 1 $keyed]
  # secondary stable sort by the primary (area) key
  set keyed [lsort -real -index 0 $keyed]
  set corder {}
  foreach k $keyed { lappend corder [lindex $k 2] }

  # total free area + usable core area
  set totarea 0
  foreach c $cnames { set totarea [expr {$totarea + $clusterarea($c)}] }
  # usable core width/height shrunk away from blockages is approximate; use
  # the full core and let slot/blockage clipping handle overlaps.
  set cw [expr {$cb_x1 - $cb_x0}]
  set ch [expr {$cb_y1 - $cb_y0}]
  if {$cw <= 0 || $ch <= 0} { return [list 0 {}] }

  # --- recursive bisection of the core into slots, assign clusters ---
  # Each cluster gets a slot sized by its area fraction of totarea. We use a
  # shelf packer: walk the core left-to-right, top-to-bottom, allocating each
  # cluster a rectangle whose area matches its need, alternating the cut
  # direction by seed so different seeds give different layouts.
  # Returns: array slot($c) = {blx bly trx try}
  array set slot {}
  # Choose first cut orientation from seed.
  set firsthoriz [expr {($seed / 2) % 2}]
  # recursive bisection list of {area cluster box}
  # We bisect a box to fit a list of clusters by area, alternating cuts.
  proc _bisect { clist area blx bly trx try depth firsthoriz seed } {
   upvar slot slot
   if {[llength $clist] == 1} {
    set c [lindex $clist 0]
    set slot($c) [list $blx $bly $trx $try]
    return
   }
   # split clist into two halves by cumulative area (median).
   set half [expr {$area / 2.0}]
   set acc 0
   set left {}
   set right {}
   set la 0
   set found 0
   foreach c $clist {
    upvar clusterarea clusterarea
    if {!$found} {
     lappend left $c
     set acc [expr {$acc + $clusterarea($c)}]
     if {$acc >= $half} { set found 1; set la $acc }
    } else {
     lappend right $c
    }
   }
   set ra [expr {$area - $la}]
   if {$la == 0 || $ra == 0} {
    # degenerate: just assign sequentially
    foreach c $clist { set slot($c) [list $blx $bly $trx $try] }
    return
   }
   # choose cut direction: alternate by depth, but the starting orientation
   # depends on seed so trials differ. Favor the longer dimension.
   set horiz [expr {($depth + $firsthoriz) % 2}]
   set w [expr {$trx - $blx}]
   set h [expr {$try - $bly}]
   if {$horiz} {
    # horizontal cut (split Y): top/bottom
    set frac [expr {$la / $area}]
    if {$frac < 0.15} { set frac 0.15 }
    if {$frac > 0.85} { set frac 0.85 }
    set cuty [expr {$bly + $h * $frac}]
    _bisect $left $la $blx $bly $trx $cuty [expr {$depth+1}] $firsthoriz $seed
    _bisect $right $ra $blx $cuty $trx $try [expr {$depth+1}] $firsthoriz $seed
   } else {
    # vertical cut (split X): left/right
    set frac [expr {$la / $area}]
    if {$frac < 0.15} { set frac 0.15 }
    if {$frac > 0.85} { set frac 0.85 }
    set cutx [expr {$blx + $w * $frac}]
    _bisect $left $la $blx $bly $cutx $try [expr {$depth+1}] $firsthoriz $seed
    _bisect $right $ra $cutx $bly $trx $try [expr {$depth+1}] $firsthoriz $seed
   }
  }
  # total area of all clusters
  _bisect $corder $totarea $cb_x0 $cb_y0 $cb_x1 $cb_y1 0 $firsthoriz $seed
  # _bisect defined inside _hp_place_trial; rename away to avoid clash on
  # re-entry (proc is local to this trial).
  rename _bisect {}

  # --- intra-cluster placement: recursive bisection of cells into a grid ---
  proc _place_cells { ids blx bly trx try depth pitch siteh obs seed haveconn } {
   upvar cellarea cellarea
   upvar instconn instconn
   set n [llength $ids]
   if {$n == 0} { return [list] }
   if {$n == 1} {
    set cid [lindex $ids 0]
    return [list [list $cid $blx $bly]]
   }
   # small enough: just pack left-to-right in rows of siteh
   set w [expr {$trx - $blx}]
   set h [expr {$try - $bly}]
   if {$n <= 3 || $h < $siteh*1.5 || $w < 0.5} {
    set res {}
    set px $blx
    set py $bly
    foreach cid $ids {
     lassign $cellarea($cid) szx szy area
     if {$px + $szx*$pitch > $trx} { set px $blx; set py [expr {$py + $siteh}] }
     if {$py + $siteh > $try} {
      # overflow: force place at blx,py anyway (best effort)
      lappend res [list $cid $px $py]
      continue
     }
     lappend res [list $cid $px $py]
     set px [expr {$px + $szx*$pitch}]
    }
    return $res
   }
   # partition ids into two halves. If we have connectivity, order by a
   # simple connectedness heuristic (BFS from a seed cell) so connected cells
   # land in the same half; else order by id (median).
   if {$haveconn && $n > 1} {
    set ordered {}
    array set seen {}
    set queue [list [lindex $ids 0]]
    set seen([lindex $ids 0]) 1
    while {[llength $queue] > 0} {
     set cur [lindex $queue 0]
     set queue [lrange $queue 1 end]
     lappend ordered $cur
     if {[info exists instconn($cur)]} {
      foreach nb $instconn($cur) {
       if {[info exists seen($nb)]} { continue }
       # only follow links within this cluster's id set
       if {[lsearch -exact $ids $nb] >= 0} {
        set seen($nb) 1
        lappend queue $nb
       }
      }
     }
    }
    # append any unseen ids
    foreach cid $ids { if {![info exists seen($cid)]} { lappend ordered $cid } }
    set ids $ordered
   }
   set mid [expr {$n / 2}]
   set left [lrange $ids 0 [expr {$mid-1}]]
   set right [lrange $ids $mid end]
   # alternate cut direction by depth + seed
   set horiz [expr {($depth + $seed) % 2}]
   set w [expr {$trx - $blx}]
   set h [expr {$try - $bly}]
   if {$horiz} {
    set cuty [expr {$bly + $h*0.5}]
    set l [_place_cells $left $blx $bly $trx $cuty [expr {$depth+1}] $pitch $siteh $obs $seed $haveconn]
    set r [_place_cells $right $blx $cuty $trx $try [expr {$depth+1}] $pitch $siteh $obs $seed $haveconn]
   } else {
    set cutx [expr {$blx + $w*0.5}]
    set l [_place_cells $left $blx $bly $cutx $try [expr {$depth+1}] $pitch $siteh $obs $seed $haveconn]
    set r [_place_cells $right $cutx $bly $trx $try [expr {$depth+1}] $pitch $siteh $obs $seed $haveconn]
   }
   return [concat $l $r]
  }

  set placed {}
  foreach c $corder {
   if {![info exists slot($c)]} { continue }
   lassign $slot($c) sblx sbly strx stry
   # clip the slot against blockages: if the slot center is inside a
   # blockage, nudge it. Simpler: shrink slot to the largest sub-rectangle
   # not covered by any blockage (greedy). For small designs this is enough.
   foreach b $obs {
    lassign $b bx0 by0 bx1 by1
    # if blockage fully covers the slot vertically, split horizontally
    if {$by0 <= $sbly && $by1 >= $stry} {
     if {$bx0 > $sblx && $bx1 < $strx} {
      # blockage in the middle: keep the larger side
      set lw [expr {$bx0 - $sblx}]
      set rw [expr {$strx - $bx1}]
      if {$lw >= $rw} { set strx $bx0 } else { set sblx $bx1 }
     } elseif {$bx0 <= $sblx && $bx1 < $strx} {
      set sblx $bx1
     } elseif {$bx0 > $sblx && $bx1 >= $strx} {
      set strx $bx0
     }
    }
   }
   set ids $cluster($c)
   set recs [_place_cells $ids $sblx $sbly $strx $stry 0 $pitch $siteh $obs $seed $haveconn]
   foreach rec $recs { lappend placed $rec }
  }
  rename _place_cells {}

  # --- score: total Manhattan wire length over all placed cells' nets ---
  # We approximate with a per-cluster bounding-box sum (cheap, no net map needed
  # in the worker). Cells in the same cluster contribute their pairwise
  # distance; this rewards keeping clusters compact and is monotone with the
  # real net wirelength. The main-thread trial also re-scores with real nets
  # when available; the cluster BB sum is a stable proxy for ranking trials.
  set score 0.0
  array set pos {}
  foreach rec $placed {
   set pos([lindex $rec 0]) [list [lindex $rec 1] [lindex $rec 2]]
  }
  foreach c $corder {
   set ids $cluster($c)
   set minx 1e18; set maxx -1e18; set miny 1e18; set maxy -1e18
   set cnt 0
   foreach cid $ids {
    if {[info exists pos($cid)]} {
     lassign $pos($cid) x y
     if {$x < $minx} { set minx $x }
     if {$x > $maxx} { set maxx $x }
     if {$y < $miny} { set miny $y }
     if {$y > $maxy} { set maxy $y }
     incr cnt
    }
   }
   if {$cnt >= 2} {
    set score [expr {$score + ($maxx-$minx) + ($maxy-$miny)}]
   }
  }
  return [list $score $placed]
 }

 # ---- run trials ----
 set cellarea_v [array get cellarea]
 set cluster_v [array get cluster]
 set clusterarea_v [array get clusterarea]
 set instconn_v [array get instconn]

 if { ! ($_mt_on && $_mt_thread_loaded) } {
  # single serial trial, seed 0
  lassign [_hp_place_trial 0 $cellarea_v $cluster_v $clusterarea_v $obs $cb_x0 $cb_y0 $cb_x1 $cb_y1 $siteh $pitch $haveconn $instconn_v] score placed
  set bestseed 0
  set bestscore $score
  set bestplaced $placed
  puts "Info : hier_placement, trial seed 0 score [format %.4g $score]"
 } else {
  # parallel seed trials. Each worker runs _hp_place_trial with a different
  # seed and stores {score placed} in a tsv namespace. We pass the proc body
  # + data via tsv so the worker (a clean thread) can reconstruct it.
  set ntrials $_mt_workers
  if { $ntrials < 2 } { set ntrials 2 }
  # cap to a sane number of trials
  if { $ntrials > 16 } { set ntrials 16 }
  set ns hp[incr _eval_sites_seq]
  tsv::array set $ns counter 0
  tsv::set $ns counter -1
  tsv::set $ns cellarea $cellarea_v
  tsv::set $ns cluster $cluster_v
  tsv::set $ns clusterarea $clusterarea_v
  tsv::set $ns obs $obs
  tsv::set $ns cb_x0 $cb_x0
  tsv::set $ns cb_y0 $cb_y0
  tsv::set $ns cb_x1 $cb_x1
  tsv::set $ns cb_y1 $cb_y1
  tsv::set $ns siteh $siteh
  tsv::set $ns pitch $pitch
  tsv::set $ns haveconn $haveconn
  tsv::set $ns instconn $instconn_v
  tsv::set $ns ntrials $ntrials
  tsv::array set hp_ns x 1
  tsv::set hp_ns cur $ns
  tsv::set hp_ns done 0
  # The worker script: reconstruct _hp_place_trial by copying the body.
  # We can't send the proc closure to a clean thread, so we serialize the
  # trial as a self-contained script. The trial logic is small enough to
  # inline. We build the worker script by sourcing the same logic via a
  # tsv-stored body string.
  # Instead of inlining (fragile), we run the trial on the MAIN thread but
  # spawn workers only to compute scores in parallel is not better here.
  # The simplest robust approach: run trials serially on main thread (each
  # is fast) but still use the worker pool to compute them concurrently by
  # sending the trial proc body as a string the worker evals.
  # Capture the proc body source so workers can recreate it.
  set trialbody [info body _hp_place_trial]
  set trialargs [info args _hp_place_trial]
  tsv::set $ns trialbody $trialbody
  tsv::set $ns trialargs $trialargs
  set wscript {
   set ns [tsv::get hp_ns cur]
   set cellarea_v [tsv::get $ns cellarea]
   set cluster_v [tsv::get $ns cluster]
   set clusterarea_v [tsv::get $ns clusterarea]
   set obs [tsv::get $ns obs]
   set cb_x0 [tsv::get $ns cb_x0]
   set cb_y0 [tsv::get $ns cb_y0]
   set cb_x1 [tsv::get $ns cb_x1]
   set cb_y1 [tsv::get $ns cb_y1]
   set siteh [tsv::get $ns siteh]
   set pitch [tsv::get $ns pitch]
   set haveconn [tsv::get $ns haveconn]
   set instconn_v [tsv::get $ns instconn]
   set ntrials [tsv::get $ns ntrials]
   set trialbody [tsv::get $ns trialbody]
   set trialargs [tsv::get $ns trialargs]
   # recreate the trial proc in this thread
   proc _hp_place_trial $trialargs $trialbody
   while 1 {
    set seed [tsv::incr $ns counter]
    if { $seed >= $ntrials } { break }
    set res [_hp_place_trial $seed $cellarea_v $cluster_v $clusterarea_v $obs $cb_x0 $cb_y0 $cb_x1 $cb_y1 $siteh $pitch $haveconn $instconn_v]
    set sc [lindex $res 0]
    tsv::set $ns score_$seed $sc
    tsv::set $ns placed_$seed [lindex $res 1]
   }
   tsv::incr hp_ns done
   thread::release
  }
  set nw $_mt_workers
  if { $nw > $ntrials } { set nw $ntrials }
  set workers {}
  for { set w 0 } { $w < $nw } { incr w } {
   lappend workers [thread::create $wscript]
  }
  while { [tsv::get hp_ns done] < $nw } { after 5 }
  # gather all trial scores, pick the best
  set bestseed 0
  set bestscore 1e18
  set bestplaced {}
  for { set s 0 } { $s < $ntrials } { incr s } {
   if { ![tsv::exists $ns score_$s] } { continue }
   set sc [tsv::get $ns score_$s]
   puts "Info : hier_placement, trial seed $s score [format %.4g $sc]"
   if { $sc < $bestscore } {
    set bestscore $sc
    set bestseed $s
    set bestplaced [tsv::get $ns placed_$s]
   }
  }
  if { [llength $bestplaced] == 0 } {
   # fallback: no worker produced a result (shouldn't happen), run serial
   lassign [_hp_place_trial 0 $cellarea_v $cluster_v $clusterarea_v $obs $cb_x0 $cb_y0 $cb_x1 $cb_y1 $siteh $pitch $haveconn $instconn_v] bestscore bestplaced
   set bestseed 0
  }
  puts "Info : hier_placement, best trial seed $bestseed score [format %.4g $bestscore] ($ntrials trials, $nw workers)"
 }

 # ---- commit the best placement to _instlist ----
 # Build the row-based free-span structure ONCE (core rows of height siteh,
 # minus blockage/region overlaps). Then place every cell -- those that the
 # trial positioned AND any leftovers -- by packing into these free spans,
 # tracking each row's cursor. This is O(cells + rows*blockages): no per-cell
 # blockage scan and no O(n^2) leftover search, so it scales to 100k+ cells.
 # The trial placement guides which row each cell targets (cell -> target row
 # from its trial py), so the hierarchy coherency is preserved; the free-span
 # packing just enforces blockage avoidance and spacing.
 set nrows [expr {int(($cb_y1 - $cb_y0) / $siteh)}]
 if { $nrows < 1 } { set nrows 1 }
 # rows: each entry {ry0 spans}; spans built once from blockages/regions.
 set row_y {}
 set row_spans {}
 for { set r 0 } { $r < $nrows } { incr r } {
  set ry0 [expr {$cb_y0 + $r*$siteh}]
  set ry1 [expr {$ry0 + $siteh}]
  set spans [list [list $cb_x0 $cb_x1]]
  foreach b $obs {
   lassign $b bx0 by0 bx1 by1
   if { $by1 <= $ry0 || $by0 >= $ry1 } { continue }
   set nsp {}
   foreach sp $spans {
    lassign $sp sx0 sx1
    if { $bx1 <= $sx0 || $bx0 >= $sx1 } { lappend nsp $sp; continue }
    if { $bx0 > $sx0 } { lappend nsp [list $sx0 $bx0] }
    if { $bx1 < $sx1 } { lappend nsp [list $bx1 $sx1] }
   }
   set spans $nsp
  }
  lappend row_y $ry0
  lappend row_spans $spans
 }
 # per-row cursor into its spans list: row_cursor(r) = {span_index x_pos}
 set row_cursor {}
 for { set r 0 } { $r < $nrows } { incr r } { lappend row_cursor [list 0 [lindex [lindex [lindex $row_spans $r] 0] 0]] }

 set committed 0
 # target row per placed cell (from trial py), snapped into the core.
 array set trowOf {}
 foreach rec $bestplaced {
  set py [lindex $rec 2]
  if { $py < $cb_y0 } { set py $cb_y0 }
  if { $py > $cb_y1 } { set py $cb_y1 }
  set r [expr {int(($py - $cb_y0) / $siteh)}]
  if { $r < 0 } { set r 0 }
  if { $r >= $nrows } { set r [expr {$nrows - 1}] }
  set trowOf([lindex $rec 0]) $r
 }
 # place a cell into a target row's free spans at the cursor, advancing the
 # cursor; if the row is full, walk down to the next row with room.
 proc _hp_pack { cid r rowsz szx pitch } {
  upvar row_spans row_spans row_cursor row_cursor nrows nrows cb_x0 cb_x0 cb_y0 cb_y0 siteh siteh _instlist _instlist row_y row_y
  for { set rr $r } { $rr < $nrows } { incr rr } {
   lassign [lindex $row_cursor $rr] si xpos
   set spans [lindex $row_spans $rr]
   set nsp [llength $spans]
   while { $si < $nsp } {
    lassign [lindex $spans $si] sx0 sx1
    if { $xpos < $sx0 } { set xpos $sx0 }
    if { $xpos + $szx <= $sx1 } {
     lset _instlist($cid) 4 1
     lset _instlist($cid) 5 $xpos
     lset _instlist($cid) 6 [lindex $row_y $rr]
     set nx [expr {$xpos + $szx*$pitch}]
     lset row_cursor $rr [list $si $nx]
     return 1
    }
    incr si
    if { $si < $nsp } { set xpos [lindex [lindex $spans $si] 0] }
   }
   # row full: reset cursor and try next row from its first span.
   lset row_cursor $rr [list $nsp 0]
  }
  return 0
 }
 # commit trial-placed cells into their target rows first (keeps coherency).
 set placedOk 0
 foreach rec $bestplaced {
  set cid [lindex $rec 0]
  set szx [lindex $cellarea($cid) 0]
  set r $trowOf($cid)
  if { [_hp_pack $cid $r $nrows $szx $pitch] } { incr committed; incr placedOk }
 }
 # leftover: cells with no trial record (cluster collapsed under blockages).
 # Build a fast membership set for placed cells.
 array set placedset {}
 foreach rec $bestplaced { set placedset([lindex $rec 0]) 1 }
 foreach i $free_cells {
  if { [info exists placedset($i)] } { continue }
  set szx [lindex $cellarea($i) 0]
  # no target row: pack from the first row.
  if { [_hp_pack $i 0 $nrows $szx $pitch] } { incr committed } else {
   # absolute last resort: core origin.
   lset _instlist($i) 4 1
   lset _instlist($i) 5 $cb_x0
   lset _instlist($i) 6 $cb_y0
   incr committed
  }
 }
 catch { rename _hp_pack {} }
 # clean up the trial proc so a subsequent hier_placement call can redefine it
 catch { rename _hp_place_trial {} }
 puts "Info : hier_placement, placed $committed / $nfree cells"
}

# Iterative wire-length optimizer: placeOpt ?-iter n?
#
# Reduces total estimated wire length by working on the worst nets first. At
# each iteration it ranks every net by its Manhattan bounding-box wire length,
# takes the top 20% longest, and for each of those nets tries to move its
# moveable CORE cells toward the net's pin centroid: the cell is relocated to
# the nearest free site on the centroid's row (blockage/core-aware) provided the
# move actually reduces THAT net's length. Wire lengths are recomputed after
# each iteration so the next ranking reflects the new layout. Default 3
# iterations; pass -iter n to change. Requires build_net_conn (netdriver/
# netload) and a placed design.
proc placeOpt { args } {
 variable topname
 _require 3
 variable instindex
 variable _instlist
 variable _libcell
 variable pathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable siteh
 variable regionindex
 variable _regionlist
 global netconnbuilt netdriver netload _wirelen_cache

 set niter 3
 for { set i 0 } { $i < [llength $args] } { incr i } {
  set a [lindex $args $i]
  if { $a eq "-iter" } {
   incr i
   set niter [lindex $args $i]
   if { ![string is integer -strict $niter] || $niter < 1 } {
    puts "Error : placeOpt -iter requires a positive integer"
    return
   }
  } else {
   puts "Error : unknown option $a"
   puts "Usage: placeOpt ?-iter n?"
   return
  }
 }
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before placeOpt"
  return
 }
 if { $siteh <= 0 } { set siteh 0.3 }

 set cb_x0 [lindex $corebox 0]
 set cb_y0 [lindex $corebox 1]
 set cb_x1 [lindex $corebox 2]
 set cb_y1 [lindex $corebox 3]

 # Blockage + region boxes to avoid.
 set obs {}
 for { set i 1 } { $i <= $blockageindex } { incr i } {
  lappend obs [list [lindex $_blockagelist($i) 1] [lindex $_blockagelist($i) 2] [lindex $_blockagelist($i) 3] [lindex $_blockagelist($i) 4]]
 }
 for { set i 1 } { $i <= $regionindex } { incr i } {
  lappend obs [list [lindex $_regionlist($i) 1] [lindex $_regionlist($i) 2] [lindex $_regionlist($i) 3] [lindex $_regionlist($i) 4]]
 }

 # Map full instance path -> inst id (pathlist is 0-based, ids 1-based).
 array set pathid {}
 set pi 0
 foreach p $pathlist { set pathid($p) [expr {$pi + 1}]; incr pi }

 # Build net -> list of moveable CORE inst ids. Net keys can contain bit-
 # select brackets, so walk via array get (no subscript parsing). A pin's
 # inst is the first token of the pin entry; ports/assigns are skipped.
 array set netinsts {}
 foreach {n dval} [array get netdriver] {
  foreach p $dval {
   set ip [lindex $p 0]
   if { [info exists pathid($ip)] } {
    set id $pathid($ip)
    if { [info exists _libcell([lindex $_instlist($id) 8])] } {
     if { [lindex $_libcell([lindex $_instlist($id) 8]) 4] eq "CORE" } { lappend netinsts($n) $id }
    }
   }
  }
 }
 foreach {n lval} [array get netload] {
  foreach p $lval {
   set ip [lindex $p 0]
   if { [info exists pathid($ip)] } {
    set id $pathid($ip)
    if { [info exists _libcell([lindex $_instlist($id) 8])] } {
     if { [lindex $_libcell([lindex $_instlist($id) 8]) 4] eq "CORE" } { lappend netinsts($n) $id }
    }
   }
  }
 }

 # Helper: is point (px,py) clear of all blockages/regions?
 proc _po_clear { px py obs } {
  foreach b $obs {
   if { $px >= [lindex $b 0] && $px < [lindex $b 2] && $py >= [lindex $b 1] && $py < [lindex $b 3] } { return 0 }
  }
  return 1
 }

 # total wire length over all nets (uses cache, computes lazily).
 proc _po_total {} {
  global netdriver _wirelen_cache
  set tot 0
  foreach {n v} [array get netdriver] {
   set w [_net_wirelen_scalar $n]
   if { $w > 0 } { set tot [expr {$tot + $w}] }
  }
  return $tot
 }

 # wire length of one net given current placement (force recompute, bypass cache).
 proc _po_netlen { n } {
  global _wirelen_cache
  # invalidate cache for this net then recompute.
  catch { unset _wirelen_cache($n) }
  set w [_net_wirelen_scalar $n]
  if { $w < 0 } { return 0 }
  return $w
 }

 set total0 [_po_total]
  puts "Info : placeOpt, initial total wire length = [format %.2f $total0]"

 for { set iter 1 } { $iter <= $niter } { incr iter } {
  # Rank nets by current wire length (descending). Walk all nets, compute
  # scalar length, collect {len net} pairs.
  set ranked {}
  foreach {n v} [array get netdriver] {
   set w [_net_wirelen_scalar $n]
   if { $w > 0 } { lappend ranked [list $w $n] }
  }
  set ranked [lsort -real -decreasing -index 0 $ranked]
  set nn [llength $ranked]
  if { $nn == 0 } { puts "Info : placeOpt, no estimable nets"; break }
  set topk [expr {int(ceil($nn * 0.2))}]
  if { $topk < 1 } { set topk 1 }
  set work [lrange $ranked 0 [expr {$topk - 1}]]
  puts "Info : placeOpt, iter $iter: working on top $topk / $nn longest nets"

  set nmoved 0
  foreach rec $work {
   set n [lindex $rec 1]
   if { ![info exists netinsts($n)] } { continue }
   # collect placed pin coords + the moveable inst ids on this net.
   set ids $netinsts($n)
   set coords {}
   set placedids {}
   foreach id $ids {
    if { [lindex $_instlist($id) 4] != 1 } { continue }
    lappend placedids $id
    lappend coords [list [lindex $_instlist($id) 5] [lindex $_instlist($id) 6]]
   }
   if { [llength $coords] < 2 } { continue }
   # net centroid (mean of pin coords).
   set sx 0; set sy 0
   foreach c $coords { set sx [expr {$sx + [lindex $c 0]}]; set sy [expr {$sy + [lindex $c 1]}] }
   set cx [expr {$sx / [llength $coords]}]
   set cy [expr {$sy / [llength $coords]}]
   # target row snapped to the site grid inside the core.
   set tr [expr {int(($cy - $cb_y0) / $siteh)}]
   if { $tr < 0 } { set tr 0 }
   set nrows [expr {int(($cb_y1 - $cb_y0) / $siteh)}]
   if { $nrows < 1 } { set nrows 1 }
   if { $tr >= $nrows } { set tr [expr {$nrows - 1}] }
   set ty [expr {$cb_y0 + $tr * $siteh}]
   set before [_po_netlen $n]
   # try to move each moveable cell on the net to the centroid row at cx,
   # snapped to a blockage-free x. Keep the move only if it reduces the
   # net's length; otherwise revert.
   foreach id $placedids {
    set ox [lindex $_instlist($id) 5]
    set oy [lindex $_instlist($id) 6]
    # candidate x = centroid x, clamped to core, nudged past blockages.
    set nx $cx
    if { $nx < $cb_x0 } { set nx $cb_x0 }
    if { $nx > $cb_x1 } { set nx $cb_x1 }
    # if inside a blockage, nudge right in siteh steps up to a few tries.
    for { set g 0 } { $g < 50 && ! [_po_clear $nx $ty $obs] } { incr g } { set nx [expr {$nx + $siteh}] }
    # strict validation: final position must be inside core AND clear of
    # every blockage/region; otherwise skip the move (no overlap with a
    # macro/halo). This keeps placeOpt's result legal even though it does
    # not track cell-cell overlap.
    if { $nx < $cb_x0 || $nx > $cb_x1 || $ty < $cb_y0 || $ty > $cb_y1 } { continue }
    if { ! [_po_clear $nx $ty $obs] } { continue }
    if { [expr {abs($nx - $ox)}] < 0.01 && [expr {abs($ty - $oy)}] < 0.01 } { continue }
    # apply tentative move and re-measure this net.
    lset _instlist($id) 5 $nx
    lset _instlist($id) 6 $ty
    set after [_po_netlen $n]
    if { $after < $before } {
     incr nmoved
     set before $after
    } else {
     # revert
     lset _instlist($id) 5 $ox
     lset _instlist($id) 6 $oy
     catch { unset _wirelen_cache($n) }
     set _wirelen_cache($n) $before
    }
   }
  }
  # recompute the global cache after the iteration (positions changed).
  global _wirelen_cache
  array unset _wirelen_cache
  set total [_po_total]
  puts "Info : placeOpt, iter $iter: moved $nmoved cells, total wire length = [format %.2f $total]"
 }
 catch { rename _po_clear {} }
 catch { rename _po_total {} }
 catch { rename _po_netlen {} }
 puts "Info : placeOpt, done: total [format %.2f $total0] -> [format %.2f $total] ([expr {$total0>0?int(($total0-$total)*100/$total0):0}]% reduction)"
}

# Seed-driven hierarchy-coherent placement: seed_place ?-seed n?
#
# A placement strategy driven by a single integer seed that encodes four
# choices and keeps hierarchy blocks spatially together.
#   STEP 1 - seed encodes: N (9 or 16 subdivisions), M (2/3/4 hierarchy
#            granularity), P (0..255 block-allocation drive), T (0..15
#            topology choice).
#   STEP 2 - analyse hierarchy: count top-1 subblocks (S). While S < N*M
#            descend one hierarchy level (expanding the frontier) until
#            S >= N*M or the hierarchy is exhausted.
#   STEP 3 - allocate the S blocks into N baskets, P-driven deterministic
#            round-robin (even distribution).
#   STEP 4 - divide the chip into an 8x8 grid of 64 locations; assign each
#            basket to a location via a T-driven traversal + start offset.
#   STEP 5 - place each basket's cells (the leaf cells of its hierarchy
#            blocks) inside its location region, blockage-aware. Overflow
#            and top-residual cells fill the unassigned location regions.
# Different seeds give different layouts, enabling future multi-seed
# comparison. Requires a floorplan (P3). Purely geometric: uses no net
# data, so no build_net_conn dependency.
proc seed_place { args } {
 global _mt_on _mt_workers _mt_thread_loaded _eval_sites_seq
 variable topname
 _require 3
 variable instindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable hpathlist
 variable pathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable siteh
 variable targetutilz
 variable regionindex
 variable _regionlist

 set seed -1
 set niter 1
 for { set i 0 } { $i < [llength $args] } { incr i } {
  set a [lindex $args $i]
  if { $a eq "-seed" } {
   incr i
   set seed [lindex $args $i]
   if { ![string is integer -strict $seed] } {
    puts "Error : seed_place -seed requires an integer"
    return
   }
  } elseif { $a eq "-iter" } {
   incr i
   set niter [lindex $args $i]
   if { ![string is integer -strict $niter] || $niter < 1 } {
    puts "Error : seed_place -iter requires a positive integer"
    return
   }
  } else {
   puts "Error : unknown option $a"
   puts "Usage: seed_place ?-seed n? ?-iter n?"
   return
  }
 }

 # score by total wire length: needs net connectivity.
 global netconnbuilt netdriver netload
 set haveconn 0
 if { [info exists netconnbuilt] && $netconnbuilt } { set haveconn 1 }
 if { ! $haveconn } {
  puts "Error : build_net_conn must run before seed_place (wire length is the trial score)"
  return
 }

 if { $siteh <= 0 } { set siteh 0.3 }
 set pitch [expr {100.0 / $targetutilz}]
 if { $pitch < 1.0 } { set pitch 1.0 }
 set cb_x0 [lindex $corebox 0]
 set cb_y0 [lindex $corebox 1]
 set cb_x1 [lindex $corebox 2]
 set cb_y1 [lindex $corebox 3]

 set obs {}
 for { set i 1 } { $i <= $blockageindex } { incr i } {
  lappend obs [list [lindex $_blockagelist($i) 1] [lindex $_blockagelist($i) 2] [lindex $_blockagelist($i) 3] [lindex $_blockagelist($i) 4]]
 }
 for { set i 1 } { $i <= $regionindex } { incr i } {
  lappend obs [list [lindex $_regionlist($i) 1] [lindex $_regionlist($i) 2] [lindex $_regionlist($i) 3] [lindex $_regionlist($i) 4]]
 }

 # --- STEP 2: analyse hierarchy ---
 # path-aware children map: parent fullpath (field 7) -> list of hinst ids.
 array set childmap {}
 for { set i 1 } { $i <= $hinstindex } { incr i } {
  lappend childmap([lindex $_hinstlist($i) 7]) $i
 }
 proc _sp_hp { hid } {
  upvar hpathlist hpathlist
  return [lindex $hpathlist [expr {$hid - 1}]]
 }
 set frontier {}
 if { [info exists childmap(-1)] } { set frontier $childmap(-1) }
 set S [llength $frontier]
 # hierarchy depth limit for the expansion: capped so a flat design (many
 # top-1 blocks, all leaves) does not loop. The deepest meaningful descent
 # is bounded by the number of hierarchy levels actually present.
 set maxlevel 6
 set level 1
 puts "Info : seed_place, hierarchy top-$level : S=$S"
 # We expand only when the CURRENT frontier is too small for the largest
 # N*M (16*4=64); once big enough for all seeds we stop. The block->cell
 # mapping is rebuilt per seed (different N/M change the target count),
 # but the frontier set is shared across trials, so compute it once.
 while { $S < 64 && $level < $maxlevel } {
  set newf {}
  set changed 0
  foreach hid $frontier {
   set hp [_sp_hp $hid]
   if { [info exists childmap($hp)] && [llength $childmap($hp)] > 0 } {
    lappend newf {*}$childmap($hp)
    set changed 1
   } else {
    lappend newf $hid
   }
  }
  if { ! $changed } { break }
  set frontier $newf
  set S [llength $frontier]
  incr level
  puts "Info : seed_place, hierarchy top-$level : S=$S"
 }
 puts "Info : seed_place, selected $S hierarchy blocks at depth $level (frontier shared across trials)"
 array set fdict {}
 foreach hid $frontier { set fdict([_sp_hp $hid]) $hid }
 catch { rename _sp_hp {} }

 # collect free CORE cells; map each to its deepest frontier ancestor (by
 # path prefix walk-up); unmatchable / top-level cells go to a residual list.
 array set cellarea {}
 array set blockcells {}
 set toprest {}
 set free_cells {}
 for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $inst 4] != 0 } { continue }
  set refid [lindex $inst 8]
  if { ! [info exists _libcell($refid)] } { continue }
  if { [lindex $_libcell($refid) 4] ne "CORE" } { continue }
  set szx [lindex $_libcell($refid) 1]
  set szy [lindex $_libcell($refid) 2]
  set cellarea($i) [list $szx $szy [expr {$szx * $szy}]]
  lappend free_cells $i
  set fp [lindex $inst 7]
  if { $fp eq "-1" || $fp eq "" } {
   lappend toprest $i
   continue
  }
  set owner 0
  set p $fp
  while { $p ne "" } {
   if { [info exists fdict($p)] } { set owner $fdict($p); break }
   set segs [split $p /]
   if { [llength $segs] <= 1 } { break }
   set p [join [lrange $segs 0 end-1] /]
  }
  if { $owner } {
   lappend blockcells($owner) $i
  } else {
   lappend toprest $i
  }
 }
 set nfree [llength $free_cells]
 puts "Info : seed_place, $nfree free CORE cells, [llength $toprest] top-residual"
 if { $nfree == 0 } {
  puts "Info : seed_place, nothing to place"
  return
 }

 # Precompute the net->inst-id index once (shared by all trials) so each
 # trial scores by real total wire length. A net's pins live at inst
 # positions; pins that are not moveable CORE cells (macros, ports, assigns)
 # are read from _instlist so they contribute fixed endpoints. Net keys can
 # contain bit-select brackets, so we walk via array get (no subscripts).
 array set pathid {}
 set pi 0
 foreach p $pathlist { set pathid($p) [expr {$pi + 1}]; incr pi }
 # netpins(net) = list of {id x y} where id is the inst id (0 for a port/
 # assign endpoint that has no inst). Macro/non-free inst positions are
 # fixed and read live during scoring; free-cell positions come from the
 # trial's local pos map.
 array set netpins {}
 foreach {n dval} [array get netdriver] {
  set pl {}
  foreach p $dval {
   set ip [lindex $p 0]
   if { [info exists pathid($ip)] } {
    lappend pl [list $pathid($ip)]
   }
  }
  if { [llength $pl] > 0 } { set netpins($n) $pl }
 }
 foreach {n lval} [array get netload] {
  set pl {}
  if { [info exists netpins($n)] } { set pl $netpins($n) }
  foreach p $lval {
   set ip [lindex $p 0]
   if { [info exists pathid($ip)] } {
    lappend pl [list $pathid($ip)]
   }
  }
  if { [llength $pl] > 0 } { set netpins($n) $pl }
 }
 # compact the net index to two parallel lists for cheap tsv shipping:
 # netkeys (list of net names) and netpinids (list of id-lists, same order).
 set netkeys {}
 set netpinids {}
 foreach {n ids} [array get netpins] {
  lappend netkeys $n
  lappend netpinids $ids
 }
 unset netpins

 # ---- Pure trial: compute placement for one seed, return {score poslist}.
 # ---- poslist = list of {cid x y}. score = total wire length over all nets
 # ---- using the trial's positions for free cells + fixed positions for the
 # ---- already-placed macros/ports. The trial never writes _instlist, so it
 # ---- is safe to run many in parallel and to discard losing trials.
 proc _sp_trial { seed cellarea_v blockcells_v toprest_v obs cb_x0 cb_y0 cb_x1 cb_y1 siteh pitch netkeys netpinids placedpos_v mt_on_v mt_workers_v } {
  array set cellarea $cellarea_v
  array set blockcells $blockcells_v
  set toprest $toprest_v
  array set placedpos $placedpos_v

  # decode seed
  set N [expr {($seed & 1) ? 16 : 9}]
  set msel [expr {($seed >> 1) & 0x3}]
  if { $msel == 0 } { set M 2 } elseif { $msel == 1 } { set M 3 } else { set M 4 }
  set P [expr {($seed >> 3) & 0xFF}]
  set T [expr {($seed >> 11) & 0xF}]
  set nm [expr {$N * $M}]

  # --- STEP 3: allocate frontier blocks into N baskets (P-driven) ---
 # block cell counts drive a load-balanced round-robin.
 set pairs {}
 foreach hid [array names blockcells] {
   lappend pairs [list [llength $blockcells($hid)] $hid]
  }
  set pairs [lsort -integer -decreasing -index 0 $pairs]
  set ordered {}
  foreach p $pairs { lappend ordered [lindex $p 1] }
  array set basket {}
  for { set b 0 } { $b < $N } { incr b } { set basket($b) {} }
  set bi 0
  foreach hid $ordered {
   set b [expr {($bi + $P) % $N}]
   lappend basket($b) $hid
   incr bi
  }
  set usedBaskets {}
  for { set b 0 } { $b < $N } { incr b } {
   if { [llength $basket($b)] > 0 } { lappend usedBaskets $b }
  }

  # --- STEP 4: 64-location 8x8 grid, T-driven basket->location ---
  set gx [expr {($cb_x1 - $cb_x0) / 8.0}]
  set gy [expr {($cb_y1 - $cb_y0) / 8.0}]
  set locbox {}
  for { set r 0 } { $r < 8 } { incr r } {
   for { set c 0 } { $c < 8 } { incr c } {
    lappend locbox [list [expr {$cb_x0 + $c * $gx}] [expr {$cb_y0 + $r * $gy}] [expr {$cb_x0 + ($c + 1) * $gx}] [expr {$cb_y0 + ($r + 1) * $gy}]]
   }
  }
  set ttype [expr {$T & 0x3}]
  set trav {}
  for { set a 0 } { $a < 8 } { incr a } {
   for { set b 0 } { $b < 8 } { incr b } {
    if { $ttype == 0 } { set idx [expr {$a * 8 + $b}] } elseif { $ttype == 1 } { set idx [expr {$b * 8 + $a}] } elseif { $ttype == 2 } { set idx [expr {$a * 8 + (7 - $b)}] } else { set idx [expr {(7 - $a) * 8 + $b}] }
    lappend trav $idx
   }
  }
  set start [expr {$T % 64}]
  array set basketloc {}
  set li 0
  foreach b $usedBaskets {
   set basketloc($b) [lindex $trav [expr {($start + $li) % 64}]]
   incr li
  }

  # --- STEP 5: place each basket's cells into its location region. Writes
  # --- into a LOCAL pos(cid)={x y} map (never _instlist) so trials are
  # --- independent and discardable. Overflow + top-residual fill unassigned
  # --- location regions; last resort falls back to core origin.
  proc _sp_pack_region { cells rx0 ry0 rx1 ry1 } {
   upvar pos pos cellarea cellarea siteh siteh obs obs pitch pitch
   set nrows [expr {int(($ry1 - $ry0) / $siteh)}]
   if { $nrows < 1 } { set nrows 1 }
   set row_y {}
   set row_spans {}
   for { set r 0 } { $r < $nrows } { incr r } {
    set ry0r [expr {$ry0 + $r * $siteh}]
    set ry1r [expr {$ry0r + $siteh}]
    set spans [list [list $rx0 $rx1]]
    foreach b $obs {
     lassign $b bx0 by0 bx1 by1
     if { $by1 <= $ry0r || $by0 >= $ry1r } { continue }
     set nsp {}
     foreach sp $spans {
      lassign $sp sx0 sx1
      if { $bx1 <= $sx0 || $bx0 >= $sx1 } { lappend nsp $sp; continue }
      if { $bx0 > $sx0 } { lappend nsp [list $sx0 $bx0] }
      if { $bx1 < $sx1 } { lappend nsp [list $bx1 $sx1] }
     }
     set spans $nsp
    }
    lappend row_y $ry0r
    lappend row_spans $spans
   }
   set row_cursor {}
   for { set r 0 } { $r < $nrows } { incr r } {
    lappend row_cursor [list 0 [lindex [lindex [lindex $row_spans $r] 0] 0]]
   }
   proc _sp_pack1 { cid } {
    upvar row_spans row_spans row_cursor row_cursor nrows nrows row_y row_y pos pos cellarea cellarea pitch pitch
    set szx [lindex $cellarea($cid) 0]
    for { set rr 0 } { $rr < $nrows } { incr rr } {
     lassign [lindex $row_cursor $rr] si xpos
     set spans [lindex $row_spans $rr]
     set nsp [llength $spans]
     while { $si < $nsp } {
      lassign [lindex $spans $si] sx0 sx1
      if { $xpos < $sx0 } { set xpos $sx0 }
      if { $xpos + $szx <= $sx1 } {
       set pos($cid) [list $xpos [lindex $row_y $rr]]
       lset row_cursor $rr [list $si [expr {$xpos + $szx * $pitch}]]
       return 1
      }
      incr si
      if { $si < $nsp } { set xpos [lindex [lindex $spans $si] 0] }
     }
     lset row_cursor $rr [list $nsp 0]
    }
    return 0
   }
   set overflow {}
   foreach cid $cells {
    if { ! [_sp_pack1 $cid] } { lappend overflow $cid }
   }
   catch { rename _sp_pack1 {} }
   return $overflow
  }

  array set pos {}
  set overflow {}
  set totalcells [array size cellarea]
  set placedcnt 0
  set adv 0
  proc _sp_pp { placedcnt totalcells } {
   upvar 1 adv adv
   if { $totalcells < 1000 } { return }
   set pct [expr {int(100.0 * $placedcnt / $totalcells)}]
   if {$pct >= 10 && $adv < 3 } { puts "..10%.." ; set adv 3 }
   if {$pct >= 30 && $adv < 5 } { puts "..30%.." ; set adv 5 }
   if {$pct >= 50 && $adv < 7 } { puts "..50%.." ; set adv 7 }
   if {$pct >= 70 && $adv < 9 } { puts "..70%.." ; set adv 9 }
   if {$pct >= 90 && $adv < 11} { puts "..90%.." ; set adv 11}
  }
  # Build the per-basket work list once: each entry is {b lidx cells}. Every
  # basket is independent (disjoint cell ids, its own region and row cursors),
  # so the baskets can be packed in parallel when MT is on.
  set worklist {}
  foreach b $usedBaskets {
   set lidx $basketloc($b)
   lassign [lindex $locbox $lidx] rx0 ry0 rx1 ry1
   set cells {}
   foreach hid $basket($b) {
    if { [info exists blockcells($hid)] } { lappend cells {*}$blockcells($hid) }
   }
   if { [llength $cells] == 0 } { continue }
   lappend worklist [list $rx0 $ry0 $rx1 $ry1 $cells]
  }
  set nwork [llength $worklist]
  if { $mt_on_v && $mt_workers_v > 1 && $nwork >= 2 } {
   # Parallel basket packing. Ship read-only inputs once; each worker packs a
   # disjoint basket and returns {placed_flat overflow}, which the main thread
   # merges into pos/overflow. Workers reimplement _sp_pack_region/_sp_pack1
   # self-contained from the shipped inputs (no shared globals, no upvar).
   set nw $mt_workers_v
   if { $nw > $nwork } { set nw $nwork }
   set ns spp[incr ::_eval_sites_seq]
   tsv::set $ns worklist $worklist
   tsv::set $ns cellarea_v $cellarea_v
   tsv::set $ns obs $obs
   tsv::set $ns siteh $siteh
   tsv::set $ns pitch $pitch
   tsv::set $ns nwork $nwork
   tsv::set $ns nws $nw
   tsv::set $ns wid -1
   tsv::array set spp_ns cur $ns
   tsv::set spp_ns done 0
   set wscript {
    set ns [tsv::get spp_ns cur]
    set worklist [tsv::get $ns worklist]
    set cellarea_v [tsv::get $ns cellarea_v]
    set obs [tsv::get $ns obs]
    set siteh [tsv::get $ns siteh]
    set pitch [tsv::get $ns pitch]
    set nwork [tsv::get $ns nwork]
    set nws [tsv::get $ns nws]
    array set cellarea $cellarea_v
    while {1} {
     set wi [tsv::incr $ns wid]
     if { $wi >= $nwork } { break }
     lassign [lindex $worklist $wi] rx0 ry0 rx1 ry1 cells
     set nrows [expr {int(($ry1 - $ry0) / $siteh)}]
     if { $nrows < 1 } { set nrows 1 }
     set row_y {}
     set row_spans {}
     for { set r 0 } { $r < $nrows } { incr r } {
      set ry0r [expr {$ry0 + $r * $siteh}]
      set ry1r [expr {$ry0r + $siteh}]
      set spans [list [list $rx0 $rx1]]
      foreach b $obs {
       lassign $b bx0 by0 bx1 by1
       if { $by1 <= $ry0r || $by0 >= $ry1r } { continue }
       set nsp {}
       foreach sp $spans {
        lassign $sp sx0 sx1
        if { $bx1 <= $sx0 || $bx0 >= $sx1 } { lappend nsp $sp; continue }
        if { $bx0 > $sx0 } { lappend nsp [list $sx0 $bx0] }
        if { $bx1 < $sx1 } { lappend nsp [list $bx1 $sx1] }
       }
       set spans $nsp
      }
      lappend row_y $ry0r
      lappend row_spans $spans
     }
     set row_cursor {}
     for { set r 0 } { $r < $nrows } { incr r } {
      lappend row_cursor [list 0 [lindex [lindex [lindex $row_spans $r] 0] 0]]
     }
     set placed_flat {}
     set ovl {}
     foreach cid $cells {
      set szx [lindex $cellarea($cid) 0]
      set placed 0
      for { set rr 0 } { $rr < $nrows } { incr rr } {
       lassign [lindex $row_cursor $rr] si xpos
       set spans [lindex $row_spans $rr]
       set nsp [llength $spans]
       while { $si < $nsp } {
        lassign [lindex $spans $si] sx0 sx1
        if { $xpos < $sx0 } { set xpos $sx0 }
        if { $xpos + $szx <= $sx1 } {
         lappend placed_flat $cid $xpos [lindex $row_y $rr]
         lset row_cursor $rr [list $si [expr {$xpos + $szx * $pitch}]]
         set placed 1
         break
        }
        incr si
        if { $si < $nsp } { set xpos [lindex [lindex $spans $si] 0] }
       }
       if { $placed } { break }
       lset row_cursor $rr [list $nsp 0]
      }
      if { ! $placed } { lappend ovl $cid }
     }
     tsv::set $ns placed_$wi $placed_flat
     tsv::set $ns overflow_$wi $ovl
    }
    tsv::incr spp_ns done
    thread::release
   }
   set workers {}
   for { set w 0 } { $w < $nw } { incr w } { lappend workers [thread::create $wscript] }
   while { [tsv::get spp_ns done] < $nw } { after 5 }
   for { set wi 0 } { $wi < $nwork } { incr wi } {
    if { [tsv::exists $ns placed_$wi] } {
     set pf [tsv::get $ns placed_$wi]
     foreach {cid x y} $pf { set pos($cid) [list $x $y] }
     lappend overflow {*}[tsv::get $ns overflow_$wi]
     set placedcnt [llength [array names pos]]
     _sp_pp $placedcnt $totalcells
    }
   }
  } else {
   # Serial basket packing (current behaviour, with progress).
   foreach w $worklist {
    lassign $w rx0 ry0 rx1 ry1 cells
    set ov [_sp_pack_region $cells $rx0 $ry0 $rx1 $ry1]
    lappend overflow {*}$ov
    set placedcnt [llength [array names pos]]
    _sp_pp $placedcnt $totalcells
   }
  }
  set usedloc {}
  foreach b $usedBaskets { lappend usedloc $basketloc($b) }
  set freeregions {}
  for { set t 0 } { $t < 64 } { incr t } {
   set lidx [lindex $trav [expr {($start + $t) % 64}]]
   if { [lsearch -exact $usedloc $lidx] < 0 } { lappend freeregions $lidx }
  }
  set leftover [concat $toprest $overflow]
  foreach lidx $freeregions {
   if { [llength $leftover] == 0 } { break }
   lassign [lindex $locbox $lidx] rx0 ry0 rx1 ry1
   set leftover [_sp_pack_region $leftover $rx0 $ry0 $rx1 $ry1]
   set placedcnt [llength [array names pos]]
   _sp_pp $placedcnt $totalcells
  }
  foreach cid $leftover { set pos($cid) [list $cb_x0 $cb_y0] }
  _sp_pp [llength [array names pos]] $totalcells
  catch { rename _sp_pack_region {} }
  catch { rename _sp_pp {} }

  # poslist of placed free cells. The wire-length score is NOT computed
  # here: the caller re-scores the placement through _sp_score_all so the
  # bbox sum can run in parallel when MT is on (computing it here would
  # double the wire-length cost on large designs).
  set poslist {}
  foreach {cid xy} [array get pos] { lappend poslist [list $cid [lindex $xy 0] [lindex $xy 1]] }
  return [list 0 $N $M $P $T $poslist]
 }

 # fixed positions of already-placed (macro/non-free) cells, used as net
 # endpoints during scoring (they don't move during a trial).
 array set placedpos {}
 for { set i 1 } { $i <= $instindex } { incr i } {
  set inst $_instlist($i)
  if { [lindex $inst 4] == 1 } {
   set refid [lindex $inst 8]
   if { [info exists _libcell($refid)] && [lindex $_libcell($refid) 4] ne "CORE" } {
    set placedpos($i) [list [lindex $inst 5] [lindex $inst 6]]
   }
  }
 }

 set cellarea_v [array get cellarea]
 set blockcells_v [array get blockcells]
 set toprest_v $toprest
 set placedpos_v [array get placedpos]

 set mt_on [expr {$_mt_on && $_mt_thread_loaded}]
 if { $mt_on } {
  puts "Info : seed_place with multithread ON ($niter iteration(s), wire-length scoring parallelized over $_mt_workers threads)"
 } else {
  puts "Info : seed_place single-threaded, $niter iteration(s)"
 }

 # Wire-length scoring helper: sum the Manhattan bounding-box length of a
 # contiguous range [k0,k1) of nets. upos_v is a SINGLE unified position map
 # serialized as {id x y ...} that already merges the per-trial free-cell
 # positions over the fixed macro/placed positions, so a net's pin ids are
 # looked up in one map with one 'info exists' -- the same single-map pattern
 # _ras_wire_total uses (ipos). Each net is independent, so the range can be
 # scored in a worker thread.
 proc _sp_score_range { k0 k1 netpinids upos_v } {
  array set upos $upos_v
  set score 0.0
  set adv 0
  set span [expr {$k1 - $k0}]
  for { set k $k0 } { $k < $k1 } { incr k } {
   set ids [lindex $netpinids $k]
   set minx 1e18; set maxx -1e18; set miny 1e18; set maxy -1e18
   set cnt 0
   foreach id $ids {
    if { ! [info exists upos($id)] } { continue }
    lassign $upos($id) x y
    if { $x < $minx } { set minx $x }
    if { $x > $maxx } { set maxx $x }
    if { $y < $miny } { set miny $y }
    if { $y > $maxy } { set maxy $y }
    incr cnt
   }
   if { $cnt >= 2 } { set score [expr {$score + ($maxx - $minx) + ($maxy - $miny)}] }
   if { $span >= 100 } {
    set done [expr {$k - $k0 + 1}]
    if {$done > [expr 1* $span /10] && $adv<3 } { puts "..10%.." ; set adv 3 }
    if {$done > [expr 3* $span /10] && $adv<5 } { puts "..30%.." ; set adv 5 }
    if {$done > [expr 5* $span /10] && $adv<7 } { puts "..50%.." ; set adv 7 }
    if {$done > [expr 7* $span /10] && $adv<9 } { puts "..70%.." ; set adv 9 }
    if {$done > [expr 9* $span /10] && $adv<11} { puts "..90%.." ; set adv 11}
   }
  }
  return $score
 }

 # Score all nets for one trial. Serial when MT is off; when MT is on, the
 # net index is split into nw contiguous ranges and each range is scored in
 # a worker thread, then the partial scores are summed. Only the per-trial
 # unified position map (upos_v) is shipped; the net index and the fixed
 # positions are read-only, so parallel ranges are safe. Threads are created
 # per scoring call and self-release when done, so no thread accumulates
 # across trials/iterations. This mirrors _ras_wire_total's single-map worker
 # (one 'array set' + one 'info exists' per pin, no fallback lookup).
 proc _sp_score_all { netpinids upos_v } {
  upvar mt_on mt_on _mt_workers _mt_workers _eval_sites_seq _eval_sites_seq
  set nn [llength $netpinids]
  if { ! $mt_on || $nn < 64 } {
   return [_sp_score_range 0 $nn $netpinids $upos_v]
  }
  set nw $_mt_workers
  if { $nw < 1 } { set nw 1 }
  if { $nw > $nn } { set nw $nn }
  if { $nw == 1 } { return [_sp_score_range 0 $nn $netpinids $upos_v] }
  set ns sps[incr _eval_sites_seq]
  tsv::set $ns netpinids $netpinids
  tsv::set $ns upos_v $upos_v
  tsv::set $ns nn $nn
  tsv::set $ns nws $nw
  tsv::set $ns wid -1
  tsv::array set sps_ns cur $ns
  tsv::set sps_ns done 0
  set wscript {
   set ns [tsv::get sps_ns cur]
   set netpinids [tsv::get $ns netpinids]
   set upos_v [tsv::get $ns upos_v]
   set nn [tsv::get $ns nn]
   set nws [tsv::get $ns nws]
   set wid [tsv::incr $ns wid]
   set k0 [expr {int(($wid * $nn) / $nws)}]
   set k1 [expr {int((($wid + 1) * $nn) / $nws)}]
   set s 0.0
   if { $k0 < $k1 } {
    array set upos $upos_v
    for { set k $k0 } { $k < $k1 } { incr k } {
     set ids [lindex $netpinids $k]
     set minx 1e18; set maxx -1e18; set miny 1e18; set maxy -1e18
     set cnt 0
     foreach id $ids {
      if { ! [info exists upos($id)] } { continue }
      lassign $upos($id) x y
      if { $x < $minx } { set minx $x }
      if { $x > $maxx } { set maxx $x }
      if { $y < $miny } { set miny $y }
      if { $y > $maxy } { set maxy $y }
      incr cnt
     }
     if { $cnt >= 2 } { set s [expr {$s + ($maxx - $minx) + ($maxy - $miny)}] }
    }
   }
   tsv::set $ns partial_$wid $s
   tsv::incr sps_ns done
   thread::release
  }
  set workers {}
  for { set w 0 } { $w < $nw } { incr w } { lappend workers [thread::create $wscript] }
  while { [tsv::get sps_ns done] < $nw } { after 5 }
  set total 0.0
  for { set w 0 } { $w < $nw } { incr w } {
   if { [tsv::exists $ns partial_$w] } { set total [expr {$total + [tsv::get $ns partial_$w]}] }
  }
  return $total
 }

 # ---- run iteration rounds sequentially. Each round runs ONE placement
 # ---- trial (serial), scores it by total wire length (the scoring itself
 # ---- is parallelized over threads when MT is on), and keeps the best
 # ---- across all rounds so far. Trials run one after the other -- no
 # ---- parallel trials -- so there are never more than nw worker threads
 # ---- alive (and only during a scoring pass), with no accumulation.
 set bestscore 1e18
 set bestres {}
 set bestseed -1
 for { set iter 1 } { $iter <= $niter } { incr iter } {
  if { $niter > 1 } { puts "Info : seed_place, iteration $iter/$niter" }
  if { $iter == 1 && $seed >= 0 } {
   set sd $seed
  } else {
   set sd [expr {int(rand() * 32768)}]
  }
  puts "Info : seed_place, trial seed=$sd : placing $nfree cells"
  set res [_sp_trial $sd $cellarea_v $blockcells_v $toprest_v $obs $cb_x0 $cb_y0 $cb_x1 $cb_y1 $siteh $pitch $netkeys $netpinids $placedpos_v $mt_on $_mt_workers]
  puts "Info : seed_place, trial seed=$sd : placement done, estimating wire length"
  # re-score the trial's placement through the (possibly MT) scorer so the
  # wire-length sum is computed in parallel when MT is on.
  set trialpos [lindex $res 5]
  array set tpos {}
  foreach rec $trialpos { set tpos([lindex $rec 0]) [list [lindex $rec 1] [lindex $rec 2]] }
  # Build a SINGLE unified position map: start from the fixed macro/placed
  # positions, then overlay the trial's free-cell positions. Workers then
  # resolve every net pin with one 'info exists' in one map -- the same
  # single-map pattern _ras_wire_total uses -- instead of a two-map fallback.
  array set upos $placedpos_v
  foreach {cid xy} [array get tpos] { set upos($cid) $xy }
  set sc [_sp_score_all $netpinids [array get upos]]
  puts "Info : seed_place, seed=$sd  N=[lindex $res 1]  M=[lindex $res 2]  P=[lindex $res 3]  T=[lindex $res 4]  score [format %.4g $sc]"
  if { $sc < $bestscore } { set bestscore $sc; set bestseed $sd; set bestres $res }
  if { $niter > 1 } {
   puts "Info : seed_place, after iteration $iter best seed $bestseed score [format %.4g $bestscore]"
  }
 }
 catch { rename _sp_trial {} }
 catch { rename _sp_score_range {} }
 catch { rename _sp_score_all {} }
 set bestplaced [lindex $bestres 5]
 puts "Info : seed_place, best seed $bestseed score [format %.4g $bestscore]"

 # ---- commit the best placement to _instlist ----
 set committed 0
 foreach rec $bestplaced {
  set cid [lindex $rec 0]
  lset _instlist($cid) 4 1
  lset _instlist($cid) 5 [lindex $rec 1]
  lset _instlist($cid) 6 [lindex $rec 2]
  incr committed
 }
 # any free cell not in the winning trial's poslist (shouldn't happen since
 # the trial places every free cell, even last-resort at core origin) is
 # forced placed at the core origin so the design stays fully placed.
 array set winset {}
 foreach rec $bestplaced { set winset([lindex $rec 0]) 1 }
 foreach cid $free_cells {
  if { ! [info exists winset($cid)] } {
   lset _instlist($cid) 4 1
   lset _instlist($cid) 5 $cb_x0
   lset _instlist($cid) 6 $cb_y0
   incr committed
  }
 }
 puts "Info : seed_place, placed $committed / $nfree cells"
}

proc create_region { hmodule blx bly trx try } {
 variable regionindex
 variable _regionlist
 variable _libcell
 variable _instlist

 _require 2

 puts "Info : Create region $hmodule "
 puts ""

 set ll [list_region_instances $hmodule]

 set accu 0
 set ncell 0
  for { set j 1} { $j < [llength $ll] } { incr j } {
   
   set i [lindex $ll $j]   
   set inst $_instlist($i)
   set refid  [lindex $inst 8]     
   set fullpath  [lindex $inst 7]
   set iname   [lindex $inst 0]
   
   set szx [lindex $_libcell($refid) 1]
   set szy [lindex $_libcell($refid) 2]
   set class [lindex $_libcell($refid) 4]

   set accu [ expr $accu + $szx*$szy ]
   incr ncell
   
  }
  
 set utilz [expr 100 * $accu / (($trx-$blx) * ($try-$bly)) ]
 puts "std cell area   : $accu um"
 puts "std cell #inst  : $ncell"
 puts "region box size : [expr $trx-$blx] um *  [expr $try-$bly] um"
 puts "region box area : [expr ($trx-$blx) * ($try-$bly) ]"
 puts "region utilz    : $utilz"
 set utilz [expr $utilz *1.02]
 puts "Target utilz   : $utilz"
 
  set newregion [ list $hmodule $blx $bly $trx $try $utilz $ll ]
  set regionindex [ expr $regionindex + 1]	
  set _regionlist($regionindex) $newregion
  puts ""
 
}

proc remove_all_region { } {
 variable regionindex
 variable _regionlist
  set regionindex 0
}


proc list_region_instances { region } {
 _require 2
 variable instindex
 variable _instlist
 variable _libcell

 set retlist [ list]
 set ll [ expr [string length $region] -1 ]
 
  for { set i 1} { $i<= $instindex } { incr i } {
   set inst $_instlist($i)
   set refid  [lindex $inst 8]     
   set fullpath  [lindex $inst 7]     
   set class [lindex $_libcell($refid) 4]
   set lcell [string range $fullpath 0 $ll ]
   
   if { $class=="CORE" && $lcell==$region } {
        lappend retlist $i
      }
  }
  return $retlist
}

proc report_unplaced { } {
 _require 2
 variable instindex
 variable _instlist
 variable _libcell
 _require 2

  for { set i 1} { $i<= $instindex } { incr i } {
   set inst $_instlist($i)
   set refid  [lindex $inst 8]     
   set fullpath  [lindex $inst 7]     
   set class [lindex $_libcell($refid) 4]

   set placed  [lindex $inst 4]
   if { $placed == 0} { puts "${fullpath}/${inst}" }
  }

}



#############################################################
#
# DBASE QUERIES AND REPORTS
#
#############################################################

proc swap_refcell { instname refname } {
 _require 2
 variable _instlist
 variable pathlist

 set instid [lsearch -exact $pathlist $instname]
 incr instid

 set refcell [lindex $_instlist($instid) 1]
 
 lset _instlist($instid) 1 $refname

 puts "Info : Changed reference cell of instance $instname from $refcell to $refname "
 puts "Info : re build design is needed for change to take effect "
  
}


proc all_macro { } {
 _require 2
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable corebox
 variable topbox
 variable pathlist
 
 set macrolist [ list ]
 
 for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  set fullname [ lindex $_instlist($i) 7 ]
  set instname [ lindex $_instlist($i) 7 ]
  set refid [ lindex $_instlist($i) 8 ]
  if  { $refid >0 } { 
        set refcell $_libcell($refid)
        set class [lindex $refcell 4]
        if { $class == "BLOCK" } { lappend macrolist "[ lindex $_instlist($i) 7 ]/[ lindex $_instlist($i) 0]" }
       }
 }
 
 return $macrolist
}

proc report_all_macro { } {
 _require 2
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable corebox
 variable topbox
 variable pathlist
 _require 2
 
 set macrolist [ list ]
 
 for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  set refid [ lindex $_instlist($i) 8 ]
  if  { $refid >0 } { 
        set refcell $_libcell($refid)
        set class [lindex $refcell 4]
        if { $class == "BLOCK" } { puts "[ lindex $_instlist($i) 7 ]/[ lindex $_instlist($i) 0]      [ lindex $_instlist($i) 1] " }
       }
 }
 
 return $macrolist
}


proc all_pad { } {
 _require 2
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable corebox
 variable topbox
 variable pathlist
 
 set macrolist [ list ]
 
 puts ""
 puts "************************************************************"
 puts " report_all_macro in design : $topname "
 puts "************************************************************"
  
 for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  set fullname [ lindex $_instlist($i) 7 ]
  set instname [ lindex $_instlist($i) 0 ]
  set refid [ lindex $_instlist($i) 8 ]
  set refcell $_libcell($refid)
  set class [lindex $refcell 4]
  if { $class == "PAD" } { lappend macrolist "[ lindex $_instlist($i) 7 ]/[ lindex $_instlist($i) 0]" }
 }
 
 return $macrolist
}

proc report_cell_properties { instname } {
 variable topname
 variable topnameid
 _require 2
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist

 set instid [lsearch -exact $pathlist $instname]
 set hinstid [lsearch -exact $hpathlist $instname]

 if { $instid ==-1 && $hinstid ==-1 } { puts " Error :  $instname cell not found " ; return }

 if { $instid >-1 && $hinstid >-1 } { puts " Warning :  $instname cell is physical and hierarchical , defaulting to physical " ; set hinstid -1 }
   
 if { $hinstid == -1 } { incr  instid; set inst $_instlist($instid) }
 if { $instid  == -1 } { incr hinstid; set inst $_hinstlist($hinstid) }

 if { [lindex $inst 3] == 0 } {
   set refid [lindex $inst 8]
   set refcell $_libcell($refid)
  }
 
 puts "************************************************************"
 puts " report_cell : $instname "
 puts "************************************************************"
 puts "instance name  : [lindex $inst 0]"
 puts "reference name : [lindex $inst 1]"
 puts "top module     : [lindex $inst 2]"
 puts "is hierarchical: [lindex $inst 3]"
 puts "is physical    : [expr 1-[lindex $inst 3]]"
 puts "is placed      : [lindex $inst 4]"
 puts "X position     : [lindex $inst 5]"
 puts "Y position     : [lindex $inst 6]"
 puts "full path      : [lindex $inst 7]"

 if { [lindex $inst 3] == 0 } {
  puts "reference id   : $refid" 
  puts "Physical Width : [lindex $refcell 1]"
  puts "Physical Heigth: [lindex $refcell 2]"
  puts "Number of pins : [lindex $refcell 3]"
  puts "Class          : [lindex $refcell 4]"
 }
 
}

 

# Helper: compute the accumulated estimated wire length of the whole design
# for report_area_stats -wire. Returns a list {total nets unknown}. When
# multithreading is on (Thread loaded), the per-net wire-length computation
# is split across worker threads: each worker resolves the pin coordinates
# for its net range and sums the bounding-box half-perimeters, then the main
# thread sums the partial results. This makes the cold-cache (first call
# after build_net_conn) path parallel, which is where the cost is -- once the
# per-net cache (_wirelen_cache) is warm, report_area_stats -wire falls back
# to a cheap serial sum of cached scalars (no parallel overhead needed).
#
# Worker threads cannot see the global netdriver/netload/_instlist/pathlist
# arrays, so the main thread pre-builds two compact, self-contained indices
# and ships them via tsv:
#   netkeys  - list of net names (the union of driver and load nets)
#   netpins  - list of pin-id-lists, same order; each pin id is 1-based inst
#              id, or 0 for a port/<assign> endpoint (no coordinate)
#   ipos    - list {id x y} for every placed inst (id is 1-based). Unplaced
#              insts are omitted so workers treat them as no-coordinate.
# A worker computes, for each net in its range, the bbox of the placed pins
# (id lookup in ipos) and adds deltaX+deltaY when >=2 pins are placed; nets
# with <2 placed pins count as unknown. This mirrors _net_wirelen exactly
# (the same _pin_xy -> _inst_xy placement lookup), just parallelised and
# without the cache writes (the cache is filled lazily later by serial
# _net_wirelen_scalar calls, e.g. from report_net).
proc _ras_wire_total { } {
 global _mt_on _mt_thread_loaded _mt_workers _eval_sites_seq
 global netdriver netload netconnbuilt _wirelen_cache
 variable _instlist
 variable pathlist
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Info : wire length : (build_net_conn must run before -wire)"
  return {0 0 0}
 }
 # Union of net names (driver nets + load-only nets). Net keys can contain
 # bit-select brackets, so array names is safe (returns literal keys); the
 # dedup uses a dict keyed by the literal name.
 set netkeys {}
 set seen {}
 foreach n [array names netdriver] { dict set seen $n 1; lappend netkeys $n }
 foreach n [array names netload] { if { ! [dict exists $seen $n] } { lappend netkeys $n } }
 unset seen
 set nn [llength $netkeys]
 if { $nn == 0 } { return {0 0 0} }

 # Pre-build the inst position map: ipos(id) = {x y} for placed insts only.
 # pathlist is 0-based, inst ids are 1-based (pathlist index + 1).
 array set pathid {}
 set pi 0
 foreach p $pathlist { set pathid($p) [expr {$pi + 1}]; incr pi }
 array set ipos {}
 set npinst [llength $pathlist]
 for { set id 1 } { $id <= $npinst } { incr id } {
  set rec $_instlist($id)
  if { [lindex $rec 4] == 1 } { set ipos($id) [list [lindex $rec 5] [lindex $rec 6]] }
  }
 # Build per-net pin-id lists (drivers + loads). Port/<assign> pins have no
 # inst and map to id 0 (no coordinate).
 array set netpinids {}
 foreach n $netkeys {
  set ids {}
  if { [info exists netdriver($n)] } {
   foreach p $netdriver($n) {
    set ip [lindex $p 0]
    if { [info exists pathid($ip)] } { lappend ids $pathid($ip) } else { lappend ids 0 }
   }
  }
  if { [info exists netload($n)] } {
   foreach p $netload($n) {
    set ip [lindex $p 0]
    if { [info exists pathid($ip)] } { lappend ids $pathid($ip) } else { lappend ids 0 }
   }
  }
  set netpinids($n) $ids
  }
 # Parallel lists for tsv shipping.
 set pinids {}
 foreach n $netkeys { lappend pinids $netpinids($n) }
 # Compact ipos to a flat list {id x y ...}.
 set ipos_v {}
 foreach id [array names ipos] { lappend ipos_v $id [lindex $ipos($id) 0] [lindex $ipos($id) 1] }

 # Decide serial vs parallel. The parallel path only pays off when there is
 # enough work (resolution of many nets) and MT is on. Below the threshold or
 # with one worker, run serially through the cached scalar getter -- this also
 # populates _wirelen_cache so a later report_net benefits.
 set use_mt [expr {$_mt_on && $_mt_thread_loaded && $nn >= 256 && $_mt_workers > 1}]
 if { ! $use_mt } {
  set total 0
  set unknown 0
  set adv 0
  set j 0
  foreach n $netkeys {
   set v [_net_wirelen_scalar $n]
   if { $v >= 0 } { set total [expr {$total + $v}] } else { incr unknown }
   if {$j > [expr    $nn/100] && $adv==0 } { puts "..1%.."  ; set adv 1 }
   if {$j > [expr 1* $nn /10] && $adv==2 } { puts "..10%.." ; set adv 3 }
   if {$j > [expr 3* $nn /10] && $adv==4 } { puts "..30%.." ; set adv 5 }
   if {$j > [expr 5* $nn /10] && $adv==6 } { puts "..50%.." ; set adv 7 }
   if {$j > [expr 7* $nn /10] && $adv==8 } { puts "..70%.." ; set adv 9 }
   if {$j > [expr 9* $nn /10] && $adv==10} { puts "..90%.." ; set adv 11}
   incr j
  }
  return [list $total [llength [array names netdriver]] $unknown]
 }

 # Multithreaded resolution: split the net list into nw contiguous ranges,
 # each worker resolves + sums its range from the shipped ipos map (no globals
 # needed), returns its partial {sum unknown}. Threads self-release when done.
 puts -nonewline "Info : estimating wire length "
 set nw $_mt_workers
 if { $nw > $nn } { set nw $nn }
 set ns ras[incr _eval_sites_seq]
 tsv::set $ns netkeys $netkeys
 tsv::set $ns pinids $pinids
 tsv::set $ns ipos_v $ipos_v
 tsv::set $ns nn $nn
 tsv::set $ns nws $nw
 tsv::set $ns wid -1
 tsv::array set ras_ns cur $ns
 tsv::set ras_ns done 0
 set wscript {
  set ns [tsv::get ras_ns cur]
  set pinids [tsv::get $ns pinids]
  set ipos_v [tsv::get $ns ipos_v]
  set nn [tsv::get $ns nn]
  set nws [tsv::get $ns nws]
  set wid [tsv::incr $ns wid]
  set k0 [expr {int(($wid * $nn) / $nws)}]
  set k1 [expr {int((($wid + 1) * $nn) / $nws)}]
  # Reconstruct the id -> {x y} map from the flat ipos_v.
  array set ipos {}
  set L [llength $ipos_v]
  for { set i 0 } { $i < $L } { incr i 3 } {
   set id [lindex $ipos_v $i]
   set ipos($id) [list [lindex $ipos_v [expr {$i+1}]] [lindex $ipos_v [expr {$i+2}]]]
  }
  set sum 0.0
  set unk 0
  for { set k $k0 } { $k < $k1 } { incr k } {
   set ids [lindex $pinids $k]
   set minx 1e18; set maxx -1e18; set miny 1e18; set maxy -1e18
   set cnt 0
   foreach id $ids {
    if { $id == 0 } { continue }
    if { ! [info exists ipos($id)] } { continue }
    lassign $ipos($id) x y
    if { $x < $minx } { set minx $x }
    if { $x > $maxx } { set maxx $x }
    if { $y < $miny } { set miny $y }
    if { $y > $maxy } { set maxy $y }
    incr cnt
   }
   if { $cnt >= 2 } {
    set sum [expr {$sum + ($maxx - $minx) + ($maxy - $miny)}]
   } else {
    incr unk
   }
  }
  tsv::set $ns partial_$wid [list $sum $unk]
  tsv::incr ras_ns done
  thread::release
 }
 set workers {}
 for { set w 0 } { $w < $nw } { incr w } { lappend workers [thread::create $wscript] }
 while { [tsv::get ras_ns done] < $nw } { after 5 }
 set total 0.0
 set unknown 0
 for { set w 0 } { $w < $nw } { incr w } {
  if { [tsv::exists $ns partial_$w] } {
   lassign [tsv::get $ns partial_$w] s u
   set total [expr {$total + $s}]
   incr unknown $u
  }
 }
 return [list $total [llength [array names netdriver]] $unknown]
}

proc report_area_stats { args } {
 variable topname
 variable topnameid
 # -wire: also report the accumulated estimated wire length of the design.
 set opt_wire 0
 foreach a $args {
  if { $a eq "-wire" } { set opt_wire 1 }
 }
 _require 2
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 
 puts "********************************" 
 puts " Report_area"
 puts "********************************" 
 puts ""   
 # total accumulated std cell surface
 set accu 0
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  set refid [ lindex $_instlist($i) 8 ]
  set refcell $_libcell($refid)
  set class [lindex $refcell 4]
  set szx [lindex $refcell 1]
  set szy [lindex $refcell 2]
  set area [expr $szx * $szy ]
  
  if { $class == "CORE" } { set accu [expr $accu + $area] }
 }
 puts "Info : total std cell area $accu um2"
 puts "Info : total number of cell $instindex"
 set carea $accu

 set accu 0
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  set refid [ lindex $_instlist($i) 8 ]
  set refcell $_libcell($refid)
  set class [lindex $refcell 4]
  set szx [lindex $refcell 1]
  set szy [lindex $refcell 2]
  set area [expr $szx * $szy ]
  
  if { $class == "BLOCK" } { set accu [expr $accu + $area] }
 }
 puts "Info : total macro cell area $accu um2"
 set marea $accu

 set accu 0
  for { set i 1} { $i<= $instindex } { set i [expr $i +1] } {
  set refid [ lindex $_instlist($i) 8 ]
  set refcell $_libcell($refid)
  set class [lindex $refcell 4]
  set szx [lindex $refcell 1]
  set szy [lindex $refcell 2]
  set area [expr $szx * $szy ]
  
  if { $class == "PAD" } { set accu [expr $accu + $area] }
 }
 puts "Info : total pad cell area $accu um2"
 set parea $accu


 set sx [ expr [ lindex $corebox 2 ] - [ lindex $corebox 0 ] ]
 set sy [ expr [ lindex $corebox 3 ] - [ lindex $corebox 1 ] ]
 set corearea [expr $sx * $sy ]
 
 puts "Info : total core available area [expr $corearea ] um2" 
 puts "Info : Expected utilization for std cell is [expr 100*$carea/($corearea-$marea)]"

 # -wire: report the accumulated estimated wire length of the whole design.
 # Sums the per-net estimate over every net built by build_net_conn. Each
 # net's length is cached in _wirelen_cache (computed lazily, -1 = unknown /
 # not estimable) so repeated reports are cheap. Requires build_net_conn.
 # When multithreading is on and the design is large enough, the per-net
 # wire-length resolution is split across worker threads (see _ras_wire_total).
 if { $opt_wire } {
  global netconnbuilt
  lassign [_ras_wire_total] total nets unknown
  if { [info exists netconnbuilt] && $netconnbuilt } {
   puts "Info : total estimated wire length [format %.4g $total] um"
   puts "Info : estimated nets $nets, unknown/unestimable nets $unknown"
  }
 }
 puts "" 
}


proc update_wire_db { } {
 _require 2
 variable hinstindex
 variable _hinstlist
 variable wireindex
 variable _wiremaster
 variable _wirelist
 variable _wireinst
 variable wiresearch
 variable wiresearch_map
 variable hinstrefsearch
 variable instrefsearch 
  
 puts "Info : update nets dbase"
 array unset wiresearch_map
 set wiresearch [ list ]
 
 set adv 0
  
 # Search through all hierarchical instances
for { set j 1 } { $j <= $wireindex } { incr j } {
 set wm $_wiremaster($j)
 set _wireinst($j) "--"     
 
 set i [ lsearch -exact $hinstrefsearch $wm ]
     if {$i >-1} {
              incr i
              set inst $_hinstlist($i)	      
              set inst_name [lindex $inst 0]
              set full_path [lindex $inst 7]
              if { $full_path == "-1" } {
                      set _wireinst($j) "$inst_name/$_wirelist($j)"
                      } else {
                      set _wireinst($j) "$full_path/$inst_name/$_wirelist($j)"
                      }
	      }
 if {$j > [expr    $wireindex/100] && $adv==0 } { puts "..1%.."  ; set adv 1 }
 if {$j > [expr    $wireindex /20] && $adv==1 } { puts "..5%.."  ; set adv 2 }
 if {$j > [expr 1* $wireindex /10] && $adv==2 } { puts "..10%.." ; set adv 3 }
 if {$j > [expr 2* $wireindex /10] && $adv==3 } { puts "..20%.." ; set adv 4 }
 if {$j > [expr 3* $wireindex /10] && $adv==4 } { puts "..30%.." ; set adv 5 }
 if {$j > [expr 4* $wireindex /10] && $adv==5 } { puts "..40%.." ; set adv 6 }
 if {$j > [expr 5* $wireindex /10] && $adv==6 } { puts "..50%.." ; set adv 7 }
 if {$j > [expr 6* $wireindex /10] && $adv==7 } { puts "..60%.." ; set adv 8 }
 if {$j > [expr 7* $wireindex /10] && $adv==8 } { puts "..70%.." ; set adv 9 }
 if {$j > [expr 8* $wireindex /10] && $adv==9 } { puts "..80%.." ; set adv 10}
 if {$j > [expr 9* $wireindex /10] && $adv==10} { puts "..90%.." ; set adv 11}
 lappend wiresearch $_wireinst($j)
 if { ! [info exists wiresearch_map($_wireinst($j))] } { set wiresearch_map($_wireinst($j)) [expr {[llength $wiresearch]-1}] }
 
 }
 
}

proc list_all_pins { } {
 _require 2
 variable instindex
 variable hinstindex
 variable _instlist
 variable _hinstlist
 variable _instpinconn1
 variable _instpinconn2
 variable _hinstpinconn1
 variable _hinstpinconn2
 
 variable wireindex
 variable _wirelist
 variable _wiremaster
 variable _wireinst
 variable _wiretype
 variable _libcell
 variable topname
 variable wiresearch
 variable wiresearch_map

 puts "************************************************************"
 puts " List pins and connections"
 puts "************************************************************"

  puts "Info :  hier cell pins parsing .. "   
  for { set i 1} { $i<= $hinstindex } { incr i } {
   set inst $_hinstlist($i)
   set inst_name [lindex $inst 0]
   set ref_name [lindex $inst 1]
   set module_name [lindex $inst 2]
   set is_hierarchical [lindex $inst 3]
   set full_path [lindex $inst 7]

   for {set j 0} {$j< [llength $_hinstpinconn1($i)] } {incr j} {
     set ppin  [lindex $_hinstpinconn1($i) $j]
     set wwire [lindex $_hinstpinconn2($i) $j]
     
     set hwire "$full_path/$wwire"
     
     set s [expr {[info exists wiresearch_map($hwire)] ? $wiresearch_map($hwire) : -1}]
     
     ##if {$s>-1} {puts "$full_path/$inst_name/$ppin $full_path/$wwire   $i $ref_name"}
     if {$s==-1} {puts "$full_path/$inst_name/$ppin $full_path/$wwire   $i $i $ref_name"}
     
   }
  }
   
  puts "Info :  lib cell pins parsing .. "   
  for { set i 1} { $i<= $instindex } { incr i } {
   set inst $_instlist($i)
   set inst_name [lindex $inst 0]
   set ref_name [lindex $inst 1]
   set module_name [lindex $inst 2]
   set is_hierarchical [lindex $inst 3]
   set full_path [lindex $inst 7]

   for {set j 0} {$j< [llength $_instpinconn1($i)] } {incr j} {
     set ppin  [lindex $_instpinconn1($i) $j]
     set wwire [lindex $_instpinconn2($i) $j]
     
     set hwire "$full_path/$wwire"
     
     set s [expr {[info exists wiresearch_map($hwire)] ? $wiresearch_map($hwire) : -1}]
     
     if {$s>-1} {puts "$full_path/$inst_name/$ppin $full_path/$wwire   $i"}
     
   }
  }
  

#$_hinstpinconn1(2930)
  
}

# Build a net connectivity map for report_path:
#   netdriver(net) = list of {instname pin} that drive the net (output pins)
#   netload(net)   = list of {instname pin} that read the net (input pins)
# Top input ports act as net drivers; top output ports act as net sinks.
proc build_net_conn { } {
 _require 2
 variable topname
 variable topnameid
 variable instindex
 variable hinstindex
 variable _instlist
 variable _hinstlist
 variable _instpinconn1
 variable _instpinconn2
 variable _hinstpinconn1
 variable _hinstpinconn2
 variable _libcell
 variable _libcellpindir
 variable portindex
 variable _portlist
 variable _porttype
 variable _portmaster
 global netdriver netload

 array unset netdriver
 array unset netload

 # Continuous assignments: assign lhs = rhs makes rhs a driver of lhs.
 variable _assignlist
 foreach a $_assignlist {
  lassign $a alhs arhs amod
  lappend netdriver($alhs) "<assign> $arhs"
  lappend netload($arhs) "<assign> $alhs"
 }

 # Top ports of the top module are net drivers (inputs) or sinks (outputs).
 for {set p 1} {$p <= $portindex} {incr p} {
  if { [lindex $_portmaster($p) 0] ne $topname } { continue }
  set ports [lindex [array get _portlist $p] 1]
  if { $ports eq "" } { continue }
  for {set k 0} {$k < [llength $ports]} {incr k} {
   set pn [lindex $ports $k]
   set pt [lindex [lindex [array get _porttype $p] 1] $k]
   if { $pt eq "in" } {
     lappend netdriver($pn) "<port> $pn"
   } elseif { $pt eq "out" } {
     lappend netload($pn) "<port> $pn"
   }
  }
 }

 # Lib-cell instances: classify each pin by LEF direction.
 # Use the full hierarchical instance path (as built in pathlist) instead of
 # the bare instance name, so netdriver/netload entries are unambiguous and
 # resolve cleanly via the pathlist lookups used by report_path.
 #
 # Net names are scoped by the containing module's hierarchical path, so a
 # wire name reused in sibling submodules (e.g. "n20719" in iu0 and in cc0)
 # stays a distinct net per scope instead of collapsing into one entry.
 # Top-level wires (fullp == -1) keep the bare name so flat designs match a
 # plain net reference.
 for {set i 1} {$i <= $instindex} {incr i} {
  set inst $_instlist($i)
  set iname [lindex $inst 0]
  set ishier [lindex $inst 3]
  set refid [lindex $inst 8]
  if { $ishier != 0 } { continue }
  set fullp [lindex $inst 7]
  if { $fullp eq "-1" } { set ipath $iname } else { set ipath "$fullp/$iname" }
  set pins $_instpinconn1($i)
  set nets $_instpinconn2($i)
  set dirs [lindex [array get _libcellpindir $refid] 1]
  for {set j 0} {$j < [llength $pins]} {incr j} {
   set rawn [lindex $nets $j]
   if { $rawn eq "<bus>" } { continue }
   set pn [lindex $pins $j]
   set wn [_scoped_net $fullp $rawn]
   set dr [lindex $dirs $j]
   if { $dr eq "OUTPUT" } {
     lappend netdriver($wn) "$ipath $pn"
   } else {
     lappend netload($wn) "$ipath $pn"
   }
  }
 }

 # Hierarchical instances: pins are treated as pass-through for now (both
 # directions recorded so paths can cross hierarchy boundaries).
 for {set i 1} {$i <= $hinstindex} {incr i} {
  set inst $_hinstlist($i)
  set iname [lindex $inst 0]
  if { ! [info exists _hinstpinconn1($i)] } { continue }
  set fullp [lindex $inst 7]
  if { $fullp eq "-1" } { set ipath $iname } else { set ipath "$fullp/$iname" }
  set pins $_hinstpinconn1($i)
  set nets $_hinstpinconn2($i)
  for {set j 0} {$j < [llength $pins]} {incr j} {
   set rawn [lindex $nets $j]
   if { $rawn eq "<bus>" } { continue }
   set pn [lindex $pins $j]
   set wn [_scoped_net $fullp $rawn]
   lappend netdriver($wn) "$ipath $pn"
   lappend netload($wn) "$ipath $pn"
  }
 }

 puts "Info : built net connectivity ([llength [array names netdriver]] driver nets, [llength [array names netload]] load nets)"
 global netconnbuilt
 set netconnbuilt 1
 # Invalidate the per-net wire-length cache: connectivity/placement may have
 # changed, so any previously cached length is stale. report_net and
 # report_area_stats -wire recompute lazily and refill the cache.
 global _wirelen_cache
 array unset _wirelen_cache
}

# Helper: scope a net name by its containing module's hierarchical path. The
# instance fullp is the path of the enclosing module; a wire declared in that
# module is uniquely named as "fullp/net". At the top level (fullp == -1) the
# bare wire name is returned so flat designs keep matching plain references.
proc _scoped_net { fullp net } {
 if { $fullp eq "-1" || $fullp eq "" } { return $net }
 return "$fullp/$net"
}

# Helper: scope of a net key. For a scoped net "a/b/c/net" the scope is the
# containing module path "a/b/c"; for a bare top-level net it is the top ("-1").
proc _net_scope { key } {
 if { ! [string match {*/*} $key] } { return "-1" }
 set parts [split $key /]
 return [join [lrange $parts 0 end-1] /]
}

# Helper: ordered list of pin names of a lib cell (refid). Pin names are stored
# in the _libcell entry at indices 5..(5+pincnt-1); the count is at index 3.
proc _libcell_pins { refid } {
 variable _libcell
 if { ! [info exists _libcell($refid)] } { return {} }
 set info $_libcell($refid)
 set npin [lindex $info 3]
 set pins {}
 for {set j 0} {$j < $npin} {incr j} { lappend pins [lindex $info [expr {5+$j}]] }
 return $pins
}

# Helper: print one net row of a report_path report. The crossed net is shown
# only when -net is set; otherwise the Net column stays blank (P6). With
# -layout the wider (x, y) column layout is used; the net itself has no
# coordinate so that field stays blank.
proc _report_path_net_line { net fanout opt_net opt_layout } {
 set netcol ""
 if { $opt_net } { set netcol $net }
 if { $opt_layout } {
  puts [format "  %-38s %-17s %-7s %s" "" "" $fanout $netcol]
 } else {
  puts [format "  %-38s %-7s %s" "" $fanout $netcol]
 }
}

# Helper: print one pin row of a report_path report. With -layout the placed
# (x, y) of the instance is shown (blank for ports/assigns/unplaced) (P5).
proc _report_path_pin_line { pin opt_layout } {
 set s [_fmt_pin $pin]
 if { $opt_layout } {
  set coord [_inst_coord [lindex $pin 0]]
  puts [format "  %-38s %-17s" $s $coord]
 } else {
  puts [format "  %s" $s]
 }
}

# report_path -from <pin|net> -to <pin|net> ?-net? ?-layout?
# P4 helper: forward-only report_path (no -to). Traces forward from -from
# across all branches (BFS) and stops each branch at the first sync load pin
# (flop CP / SRAM CK via _libsyncpin). Reports every reached sync endpoint's
# path and the count of sync endpoints reached. Requires build_net_conn (P2)
# and add_lib (L2).
proc _report_path_forward { from cur_net start_point opt_net opt_layout } {
 global netdriver netload netconnbuilt
 variable pathlist
 variable hpathlist
 variable _libsyncpin

 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before report_path -from"
  return
 }
 # add_lib (L2) is required for the sync-pin map; without it no leaf can be a
 # sync endpoint, so the forward trace would reach nothing.
 if { [llength [array names _libsyncpin]] == 0 } {
  puts "Warning : no sync pins loaded (run add_lib before report_path -from)"
 }

 puts "************************************************************"
 set h " report_path : -from $from"
 if { $opt_net }    { append h " -net" }
 if { $opt_layout } { append h " -layout" }
 puts $h
 puts "************************************************************"
 if { $start_point eq "" } {
  puts "Startpoint : <net> $cur_net"
 } else {
  puts "Startpoint : [_fmt_pin $start_point]"
 }
 puts "Path type  : functional, forward to sync endpoint (no timing)"
 puts ""
 if { $opt_layout } {
  puts "  Point                                   (x, y)            Fanout   Net"
  puts "  ---------------------------------------------------------------"
 } else {
  puts "  Point                                   Fanout   Net"
  puts "  -------------------------------------------------------"
 }

 # BFS across all branches. Each reached sync load pin becomes a discovered
 # endpoint; the parent map records how each net was reached so the path can
 # be reconstructed. A net is visited once (combinational loops cannot recurse).
 array set seen_net {}
 array set parent_net {}
 array set via_inst {}
 array set via_pin {}
 set q [list $cur_net]
 set seen_net($cur_net) 1
 set endpoints [list]
 while {[llength $q]} {
  set net [lindex $q 0]
  set q [lrange $q 1 end]
  set loads [_net_loads $net]
  foreach lp $loads {
   set ln [lindex $lp 0]
   set lpin [lindex $lp 1]
   if { $ln eq "<port>" } { continue }
   if { $ln eq "<assign>" } {
    set out_net $lpin
   } elseif { [lsearch -exact $hpathlist $ln] >= 0 } {
    set out_net [_hier_pin_inner_net $ln $lpin]
   } elseif { [_is_sync_pin $ln $lpin] } {
    # First sync endpoint on this branch: record it and stop the branch.
    lappend endpoints [list $net $ln $lpin]
    continue
   } else {
    set out_net [_cell_out_net $ln $lpin]
   }
   if { $out_net eq "" } { continue }
   if { [info exists seen_net($out_net)] } { continue }
   set seen_net($out_net) 1
   set parent_net($out_net) $net
   set via_inst($out_net) $ln
   set via_pin($out_net) $lpin
   lappend q $out_net
  }
 }

 # Emit one path block per reached sync endpoint, plus a count.
 set nendp [llength $endpoints]
 set idx 0
 foreach ep $endpoints {
  incr idx
  set ep_net [lindex $ep 0]
  set ep_inst [lindex $ep 1]
  set ep_pin [lindex $ep 2]
  puts "--- path $idx to [_fmt_pin "$ep_inst $ep_pin"] (sync endpoint) ---"
  if { $start_point ne "" } {
   _report_path_pin_line $start_point $opt_layout
  }
  set path [list]
  set n $ep_net
  while { $n ne $cur_net && [info exists parent_net($n)] } {
   set path [list $n {*}$path]
   set n $parent_net($n)
  }
  set prev_net $cur_net
  foreach seg $path {
   set fanout [llength [_net_loads $prev_net]]
   set ln $via_inst($seg)
   set lpin $via_pin($seg)
   _report_path_net_line $prev_net $fanout $opt_net $opt_layout
   _report_path_pin_line "$ln $lpin" $opt_layout
   set prev_net $seg
  }
  set fanout [llength [_net_loads $ep_net]]
  _report_path_net_line $ep_net $fanout $opt_net $opt_layout
  _report_path_pin_line "$ep_inst $ep_pin" $opt_layout
  if { $opt_layout } {
   puts "  ---------------------------------------------------------------"
  } else {
   puts "  -------------------------------------------------------"
  }
 }
 if { ! $nendp } {
  puts "No sync endpoint reached from $from."
 } else {
  puts "$nendp sync endpoint(s) reached."
 }
 puts ""
}

# Text-only connectivity report (report_timing-style, no timing). Traces a path
# from a source point to a sink point across the net connectivity map built by
# build_net_conn. A point is either a net name or a pin "inst/pin".
#   -net    : also print the logical nets crossed (by default only the pins are
#             listed and the Net column stays blank) (P6).
#   -layout : add an (x, y) coordinate column for placed crossed cells/pins;
#             nets/ports/unplaced cells stay blank (P5).
proc report_path { args } {
 _require 2
 variable topname
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable instindex
 variable hinstindex
 global netdriver netload netconnbuilt
 variable pathlist
 variable hpathlist
 variable _libsyncpin

 set from ""
 set to ""
 set opt_net 0
 set opt_layout 0
 for {set i 0} {$i < [llength $args]} {incr i} {
  set a [lindex $args $i]
  if { $a eq "-from" }   { set from [lindex $args [incr i]] ; continue }
  if { $a eq "-to" }     { set to [lindex $args [incr i]] ; continue }
  if { $a eq "-net" }    { set opt_net 1 ; continue }
  if { $a eq "-layout" } { set opt_layout 1 ; continue }
  puts "Error : unknown option '$a'"
  puts "Usage: report_path -from <pin|net> -to <pin|net> ?-net? ?-layout?"
  puts "       report_path -from <pin|net> ?-net? ?-layout?"
  return
 }
 if { $from eq "" } {
  puts "Error : report_path requires -from"
  puts "Usage: report_path -from <pin|net> -to <pin|net> ?-net? ?-layout?"
  puts "       report_path -from <pin|net> ?-net? ?-layout?"
  return
 }
 # Both modes trace the net connectivity map, so build_net_conn must have run.
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before report_path"
  return
 }

 # Resolve the -from point into a starting (net, inst, pin).
 # A point is a pin "inst/pin" only if that instance and pin exist; otherwise
 # it is treated as a net (net names may themselves contain '/').
 set cur_net ""
 set start_point ""
 set from_is_pin 0
 if { [regexp {^(.*)/([^/]+)$} $from -> inst pin] } {
  set n [_pin_net $inst $pin]
  if { $n ne "" } {
   set start_point "$inst $pin"
   set cur_net $n
   set from_is_pin 1
  }
 }
 if { ! $from_is_pin } {
  set cur_net [_resolve_net $from]
  set d [_net_drivers $cur_net]
  if { [llength $d] } { set start_point [lindex $d 0] }
 }
 if { $cur_net eq "" } { puts "Error : -from point $from not found" ; return }

 # P4: with only -from (no -to), trace forward to the nearest sync load pin
 # (flop CP / SRAM CK via _libsyncpin) along every branch, stop at the first
 # sync endpoint found on each branch, and report the path(s) reached plus the
 # count of sync endpoints. Requires build_net_conn (P2) and add_lib (L2).
 if { $to eq "" } {
  _report_path_forward $from $cur_net $start_point $opt_net $opt_layout
  return
 }

 # Resolve the -to point similarly.
 set end_net ""
 set end_point ""
 set to_is_pin 0
 if { [regexp {^(.*)/([^/]+)$} $to -> inst pin] } {
  set n [_pin_net $inst $pin]
  if { $n ne "" } {
   set end_point "$inst $pin"
   set end_net $n
   set to_is_pin 1
  }
 }
 if { ! $to_is_pin } {
  set end_net [_resolve_net $to]
  set l [_net_loads $end_net]
  if { [llength $l] } { set end_point [lindex $l 0] }
  if { $end_point eq "" } { set end_point "<net> $end_net" }
 }
 if { $end_net eq "" } { puts "Error : -to point $to not found" ; return }

 puts "************************************************************"
 set h2 " report_path : -from $from -to $to"
 if { $opt_net }    { append h2 " -net" }
 if { $opt_layout } { append h2 " -layout" }
 puts $h2
 puts "************************************************************"
 if { $start_point eq "" } {
  puts "Startpoint : <net> $cur_net"
 } else {
  puts "Startpoint : [_fmt_pin $start_point]"
 }
 if { $end_point eq "" } {
  puts "Endpoint   : <net> $end_net"
 } else {
  puts "Endpoint   : [_fmt_pin $end_point]"
 }
 puts "Path type  : functional (no timing)"
 puts ""
 # Column header. -layout adds an (x, y) column for placed instance pins
 # (nets/ports stay blank); -net keeps the crossed-net column visible (by
 # default only the pins are listed and the Net column is blank).
 if { $opt_layout } {
  puts "  Point                                   (x, y)            Fanout   Net"
  puts "  ---------------------------------------------------------------"
 } else {
  puts "  Point                                   Fanout   Net"
  puts "  -------------------------------------------------------"
 }

 # BFS from cur_net toward end_net via loads, following each load pin's
 # cell output. Unlike a single greedy walk, all load branches are explored,
 # so a path through any branch (not just the first) is found. A parent map
 # records how each net was reached so the path can be reconstructed.
 array set seen_net {}
 array set parent_net {}
 array set via_inst {}
 array set via_pin {}
 set q [list $cur_net]
 set seen_net($cur_net) 1
 set found 0
 while {[llength $q]} {
  set net [lindex $q 0]
  set q [lrange $q 1 end]
  if { $net eq $end_net } { set found 1 ; break }
  set loads [_net_loads $net]
  foreach lp $loads {
   set ln [lindex $lp 0]
   set lpin [lindex $lp 1]
   if { $ln eq "<port>" } { continue }
   if { $ln eq "<assign>" } {
    set out_net $lpin
   } else {
    set out_net [_cell_out_net $ln $lpin]
   }
   if { $out_net eq "" } { continue }
   if { [info exists seen_net($out_net)] } { continue }
   set seen_net($out_net) 1
   set parent_net($out_net) $net
   set via_inst($out_net) $ln
   set via_pin($out_net) $lpin
   lappend q $out_net
  }
 }

 # Reconstruct the path of nets from cur_net to end_net.
 set path [list]
 if { $found } {
  set n $end_net
  while { $n ne $cur_net } {
   set path [list $n {*}$path]
   set n $parent_net($n)
  }
 }

 # Emit the report. Each net line lists the crossed net (only with -net,
 # otherwise blank) and fanout; each pin line lists the pin, its (x, y) with
 # -layout, and the cell name. Columns stay aligned for both layouts.
 if { $start_point ne "" } {
  _report_path_pin_line $start_point $opt_layout
 }
 set prev_net $cur_net
 foreach seg $path {
  set fanout [llength [_net_loads $prev_net]]
  set ln $via_inst($seg)
  set lpin $via_pin($seg)
  _report_path_net_line $prev_net $fanout $opt_net $opt_layout
  _report_path_pin_line "$ln $lpin" $opt_layout
  set prev_net $seg
 }
 if { $found } {
  set fanout [llength [_net_loads $end_net]]
  _report_path_net_line $end_net $fanout $opt_net $opt_layout
 }
 if { $opt_layout } {
  puts "  ---------------------------------------------------------------"
 } else {
  puts "  -------------------------------------------------------"
 }
 if { $found } {
  puts "1 path found."
 } else {
  puts "No path found between $from and $to."
 }
 puts ""
}

# Helper: net connected to a given instance pin (inst pin).
proc _pin_net { inst pin } {
 variable _instlist
 variable _hinstlist
 variable _instpinconn1
 variable _instpinconn2
 variable _hinstpinconn1
 variable _hinstpinconn2
 variable instindex
 variable hinstindex
 variable pathlist
 variable hpathlist
 set iid [lsearch -exact $pathlist $inst]
 if { $iid >= 0 } {
  incr iid
  if { [info exists _instpinconn1($iid)] } {
   set k [lsearch -exact $_instpinconn1($iid) $pin]
   if { $k >= 0 } {
    set rawn [lindex $_instpinconn2($iid) $k]
    if { $rawn eq "<bus>" } { return "" }
    set fullp [lindex $_instlist($iid) 7]
    return [_scoped_net $fullp $rawn]
   }
  }
 }
 set hid [lsearch -exact $hpathlist $inst]
 if { $hid >= 0 } {
  incr hid
  if { [info exists _hinstpinconn1($hid)] } {
   set k [lsearch -exact $_hinstpinconn1($hid) $pin]
   if { $k >= 0 } {
    set rawn [lindex $_hinstpinconn2($hid) $k]
    if { $rawn eq "<bus>" } { return "" }
    set fullp [lindex $_hinstlist($hid) 7]
    return [_scoped_net $fullp $rawn]
   }
  }
 }
 return ""
}

# Helper: output net of a cell given one of its (input) pins.
proc _hier_pin_inner_net { inst pin } {
 variable _hinstlist
 variable _hinstpinconn1
 variable _hinstpinconn2
 variable hpathlist
 set hid [lsearch -exact $hpathlist $inst]
 if { $hid < 0 } { return "" }
 incr hid
 # The inner net is the pin name scoped by the instance's OWN full path
 # (e.g. core0/w0/clk), which is the $inst argument itself.
 return "$inst/$pin"
}

# Helper: output net of a cell given one of its (input) pins.
proc _cell_out_net { inst pin } {
 variable _instlist
 variable _instpinconn1
 variable _instpinconn2
 variable _libcell
 variable _libcellpindir
 variable pathlist
 set iid [lsearch -exact $pathlist $inst]
 if { $iid < 0 } { return "" }
  incr iid
 if { ! [info exists _instpinconn1($iid)] } { return "" }
 set pins $_instpinconn1($iid)
 set nets $_instpinconn2($iid)
 set refid [lindex $_instlist($iid) 8]
 set fullp [lindex $_instlist($iid) 7]
 set dirs [lindex [array get _libcellpindir $refid] 1]
 for {set j 0} {$j < [llength $pins]} {incr j} {
  if { [lindex $dirs $j] eq "OUTPUT" } { return [_scoped_net $fullp [lindex $nets $j]] }
 }
 return ""
}

# Helper: format a pin "inst pin" as "inst/pin (cell, pin dir)".
proc _fmt_pin { p } {
 variable _instlist
 variable _libcell
 variable _libcellpindir
 variable pathlist
 set iname [lindex $p 0]
 set pin [lindex $p 1]
 if { $iname eq "<port>" } { return "$pin (port)" }
 if { $iname eq "<assign>" } { return "assign $pin" }
 set iid [lsearch -exact $pathlist $iname]
 if { $iid < 0 } { return "$iname/$pin" }
 incr iid
 set refid [lindex $_instlist($iid) 8]
 set cname [lindex $_libcell($refid) 0]
 return "$iname/$pin ($cname)"
}

# Helper: (x, y) placement of an instance, or "" when unplaced / a port /
# assign. Used by report_path -layout to add a coordinate column for crossed
# cells; nets have no coordinate and stay blank.
proc _inst_coord { inst } {
 variable _instlist
 variable pathlist
 if { $inst eq "<port>" || $inst eq "<assign>" } { return "" }
 set iid [lsearch -exact $pathlist $inst]
 if { $iid < 0 } { return "" }
 incr iid
 if { [lindex $_instlist($iid) 4] != 1 } { return "" }
 set x [lindex $_instlist($iid) 5]
 set y [lindex $_instlist($iid) 6]
 # Strip float rounding noise (e.g. 45.89999999999992 -> 45.9).
 set x [format %.4g $x]
 set y [format %.4g $y]
 return "($x, $y)"
}

# Helper: numeric (x, y) placement of an instance as a list {x y}, or "" when
# unplaced / a port / assign. Used by wire-length estimation in report_net.
proc _inst_xy { inst } {
 variable _instlist
 variable pathlist
 if { $inst eq "<port>" || $inst eq "<assign>" } { return "" }
 set iid [lsearch -exact $pathlist $inst]
 if { $iid < 0 } { return "" }
 incr iid
 if { [lindex $_instlist($iid) 4] != 1 } { return "" }
 set x [lindex $_instlist($iid) 5]
 set y [lindex $_instlist($iid) 6]
 return [list $x $y]
}

# Helper: numeric (x, y) of an instance pin (a {inst pin} pair), or "" when
# the instance is unplaced / a port / assign. Used by wire-length estimation
# in report_net (W1).
proc _pin_xy { p } {
 return [_inst_xy [lindex $p 0]]
}

# Helper: resolve a -from/-to point that is a net (not an inst/pin). Net
# names are stored scoped by their containing module's hierarchical path
# (e.g. "core0/w0/nv_c0/c0/iu0/n20719"), so a full hierarchical reference
# matches directly. A bare top-level name is also tried, and finally the
# trailing token is matched for a partial reference; the most specific match
# (full path, then bare, then tail) wins so distinct same-named nets in
# sibling scopes are not collapsed.
proc _resolve_net { s } {
 global netdriver netload
 if { [info exists netdriver($s)] || [info exists netload($s)] } { return $s }
 if { [regexp {/([^/]+)$} $s -> tail] } {
  if { [info exists netdriver($tail)] || [info exists netload($tail)] } { return $tail }
 }
 return ""
}

# Helpers: return the driver/load list of a net by EXACT key. Net keys can
# contain bit-select brackets (e.g. "alu/result[0]"), and `array get` treats the
# argument as a glob pattern so the brackets would be parsed as a character
# class and the lookup silently fails. These helpers use info exists + direct
# indexing instead, so bracket keys look up correctly.
proc _net_drivers { n } {
 global netdriver
 if { [info exists netdriver($n)] } { return $netdriver($n) }
 return {}
}
proc _net_loads { n } {
 global netload
 if { [info exists netload($n)] } { return $netload($n) }
 return {}
}

# get_cell <pattern> ?-hier?
# Return the list (collection) of cells (leaf and hierarchical) whose full
# hierarchical instance path matches the glob pattern. Wildcards are the
# standard glob ones (*, ?, [..]). Nothing is printed; callers capture the
# returned list, e.g. 'set cells [get_cell core0/w0/*]'.
#
# By default (no -hier) only the DIRECT children of the scope implied by the
# pattern are returned:
#   get_cell *             -> top-level instances only
#   get_cell core0/w0/*    -> direct children of core0/w0 only
#   get_cell *reg*         -> top-level instances matching *reg* only
# This matches the common EDA convention that a non-hierarchical query stays
# within one scope. With -hier the match is cross-hierarchy (the previous
# behaviour): every instance whose full path matches the pattern is returned,
# at any depth.
proc get_cell { args } {
 variable instindex
 variable hinstindex
 variable _instlist
 variable _hinstlist
 variable _libcell
 variable pathlist
 variable hpathlist

 _require 2

 if { [llength $args] == 0 } {
  puts "Error : get_cell requires a pattern"
  puts "Usage: get_cell <pattern> ?-hier?"
  return
 }
 set pattern [lindex $args 0]
 set hier 0
 foreach a [lrange $args 1 end] {
  if { $a eq "-hier" } { set hier 1 ; continue }
  puts "Error : unknown option '$a'"
  puts "Usage: get_cell <pattern> ?-hier?"
  return
 }

 # In the default (non-hier) mode, restrict the match to the direct children
 # of the scope implied by the pattern. The scope is the literal prefix of
 # the pattern up to the last component that still contains no wildcard; a
 # bare pattern with no '/' scopes to the top level. "-1" marks the top.
 set scope "-1"
 if { ! $hier } {
  if { [string match {*/*} $pattern] } {
   set parts [split $pattern /]
   set pre {}
   foreach p $parts {
    if { [string match {*[?*]*} $p] || [string match {*\[*\]*} $p] } { break }
    lappend pre $p
   }
   if { [llength $pre] } { set scope [join $pre /] }
  }
 }

 set cells {}
 for { set i 1 } { $i <= $instindex } { incr i } {
  set fullp [lindex $_instlist($i) 7]
  if { ! $hier && $fullp ne $scope } { continue }
  set iname [lindex $_instlist($i) 0]
  if { $fullp eq "-1" } { set ipath $iname } else { set ipath "$fullp/$iname" }
  if { [string match $pattern $ipath] } {
   lappend cells $ipath
  }
 }
 for { set i 1 } { $i <= $hinstindex } { incr i } {
  set fullp [lindex $_hinstlist($i) 7]
  if { ! $hier && $fullp ne $scope } { continue }
  set iname [lindex $_hinstlist($i) 0]
  if { $fullp eq "-1" } { set ipath $iname } else { set ipath "$fullp/$iname" }
  if { [string match $pattern $ipath] } {
   lappend cells $ipath
  }
 }
 return $cells
}

# get_lib_cell <refname>
# Return the list (collection) of library-cell references (refnames) whose
# name matches the glob pattern (standard globs: *, ?, [..]). A bare refname
# with no wildcard is an exact lookup. Nothing is printed; callers capture the
# returned list, e.g. 'set cells [get_lib_cell SP*]' ->
# {SP128X33M2 SP128X33M4 SP512X40M2 SP512X40M4}. Unlike get_cell/get_net this
# queries the loaded library (cataloglist / _libcell), so it works as soon as
# a LEF has been imported and does not require a design to be set or built.
proc get_lib_cell { pattern } {
 variable cellindex
 variable _libcell
 variable _libcellpindir
 variable cataloglist

 if { $pattern eq "" } {
  puts "Error : get_lib_cell requires a pattern"
  puts "Usage: get_lib_cell <refname>"
  return
 }

 set names {}
 for { set i 1 } { $i <= $cellindex } { incr i } {
  if { ! [info exists _libcell($i)] } { continue }
  set info $_libcell($i)
  set cname [lindex $info 0]
  if { ! [string match $pattern $cname] } { continue }
  lappend names $cname
 }
 return $names
}

# get_net <pattern> ?-hier?
# Return the list (collection) of nets whose (scoped) name matches the glob
# pattern. Net names are stored scoped by their containing module's
# hierarchical path (e.g. "core0/w0/nv_c0/c0/iu0/n20719"); top-level nets keep
# the bare name. Wildcards are the standard glob ones (*, ?, [..]). Nothing is
# printed; callers capture the returned list, e.g. 'set nets [get_net n2*]'.
#
# By default (no -hier) only the nets of the SINGLE scope implied by the
# pattern are returned:
#   get_net *                    -> top-level nets only
#   get_net core0/w0/nv_c0/c0/*  -> nets declared in core0/w0/nv_c0/c0 only
#   get_net n2*                  -> top-level nets matching n2* only
# With -hier the match is cross-hierarchy: every net whose full scoped name
# matches the pattern is returned, at any depth.
proc get_net { args } {
 global netdriver netload

 _require 2

 if { [llength $args] == 0 } {
  puts "Error : get_net requires a pattern"
  puts "Usage: get_net <pattern> ?-hier?"
  return
 }
 set pattern [lindex $args 0]
 set hier 0
 foreach a [lrange $args 1 end] {
  if { $a eq "-hier" } { set hier 1 ; continue }
  puts "Error : unknown option '$a'"
  puts "Usage: get_net <pattern> ?-hier?"
  return
 }

 # In the default (non-hier) mode, restrict the match to nets whose scope
 # equals the scope implied by the pattern: the pattern minus its last path
 # component (the net-name filter). A bare pattern with no '/' scopes to the
 # top level. So "a/b/c/*" scopes to a/b/c, and an exact "a/b/c/n2" also
 # scopes to a/b/c (its parent module).
 set scope "-1"
 if { ! $hier && [string match {*/*} $pattern] } {
  set parts [split $pattern /]
  set scope [join [lrange $parts 0 end-1] /]
 }

 # Collect the union of all known net keys, then filter by scope (non-hier)
 # and by the glob pattern. De-duplicate via an array (O(1)) rather than a
 # list search so the command stays fast on large designs.
 array set seen {}
 foreach name [array names netdriver] { set seen($name) 1 }
 foreach name [array names netload]   { set seen($name) 1 }

 set nets {}
 foreach k [lsort [array names seen]] {
  if { ! $hier && [_net_scope $k] ne $scope } { continue }
  if { [string match $pattern $k] } { lappend nets $k }
 }

 return $nets
}

# all_connected <net or pin>
# Report the nets connected to a net or pin. A pin "inst/pin" argument
# reports the single net that pin is on. A net argument may use globs
# (*, ?, [..]); like get_net, the match is scoped: only nets of the single
# scope implied by the pattern are reported (the pattern minus its last path
# component; a bare name with no '/' scopes to the top level). So
# "all_connected n77" reports only the top-level net n77 (not same-named nets
# reused in submodules), and "all_connected core0/w0/n77" reports only that
# scope's net. If the net is not in that hierarchy, nothing is found.
proc all_connected { pattern } {
 _require 2
 global netdriver netload netconnbuilt
 variable pathlist
 variable hpathlist

 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before all_connected"
  return
 }
 puts "************************************************************"
 puts " all_connected : $pattern"
 puts "************************************************************"

 # If the argument resolves to a pin, report that pin's net.
 if { [regexp {^(.*)/([^/]+)$} $pattern -> inst pin] } {
  set n [_pin_net $inst $pin]
  if { $n ne "" } {
   puts "  pin $pattern is on net $n"
   _report_net $n
   return
  }
 }

 # Otherwise treat the argument as a net pattern, scoped like get_net: the
 # scope is the pattern minus its last path component (top level "-1" for a
 # bare name). Only nets whose containing scope equals this scope AND whose
 # scoped name matches the pattern are reported, so same-named nets in sibling
 # submodules are not pulled in.
 set scope "-1"
 if { [string match {*/*} $pattern] } {
  set parts [split $pattern /]
  set scope [join [lrange $parts 0 end-1] /]
 }

 array set seen {}
 foreach name [array names netdriver] { set seen($name) 1 }
 foreach name [array names netload]   { set seen($name) 1 }

 set nets2 {}
 foreach k [lsort [array names seen]] {
  if { [_net_scope $k] ne $scope } { continue }
  if { [string match $pattern $k] } { lappend nets2 $k }
 }

 if { [llength $nets2] == 0 } {
  puts "No net matches $pattern."
  puts ""
  return
 }
 foreach n $nets2 { _report_net $n }
 puts "  -------------------------------------------------------"
 set nm [llength $nets2]
 if { $nm == 1 } { puts "$nm net matching $pattern." } else { puts "$nm nets matching $pattern." }
 puts ""
}

# Helper: print the drivers and receivers of a single net.
proc _report_net { n } {
 global netdriver netload
 puts "  net $n"
 set d [_net_drivers $n]
 if { [llength $d] } {
  puts "    drivers :"
  foreach p $d { puts "      [_fmt_pin $p]" }
 } else {
  puts "    drivers : (none)"
 }
 set l [_net_loads $n]
 if { [llength $l] } {
  puts "    receivers :"
  foreach p $l { puts "      [_fmt_pin $p]" }
 } else {
  puts "    receivers : (none)"
 }
}

# G4 report_net <net>
# Report a single net: its driver(s), receiver(s) and the full list of
# connected instance pins. The net is scoped like get_net/all_connected: the
# trailing token is the net name and the prefix (the path before the last
# '/') is the containing hierarchical scope; a bare name with no '/' is a
# top-level net. Requires build_net_conn (P2) to have run first.
proc report_net { net } {
 global netdriver netload netconnbuilt

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before report_net"
  return
 }
 if { $net eq "" } {
  puts "Error : report_net requires a net name"
  puts "Usage: report_net <net>"
  return
 }

 # Resolve the scoped net key the same way get_net/all_connected scope a
 # net: only nets whose containing scope equals the scope implied by the
 # argument (the path before the last '/') are considered, so a same-named
 # net reused in a sibling submodule is never collapsed onto another. A
 # bare name scopes to the top level. The first matching key (preferably an
 # exact match) is reported.
 set key [_report_net_resolve $net]
 if { $key eq "" } {
  puts "Error : net $net not found"
  return
 }

 puts "************************************************************"
 puts " report_net : $net"
 puts "************************************************************"
 _report_net_detail $key
 puts ""
}

# Helper for report_net: resolve a net argument to a single scoped net key,
# using the same scope rule as get_net/all_connected (scope = path before the
# last '/', top level for a bare name). The exact scoped name is preferred; if
# not present, any net of that scope whose name matches the glob is accepted.
# A bus base name (e.g. "alu/result") also aggregates its per-bit members
# (alu/result[0]..[31]); this is reported only when no scalar key exists.
proc _report_net_resolve { net } {
 global netdriver netload

 if { [info exists netdriver($net)] || [info exists netload($net)] } {
  return $net
 }

 set scope "-1"
 if { [string match {*/*} $net] } {
  set parts [split $net /]
  set scope [join [lrange $parts 0 end-1] /]
 }

 foreach k [array names netdriver] {
  if { [_net_scope $k] ne $scope } { continue }
  if { [string match $net $k] } { return $k }
 }
 foreach k [array names netload] {
  if { [_net_scope $k] ne $scope } { continue }
  if { [string match $net $k] } { return $k }
 }
 return ""
}

# G4 report_pin <inst>/<pin>
# Report a single instance pin: its direction, the net it is on, and that
# net's driver(s), receiver(s) and connected instance pins. Requires
# build_net_conn (P2) to have run first. For a leaf cell the direction comes
# from the LEF (_libcellpindir); for a hierarchical instance the direction
# comes from the module's port declaration (_porttype), since a hierarchical
# instance has no LEF entry.
proc report_pin { pin } {
 global netdriver netload netconnbuilt
 variable _instlist
 variable _instpinconn1
 variable _instpinconn2
 variable _hinstlist
 variable _hinstpinconn1
 variable _hinstpinconn2
 variable _libcellpindir
 variable _portlist
 variable _porttype
 variable pathlist
 variable hpathlist
 variable hierlistdef

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before report_pin"
  return
 }
 if { $pin eq "" } {
  puts "Error : report_pin requires an instance pin"
  puts "Usage: report_pin <inst>/<pin>"
  return
 }
 if { ! [regexp {^(.*)/([^/]+)$} $pin -> inst pinname] } {
  puts "Error : pin must be given as <inst>/<pin>"
  return
 }

 # Look up the pin direction and the net it is on.
 set dir ""
 set netkey [_pin_net $inst $pinname]
 set iid [lsearch -exact $pathlist $inst]
 if { $iid >= 0 } {
  incr iid
  set k [lsearch -exact $_instpinconn1($iid) $pinname]
  if { $k >= 0 } {
   set refid [lindex $_instlist($iid) 8]
   set dirs [lindex [array get _libcellpindir $refid] 1]
   set dir [lindex $dirs $k]
  }
 } else {
  set hid [lsearch -exact $hpathlist $inst]
  if { $hid >= 0 } {
   incr hid
   if { [info exists _hinstpinconn1($hid)] } {
    set k [lsearch -exact $_hinstpinconn1($hid) $pinname]
    if { $k >= 0 } {
     # Hierarchical instance: direction comes from the module's port
     # declaration, not from a LEF entry (refid is 0 here). The instance's
     # own module is at _hinstlist index 1; its portindex is its position
     # in hierlistdef (1-based) + 1.
     set modname [lindex $_hinstlist($hid) 1]
     set mid [lsearch -exact $hierlistdef $modname]
     if { $mid >= 0 } {
      set pid [expr {$mid + 1}]
      set pnames [lindex [array get _portlist $pid] 1]
      set ptypes [lindex [array get _porttype $pid] 1]
      set pk [lsearch -exact $pnames $pinname]
      if { $pk >= 0 } {
       set pt [lindex $ptypes $pk]
       if { [lindex $pt 0] eq "bus" } {
        set dir [_port_kw [lindex $pt 1]]
       } else {
        set dir [_port_kw $pt]
       }
      }
     }
    }
   }
  }
 }

 puts "************************************************************"
 puts " report_pin : $pin"
 puts "************************************************************"
 if { $dir eq "" } { set dir "(unknown)" }
 puts "  pin $pin  direction: $dir"
 if { $netkey eq "" } {
  puts "  not connected to a scalar net"
  puts ""
  return
 }
 puts "  net $netkey"
 _report_net_detail $netkey
 puts ""
}

# Helper: print a net's drivers, receivers and the connected instance pins
# (drivers + receivers grouped), with counts.
proc _report_net_detail { n } {
 global netdriver netload
 set d [_net_drivers $n]
 set l [_net_loads $n]
 if { [llength $d] } {
  puts "    drivers ([llength $d]) :"
  foreach p $d { puts "      [_fmt_pin $p]" }
 } else {
  puts "    drivers : (none)"
 }
 if { [llength $l] } {
  puts "    receivers ([llength $l]) :"
  foreach p $l { puts "      [_fmt_pin $p]" }
 } else {
  puts "    receivers : (none)"
 }
 set nc [expr {[llength $d] + [llength $l]}]
 puts "    connected pins: $nc"

 # Wire-length estimation (W1): from the placed (x, y) of the driver and
 # receiver instance pins, take the bounding box (min/max x, min/max y) of
 # all placed pins on the net. The estimated Manhattan half-perimeter wire
 # length is deltaX + deltaY. The bounding-box corners are also reported.
 # Unplaced pins, hierarchical pins, ports and assigns have no coordinate
 # and are skipped.
 set w [_net_wirelen $n]
 if { $w eq "" } {
  puts "    wire length   : (unavailable - fewer than 2 placed pins)"
 } else {
  lassign $w est deltax deltay minx miny maxx maxy
  puts "    wire length   : estimated $est (deltaX $deltax + deltaY $deltay)"
  puts "    bounding box  : ($minx, $miny) - ($maxx, $maxy)"
 }
}

# Helper: compute the wire-length estimate for a scoped net key. Returns a
# list {est deltax deltay minx miny maxx maxy} with all values formatted to
# %.4g, or "" when fewer than 2 placed pins are on the net (so no bounding
# box can be formed). Used by report_net (_report_net_detail) and the
# report_net_wirelen getter. Unplaced pins, hierarchical pins, ports and
# assigns have no coordinate and are skipped.
proc _net_wirelen { n } {
 global netdriver netload _wirelen_cache
 set d [_net_drivers $n]
 set l [_net_loads $n]
 set coords {}
 foreach p [concat $d $l] { set c [_pin_xy $p]; if { $c ne "" } { lappend coords $c } }
 if { [llength $coords] < 2 } {
  # Cache as unknown (-1) so report_area_stats -wire can sum without
  # recomputing the geometry for every net on each call.
  set _wirelen_cache($n) -1
  return ""
 }
 set minx [lindex [lindex $coords 0] 0]
 set maxx $minx
 set miny [lindex [lindex $coords 0] 1]
 set maxy $miny
 foreach c $coords {
  set cx [lindex $c 0]
  set cy [lindex $c 1]
  if { $cx < $minx } { set minx $cx }
  if { $cx > $maxx } { set maxx $cx }
  if { $cy < $miny } { set miny $cy }
  if { $cy > $maxy } { set maxy $cy }
 }
 set deltax [expr {$maxx - $minx}]
 set deltay [expr {$maxy - $miny}]
 set est [expr {$deltax + $deltay}]
 set _wirelen_cache($n) $est
 return [list [format %.4g $est] [format %.4g $deltax] [format %.4g $deltay] [format %.4g $minx] [format %.4g $miny] [format %.4g $maxx] [format %.4g $maxy]]
}

# Helper: return the cached scalar wire-length estimate for a scoped net key,
# computing it on first use. Returns the numeric estimate, or -1 when the net
# has fewer than 2 placed pins (unknown / not estimable). Used by
# report_area_stats -wire and report_net_wirelen. The cache (_wirelen_cache)
# is invalidated by build_net_conn.
proc _net_wirelen_scalar { n } {
 global _wirelen_cache
 if { [info exists _wirelen_cache($n)] } {
  return $_wirelen_cache($n)
 }
 set w [_net_wirelen $n]
 if { $w eq "" } { return -1 }
 return [lindex $w 0]
}

# W1 report_net_wirelen <net>
# Return the estimated Manhattan wire length (deltaX + deltaY) of a net as a
# number, or "" when fewer than 2 placed pins are on the net (unavailable).
# Same scope rule as report_net (scope = path before the last '/', top level
# for a bare name). Requires build_net_conn (P2). Getter counterpart to the
# wire-length line printed by report_net.
proc report_net_wirelen { net } {
 global netconnbuilt
 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before report_net_wirelen"
  return ""
 }
 if { $net eq "" } {
  puts "Error : report_net_wirelen requires a net name"
  return ""
 }
 set key [_report_net_resolve $net]
 if { $key eq "" } {
  puts "Error : net $net not found"
  return ""
 }
 set v [_net_wirelen_scalar $key]
 if { $v < 0 } { return "" }
 return $v
}

# E1 create_net <netname>
# Create a new net inside a scope. The trailing token is the net name and the
# prefix (the path before the last '/') is the containing hierarchical scope; a
# bare name with no '/' creates a top-level net. The net is registered as an
# empty entry in the netdriver/netload map so get_net/all_connected see it and
# it can later receive pins via connect_net (E4). Requires build_net_conn (P2)
# to have run first, since ECO commands mutate that map.
proc create_net { netname } {
 global netdriver netload netconnbuilt

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before create_net"
  return
 }
 if { $netname eq "" } {
  puts "Error : create_net requires a net name"
  puts "Usage: create_net <netname>"
  return
 }

 # Scope the net name like get_net/all_connected: top-level "-1" keeps the
 # bare name, a hierarchical reference becomes "scope/net".
 if { [string match {*/*} $netname] } {
  set key $netname
 } else {
  set key $netname
 }

 if { [info exists netdriver($key)] || [info exists netload($key)] } {
  puts "Error : net $key already exists"
  return
 }
 set netdriver($key) {}
 set netload($key) {}

 puts "************************************************************"
 puts " create_net : $netname"
 puts "************************************************************"
 puts "  created net $key (0 drivers, 0 receivers)"
 puts ""
}

# E2 create_cell <inst_path> <celltype>
# Instantiate a lib cell inside a scope. <inst_path> is "<scope>/<instname>";
# a bare instname (no '/') places the cell at the top level. <celltype> must be
# a lib cell present in cataloglist. A new _instlist entry, pathlist entry and
# per-pin _instpinconn1/2 entries are created; the new cell's pins are left
# unconnected ("<unconnected>") so connect_net (E4) can wire them. The new
# cell is also recorded in the netdriver/netload map only once connect_net
# attaches it. Requires build_design (hierarchy built).
proc create_cell { inst_path celltype } {
 variable instindex
 variable _instlist
 variable _instpinconn1
 variable _instpinconn2
 variable _libcell
 variable _libcellpindir
 variable cataloglist
 variable pathlist
 variable topname

 _require 2
 if { $inst_path eq "" || $celltype eq "" } {
  puts "Error : create_cell requires an instance path and a cell type"
  puts "Usage: create_cell <inst_path> <celltype>"
  return
 }

 set refid [lsearch -exact $cataloglist $celltype]
 incr refid
 if { ! [info exists _libcell($refid)] } {
  puts "Error : cell type $celltype not found in library"
  return
 }

 # Split the instance path into scope (parent path) and instance name. A
 # bare name places the cell at the top level (fullp == "-1").
 if { [string match {*/*} $inst_path] } {
  set parts [split $inst_path /]
  set instname [lindex $parts end]
  set fullp [join [lrange $parts 0 end-1] /]
 } else {
  set instname $inst_path
  set fullp "-1"
 }

 # Reject a duplicate instance path so the new cell is unambiguous.
 if { [lsearch -exact $pathlist $inst_path] >= 0 } {
  puts "Error : instance $inst_path already exists"
  return
 }

 incr instindex
 set _instlist($instindex) [list $instname $celltype $topname 0 0 0 0 $fullp $refid "N"]
 lappend pathlist $inst_path

 # Per-pin records: the new cell has the lib cell's pins, all unconnected.
 set pins [_libcell_pins $refid]
 set dirs [lindex [array get _libcellpindir $refid] 1]
 set _instpinconn1($instindex) $pins
 set _instpinconn2($instindex) {}
 foreach p $pins { lappend _instpinconn2($instindex) "<unconnected>" }

 puts "************************************************************"
 puts " create_cell : $inst_path $celltype"
 puts "************************************************************"
 puts "  created instance $inst_path ($celltype)"
 puts "  pins: [join $pins { }]"
 puts "  directions: [join $dirs { }]"
 puts ""
}

# E3 disconnect_net <net> <pin>
# Detach an instance pin from a net. <pin> is "<inst>/<pinname>". The net is
# scoped like get_net (trailing token = net name, prefix = scope; bare name =
# top level). The pin entry is removed from the net's driver list (if it is an
# output pin) or its receiver list (if it is an input pin). Requires
# build_net_conn (P2) to have run first.
proc disconnect_net { net pin } {
 global netdriver netload netconnbuilt
 variable _instpinconn1
 variable _instpinconn2
 variable _instlist
 variable pathlist
 variable _libcellpindir

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before disconnect_net"
  return
 }
 if { $net eq "" || $pin eq "" } {
  puts "Error : disconnect_net requires a net and a pin"
  puts "Usage: disconnect_net <net> <pin>"
  return
 }

 set key $net
 if { ! [info exists netdriver($key)] && ! [info exists netload($key)] } {
  puts "Error : net $net not found"
  return
 }

 # The pin argument is "inst/pin". Find the instance in pathlist to learn
 # the pin direction, then remove the matching {inst pin} entry from the
 # net's driver or receiver list.
 if { ! [regexp {^(.*)/([^/]+)$} $pin -> inst pinname] } {
  puts "Error : pin must be given as <inst>/<pin>"
  return
 }
 set iid [lsearch -exact $pathlist $inst]
 if { $iid < 0 } {
  puts "Error : instance $inst not found"
  return
 }
 incr iid
 if { ! [info exists _instpinconn1($iid)] } {
  puts "Error : instance $inst has no pins"
  return
 }
 set pk [lsearch -exact $_instpinconn1($iid) $pinname]
 if { $pk < 0 } {
  puts "Error : pin $pinname not found on instance $inst"
  return
 }
 set refid [lindex $_instlist($iid) 8]
 set dirs [lindex [array get _libcellpindir $refid] 1]
 set dr [lindex $dirs $pk]
 set entry "$inst $pinname"
 set removed 0
 if { $dr eq "OUTPUT" } {
  set d [_net_drivers $key]
  set k [lsearch -exact $d $entry]
  if { $k >= 0 } {
   set netdriver($key) [lreplace $d $k $k]
   set removed 1
  }
 } else {
  set l [_net_loads $key]
  set k [lsearch -exact $l $entry]
  if { $k >= 0 } {
   set netload($key) [lreplace $l $k $k]
   set removed 1
  }
 }
 if { ! $removed } {
  puts "Error : pin $pin is not connected to net $net"
  return
 }
 # Reflect the disconnect in the per-pin net record too.
 lset _instpinconn2($iid) $pk "<unconnected>"

 puts "************************************************************"
 puts " disconnect_net : $net $pin"
 puts "************************************************************"
 puts "  disconnected pin $pin from net $key"
 puts ""
}

# E4 connect_net <net> <pin>
# Attach an instance pin to a net. <pin> is "<inst>/<pinname>". The net is
# scoped like get_net. The pin is added to the net's driver list (if it is an
# output pin) or its receiver list (if it is an input pin). Requires
# build_net_conn (P2) to have run first.
proc connect_net { net pin } {
 global netdriver netload netconnbuilt
 variable _instpinconn1
 variable _instpinconn2
 variable _instlist
 variable pathlist
 variable _libcellpindir

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before connect_net"
  return
 }
 if { $net eq "" || $pin eq "" } {
  puts "Error : connect_net requires a net and a pin"
  puts "Usage: connect_net <net> <pin>"
  return
 }

 set key $net
 if { ! [info exists netdriver($key)] && ! [info exists netload($key)] } {
  puts "Error : net $net not found"
  return
 }

 if { ! [regexp {^(.*)/([^/]+)$} $pin -> inst pinname] } {
  puts "Error : pin must be given as <inst>/<pin>"
  return
 }
 set iid [lsearch -exact $pathlist $inst]
 if { $iid < 0 } {
  puts "Error : instance $inst not found"
  return
 }
 incr iid
 if { ! [info exists _instpinconn1($iid)] } {
  puts "Error : instance $inst has no pins"
  return
 }
 set pk [lsearch -exact $_instpinconn1($iid) $pinname]
 if { $pk < 0 } {
  puts "Error : pin $pinname not found on instance $inst"
  return
 }
 set refid [lindex $_instlist($iid) 8]
 set dirs [lindex [array get _libcellpindir $refid] 1]
 set dr [lindex $dirs $pk]
 set entry "$inst $pinname"
 if { $dr eq "OUTPUT" } {
  if { [info exists netdriver($key)] } {
   set d [_net_drivers $key]
   if { [lsearch -exact $d $entry] >= 0 } {
    puts "Error : pin $pin already drives net $net"
    return
   }
   lappend netdriver($key) $entry
  } else {
   set netdriver($key) [list $entry]
  }
 } else {
  if { [info exists netload($key)] } {
   set l [_net_loads $key]
   if { [lsearch -exact $l $entry] >= 0 } {
    puts "Error : pin $pin already loads net $net"
    return
   }
   lappend netload($key) $entry
  } else {
   set netload($key) [list $entry]
  }
 }
 lset _instpinconn2($iid) $pk [lindex [split $key /] end]

 puts "************************************************************"
 puts " connect_net : $net $pin"
 puts "************************************************************"
 puts "  connected pin $pin to net $key"
 puts ""
}

# O1 set_max_fanout <n>
# Set the global fanout threshold (max receivers per net) used by
# fix_max_fanout (O2). A net whose receiver count exceeds this threshold is a
# candidate for buffer insertion. <n> must be a positive integer. The value is
# stored in the global maxfanout variable. Requires no design state by itself.
proc set_max_fanout { n } {
 global maxfanout
 if { $n eq "" } {
  puts "Error : set_max_fanout requires a positive integer"
  puts "Usage: set_max_fanout <n>"
  return
 }
 if { ! [string is integer -strict $n] || $n < 1 } {
  puts "Error : set_max_fanout requires a positive integer"
  return
 }
 set maxfanout $n
 puts "************************************************************"
 puts " set_max_fanout : $n"
 puts "************************************************************"
 puts "  max fanout threshold is now $n"
 puts ""
}

# Helper: return the {input output} pin names of a lib cell by refid, using the
# _libcellpindir map (the first INPUT pin is treated as the buffer input and
# the first OUTPUT pin as the buffer output). Returns {} if either is missing.
proc _buf_pins { refid } {
 variable _libcellpindir
 variable _libcell
 if { ! [info exists _libcellpindir($refid)] } { return {} }
 set dirs $_libcellpindir($refid)
 set pins [_libcell_pins $refid]
 set ipin ""
 set opin ""
 for {set j 0} {$j < [llength $dirs]} {incr j} {
  if { [lindex $dirs $j] eq "INPUT"  && $ipin eq "" } { set ipin [lindex $pins $j] }
  if { [lindex $dirs $j] eq "OUTPUT" && $opin eq "" } { set opin [lindex $pins $j] }
 }
 if { $ipin eq "" || $opin eq "" } { return {} }
 return [list $ipin $opin]
}

# O2 fix_max_fanout -cell <buffer>
# Insert buffers of the given lib cell on nets whose receiver count exceeds the
# threshold set by set_max_fanout (O1). For each over-fanout net the receivers
# are split into groups of at most maxfanout: one buffer is created per group,
# the buffer input loads the original net, a new net per buffer is created,
# the group's receivers are moved from the original net to the new net, and the
# buffer output drives the new net. After insertion every net involved has at
# most maxfanout receivers. Uses the netload map from build_net_conn (P2), so
# build_net_conn must have run first. The buffer cell type must be present in
# cataloglist.
proc fix_max_fanout { args } {
 global netdriver netload netconnbuilt maxfanout
 variable instindex
 variable _instlist
 variable _instpinconn1
 variable _instpinconn2
 variable _libcell
 variable _libcellpindir
 variable cataloglist
 variable pathlist
 variable topname

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before fix_max_fanout"
  return
 }
 set bufcell ""
 for {set i 0} {$i < [llength $args]} {incr i} {
  set a [lindex $args $i]
  if { $a eq "-cell" } { set bufcell [lindex $args [incr i]] ; continue }
  puts "Error : unknown option '$a'"
  puts "Usage: fix_max_fanout -cell <buffer>"
  return
 }
 if { $bufcell eq "" } {
  puts "Error : fix_max_fanout requires -cell <buffer>"
  puts "Usage: fix_max_fanout -cell <buffer>"
  return
 }
 if { $maxfanout < 1 } {
  puts "Error : max fanout threshold not set (run set_max_fanout <n> first)"
  return
 }

 set refid [lsearch -exact $cataloglist $bufcell]
 incr refid
 if { ! [info exists _libcell($refid)] } {
  puts "Error : buffer cell $bufcell not found in library"
  return
 }
 set bp [_buf_pins $refid]
 if { $bp eq "" } {
  puts "Error : buffer cell $bufcell has no input/output pin pair"
  return
 }
 set b_ipin [lindex $bp 0]
 set b_opin [lindex $bp 1]

 puts "************************************************************"
 puts " fix_max_fanout : -cell $bufcell  (max $maxfanout)"
 puts "************************************************************"

 # Snapshot the over-fanout nets before any mutation so the loop is not
 # disturbed by the receivers we move around. A net with no driver (no
 # netdriver entry, or an empty one) is skipped: ports/constants/hierarchical
 # pin nets have no real driver to buffer.
 set targets {}
 foreach k [array names netload] {
  if { ! [info exists netdriver($k)] } { continue }
  if { [llength $netdriver($k)] == 0 } { continue }
  set nl [llength $netload($k)]
  if { $nl > $maxfanout } { lappend targets $k }
 }

 set nbuf 0
 set nnet [llength $targets]
 set gi 0
 foreach net $targets {
  set loads $netload($net)
  set nl [llength $loads]
  # Split the receiver list into groups of at most maxfanout.
  set groups {}
  for {set s 0} {$s < $nl} {incr s $maxfanout} {
   lappend groups [lrange $loads $s [expr {$s + $maxfanout - 1}]]
  }
  set nb [llength $groups]
  # Move every receiver off the original net: it will keep only the buffer
  # inputs as its new receivers.
  set netload($net) {}
  set gi 0
  foreach grp $groups {
   incr gi
   incr nbuf
   # Create a buffer instance in the same scope as the net. The net key is
   # already "scope/netname"; the buffer instance path is "scope/buf_<net>_<n>".
   set binst "${net}___b${gi}"
   if { [string match {*/*} $net] } {
    set scope [join [lrange [split $net /] 0 end-1] /]
    set bpath "${scope}/${binst}"
   } else {
    set bpath $binst
    set scope "-1"
   }
   # Ensure a unique instance path (defensive: collisions should not happen).
   while { [lsearch -exact $pathlist $bpath] >= 0 } {
    append bpath "x"
   }
   incr instindex
   set _instlist($instindex) [list $binst $bufcell $topname 0 0 0 0 $scope $refid "N"]
   lappend pathlist $bpath
   set _instpinconn1($instindex) [_libcell_pins $refid]
   set _instpinconn2($instindex) {}
   foreach p [_libcell_pins $refid] { lappend _instpinconn2($instindex) "<unconnected>" }
   # Buffer input loads the original net.
   set pk [lsearch -exact $_instpinconn1($instindex) $b_ipin]
   lappend netload($net) "$bpath $b_ipin"
   lset _instpinconn2($instindex) $pk [lindex [split $net /] end]
   # Create the new net driven by the buffer output.
   set newnet "${net}_b${gi}"
   set netdriver($newnet) [list "$bpath $b_opin"]
   set netload($newnet) {}
   set ok [lsearch -exact $_instpinconn1($instindex) $b_opin]
   lset _instpinconn2($instindex) $ok [lindex [split $newnet /] end]
   # Move the group's receivers from the original net to the new net,
   # and update their per-pin net record to the new net's trailing token.
   set newtail [lindex [split $newnet /] end]
   foreach lp $grp {
    set linst [lindex $lp 0]
    set lpin [lindex $lp 1]
    lappend netload($newnet) $lp
    set lid [lsearch -exact $pathlist $linst]
    if { $lid >= 0 } {
     incr lid
     if { [info exists _instpinconn1($lid)] } {
      set lpk [lsearch -exact $_instpinconn1($lid) $lpin]
      if { $lpk >= 0 } { lset _instpinconn2($lid) $lpk $newtail }
     }
    }
   }
  }
  puts "  net $net: $nl receivers -> $nb buffer(s), each <= $maxfanout loads"
 }
 puts "  -------------------------------------------------------"
 if { $nnet == 1 } { set nkw net } else { set nkw nets }
 if { $nbuf == 1 } { puts "$nbuf buffer inserted on $nnet $nkw." } else { puts "$nbuf buffers inserted on $nnet $nkw." }
 puts ""
}

# Helper: map the internal short port-direction token to the Verilog keyword.
proc _port_kw { t } {
 if { $t eq "in" }  { return "input" }
 if { $t eq "out" } { return "output" }
 return "inout"
}

# N1 write_verilog <filename>
# Dump the loaded netlist back out as Verilog: modules, ports, wires, leaf-cell
# instances, hierarchical instances and continuous assignments. Comments and
# line wrapping may differ from the source, but the structural content
# (module/port/wire/instance/assign structure) is preserved so a
# read_netlist -> write_verilog -> read_netlist round-trip is structurally
# equivalent. Requires a design to have been read and set (set_top_design).
# Works from the raw netlist capture, so it does not need build_design.
proc write_verilog { filename } {
 variable topname
 variable hierindex
 variable portindex
 variable wireindex
 variable instindex
 variable hinstindex
 variable _portlist
 variable _porttype
 variable _portmaster
 variable _wirelist
 variable _wiretype
 variable _wiremaster
 variable _instlist
 variable _hinstlist
 variable _instpinconn1
 variable _instpinconn2
 variable _hinstpinconn1
 variable _hinstpinconn2
 variable hierlistdef
 variable _assignlist

 _require 1
 if { $filename eq "" } {
  puts "Error : write_verilog requires a filename"
  puts "Usage: write_verilog <filename>"
  return
 }

 set fo [open $filename w]
 puts $fo "// Verilog netlist dumped by My Little EDA"
 puts $fo "// Top module: $topname"
 puts $fo ""

 # Modules are stored in parse order in hierlistdef (1-based via portindex).
 # For each module emit a Verilog module with ANSI-style ports.
 set mlist [lrange $hierlistdef 0 [expr {$hierindex-1}]]
 for { set m 0 } { $m < $hierindex } { incr m } {
  set modname [lindex $mlist $m]
  set pid [expr {$m+1}]

  # Port header (ANSI style).
  set pnames [lindex [array get _portlist $pid] 1]
  set ptypes [lindex [array get _porttype $pid] 1]
  set hdr {}
  if { [llength $pnames] } {
   for { set j 0 } { $j < [llength $pnames] } { incr j } {
    set pn [lindex $pnames $j]
    set pt [lindex $ptypes $j]
    if { [lindex $pt 0] eq "bus" } {
     set dir [_port_kw [lindex $pt 1]]
     set lo [lindex $pt 2]
     set hi [lindex $pt 3]
     lappend hdr "$dir \[$hi:$lo\] $pn"
    } else {
     lappend hdr "[_port_kw $pt] $pn"
    }
   }
  }
  if { [llength $hdr] } {
   puts $fo "module $modname ( [join $hdr { , }] ) ;"
  } else {
   puts $fo "module $modname ( ) ;"
  }
  puts $fo ""

  # Wires declared inside this module.
  for { set w 1 } { $w <= $wireindex } { incr w } {
   set wm [lindex [array get _wiremaster $w] 1]
   if { $wm ne $modname } { continue }
   set wn [lindex [array get _wirelist $w] 1]
   set wt [lindex [array get _wiretype $w] 1]
   if { [lindex $wt 0] eq "bus" } {
    set lo [lindex $wt 2]
    set hi [lindex $wt 3]
    puts $fo "  wire \[$hi:$lo\] $wn ;"
   } else {
    puts $fo "  wire $wn ;"
   }

  }
  puts $fo ""

  # Leaf-cell instances in this module (skip the synthetic "assign" instances).
  for { set i 1 } { $i <= $instindex } { incr i } {
   set inst $_instlist($i)
   if { [lindex $inst 2] ne $modname } { continue }
   set refname [lindex $inst 1]
   if { $refname eq "assign" } { continue }
   set iname [lindex $inst 0]
   set pins $_instpinconn1($i)
   set nets $_instpinconn2($i)
   set conns {}
   for { set j 0 } { $j < [llength $pins] } { incr j } {
    lappend conns ".[lindex $pins $j] ( [lindex $nets $j] )"
   }
   puts $fo "  $refname $iname ( [join $conns { , }] ) ;"
  }

  # Hierarchical instances in this module (skip the synthetic "assign" ones).
  for { set i 1 } { $i <= $hinstindex } { incr i } {
   set inst $_hinstlist($i)
   if { [lindex $inst 2] ne $modname } { continue }
   set refname [lindex $inst 1]
   if { $refname eq "assign" } { continue }
   set iname [lindex $inst 0]
   set pins $_hinstpinconn1($i)
   set nets $_hinstpinconn2($i)
   set conns {}
   for { set j 0 } { $j < [llength $pins] } { incr j } {
    lappend conns ".[lindex $pins $j] ( [lindex $nets $j] )"
   }
   puts $fo "  $refname $iname ( [join $conns { , }] ) ;"
  }

  # Continuous assignments in this module.
  foreach a $_assignlist {
   lassign $a alhs arhs amod
   if { $amod ne $modname } { continue }
   puts $fo "  assign $alhs = $arhs ;"
  }

  puts $fo "endmodule"
  puts $fo ""
 }

 close $fo
 puts "Info : wrote Verilog netlist to $filename"
}

# N2 write_db <file>
# Dump the full in-memory database to a file: every scalar, list and array
# variable that holds design state (instances, wires, placement, the net
# connectivity map, the loaded LEF library, ports, assigns, etc.) is written so
# restore_db can reload the whole database without re-parsing the netlist or
# rebuilding the design. The format is a Tcl-sourceable text representation
# (a single Tcl value per line, arrays emitted as a flat list of key/value
# pairs), prefixed with a magic header and version tag for a fast sanity check
# on restore.
proc write_db { filename } {
 _require 1
 if { $filename eq "" } {
  puts "Error : write_db requires a filename"
  puts "Usage: write_db <file>"
  return
 }

 set fo [open $filename w]
 puts $fo "# mylittleda db"
 puts $fo "# version 1"

 # Scalars that hold scalar design state.
 foreach v {topname topnameid bumpindex cellindex hierindex instindex hinstindex portindex wireindex blockageindex regionindex scale_f siteh fontsize targetutilz netconnbuilt} {
  variable $v
  puts $fo "S $v [list [set $v]]"
 }
 # maxfanout is a global threshold (set via `set`, not `variable`).
 global maxfanout
 puts $fo "S maxfanout [list $maxfanout]"

 # Lists that hold design state.
 foreach v {cataloglist hierlistdef hierlist pathlist hpathlist corebox topbox instrefsearch hinstrefsearch wiresearch _assignlist _libcellsync gridutil utlzmap hier_dontshow} {
  variable $v
  puts $fo "L $v [list [set $v]]"
 }

 # Arrays: emit each array as a flat list of {key value key value ...} so the
 # whole array is restored with array set. Iterate over a fixed name list so
 # the set is explicit and stable (no incidental globals leak in).
 foreach v {_libcell _libcellpindir _libsyncpin _instlist _hinstlist _blockagelist _regionlist _portlist _porttype _portmaster _wirelist _wiretype _wiremaster _wireinst _instpinconn1 _instpinconn2 _hinstpinconn1 _hinstpinconn2 _wirepinconn _bumplist wiresearch_map _wirelen_cache} {
  variable $v
  set names [array names $v]
  set pairs {}
  foreach k $names {
   lappend pairs $k [set ${v}($k)]
  }
  puts $fo "A $v [list $pairs]"
 }

 # The net connectivity map is global (not a variable) in this script.
 global netdriver netload
 set pairs {}
 foreach k [array names netdriver] { lappend pairs $k $netdriver($k) }
 puts $fo "G netdriver [list $pairs]"
 set pairs {}
 foreach k [array names netload] { lappend pairs $k $netload($k) }
 puts $fo "G netload [list $pairs]"

 close $fo
 puts "Info : wrote database to $filename"
}

# N3 restore_db <file>
# Reload a database written by write_db. Every scalar, list and array variable
# is restored, so the session is ready immediately: get_cell / get_net /
# all_connected / get_lib_cell and the placement / library data are all
# available without read_netlist, set_top_design, build_design or
# build_net_conn. The source netlist and LEFs do not need to be re-imported.
proc restore_db { filename } {
 if { $filename eq "" } {
  puts "Error : restore_db requires a filename"
  puts "Usage: restore_db <file>"
  return
 }
 if { ! [file exists $filename] } {
  puts "Error : db file $filename not found"
  return
 }

 set fi [open $filename r]
 set magic [gets $fi]
 set verline [gets $fi]
 if { $magic ne "# mylittleda db" } {
  puts "Error : not a mylittleda db file"
  close $fi
  return
 }
 if { ! [regexp {# version ([0-9]+)} $verline -> vdb] } { set vdb 0 }
 if { $vdb != 1 } {
  puts "Error : unsupported db version $vdb"
  close $fi
  return
 }

 global netdriver netload
 array unset netdriver
 array unset netload

 while {[gets $fi line] >= 0} {
  if { $line eq "" } { continue }
  set tag [lindex $line 0]
  set name [lindex $line 1]
  set val [lrange $line 2 end]
  if { $tag eq "S" } {
   if { $name eq "maxfanout" } {
    global maxfanout
    set maxfanout [lindex $val 0]
   } else {
    variable $name
    set $name [lindex $val 0]
   }
  } elseif { $tag eq "L" } {
   variable $name
   set $name [lindex $val 0]
  } elseif { $tag eq "A" } {
   variable $name
   array unset $name
   array set $name [lindex $val 0]
  } elseif { $tag eq "G" } {
   set gv [lindex $val 0]
   if { $name eq "netdriver" } { array set netdriver $gv }
   if { $name eq "netload" }   { array set netload $gv }
  }
 }
 close $fi

 # The scalar/array values were restored via `variable $name` in the loop
 # above, so they are linked into this namespace; declare the ones used in the
 # summary so they are visible here (each name separately: `variable a b c`
 # would treat b/c as initial values, not extra names).
 variable topname
 variable instindex
 variable hinstindex
 variable portindex
 puts "Info : restored database from $filename"
 puts "Info : top $topname, $instindex leaf insts, $hinstindex hier insts, $portindex ports"
}

#
#############################################################

proc make_lef { filename } {
 variable topname
 variable topbox
 _require 2
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable portindex
 variable _portlist
 variable _porttype
  
 puts -nonewline "Info : make abstract and dump LEF file $filename for design  " 
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"  			

 set fo [open $filename "w"] 

 puts $fo "VERSION 5.8 ;"
 puts $fo "BUSBITCHARS \"\[\]\" ;"
 puts $fo "DIVIDERCHAR \"\/\" ;"
 

 puts $fo "MACRO $topname"
 puts $fo "FIXEDMASK ;"
 puts $fo "CLASS BLOCK ;"
 puts $fo "FOREIGN $topname 0.0 0.0 ;"
 puts $fo "ORIGIN 0.0 0.0 ;"
 puts $fo "SIZE  [ lindex $topbox 2 ] BY [ lindex $topbox 3 ] ;"
 puts $fo "SYMMETRY X Y ;"

 set pinlist $_portlist($portindex)
 set pintype $_porttype($portindex)

 for {set i 0} {$i<[llength $pinlist] } {incr i} {
  set pin [lindex $pinlist $i]
  set dir [lindex $pintype $i]
  set bdir [scan $dir "%s %s %d %d"]
  
  if { [lindex $bdir 0] == "bus"} {
     set dir2 [lindex $bdir 1]
     
     for {set j [lindex $bdir 2] } {$j<= [lindex $bdir 3]} { incr j} {
       puts $fo "PIN $pin\[$j\]"     
       if { $dir2 == "in"} { puts $fo "         DIRECTION INPUT ;"  }
       if { $dir2 == "out"} { puts $fo "         DIRECTION OUTPUT ;"  }
       if { $dir2 == "inout"} { puts $fo "         DIRECTION INOUT ;"  }
       puts $fo "         USE SIGNAL ;" 
       puts $fo "         PORT" 
       puts $fo "             LAYER M1 ;" 
       puts $fo "             RECT MASK 2 26.0875 97.7750 26.1245 97.9750 ;" 
       puts $fo "         END" 
       puts $fo "END $pin\[$j\]" 
    }
    
  } else {
   puts $fo "PIN $pin"     
   if { $dir == "in"} { puts $fo "         DIRECTION INPUT ;"  }
   if { $dir == "out"} { puts $fo "         DIRECTION OUTPUT ;"  }
   if { $dir == "inout"} { puts $fo "         DIRECTION INOUT ;"  }
   puts $fo "         USE SIGNAL ;" 
   puts $fo "         PORT" 
   puts $fo "             LAYER M1 ;" 
   puts $fo "             RECT MASK 2 26.0875 97.7750 26.1245 97.9750 ;" 
   puts $fo "         END" 
   puts $fo "END $pin" 
  }
  	       
  puts $fo " " 
 }
 
 puts $fo "END $topname" 
 puts $fo " "
 puts $fo "END LIBRARY" 

 close $fo
}

proc make_lib { filename } {
 variable topname
 variable topbox
 _require 2
 variable topnameid
 variable hierindex
 variable instindexu
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable portindex
 variable _portlist
 variable _porttype
  
 puts -nonewline "Info : make Liberty file $filename for design  " 

 set pinlist $_portlist($portindex)
 set pintype $_porttype($portindex)
 

 set fo [open $filename "w"] 

 puts $fo "library($topname) {"
 puts $fo "  delay_model : table_lookup;"


 for {set i 0} {$i<[llength $pinlist] } {incr i} {
  set pin [lindex $pinlist $i]
  set dir [lindex $pintype $i]
  set bdir [scan $dir "%s %s %d %d"]
  
  #is it new bus definition ?
  set pnew 1
   for {set j 0} {$j <$i } {incr j} { 
     set bdir2 [scan [lindex $pintype $j] "%s %s %d %d"]
     if { [lindex $bdir 2] == [lindex $bdir2 2] && [lindex $bdir 3] == [lindex $bdir2 3] } { set pnew 0 }
    }
   
  if {$pnew == 1 } {
   if { [lindex $bdir 0] == "bus"} {
     set ll [lindex $bdir 2]
     set ul [lindex $bdir 3]
     set dw "true"
     set bfrom $ul
     set bwidth [expr $ul-$ll+1]
     
     if { $ul < $ll } { set bfrom $ll ; set dw "false" ; set bwidth [expr $ll-$ul+1] }
     
      puts $fo "type ( BUS_${ll}_${ul} ) {"
      puts $fo  "  base_type : array ;"
      puts $fo  "  data_type : bit ;"
      puts $fo  "bit_width : $bwidth ;"
      puts $fo  "bit_from : $bfrom ;"
      puts $fo  "downto : $dw ;"
      puts $fo  "  }"
     }
   }
  }



 puts $fo "  cell($topname) {"
 
 
 for {set i 0} {$i<[llength $pinlist] } {incr i} {
  set pin [lindex $pinlist $i]
  set dir [lindex $pintype $i]
  set bdir [scan $dir "%s %s %d %d"]

  if { [lindex $bdir 0] == "bus"} {
     set dir2 [lindex $bdir 1]     
      puts $fo "bus \( $pin \) \{"
      puts $fo "        bus_type : BUS_[lindex $bdir 2]_[lindex $bdir 3] ;"
      if { $dir2 == "in"} { puts $fo "         direction : input ;"  }
      if { $dir2 == "out"} { puts $fo "         direction : output ;"  }
      if { $dir2 == "inout"} { puts $fo "         direction : inout ;"  }
      puts $fo " \}"
   } else {
      puts $fo "pin \( $pin \) \{"
      if { $dir == "in"} { puts $fo "         direction : input ;"  }
      if { $dir == "out"} { puts $fo "         direction : output ;"  }
      if { $dir == "inout"} { puts $fo "         direction : inout ;"  }
      puts $fo " \}"
   }
   

 }

 puts $fo "   }" 
 puts $fo "}"

 close $fo
 puts ""
}



proc export_def { filename } {

 variable topname
 variable topbox
 _require 2
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable portindex
 variable _portlist
 variable _porttype
  
 set unit 2000 
 puts -nonewline "Info : Write DEF to file $filename for design  " 
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"  			

 set fo [open $filename "w"] 

 puts $fo "VERSION 5.8 ;"
 puts $fo "DIVIDERCHAR \"/\" ;"
 puts $fo "BUSBITCHARS \"\[\]\" ;"
 puts $fo "DESIGN $topname ;"
 puts $fo "UNITS DISTANCE MICRONS 2000 ;"
 set bl_x [expr $unit*[lindex $topbox 0]]
 set bl_y [expr $unit*[lindex $topbox 1]]
 set tr_x [expr $unit*[lindex $topbox 2]]
 set tr_y [expr $unit*[lindex $topbox 3]]
 puts $fo "DIEAREA ( $bl_x $bl_y ) ( $tr_x $tr_y ) ;"

 set macrolist [ list ]
 
 for { set i 1} { $i<= $instindex } { incr i } {
  set inst $_instlist($i)
  set fullname [ lindex $inst 7 ]
  set instname [ lindex $inst 0 ]
  set placed [ lindex $inst 4 ]
  set psx [ lindex $inst 5 ]
  set psy [ lindex $inst 6 ]
  set ori [ lindex $inst 9 ]
  
  set refid [ lindex $_instlist($i) 8 ]
  set refcell $_libcell($refid)
  set class [lindex $refcell 4]
  set refname [lindex $refcell 0]
  
  set nami "${fullname}/${instname}"
  if {$fullname =="-1"} { set nami "${instname}" }
  if { $class == "BLOCK" || $class == "PAD" || $class == "CORE" } { lappend macrolist "- $nami $refname + FIXED ( [expr $unit*$psx] [expr $unit*$psy] ) $ori ;" }
 }
 
 puts $fo "COMPONENTS [llength $macrolist] ;"  

 for { set i 0} { $i< [llength $macrolist] } { incr i  } {
  puts $fo [lindex $macrolist $i]
 }

 puts $fo "END COMPONENTS"  
 puts $fo "END DESIGN"  

 close $fo
}



proc export_dc_floorplan { filename } {

 variable topname
 variable topbox
 _require 2
 variable topnameid
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable pathlist
 variable hpathlist
 variable blockageindex
 variable _blockagelist
 variable corebox
 variable utlzmap
 variable siteh
 variable portindex
 variable _portlist
 variable _porttype
 variable _instpinconn1
 variable _instpinconn2
  
 puts -nonewline "Info : Write SNPS DC floorplan commands to file $filename for design  " 
 puts -nonewline "\033\[33;1;4m"
 puts -nonewline $topname
 puts            "\033\[1;0m"  			

 set fo [open $filename "w"] 

 set bl_x [lindex $topbox 0]
 set bl_y [lindex $topbox 1]
 set tr_x [lindex $topbox 2]
 set tr_y [lindex $topbox 3]
 puts $fo "create_die_area -coordinate \[ list  $bl_x $bl_y  $tr_x $tr_y \]"

 set macrolist [ list ]
 
 for { set i 1} { $i<= $instindex } { incr i } {
  set inst $_instlist($i)
  set fullname [ lindex $inst 7 ]
  set instname [ lindex $inst 0 ]
  set placed [ lindex $inst 4 ]
  set psx [ lindex $inst 5 ]
  set psy [ lindex $inst 6 ]
  set ori [ lindex $inst 9 ]
  
  set refid [ lindex $_instlist($i) 8 ]
  set refcell $_libcell($refid)
  set class [lindex $refcell 4]
  set refname [lindex $refcell 0]
  
  set nami "${fullname}/${instname}"
  if {$fullname =="-1"} { set nami "${instname}" }
  if { $class == "BLOCK" || $class == "PAD"} { 
    lappend macrolist "set_cell_location $nami -coordinates \[ list $psx $psy \] -fixed -orientation $ori"
    }
 }
 
 for { set i 0} { $i< [llength $macrolist] } { incr i  } {
  puts $fo [lindex $macrolist $i]
 }

 close $fo
}

proc ls {} {
exec ls
}

proc lkj {} {
exec ls -latr
}

proc ll {} {
exec ls -la
}

proc cd { direc } {
exec cd $direc
}

proc pwd { } {
exec pwd
}

####################################################
#
# IMPORT FILES 
#
####################################################

proc add_lef { filename } {
 variable cellindex
 variable _libcell
 variable _libcellpindir
 variable cataloglist
 set enacell 0
 set cellcnt 0
 set curpin ""
 set fp [ open $filename r]
 puts "Info : LEF file import $filename"
 while { [gets $fp line] >=0 } {
  set words [regexp -all -inline -- {\S+} $line]
  set ARG1 [lindex $words 0]
  set ARG2  [lindex $words 1]
  set ARG3  [lindex $words 2]
  set ARG4  [lindex $words 3]
  
  if { $ARG1 == "MACRO" } {
                     set enacell 1
                     set cellcnt [ expr $cellcnt + 1 ]
                     set cellindex [ expr $cellindex + 1 ]
		     set _libcell($cellindex) [list $ARG2 0.0 0.0 0 class ]
		     lappend cataloglist $ARG2
		     }


  if { $ARG1 == "END" && $enacell == 1} { 
                     if { $ARG2 == [lindex $_libcell($cellindex) 0] } {
                        if { $curpin ne "" } { lappend _libcellpindir($cellindex) $curpindir ; set curpin "" }
                        set enacell 0
		       }
		     }

  if { $ARG1 == "PIN" && $enacell == 1} {
                      if { $curpin ne "" } { lappend _libcellpindir($cellindex) $curpindir }
                      set curpin $ARG2
                      set curpindir "INPUT"
                      lset _libcell($cellindex) 3 [expr [lindex $_libcell($cellindex) 3] +1 ]
                      lset _libcell($cellindex) [expr [lindex $_libcell($cellindex) 3]+4]  $ARG2
		     }

  if { $ARG1 == "DIRECTION" && $enacell == 1 && $curpin ne "" } {
                      set curpindir $ARG2
		     }
		     		     
  if { $ARG1 == "SIZE" && $enacell == 1 } {
		     lset _libcell($cellindex) 1 $ARG2
		     # ARG# is "BY" keyword
		     lset _libcell($cellindex) 2 $ARG4
		     }

  if { $ARG1 == "CLASS" && $enacell == 1 && $ARG2 == "PAD"} {
		     lset _libcell($cellindex) 4 "PAD"
		     }

  if { $ARG1 == "CLASS" && $enacell == 1 && $ARG2 == "BLOCK"} {
		     lset _libcell($cellindex) 4 "BLOCK"
		     }

  if { $ARG1 == "CLASS" && $enacell == 1 && $ARG2 == "CORE"} {
		     lset _libcell($cellindex) 4 "CORE"
		     }


 }
 close $fp
 puts "Info : LEF physical cell import, imported $cellcnt cells"
 puts "Info : total physical cell in memory $cellindex cells"
 puts ""
 
}

proc add_lib { filename } {
 variable _libsyncpin
 variable _libcellsync
 set libcnt 0
 set syncpin 0
 set curcell ""
 set curpin ""
 set inpin 0
 set isclock 0
 set fp [ open $filename r]
 puts "Info : Liberty file import $filename"
 while { [gets $fp line] >=0 } {
  set words [regexp -all -inline -- {\S+} $line]
  set ARG1 [lindex $words 0]
  set ARG2 [lindex $words 1]
  set ARG3 [lindex $words 2]

  if { $ARG1 == "cell" } {
                     if { $curcell ne "" && [info exists _libsyncpin($curcell)] } { lappend _libcellsync $curcell }
                     set curcell [string trim $ARG2 "()"]
                     set _libsyncpin($curcell) [ list ]
                     set libcnt [ expr $libcnt + 1 ]
                     set inpin 0
		     }

  if { $ARG1 == "pin" && $curcell ne "" } {
                     if { $inpin && $curpin ne "" && $isclock } { lappend _libsyncpin($curcell) $curpin }
                     set curpin [string trim $ARG2 "()"]
                     set isclock 0
                     set inpin 1
		     }

  if { $ARG1 == "clock" && $inpin && $ARG2 == ":" && $ARG3 == "true" } { set isclock 1 }
  if { $ARG1 == "clock" && $inpin && $ARG2 == "true" } { set isclock 1 }
  }

 if { $curcell ne "" && $inpin && $curpin ne "" && $isclock } { lappend _libsyncpin($curcell) $curpin }
 if { $curcell ne "" && [info exists _libsyncpin($curcell)] } { lappend _libcellsync $curcell }
 close $fp
 puts "Info : Liberty logical cell import, imported $libcnt cells"
 foreach c $_libcellsync { set s $_libsyncpin($c) ; if { [llength $s] > 0 } { set syncpin [ expr $syncpin + [llength $s] ] } }
 puts "Info : total sync (clock) pins recovered $syncpin pins"
 puts ""
}

proc get_sync_pins { cellname } {
 variable _libsyncpin
 if { ! [info exists _libsyncpin($cellname)] } { return "" }
 return $_libsyncpin($cellname)
}

# Helper: is the given instance pin a sync (clock) load pin of its cell?
# Uses the _libsyncpin map (flop CP / SRAM CK) built by add_lib (L2).
proc _is_sync_pin { inst pin } {
 variable _instlist
 variable pathlist
 variable _libsyncpin
 set iid [lsearch -exact $pathlist $inst]
 if { $iid < 0 } { return 0 }
 incr iid
 set refname [lindex $_instlist($iid) 1]
 if { ! [info exists _libsyncpin($refname)] } { return 0 }
 set sp [lsearch -exact $_libsyncpin($refname) $pin]
 return [expr {$sp >= 0}]
}

# R2 trace_clock <pin|net>
# Tree-like report tracing from a pin or net down through combinational logic
# to all leaf sync load pins (flop CP / SRAM CK via _libsyncpin). Each branch
# is followed (not just one path, unlike report_path), and the trace stops at a
# sync load pin. Requires build_net_conn (P2) and add_lib (L2) to have run so
# the net connectivity map and the sync-pin map exist.
proc trace_clock { root } {
 global netdriver netload netconnbuilt
 variable _libsyncpin

 _require 2
 if { ! [info exists netconnbuilt] || ! $netconnbuilt } {
  puts "Error : build_net_conn must run before trace_clock"
  return
 }
 if { $root eq "" } {
  puts "Error : trace_clock requires a pin or net"
  puts "Usage: trace_clock <pin|net>"
  return
 }
 # add_lib (L2) is required for the sync-pin map; without it no leaf can be a
 # sync endpoint, so the trace would report only combinational fanout.
 if { [llength [array names _libsyncpin]] == 0 } {
  puts "Warning : no sync pins loaded (run add_lib before trace_clock)"
 }

 # Resolve the root into a starting net. A pin "inst/pin" is recognised only
 # if that instance and pin exist; otherwise the argument is a net.
 set start_net ""
 set start_pin ""
 set is_pin 0
 if { [regexp {^(.*)/([^/]+)$} $root -> inst pin] } {
  set n [_pin_net $inst $pin]
  if { $n ne "" } { set start_net $n ; set start_pin "$inst $pin" ; set is_pin 1 }
 }
 if { ! $is_pin } { set start_net [_report_net_resolve $root] }
 if { $start_net eq "" } { puts "Error : root point $root not found" ; return }

 puts "************************************************************"
 puts " trace_clock : $root"
 puts "************************************************************"

 # Visited nets prevent combinational loops from recursing forever.
 array set seen {}
 set nendp 0
 set nbranch 0
 if { $is_pin } {
  puts "  [_fmt_pin $start_pin]"
  _trace_clock_net $start_net 1 seen nendp nbranch
 } else {
  puts "  $start_net"
  _trace_clock_net $start_net 1 seen nendp nbranch
 }
 puts "  -------------------------------------------------------"
 puts "  $nendp sync endpoint(s), $nbranch combinational branch(es) traced."
 puts ""
}

# Recursive helper: trace from a net to its load pins. For each load pin:
#   - sync load pin (flop CP / SRAM CK) -> print as a leaf endpoint and stop.
#   - combinational input -> follow to that cell's output net and recurse one
#     level deeper. Hierarchy/assign pass-through pins are followed through.
# 'level' is the indentation depth; 'vref'/'nendpref'/'nbranchref' are upvar
# aliases for the visited set and counters kept by the caller.
proc _trace_clock_net { net level vref nendpref nbranchref } {
 upvar 1 $vref seen $nendpref nendp $nbranchref nbranch
 variable hpathlist
 if { [info exists seen($net)] } { return }
 set seen($net) 1
 set loads [_net_loads $net]
 set any 0
 set pad [string repeat "  " $level]
 foreach lp $loads {
  set ln [lindex $lp 0]
  set lpin [lindex $lp 1]
  # A sync load pin is a leaf endpoint.
  if { $ln ne "<port>" && $ln ne "<assign>" && [_is_sync_pin $ln $lpin] } {
   puts "${pad}+-- [_fmt_pin $lp]  (sync endpoint)"
   incr nendp
   set any 1
   continue
  }
  # Follow through combinational / hierarchy / assign to the next net.
  if { $ln eq "<assign>" } {
   set out_net $lpin
  } elseif { [lsearch -exact $hpathlist $ln] >= 0 } {
   # Hierarchical instance pin: follow the connection into the child scope.
   # The inner net is the pin name scoped by the instance path (e.g. rf/clk).
   set out_net [_hier_pin_inner_net $ln $lpin]
  } else {
   set out_net [_cell_out_net $ln $lpin]
  }
  if { $out_net eq "" } {
   # A non-sync load with no traced output (e.g. a leaf data pin or a
   # hierarchical output): dead branch, not a clock path.
   continue
  }
  puts "${pad}+-- [_fmt_pin $lp]"
  incr nbranch
  set any 1
  _trace_clock_net $out_net [expr {$level+1}] seen nendp nbranch
 }
 if { ! $any } { puts "${pad}(no clock path forward)" }
}

proc get_cell_id  { refname } {
 variable topname
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable hierlistdef

 set res [ lsearch $hierlist $refname ]
 
 return $res
}


proc read_netlist { filename } {
 variable hierindex
 variable instindex
 variable cellindex
 variable hinstindex
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable cataloglist
 variable hierlist
 variable hierlistdef
 variable portindex
 variable _portlist
 variable _porttype
 variable _portmaster
 variable wireindex
 variable _wirelist
 variable _wiretype
 variable _wiremaster
 variable _instpinconn1
 variable _instpinconn2
 variable _hinstpinconn1
 variable _hinstpinconn2
 variable hinstrefsearch
 variable instrefsearch
 variable _assignlist 
  
 # read module definition
 puts "Info : VERILOG import, module definition.."
 set fp [ open $filename r]
 
 set ishier 0
 set hierindex 0 
 set _nline 0
 set continput 0 
 set contoutput 0 
 set continout 0 
 set current_module ""
 set current_hi_idx ""
 set current_lo_idx ""
 set ansi_dir ""
 set cur_bit ""
 set b1_is_bit 0
 set prev ""
 set vstate "idle"
 set hinstindex 0
    
 while { [gets $fp line] >=0 } {
  
  if { [regexp {^[ \t]*assign[ \t]+([A-Za-z0-9_\[\]\:]+)[ \t]*=[ \t]*([^;]+);[ \t]*$} $line -> alhs arhs] } {
     set alhs [string trim $alhs]
     foreach r [split [string trim $arhs] " "] {
       set r [string trim $r]
       if { $r ne "" && $r ne "+" && $r ne "^" && $r ne "&" && $r ne "~" } { lappend _assignlist [list $alhs $r $current_module] }
     }
  }
  set rline1  [string map {";" " ; "} $line   ]
  set rline2  [string map {")" " ) "} $rline1 ]
  set rline3  [string map {"(" " ( "} $rline2 ]
  set rline4  [string map {"." " . "} $rline3 ]
  set rline5  [string map {"," " , "} $rline4 ]
  set rline6  [string map {"\{" " \{ "} $rline5 ]
  set rline7  [string map {"\}" " \} "} $rline6 ]
  set rline8  [string map {"\[" " \[ "} $rline7 ]
  set rline9  [string map {"\]" " \] "} $rline8 ]
  set rline10 [string map {"\:" " \: "} $rline9 ]
  set rline $rline10
  
  set words [regexp -all -inline -- {\S+} $rline] 
  
  if { [ string first "/" $rline] >= 0 } { continue;}
  
  
  for {set i 0 } { $i < [llength $words] } {incr i} {
    set word [lindex $words $i]
    
    ###############################
    # NEW MODULE DEF 
    ###############################
    
    ######### TOP NAME
    if {$vstate == "module_decl"} {
                                  incr hierindex
			          incr portindex
		                  set _portlist($portindex) [ list ]
		                  set _porttype($portindex) [ list ]				  
		                  lappend hierlistdef $word
				  set current_module $word
                                  }
    ######### TOP PORTS
    if { $vstate == "port_input" && $word != "\]" && $word !="\["  && $word !="," && $word !=";" } {
	    		                    lappend _portlist($portindex) $word
		                            lappend _porttype($portindex) "in"
					    lappend _portmaster($portindex) $current_module
	                                    }
	
    if { $vstate == "port_output" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } {
	    		                    lappend _portlist($portindex) $word
		                            lappend _porttype($portindex) "out"
					    lappend _portmaster($portindex) $current_module
	                                    }

    if { $vstate == "port_inout" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } {
	    		                    lappend _portlist($portindex) $word
		                            lappend _porttype($portindex) "inout"
					    lappend _portmaster($portindex) $current_module
	                                    }
    ######### TOP BUSSED PORT
    if { $vstate == "port_input_hi"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" && $word !=":"} { set current_hi_idx $word }
    if { $vstate == "port_input_lo"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" && $word !=":"} { set current_lo_idx $word }
    if { $vstate == "port_output_hi" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" && $word !=":"} { set current_hi_idx $word }
    if { $vstate == "port_output_lo" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" && $word !=":"} { set current_lo_idx $word }
    if { $vstate == "port_inout_hi"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" && $word !=":"} { set current_hi_idx $word }
    if { $vstate == "port_inout_lo"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" && $word !=":"} { set current_lo_idx $word }
    
    if { $vstate == "port_input_busname"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } { 
	  lappend _portlist($portindex) $word
	  lappend _porttype($portindex) "bus in $current_lo_idx $current_hi_idx"
	  lappend _portmaster($portindex) $current_module
	 }

    if { $vstate == "port_output_busname"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } { 
	  lappend _portlist($portindex) $word
	  lappend _porttype($portindex) "bus out $current_lo_idx $current_hi_idx"
	  lappend _portmaster($portindex) $current_module
	 }

    if { $vstate == "port_inout_busname"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } { 
	  lappend _portlist($portindex) $word
	  lappend _porttype($portindex) "bus inout $current_lo_idx $current_hi_idx"
	  lappend _portmaster($portindex) $current_module
	 }
    ######### INTERNAL WIRES
    if { $vstate == "wire_decl_hi" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } { set current_hi_idx $word }
    if { $vstate == "wire_decl_lo" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } { set current_lo_idx $word }


    if { $vstate == "wire_decl" && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } {
                                            incr wireindex
	    		                    lappend _wirelist($wireindex) $word
		                            lappend _wiretype($wireindex) "net"
					    lappend _wiremaster($wireindex) $current_module
	                                    }

    ######### BUSSED WIRES
    if { $vstate == "wire_decl_busname"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } { 
          incr wireindex
	  lappend _wirelist($wireindex) $word
	  lappend _wiretype($wireindex) "bus net $current_lo_idx $current_hi_idx"
	  lappend _wiremaster($wireindex) $current_module
	 }



    ######### NEW INSTANCE INSIDE MODULE : HIERARCHICAL OR LIB-CELL
    if { $vstate == "inst_decl"} {
       if { [lsearch -exact $cataloglist $vstate_refname] >= 0 }	{ 
                                                         set ishier 0
                                                         incr instindex
    					                 set _instlist($instindex) [list $word $vstate_refname $current_module 0 0 0 0 "-1" 0 "N" ] 
							 lappend instrefsearch $current_module						 
                                                        } else {
							 set ishier 1
    					                 incr hinstindex
      					                 set _hinstlist($hinstindex) [list $word $vstate_refname $current_module 1 0 0 0 "-1" 0 "N" ] 
                                                         lappend hierlist $vstate_refname
							 lappend hinstrefsearch $current_module						 
                                                      }
                                       }						     

    ########## INSTANCE PIN PARSING
    # A pin connected to a bus concatenation (e.g. .p({a, b, c})) records one
    # pin but its {..} body is skipped, which used to leave the pin without a
    # net entry and misalign the pin/net lists. Append a single <bus> placeholder
    # net so every pin keeps exactly one net entry; the placeholder is inert in
    # the scalar net connectivity map (no driver/receiver).
    if { $ishier==0 } {
     if { $vstate == "inst_pin_conn" && $word != "(" && $word != ")"                                                                                      } {    lappend _instpinconn1($instindex) $word   }
     if { $vstate == "inst_pin_connw" && $word == "\{" } {    lappend _instpinconn2($instindex) "<bus>"   }
     if { $vstate == "inst_pin_connw" && $word != "(" && $word != ")" && $word != "\[" && $word != "\]" && $word != "\{" && $word != "\}" && $word != "\,"} {    lappend _instpinconn2($instindex) $word   }
     if { $vstate == "inst_pin_connw_b1" && $b1_is_bit && $word != "\[" && $word != "\]" } { append cur_bit $word }
    } else {
     if { $vstate == "inst_pin_conn" && $word != "(" && $word != ")"                                    			          		  } {    lappend _hinstpinconn1($hinstindex) $word   }
     if { $vstate == "inst_pin_connw" && $word == "\{" } {    lappend _hinstpinconn2($hinstindex) "<bus>"   }
     if { $vstate == "inst_pin_connw" && $word != "(" && $word != ")" && $word != "\[" && $word != "\]" && $word != "\{" && $word != "\}" && $word != "\,"} {    lappend _hinstpinconn2($hinstindex) $word   }
     if { $vstate == "inst_pin_connw_b1" && $b1_is_bit && $word != "\[" && $word != "\]" } { append cur_bit $word }
    }
    
   #######################  
   # FSM : next state
   #######################

    if { $vstate == "port_input" && $word == "\[" } { set vstate "port_input_hi" ; continue }
    if { $vstate == "port_input_hi" && $word == ":" } { set vstate "port_input_lo" ; continue }
    if { $vstate == "port_input_lo" && $word == "\]" } { set vstate "port_input_busname" ; continue }
    if { $vstate == "port_input_busname" && $word == ";" } { set vstate "idle" ; continue }
    if { $vstate == "port_input" && $word == ";" } { set vstate "idle" ; continue }   
    if { $vstate == "port_input_busname" && $word == "," } { set vstate "port_input_busname" ; continue }
    if { $vstate == "port_input" && $word == "," } { set vstate "port_input" ; continue }
    
    if { $vstate == "port_output" && $word == "\[" } { set vstate "port_output_hi" ; continue }
    if { $vstate == "port_output_hi" && $word == ":" } { set vstate "port_output_lo" ; continue }
    if { $vstate == "port_output_lo" && $word == "\]" } { set vstate "port_output_busname" ; continue }
    if { $vstate == "port_output_busname" && $word == ";" } { set vstate "idle" ; continue }
    if { $vstate == "port_output" && $word == ";" } { set vstate "idle" ; continue }   
    if { $vstate == "port_output_busname" && $word == "," } { set vstate "port_output_busname" ; continue }
    if { $vstate == "port_output" && $word == "," } { set vstate "port_output" ; continue }

    if { $vstate == "port_inout" && $word == "\[" } { set vstate "port_inout_hi" ; continue }
    if { $vstate == "port_inout_hi" && $word == ":" } { set vstate "port_inout_lo" ; continue }
    if { $vstate == "port_inout_lo" && $word == "\]" } { set vstate "port_inout_busname" ; continue }
    if { $vstate == "port_inout_busname" && $word == ";" } { set vstate "idle" ; continue }
    if { $vstate == "port_inout" && $word == ";" } { set vstate "idle" ; continue }   
    if { $vstate == "port_inout_busname" && $word == "," } { set vstate "port_inout_busname" ; continue }
    if { $vstate == "port_inout" && $word == "," } { set vstate "port_inout" ; continue }

    if { $vstate == "wire_decl" && $word == "\[" } { set vstate "wire_decl_hi" ; continue }  
    if { $vstate == "wire_decl_hi" && $word == ":" } { set vstate "wire_decl_lo" ; continue }
    if { $vstate == "wire_decl_lo" && $word == "\]" } { set vstate "wire_decl_busname" ; continue }
    if { $vstate == "wire_decl_busname" && $word == ";" } { set vstate "idle"  ; continue }
    if { $vstate == "wire_decl" && $word == ";" } { set vstate "idle" ; continue }   
    if { $vstate == "wire_decl_busname" && $word == "," } { set vstate "wire_decl_busname" ; continue }
    if { $vstate == "wire_decl" && $word == "," } { set vstate "wire_decl" ; continue }

    if { $vstate == "idle" && $word == "input"  } { set vstate "port_input"  ; continue }
    if { $vstate == "idle" && $word == "output" } { set vstate "port_output" ; continue }
    if { $vstate == "idle" && $word == "inout"  } { set vstate "port_inout"  ; continue }
    if { $vstate == "idle" && $word == "wire"   } { set vstate "wire_decl"   ; continue }

    if { $vstate == "module_decl" } { set vstate "port_decl1" ; set ansi_dir "" ; continue }  
    if { $word == ";" && $vstate == "port_decl1" } { set vstate "idle" ; continue }  
    # ANSI-style port declarations inside the module header (e.g.
    # `module m ( input clk, output [31:0] data )`). The non-ANSI style (a bare
    # name list in the header, declared in the body) has no direction keyword
    # here, so ansi_dir stays empty and nothing is captured, leaving the body
    # declarations to populate the port arrays.
    if { $vstate == "port_decl1" && $word == "input" }  { set ansi_dir "in"   ; continue }
    if { $vstate == "port_decl1" && $word == "output" } { set ansi_dir "out"  ; continue }
    if { $vstate == "port_decl1" && $word == "inout" }  { set ansi_dir "inout"; continue }
    if { $vstate == "port_decl1" && $word == "\[" } { set vstate "port_decl1_hi" ; continue }
    if { $vstate == "port_decl1_hi" && $word != "\]" && $word != ":" } { set current_hi_idx $word ; continue }
    if { $vstate == "port_decl1_hi" && $word == ":" } { set vstate "port_decl1_lo" ; continue }
    if { $vstate == "port_decl1_lo" && $word != "\]" } { set current_lo_idx $word ; continue }
    if { $vstate == "port_decl1_lo" && $word == "\]" } { set vstate "port_decl1_bus" ; continue }
    if { $vstate == "port_decl1" && $ansi_dir ne "" && $word != "," && $word != ")" && $word != "(" } {
     lappend _portlist($portindex) $word
     if { $ansi_dir eq "in" }  { lappend _porttype($portindex) "in" }
     if { $ansi_dir eq "out" } { lappend _porttype($portindex) "out" }
     if { $ansi_dir eq "inout" } { lappend _porttype($portindex) "inout" }
     lappend _portmaster($portindex) $current_module
     continue
    }
    if { $vstate == "port_decl1_bus" && $word != "," && $word != ")" && $word != "(" } {
     lappend _portlist($portindex) $word
     if { $ansi_dir eq "in" }  { lappend _porttype($portindex) "bus in $current_lo_idx $current_hi_idx" }
     if { $ansi_dir eq "out" } { lappend _porttype($portindex) "bus out $current_lo_idx $current_hi_idx" }
     if { $ansi_dir eq "inout" } { lappend _porttype($portindex) "bus inout $current_lo_idx $current_hi_idx" }
     lappend _portmaster($portindex) $current_module
     set vstate "port_decl1"
     continue
    }
    if { $vstate == "port_decl1_bus" && $word == "," } { set vstate "port_decl1" ; continue }
    if { $word == "module" && $vstate == "idle" } { set vstate "module_decl" ; continue } 
    
    if { $word == "endmodule" && $vstate == "idle" } { set vstate "idle" ; continue } 


    if { $vstate == "inst_decl" } { set vstate "inst_decl_pins" ; continue }   

          
    if { $word == "." && $vstate == "inst_decl_pins" } { set vstate "inst_pin_conn" ; continue }         

    if { $word == "(" && $vstate == "inst_pin_conn"  } { set vstate "inst_pin_connw" ; continue }         

    if { $word == ")" && $vstate == "inst_pin_connw"  } { set vstate "inst_decl_pins" ; continue }         


    if { $word == "\[" && $vstate == "inst_pin_connw"     } { set vstate "inst_pin_connw_b1" ; set b1_is_bit 1 ; set cur_bit "" ; continue }
    if { $word == "\]" && $vstate == "inst_pin_connw_b1"  } {
     set vstate "inst_pin_connw"
     if { $b1_is_bit } {
      if { $ishier == 0 } {
       set nidx [llength $_instpinconn2($instindex)]
       if { $nidx > 0 } { lset _instpinconn2($instindex) [expr {$nidx-1}] "[lindex $_instpinconn2($instindex) [expr {$nidx-1}]]\[$cur_bit\]" }
      } else {
       set nidx [llength $_hinstpinconn2($hinstindex)]
       if { $nidx > 0 } { lset _hinstpinconn2($hinstindex) [expr {$nidx-1}] "[lindex $_hinstpinconn2($hinstindex) [expr {$nidx-1}]]\[$cur_bit\]" }
      }
     }
     continue
    }

    if { $word == "\{" && $vstate == "inst_pin_connw"     } { set vstate "inst_pin_connw_b1" ; set b1_is_bit 0 ; continue }
    if { $word == "\}" && $vstate == "inst_pin_connw_b1"  } { set vstate "inst_pin_connw" ; continue }         
    
    if { $word == ";" && $vstate == "inst_decl_pins" } { set vstate "idle" ; continue }         
    
    if { $vstate == "idle"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } {set vstate "inst_decl" ; set vstate_refname $word } ;
    
  }
    
 } 
 
 puts "Info : read $instindex lib instances"
 puts "Info : read $hinstindex hierarchical instances"
 puts "Info : read $wireindex nets"

}


