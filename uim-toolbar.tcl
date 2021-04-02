#!/bin/sh
# Tcl ignores the next line -*- tcl -*- \
exec wish "$0" -- "$@"

# uim-toolbar implemented in tcl/tk
# watch the uim-helper (unix domain socket) using openbsd netcat

package require Tk

################################################################
### procedures

# return command line string to open uim-helper
proc open_uim_helper_command {} {
	if {[array names ::env -exact XDG_RUNTIME_DIR] != {}} {
		set sockfile "$::env(XDG_RUNTIME_DIR)/uim/socket/uim-helper"
	} else {
		set sockfile "$::env(HOME)/.uim.d/socket/uim-helper";
	}
	return "|nc -U $sockfile"
}

# open uim-helper socket and return channel
proc open_uim_helper {} {
	set chan [open [open_uim_helper_command] r+]
	return $chan
}

# send a message to uim-helper
# it seems no response if send a message to the channel that already open,
# so open/close a channel every time
proc send_message {msg} {
	#puts "send_message $msg"
	set chan [open_uim_helper]
	# send a message
	puts $chan "$msg"
	# close channel. should check error?
	close $chan
}

# send prop_activate with action to uim-helper
proc menu_command {act} {
	#puts "prop_activate\n$act\n\n"
	send_message "prop_activate\n$act\n\n"
}

# called when uim-helper is readable
proc read_cb {chan} {
	global top1 frame1
	set data [read $chan]

	# check eof flag
	if {[eof $chan]} {
		puts "$::argv0 : eof $chan"
		close $chan
		# try to watch uim-helper again
		watch_uim_helper
	}

	################################################################
	# parse per line
	#   prop_list_update: delete all menus
	#   branch: create menubutton widget, menu widget
	#   leaf: add item to menu
	#   others: ignore
	# hold current menubutton pathname, set by "branch"
	set mb1 ""
	# hold current menu pathname, set by "leaf"
	set m1 ""
	# split data into lines
	set records [split $data "\n"]
	foreach line $records {
		# split data into fields
		set fields [split $line "\t"]

		# prop_list_update
		if {[string equal "prop_list_update" [lindex $fields 0]]} {
			# destroy frame's children menubutton
			foreach w [winfo children $frame1] {
				#puts "$w [winfo class $w]"
				if {[winfo class $w] eq "Menubutton"} {
					destroy $w
				}
			}
		}

		# branch
		if {[string equal "branch" [lindex $fields 0]]} {
			# set and count number of branch
			incr branch_count
			# menu is child of menubutton, so create menubutton first
			# menubutton
			set mb1 [menubutton $frame1.mb$branch_count -direction right \
			             -relief raised]
			# menu
			set m1 [menu $mb1.m1 -tearoff 0]
			# associate menubutton and menu
			$mb1 configure -menu $m1
			# display menubutton
			pack $mb1 -side left
		}

		# leaf
		if {[string equal "leaf" [lindex $fields 0]]} {
			# if menubutton and menu was created
			if {$mb1 != "" && $m1 != ""} {
				# short string to be shown in the menu
				set label_str [lindex $fields 3]
				# prop_activate action to send uim-helper
				set act [lindex $fields 5]
				# marked `*' is selected item
				if {"*" eq [lindex $fields end]} {
					# very short string typically 1 character
					set iconic_label [lindex $fields 2]
					# set menubutton text
					$mb1 configure -text $iconic_label
					# append * to menu's label
					set label_str "$label_str *"
				}
				# add to menu with action command
				$m1 add command -label $label_str -command "menu_command $act"
			}
		}
	}
}

# return true if can open uim-helper
proc check_open_uim_helper {} {
	# uim-helper-server socket
	set chan [open_uim_helper]
	# check a error, whether the channel can be closed successfully
	if {[catch {close $chan} err]} {
		puts "error: open \"[open_uim_helper_command]\" r+"
		# false
		return 0
	}
	# true
	return 1
}

# connect to uim-helper and set callback if it becomes readable
proc watch_uim_helper {} {
	# if can not open uim-helper socket, try after 5 seconds
	if {![check_open_uim_helper]} {
		after 5000 watch_uim_helper
		return
	}
	# uim-helper-server socket
	set chan [open_uim_helper]
	# nonblocking mode is needed
	fconfigure $chan -blocking false
	# watch socket
	fileevent $chan readable [list read_cb $chan]

	# after ensures can open uim-helper, send prop_list_get message
	# to requests a prop_list_update.
	send_message "prop_list_get\n\n"
}
################################################################
### program start
# main window
set top1 .
# frame, menubuttons ships on it
set frame1 [frame $top1.frame1 -borderwidth 5]
pack $frame1 -side left
# exit button
set b1 [button $top1.b1 -text "exit" -command { exit }]
pack $b1 -side right
# disable xim, otherwise receives messages to yourself
tk useinputmethods 0

# overrideredirect & drag-move
bind $top1 <ButtonPress-1> {
	set winpx %x;               # pointerx on window
	set winpy %y;               # pointery on window
}
bind $top1 <B1-Motion> {
	set rootpx [winfo pointerx %W]; # pointerx on root
	set rootpy [winfo pointery %W]; # pointery on root
	# do not move window on button widget
	if {"%W" == "$top1" || "%W" == "$frame1"} {
		wm geometry $top1 "+[expr $rootpx - $winpx]+[expr $rootpy - $winpy]"
	}
}

# remove window decoration
wm overrideredirect $top1 1

# set fileevent, send prop_list_get message
watch_uim_helper
