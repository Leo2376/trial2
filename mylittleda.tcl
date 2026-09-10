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

set gridutil [ list ]

set utlzmap  [ list ]
set hier_dontshow [ list clk_gate ]

set siteh 0.3

set fontsize 6

set targetutilz 65


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
 variable _gui_mode
 

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

proc set_font_size { sz } {
 variable fontsize
 
 set $fontsize $sz
}

proc scalepx { sx } {
 variable scale_f
 set offset_x 20.0
 set bl_x [expr $offset_x+$scale_f*$sx]
 return $bl_x
 }

proc scalepy { sy } {
 variable scale_f
 variable app_height
 set wsizey $app_height
 set offset_y 20.0
 set bl_y [expr $offset_y+$scale_f*$sy]
 set bl_y [expr $wsizey-$bl_y]
 return $bl_y
 }



proc redraw { } {
 variable _gui_mode
 if { ! $_gui_mode } {
    puts "Info: REDRAW (batch mode - no GUI)"
    return
 }
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
 
 .can delete all

 puts "Info : REDRAW APR objects .."
 
 # APR objects
 set wsizex $app_width
 set wsizey $app_height
 set offset_x 20.0
 set offset_y 20.0
 
 # top Boudary
 puts "Info : REDRAW top boundary .."
 set bl_x [lindex $topbox 0]
 set bl_y [lindex $topbox 1]
 set tr_x [lindex $topbox 2]
 set tr_y [lindex $topbox 3]
 
 set scale_fx [expr ($wsizex-2.0*$offset_x) / $tr_x ]
 set scale_fy [expr ($wsizey-2.0*$offset_y) / $tr_y ]
 set scale_f  1
  
 if { $scale_fx <  $scale_fy } { set scale_f $scale_fx }
 if { $scale_fx >= $scale_fy } { set scale_f $scale_fy }
 
 set bound_x [expr $offset_x+$scale_f*$tr_x]
 set bound_y [expr $offset_y+$scale_f*$tr_y]
 
 .can create rectangle $offset_x [expr $wsizey-$offset_y] $bound_x [expr $wsizey-$bound_y] -width 2 -outline "#b0b0b0"

 # core Boundary
 puts "Info : REDRAW top boundary .."
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
 
 puts "Info : REDRAW placement blockage .."
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

 puts "Info : REDRAW placement regions .."
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
 puts "Info : REDRAW placed instance .."
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
         if {$class == "BLOCK" && $szx<$szy}		 
         set text [lindex $_libcell($refid) 0]
         set tx_y [expr $bl_y+($tr_y-$bl_y)/20 ]
         set tx_x [expr $tr_x-($tr_x-$bl_x)/4 ]
  
        .can create line      $bl_x $tx_y $tx_x $bl_y -width 1 -fill $outline	 
	
				 if { [expr $bl_y-$tr_y] > 300                              } { .can create text $tx_x $tx_y -text $text -fill $outline -angle 90 -justify left -anchor w -font {Helvetica -14 bold}}
 				 if { [expr $bl_y-$tr_y] >  70 && [expr $bl_y-$tr_y] <= 300 } { .can create text $tx_x $tx_y -text $text -fill $outline -angle 90 -justify left -anchor w -font {Helvetica -7 bold}}
				 if { [expr $bl_y-$tr_y] >  40 && [expr $bl_y-$tr_y] <=  70 } { .can create text $tx_x $tx_y -text $text -fill $outline -angle 90 -justify left -anchor w -font {Helvetica -5 bold}}
	                        
				

         if {$class == "BLOCK" && $szx>=$szy}
         set text [lindex $_libcell($refid) 0]
         set tx_y [expr $bl_y+($tr_y-$bl_y)/4 ]
         set tx_x [expr $bl_x+($tr_x-$bl_x)/20 ]

        .can create line      $bl_x $tx_y $tx_x $bl_y -width 1 -fill $outline	 

				 if { [expr $tr_x-$bl_x] > 300 			    } {  .can create text $tx_x $tx_y -text $text -fill $outline -angle 0 -justify left -anchor w -font {Helvetica -24 bold}}
				 if { [expr $tr_x-$bl_x] >  70 && [expr $tr_x-$bl_x] <= 300 } {  .can create text $tx_x $tx_y -text $text -fill $outline -angle 0 -justify left -anchor w -font {Helvetica -14 bold}}
				 if { [expr $tr_x-$bl_x] >  40 && [expr $tr_x-$bl_x] <=  70 } {  .can create text $tx_x $tx_y -text $text -fill $outline -angle 0 -justify left -anchor w -font {Helvetica -9 bold}}
	                        
	 }
 }


 puts "Info : Bump redraw  .."
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

