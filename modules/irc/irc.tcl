# irc.tcl --
#
#	irc implementation for Tcl.
#
# Copyright (c) 2001-2003 by David N. Welton <davidw@dedasys.com>.
# This code may be distributed under the same terms as Tcl.
#
# $Id: irc.tcl,v 1.14 2003/06/30 10:24:17 davidw Exp $

package provide irc 0.4
package require Tcl 8.3
package require logger

namespace eval ::irc {
    # counter used to differentiate connections
    variable conn 0
    variable config
    variable irctclfile [info script]
    array set config {
        debug 0
    }
}

# ::irc::config --
#
# Set global configuration options.
#
# Arguments:
#
# key	name of the configuration option to change.
#
# value	value of the configuration option.

proc ::irc::config { key args } {
    variable config
    if { [llength $args] == 0 } {
	return $config($key)
    }
    if { [llength $args] > 1 } {
	error "wrong # args: should be \"config key ?val?\""
    }
    set value [lindex $args 0]
    foreach ns [namespace children] {
        if { [info exists config($key)] && [info exists ${ns}::config($key)] \
                && ${ns}::config($key) == $config($key)} {
            ${ns}::cmd-config $key $value
        }
    }
    set config($key) $value
}


# ::irc::connections --
#
# Return a list of handles to all existing connections

proc ::irc::connections { } {
    set r {}
    foreach ns [namespace children] {
        lappend r ${ns}::network
    }
    return $r
}


# ::irc::connection --
#
# Create an IRC connection namespace and associated commands.

