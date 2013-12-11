#
#   JSON parser for Tcl.
#
#   See http://www.json.org/ && http://www.ietf.org/rfc/rfc4627.txt
#
#   Total rework of the code published with version number 1.0 by
#   Thomas Maeder, Glue Software Engineering AG
#
#   $Id: json.tcl,v 1.7 2011/11/10 21:05:58 andreas_kupries Exp $
#

if {![package vsatisfies [package provide Tcl] 8.5]} {
    package require dict
}

namespace eval json {
    # Regular expression for tokenizing a JSON text (cf. http://json.org/)

    # tokens consisting of a single character
    variable singleCharTokens { "{" "}" ":" "\\[" "\\]" "," }
    variable singleCharTokenRE "\[[join $singleCharTokens {}]\]"

    # quoted string tokens
    variable escapableREs { "[\\\"\\\\/bfnrt]" "u[[:xdigit:]]{4}" }
    variable escapedCharRE "\\\\(?:[join $escapableREs |])"
    variable unescapedCharRE {[^\\\"]}
    variable stringRE "\"(?:$escapedCharRE|$unescapedCharRE)*\""

    # (unquoted) words
    variable wordTokens { "true" "false" "null" }
    variable wordTokenRE [join $wordTokens "|"]

    # number tokens
    # negative lookahead (?!0)[[:digit:]]+ might be more elegant, but
    # would slow down tokenizing by a factor of up to 3!
    variable positiveRE {[1-9][[:digit:]]*}
    variable cardinalRE "-?(?:$positiveRE|0)"
    variable fractionRE {[.][[:digit:]]+}
    variable exponentialRE {[eE][+-]?[[:digit:]]+}
    variable numberRE "${cardinalRE}(?:$fractionRE)?(?:$exponentialRE)?"

    # JSON token
    variable tokenRE "$singleCharTokenRE|$stringRE|$wordTokenRE|$numberRE"


    # 0..n white space characters
    set whiteSpaceRE {[[:space:]]*}

    # Regular expression for validating a JSON text
    variable validJsonRE "^(?:${whiteSpaceRE}(?:$tokenRE))*${whiteSpaceRE}$"
}


# Validate JSON text
# @param jsonText JSON text
# @return 1 iff $jsonText conforms to the JSON grammar
#           (@see http://json.org/)
proc ::json::validate_tcl {jsonText} {
    variable validJsonRE

    return [regexp -- $validJsonRE $jsonText]
}

# Parse JSON text into a dict
# @param jsonText JSON text
# @return dict (or list) containing the object represented by $jsonText
proc ::json::json2dict_tcl {jsonText} {
    variable tokenRE

    set tokens [regexp -all -inline -- $tokenRE $jsonText]
    set nrTokens [llength $tokens]
    set tokenCursor 0
    return [parseValue $tokens $nrTokens tokenCursor]
}

# Parse multiple JSON entities in a string into a list of dictionaries
# @param jsonText JSON text to parse
# @param max      Max number of entities to extract.
# @return list of (dict (or list) containing the objects) represented by $jsonText
proc ::json::many-json2dict_tcl {jsonText {max -1}} {
    variable tokenRE

    if {$max == 0} {
	return -code error -errorCode {JSON BAD-LIMIT ZERO} \
	    "Bad limit 0 of json entities to extract."
    }

    set tokens [regexp -all -inline -- $tokenRE $jsonText]
    set nrTokens [llength $tokens]
    set tokenCursor 0

    set result {}
    set found 0
    set n $max
    while {$n != 0} {
	if {$tokenCursor >= $nrTokens} break
	lappend result [parseValue $tokens $nrTokens tokenCursor]
	incr found
	if {$n > 0} {incr n -1}
    }

    if {$n > 0} {
	return -code error -errorCode {JSON BAD-LIMIT TOO LARGE} \
	    "Bad limit $max of json entities to extract, found only $found."
    }

    return $result
}

# Throw an exception signaling an unexpected token
proc ::json::unexpected {tokenCursor token expected} {
    return -code error -errorcode [list JSON UNEXPECTED $tokenCursor $expected] \
	"unexpected token \"$token\" at position $tokenCursor; expecting $expected"
}

# Get rid of the quotes surrounding a string token and substitute the
# real characters for escape sequences within it
# @param token
# @return unquoted unescaped value of the string contained in $token
proc ::json::unquoteUnescapeString {token} {
    set unquoted [string range $token 1 end-1]
    return [subst -nocommands -novariables $unquoted]
}

# Parse an object member
# @param tokens list of tokens
# @param nrTokens length of $tokens
# @param tokenCursorName name (in caller's context) of variable
#                        holding current position in $tokens
# @param objectDictName name (in caller's context) of dict
#                       representing the JSON object of which to
#                       parse the next member
proc ::json::parseObjectMember {tokens nrTokens tokenCursorName objectDictName} {
    upvar $tokenCursorName tokenCursor
    upvar $objectDictName objectDict

    set token [lindex $tokens $tokenCursor]
    incr tokenCursor

    set leadingChar [string index $token 0]
    if {$leadingChar eq "\""} {
        set memberName [unquoteUnescapeString $token]

        if {$tokenCursor == $nrTokens} {
            unexpected $tokenCursor "END" "\":\""
        } else {
            set token [lindex $tokens $tokenCursor]
            incr tokenCursor

            if {$token eq ":"} {
                set memberValue [parseValue $tokens $nrTokens tokenCursor]
                dict set objectDict $memberName $memberValue
            } else {
                unexpected $tokenCursor $token "\":\""
            }
        }
    } else {
        unexpected $tokenCursor $token "STRING"
    }
}

# Parse the members of an object
# @param tokens list of tokens
# @param nrTokens length of $tokens
# @param tokenCursorName name (in caller's context) of variable
#                        holding current position in $tokens
# @param objectDictName name (in caller's context) of dict
#                       representing the JSON object of which to
#                       parse the next member
proc ::json::parseObjectMembers {tokens nrTokens tokenCursorName objectDictName} {
    upvar $tokenCursorName tokenCursor
    upvar $objectDictName objectDict

    while true {
        parseObjectMember $tokens $nrTokens tokenCursor objectDict

        set token [lindex $tokens $tokenCursor]
        incr tokenCursor

        switch -exact $token {
            "," {
                # continue
            }
            "\}" {
                break
            }
            default {
                unexpected $tokenCursor $token "\",\"|\"\}\""
            }
        }
    }
}

# Parse an object
# @param tokens list of tokens
# @param nrTokens length of $tokens
# @param tokenCursorName name (in caller's context) of variable
#                        holding current position in $tokens
# @return parsed object (Tcl dict)
proc ::json::parseObject {tokens nrTokens tokenCursorName} {
    upvar $tokenCursorName tokenCursor

    if {$tokenCursor == $nrTokens} {
        unexpected $tokenCursor "END" "OBJECT"
    } else {
        set result [dict create]

        set token [lindex $tokens $tokenCursor]

        if {$token eq "\}"} {
            # empty object
            incr tokenCursor
        } else {
            parseObjectMembers $tokens $nrTokens tokenCursor result
        }

        return $result
    }
}

# Parse the elements of an array
# @param tokens list of tokens
# @param nrTokens length of $tokens
# @param tokenCursorName name (in caller's context) of variable
#                        holding current position in $tokens
# @param resultName name (in caller's context) of the list
#                   representing the JSON array
proc ::json::parseArrayElements {tokens nrTokens tokenCursorName resultName} {
    upvar $tokenCursorName tokenCursor
    upvar $resultName result

    while true {
        lappend result [parseValue $tokens $nrTokens tokenCursor]

        if {$tokenCursor == $nrTokens} {
            unexpected $tokenCursor "END" "\",\"|\"\]\""
        } else {
            set token [lindex $tokens $tokenCursor]
            incr tokenCursor

            switch -exact $token {
                "," {
                    # continue
                }
                "\]" {
                    break
                }
                default {
                    unexpected $tokenCursor $token "\",\"|\"\]\""
                }
            }
        }
    }
}

# Parse an array
# @param tokens list of tokens
# @param nrTokens length of $tokens
# @param tokenCursorName name (in caller's context) of variable
#                        holding current position in $tokens
# @return parsed array (Tcl list)
proc ::json::parseArray {tokens nrTokens tokenCursorName} {
    upvar $tokenCursorName tokenCursor

    if {$tokenCursor == $nrTokens} {
        unexpected $tokenCursor "END" "ARRAY"
    } else {
        set result {}

        set token [lindex $tokens $tokenCursor]

        set leadingChar [string index $token 0]
        if {$leadingChar eq "\]"} {
            # empty array
            incr tokenCursor
        } else {
            parseArrayElements $tokens $nrTokens tokenCursor result
        }

        return $result
    }
}

# Parse a value
# @param tokens list of tokens
# @param nrTokens length of $tokens
# @param tokenCursorName name (in caller's context) of variable
#                        holding current position in $tokens
# @return parsed value (dict, list, string, number)
proc ::json::parseValue {tokens nrTokens tokenCursorName} {
    upvar $tokenCursorName tokenCursor

    if {$tokenCursor == $nrTokens} {
        unexpected $tokenCursor "END" "VALUE"
    } else {
        set token [lindex $tokens $tokenCursor]
        incr tokenCursor

        set leadingChar [string index $token 0]
        switch -exact -- $leadingChar {
            "\{" {
                return [parseObject $tokens $nrTokens tokenCursor]
            }
            "\[" {
                return [parseArray $tokens $nrTokens tokenCursor]
            }
            "\"" {
                # quoted string
                return [unquoteUnescapeString $token]
            }
            "t" {
		# bare word: true (mapped to numeric boolean)
		return 1
	    }
            "f" {
		# bare word: false (mapped to numeric boolean)
		return 0
	    }
            "n" {
                # bare word: null (return as is)
                return $token
            }
            default {
                # number?
                if {[string is double -strict $token]} {
                    return $token
                } else {
                    unexpected $tokenCursor $token "VALUE"
                }
            }
        }
    }
}