proc make_placement { {opt "-full"} } {
 variable topname
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
  set utlz 0 
 for { set searchx 0 } { $searchx < 20 } { set searchx [expr $searchx + 1] } {
     for { set searchy 0 } { $searchy < 20 } { set searchy [expr $searchy + 1] } {	
        set gx [ expr $bx + $searchx  ]	        
        set gy [ expr $by + $searchy  ]
        if { [lindex $utlzmap [expr $gy+100*$gx]] == 1 } { incr utlz }	
      }
 }
    puts "Info : placement site $psite has occupation of [expr $utlz/4] %"
    lappend msite $utlz
 }

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

 

proc report_area_stats { } {
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
 puts "" 
}


proc update_wire_db { } {
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
  lassign $a alhs arhs
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
   set pn [lindex $pins $j]
   set wn [_scoped_net $fullp [lindex $nets $j]]
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
   set pn [lindex $pins $j]
   set wn [_scoped_net $fullp [lindex $nets $j]]
   lappend netdriver($wn) "$ipath $pn"
   lappend netload($wn) "$ipath $pn"
  }
 }

 puts "Info : built net connectivity ([llength [array names netdriver]] driver nets, [llength [array names netload]] load nets)"
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

# report_path -from <pin|net> -to <pin|net>
# Text-only connectivity report (report_timing-style, no timing). Traces a path
# from a source point to a sink point across the net connectivity map built by
# build_net_conn. A point is either a net name or a pin "inst/pin".
proc report_path { args } {
 variable topname
 variable _libcell
 variable _instlist
 variable _hinstlist
 variable instindex
 variable hinstindex
 global netdriver netload

 set from ""
 set to ""
 for {set i 0} {$i < [llength $args]} {incr i} {
  set a [lindex $args $i]
  if { $a eq "-from" } { set from [lindex $args [incr i]] ; continue }
  if { $a eq "-to" }   { set to [lindex $args [incr i]] ; continue }
  puts "Error : unknown option '$a'"
  puts "Usage: report_path -from <pin|net> -to <pin|net>"
  return
 }
 if { $from eq "" || $to eq "" } {
  puts "Error : report_path requires -from and -to"
  puts "Usage: report_path -from <pin|net> -to <pin|net>"
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
  set d [lindex [array get netdriver $cur_net] 1]
  if { [llength $d] } { set start_point [lindex $d 0] }
 }
 if { $cur_net eq "" } { puts "Error : -from point $from not found" ; return }

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
  set l [lindex [array get netload $end_net] 1]
  if { [llength $l] } { set end_point [lindex $l 0] }
  if { $end_point eq "" } { set end_point "<net> $end_net" }
 }
 if { $end_net eq "" } { puts "Error : -to point $to not found" ; return }

 puts "************************************************************"
 puts " report_path : -from $from -to $to"
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
 puts "  Point                                   Fanout   Net"
 puts "  -------------------------------------------------------"

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
  set loads [lindex [array get netload $net] 1]
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

 # Emit the report.
 if { $start_point ne "" } {
  puts "  [_fmt_pin $start_point]"
 }
 set prev_net $cur_net
 foreach seg $path {
  set fanout [llength [lindex [array get netload $prev_net] 1]]
  set ln $via_inst($seg)
  set lpin $via_pin($seg)
  puts "  $prev_net                                   $fanout"
  puts "  [_fmt_pin "$ln $lpin"]"
  set prev_net $seg
 }
 if { $found } {
  set fanout [llength [lindex [array get netload $end_net] 1]]
  puts "  $end_net                                   $fanout"
 }
 puts "  -------------------------------------------------------"
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
    set fullp [lindex $_instlist($iid) 7]
    return [_scoped_net $fullp [lindex $_instpinconn2($iid) $k]]
   }
  }
 }
 set hid [lsearch -exact $hpathlist $inst]
 if { $hid >= 0 } {
  incr hid
  if { [info exists _hinstpinconn1($hid)] } {
   set k [lsearch -exact $_hinstpinconn1($hid) $pin]
   if { $k >= 0 } {
    set fullp [lindex $_hinstlist($hid) 7]
    return [_scoped_net $fullp [lindex $_hinstpinconn2($hid) $k]]
   }
  }
 }
 return ""
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