proc ::irc::connection { args } {
    variable conn
    variable config

    # Create a unique namespace of the form irc$conn::$host

    set name [format "%s::irc%s" [namespace current] $conn]

    namespace eval $name {
	set nick ""
	set state 0
	set sock {}
	set logger [logger::init [namespace qualifiers [namespace current]]]
	array set dispatch {}
	array set linedata {}
	array set config [array get ::irc::config]

	# ircsend --
	# send text to the IRC server

	proc ircsend { msg } {
	    variable sock
	    variable dispatch
	    variable state
	    variable logger
	    ${logger}::debug "ircsend: '$msg'"
	    if { [catch {puts $sock $msg} err] } {
	        close $sock
	        set state 0
		if { [info exists dispatch(EOF)] } {
		    eval $dispatch(EOF)
		}
		${logger}::error "Error in ircsend: $err"
	    }
	}


	#########################################################
	# Implemented user-side commands, meaning that these commands
	# cause the calling user to perform the given action.
	#########################################################


        # cmd-config --
        #
        # Set or return per-connection configuration options.
        #
        # Arguments:
        #
        # key	name of the configuration option to change.
        #
        # value	value (optional) of the configuration option.

        proc cmd-config { key args } {
            variable config
	    variable logger

	    if { [llength $args] == 0 } {
		return $config($key)
	    }
	    if { [llength $args] > 1 } {
		error "wrong # args: should be \"cmd-config key ?val?\""
	    }
	    set value [lindex $args 0]
            if { $key == "debug" } {
                if { $value > 0 } {
                    ${logger}::enable debug
                } else {
                    ${logger}::disable debug
	        }
            }
            set config($key) $value
        }


        # cmd-destroy --
        #
        # destroys the current connection and its namespace

        proc cmd-destroy { } {
            variable logger
            variable sock
            ${logger}::delete
            catch {close $sock}
            namespace delete [namespace current]
        }

        proc cmd-connected { } {
            variable state
            return $state
        }

	proc cmd-user { username hostname servername {userinfo ""} } {
	    if { $userinfo == "" } {
		ircsend "USER $username $hostname server :$servername"
	    } else {
		ircsend "USER $username $hostname $servername :$userinfo"
	    }
	}

	proc cmd-nick { nk } {
	    variable nick
	    set nick $nk
	    ircsend "NICK $nk"
	}

	proc cmd-ping { target } {
	    ircsend "PRIVMSG $target :\001PING [clock seconds]\001"
	}

	proc cmd-serverping { } {
	    ircsend "PING [clock seconds]"
	}

	proc cmd-ctcp { target line } {
	    ircsend "PRIVMSG $target :\001$line\001"
	}

	proc cmd-join { chan {key {}} } {
	    ircsend "JOIN $chan $key"
	}

	proc cmd-part { chan {msg ""} } {
	    if { $msg == "" } {
		ircsend "PART $chan"
	    } else {
		ircsend "PART $chan :$msg"
	    }
	}

	proc cmd-quit { {msg {tcllib irc module - http://tcllib.sourceforge.net/}} } {
	    ircsend "QUIT :$msg"
	}

	proc cmd-privmsg { target msg } {
	    ircsend "PRIVMSG $target :$msg"
	}

	proc cmd-notice { target msg } {
	    ircsend "NOTICE $target :$msg"
	}

	proc cmd-kick { chan target {msg {}} } {
	    ircsend "KICK $chan $target :$msg"
	}

	proc cmd-mode { target args } {
	    ircsend "MODE $target [join $args]"
	}

	proc cmd-topic { chan msg } {
	    ircsend "TOPIC $chan :$msg"
	}

	proc cmd-invite { chan target } {
	    ircsend "INVITE $target $chan"
	}

	proc cmd-send { line } {
	    ircsend $line
	}

	proc cmd-peername { } {
	    variable sock
	    variable state
	    if { $state == 0 } { return {} }
	    return [fconfigure $sock -peername]
	}

	proc cmd-sockname { } {
	    variable sock
	    variable state
	    if { $state == 0 } { return {} }
	    return [fconfigure $sock -sockname]
	}

	proc cmd-disconnect { } {
	    variable sock
	    variable state
	    if { $state == 0 } { return -1 }
	    catch { close $sock }
	    return 0
	}

	proc cmd-reload {} {
	    variable nick
	    variable sock
	    variable state
	    variable logger
	    variable dispatch
	    variable host
	    variable port
	    # Reload this file, and merge the current connection into
	    # the new one.
	    set sk $sock
	    set nk $nick
	    set st $state
	    set lg $logger
	    array set ds [array get dispatch]
	    set hs $host
	    set pt $port
	    namespace eval :: {
		source [set ::irc::irctclfile]
	    }
	    set conn [namespace qualifiers [::irc::connection]]
	    set ${conn}::logger $lg
	    set ${conn}::sock $sk
	    set ${conn}::state $st
	    set ${conn}::nick $nk
	    set ${conn}::port $pt
	    set ${conn}::host $hs
	    array set ${conn}::dispatch [array get ds]
	    return ${conn}::network
	}

	# Connect --
	# Create the actual tcp connection.

	proc cmd-connect { args } {
	    variable state
	    variable sock
	    variable logger
	    variable host
	    variable port

	    # FIXME: This should be REMOVED for the tcllib 1.6 release
	    # cycle.
	    # It is for backwards compatibility only!
	    if { [llength $args] < 1 } {
		${logger}::warn "You are using a deprecated API - correct usage: 'connect host ?port?'"
	    } else {
		set host [lindex $args 0]
		if { [llength $args] > 1 } {
		    set port [lindex $args 1]
		} else {
		    set port 6667
		}
	    }

	    if { $state == 0 } {
		if { [catch { socket $host $port } sock] } {
		    error "Could not open connection to $host $port"
		}
		set state 1
		fconfigure $sock -translation crlf -buffering line
		fileevent $sock readable [namespace current]::GetEvent
	    }
	    return 0
	}

	# Callback API:

	# These are all available from within callbacks, so as to
	# provide an interface to provide some information on what is
	# coming out of the server.

	# action --

	# Action returns the action performed, such as KICK, PRIVMSG,
	# MODE etc, including numeric actions such as 001, 252, 353,
	# and so forth.

	proc action { } {
	    variable linedata
	    return $linedata(action)
	}

	# msg --

	# The last argument of the line, after the last ':'.

	proc msg { } {
	    variable linedata
	    return $linedata(msg)
	}

	# who --

	# Who performed the action.  If the command is called as [who address],
	# it returns the information in the form
	# nick!ident@host.domain.net

	proc who { {address 0} } {
	    variable linedata
	    if { $address == 0 } {
		return [lindex [split $linedata(who) !] 0]
	    } else {
		return $linedata(who)
	    }
	}

	# target --

	# To whom was this action done.

	proc target { } {
	    variable linedata
	    return $linedata(target)
	}

	# additional --

	# Returns any additional header elements beyond the target as a list.

	proc additional { } {
	    variable linedata
	    return $linedata(additional)
	}

	# header --

	# Returns the entire header in list format.

	proc header { } {
	    variable linedata
	    return [concat [list $linedata(who) $linedata(action) \
				$linedata(target)] $linedata(additional)]
	}

	# GetEvent --

	# Get a line from the server and dispatch it.

	proc GetEvent { } {
	    variable linedata
	    variable sock
	    variable dispatch
	    variable state
	    variable logger
	    variable nick
	    array set linedata {}
	    set line "eof"
	    if { [eof $sock] || [catch {gets $sock} line] } {
		close $sock
		set state 0
		${logger}::error "Error receiving from network: $line"
		if { [info exists dispatch(EOF)] } {
		    eval $dispatch(EOF)
		}
		return
	    }
	    ${logger}::debug "Recieved: $line"
	    if { [set pos [string first " :" $line]] > -1 } {
		set header [string range $line 0 [expr $pos - 1]]
		set linedata(msg) [string range $line [expr $pos + 2] end]
	    } else {
		set header [string trim $line]
		set linedata(msg) {}
	    }

	    if { [string match :* $header] } {
		set header [split [string trimleft $header :]]
	    } else {
		set header [linsert [split $header] 0 {}]
	    }
	    set linedata(who) [lindex $header 0]
	    set linedata(action) [lindex $header 1]
	    set linedata(target) [lindex $header 2]
	    set linedata(additional) [lrange $header 3 end]
	    if { [info exists dispatch($linedata(action))] } {
		eval $dispatch($linedata(action))
	    } elseif { [string match {[0-9]??} $linedata(action)] } {
		eval $dispatch(defaultnumeric)
	    } elseif { $linedata(who) == "" } {
		eval $dispatch(defaultcmd)
	    } else {
		eval $dispatch(defaultevent)
	    }
	}

	# registerevent --

	# Register an event in the dispatch table.

	# Arguments:
	# evnt: name of event as sent by IRC server.
	# cmd: proc to register as the event handler

	proc cmd-registerevent { evnt cmd } {
	    variable dispatch
	    set dispatch($evnt) $cmd
	    if { $cmd == "" } {
		unset dispatch($evnt)
	    }
	}

	# getevent --

	# Return the currently registered handler for the event.

	# Arguments:
	# evnt: name of event as sent by IRC server.

	proc cmd-getevent { evnt } {
	    variable dispatch
	    if { [info exists dispatch($evnt)] } {
		return $dispatch($evnt)
	    }
	    return {}
	}

	# eventexists --

	# Return a boolean value indicating if there is a handler
	# registered for the event.

	# Arguments:
	# evnt: name of event as sent by IRC server.

	proc cmd-eventexists { evnt } {
	    variable dispatch
	    return [info exists dispatch($evnt)]
	}

	# network --

	# Accepts user commands and dispatches them.

	# Arguments:
	# cmd: command to invoke
	# args: arguments to the command

	proc network { cmd args } {
	    eval [namespace current]::cmd-$cmd $args
	}

	# Create default handlers.

	set dispatch(PING) {network send "PONG :[msg]"}
	set dispatch(defaultevent) #
	set dispatch(defaultcmd) #
	set dispatch(defaultnumeric) #
    }

    # FIXME: This should be REMOVED for the tcllib 1.6 release cycle.
    # It is for backwards compatibility only!
    if { [llength $args] > 0 } {
	[set ${name}::logger]::warn "'connection' no longer takes args - use the 'connect' call to specifiy the host and port."
	set host [lindex $args 0]
	if { [llength $args] > 1 } {
	    set port [lindex $args 1]
	} else {
	    set port 6667
	}
	${name}::cmd-connect $host $port
    }

    set returncommand [format "%s::irc%s::network" [namespace current] $conn]
    incr conn
    return $returncommand
}