# get_cell <pattern> ?-hier?
# Report cells (leaf and hierarchical) whose full hierarchical instance path
# matches the glob pattern. Wildcards are the standard glob ones (*, ?, [..]).
#
# By default (no -hier) only the DIRECT children of the scope implied by the
# pattern are reported:
#   get_cell *             -> top-level instances only
#   get_cell core0/w0/*    -> direct children of core0/w0 only
#   get_cell *reg*         -> top-level instances matching *reg* only
# This matches the common EDA convention that a non-hierarchical query stays
# within one scope. With -hier the match is cross-hierarchy (the previous
# behaviour): every instance whose full path matches the pattern is reported,
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

 puts "************************************************************"
 puts " get_cell : $pattern"
 puts "************************************************************"

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

 set n 0
 for { set i 1 } { $i <= $instindex } { incr i } {
  set fullp [lindex $_instlist($i) 7]
  if { ! $hier && $fullp ne $scope } { continue }
  set iname [lindex $_instlist($i) 0]
  if { $fullp eq "-1" } { set ipath $iname } else { set ipath "$fullp/$iname" }
  if { [string match $pattern $ipath] } {
   set refid [lindex $_instlist($i) 8]
   if { [info exists _libcell($refid)] } {
    set refname [lindex $_libcell($refid) 0]
   } else {
    set refname [lindex $_instlist($i) 1]
   }
   puts "  $ipath ($refname)"
   incr n
  }
 }
 for { set i 1 } { $i <= $hinstindex } { incr i } {
  set fullp [lindex $_hinstlist($i) 7]
  if { ! $hier && $fullp ne $scope } { continue }
  set iname [lindex $_hinstlist($i) 0]
  if { $fullp eq "-1" } { set ipath $iname } else { set ipath "$fullp/$iname" }
  if { [string match $pattern $ipath] } {
   set refname [lindex $_hinstlist($i) 1]
   puts "  $ipath ($refname) hierarchical"
   incr n
  }
 }
 puts "  -------------------------------------------------------"
 set hdr $pattern
 if { $hier } { append hdr " -hier" }
 if { $n == 1 } { puts "$n cell matching $hdr." } else { puts "$n cells matching $hdr." }
 puts ""
}

# get_net <pattern> ?-hier?
# Report nets whose (scoped) name matches the glob pattern. Net names are
# stored scoped by their containing module's hierarchical path
# (e.g. "core0/w0/nv_c0/c0/iu0/n20719"); top-level nets keep the bare name.
# Wildcards are the standard glob ones (*, ?, [..]).
#
# By default (no -hier) only the nets of the SINGLE scope implied by the
# pattern are reported:
#   get_net *                    -> top-level nets only
#   get_net core0/w0/nv_c0/c0/*  -> nets declared in core0/w0/nv_c0/c0 only
#   get_net n2*                  -> top-level nets matching n2* only
# With -hier the match is cross-hierarchy: every net whose full scoped name
# matches the pattern is reported, at any depth.
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

 puts "************************************************************"
 puts " get_net : $pattern"
 puts "************************************************************"

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

 foreach n $nets {
  set d [lindex [array get netdriver $n] 1]
  set nd [llength $d]
  set l [lindex [array get netload $n] 1]
  set nl [llength $l]
  puts "  $n  (drivers:$nd receivers:$nl)"
 }
 puts "  -------------------------------------------------------"
 set hdr $pattern
 if { $hier } { append hdr " -hier" }
 set nm [llength $nets]
 if { $nm == 1 } { puts "$nm net matching $hdr." } else { puts "$nm nets matching $hdr." }
 puts ""
}

# all_connected <net or pin>
# Report all nets connected to a net or pin. The argument may be a glob
# pattern (with *, ?, [..]); every net whose name matches is reported with
# its driver pin(s) and receiver pin(s). A pin "inst/pin" argument reports
# the single net that pin is on.
proc all_connected { pattern } {
 global netdriver netload
 variable pathlist
 variable hpathlist

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

 # Otherwise treat the argument as a net pattern and expand over all
 # known nets. Net names are stored scoped by their containing module's
 # hierarchical path (e.g. "core0/w0/nv_c0/c0/iu0/n20719"), so a full
 # hierarchical reference matches its own scope exactly and does not pull in
 # same-named nets from sibling scopes. The trailing-token fallback is only
 # used for a bare (non-hierarchical) pattern, so a plain "n2*" can still
 # list every matching net across scopes.
 set nets [list]
 foreach name [array names netdriver] { if { [string match $pattern $name] } { lappend nets $name } }
 foreach name [array names netload]   { if { [string match $pattern $name] } { lappend nets $name } }
 if { ! [string match {*/*} $pattern] } {
  set tail $pattern
  foreach name [array names netdriver] { if { [string match $tail [lindex [split $name /] end]] } { lappend nets $name } }
  foreach name [array names netload]   { if { [string match $tail [lindex [split $name /] end]] } { lappend nets $name } }
 }
 # unique, sorted
 set seen {}
 set nets2 {}
 foreach n [lsort $nets] { if { [lsearch -exact $seen $n] < 0 } { lappend seen $n ; lappend nets2 $n } }

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
 set d [lindex [array get netdriver $n] 1]
 if { [llength $d] } {
  puts "    drivers :"
  foreach p $d { puts "      [_fmt_pin $p]" }
 } else {
  puts "    drivers : (none)"
 }
 set l [lindex [array get netload $n] 1]
 if { [llength $l] } {
  puts "    receivers :"
  foreach p $l { puts "      [_fmt_pin $p]" }
 } else {
  puts "    receivers : (none)"
 }
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
 set prev ""
 set vstate "idle"
 set hinstindex 0
    
 while { [gets $fp line] >=0 } {
  
  if { [regexp {^[ \t]*assign[ \t]+([A-Za-z0-9_\[\]]+)[ \t]*=[ \t]*([^;]+);[ \t]*$} $line -> alhs arhs] } {
     set alhs [string trim $alhs]
     foreach r [split [string trim $arhs] " "] {
       set r [string trim $r]
       if { $r ne "" && $r ne "+" && $r ne "^" && $r ne "&" && $r ne "~" } { lappend _assignlist [list $alhs $r] }
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
    if { $ishier==0 } { 
     if { $vstate == "inst_pin_conn" && $word != "(" && $word != ")"                                                                                      } {    lappend _instpinconn1($instindex) $word   }       
     if { $vstate == "inst_pin_connw" && $word != "(" && $word != ")" && $word != "\[" && $word != "\]" && $word != "\{" && $word != "\}" && $word != "\,"} {    lappend _instpinconn2($instindex) $word   }
    } else {
     if { $vstate == "inst_pin_conn" && $word != "(" && $word != ")"                                    			          		  } {    lappend _hinstpinconn1($hinstindex) $word   }       
     if { $vstate == "inst_pin_connw" && $word != "(" && $word != ")" && $word != "\[" && $word != "\]" && $word != "\{" && $word != "\}" && $word != "\,"} {    lappend _hinstpinconn2($hinstindex) $word   }
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

    if { $vstate == "module_decl" } { set vstate "port_decl1" ; continue }   
    if { $word == ";" && $vstate == "port_decl1" } { set vstate "idle" ; continue }  
    if { $word == "module" && $vstate == "idle" } { set vstate "module_decl" ; continue } 
    
    if { $word == "endmodule" && $vstate == "idle" } { set vstate "idle" ; continue } 


    if { $vstate == "inst_decl" } { set vstate "inst_decl_pins" ; continue }   

          
    if { $word == "." && $vstate == "inst_decl_pins" } { set vstate "inst_pin_conn" ; continue }         

    if { $word == "(" && $vstate == "inst_pin_conn"  } { set vstate "inst_pin_connw" ; continue }         

    if { $word == ")" && $vstate == "inst_pin_connw"  } { set vstate "inst_decl_pins" ; continue }         


    if { $word == "\[" && $vstate == "inst_pin_connw"     } { set vstate "inst_pin_connw_b1" ; continue }         
    if { $word == "\]" && $vstate == "inst_pin_connw_b1"  } { set vstate "inst_pin_connw" ; continue }         

    if { $word == "\{" && $vstate == "inst_pin_connw"     } { set vstate "inst_pin_connw_b1" ; continue }         
    if { $word == "\}" && $vstate == "inst_pin_connw_b1"  } { set vstate "inst_pin_connw" ; continue }         
    
    if { $word == ";" && $vstate == "inst_decl_pins" } { set vstate "idle" ; continue }         
    
    if { $vstate == "idle"  && $word != "\]" && $word !="\[" && $word !="," && $word !=";" } {set vstate "inst_decl" ; set vstate_refname $word } ;
    
  }
    
 } 
 
 puts "Info : read $instindex lib instances"
 puts "Info : read $hinstindex hierarchical instances"
 puts "Info : read $wireindex nets"

}


