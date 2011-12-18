# underscore.tcl - Collection of utility methods
#
# Inspired by Underscore.js - http://documentcloud.github.com/underscore/ and
# the Ruby Enumerable module.
#
# This package provides a collection of different utility methods, that try to
# bring functional programming aspects known from other programming languages
# like Ruby or JavaScript to Tcl.
package provide underscore 0.1

namespace eval _ {
    variable __return_value {}
    variable __return_options {}

    # Yields a block of code in a specific stack-level.
    #
    # This function yields the passed block of code in a seperate stack frame
    # (by wrapping it into an ::apply call), but allows easy access to
    # surrounding variables using the tcl-native upvar mechanism.
    #
    # Yielding the code in an anonymous proc prevents the leakage of variable
    # definitions, while still giving the block access to surrounding variables
    # using upvar.
    #
    # @example Calculating the first n Fibonnacci numbers
    #   proc fib_up_to { max block } {
    #       set i1 [set i2 1]
    #
    #       while { $i1 <= $max } {
    #           _::yield 1 $block $i1
    #           set tmp [expr $i + $i2]
    #           set i1 $i2
    #           set i2 $tmp
    #       }
    #   }
    #
    #   fib_up_to 50 {{n} { puts $n }} ;# prints the fibonnaci sequence up to 50
    #
    # @example Automatic resource cleanup
    #   # Guarantess that the file descriptor is closed,
    #   # even in case of an error being raised while executing the block.
    #   proc file_open { path mode block } {
    #       open $fd
    #
    #       # Catch any exceptions that might happen
    #       set error [catch { _::yield 1 $block $fd } value options]]
    #
    #       catch { close $fd }
    #
    #       if { $error } {
    #           # if an exception happened, rethrow it
    #           return {*}$options $value
    #       } else {
    #           # Do nothing
    #           return
    #       }
    #   }
    #
    #   file_open "/tmp/test" "w" {{fd} {
    #       puts $fd "test"
    #   }}
    #
    # If you want to return from the stack frame where the method that yields a block
    # was called from, you can use 'return -code return'.
    #
    # @example Returning from the stack frame that called the yielding method.
    #   proc return_to_calling_frame {} {
    #       _::each {1 2 3 4} {{item} {
    #           if { $item == 2 } {
    #               # Stops the iteration and will return "done" from "return_to_calling_frame"
    #               return -code return "done"
    #           }
    #       }}
    #       # This return will not be executed
    #       return "fail"
    #   }
    #
    # 'return -code break ?value?' and 'return -code continue ?value?' have special
    # meanings inside a block.
    #
    # @example Passing a block down, by specifying a yield level
    #   # Reverse each, like _::each, but in reverse
    #   proc reverse_each { list block } {
    #       _::each [lreverse $list] {{args} {
    #           # Include the passed block
    #           upvar block block
    #
    #           # we have to increase the yield level here, as we want to
    #           # execute the block on the same stack level as reverse_each
    #           # was called on
    #           _::yield 2 $block {*}$args
    #       }}
    #   }
    #
    # @example Passing a block down by upleveling the call to each.
    #   # Reverse each, like _::each, but in reverse
    #   proc reverse_each { list block } {
    #       uplevel [list _::each [lreverse $list] $block]
    #   }
    #
    # @param level Distance to move up the procedure stack before calling
    #   ::apply with the passed block and arguments.
    # @param block_or_proc The block (anonymous function) or proc to be executed
    #   with the passed arguments. If it's a block, it can be either in the form
    #   of {args block} or {args block namespace} (see the documentation for ::apply).
    # @param args The arguments with which the passed block should be called.
    #
    # @return Return value of the block.
    proc yield { level block_or_proc args } {
        if { [llength $block_or_proc] == 1 } {
            set command [list $block_or_proc {*}$args]
        } else {
            set command [list apply $block_or_proc {*}$args]
        }

        if { [uplevel [expr { $level + 1 }] [list catch $command _::__return_value _::__return_options ]] } {
            set old_code [dict get $_::__return_options -code]
            set old_level [dict get $_::__return_options -level]

            if { $old_code == 3 && $old_level == 0 } {
                dict set _::__return_options -code return
                dict set _::__return_options -level [expr { $old_level + $level }]
            } elseif { $old_code == 0 && $old_level == 1 } {
                dict set _::__return_options -level [expr { $old_level + $level + 1 }]
            }
            return {*}$_::__return_options $_::__return_value
        }
        return $_::__return_value
    }

    # Iterates over the passed list, yielding each element in turn to the
    # passed iterator
    proc each { list iterator } {
        foreach item $list {
            yield 1 $iterator $item
        }

        return $list
    }

    proc map { list iterator } {
        set result [list]

        foreach item $list {
            if { [catch { set temp [_::yield 1 $iterator $item] } value options] } {
                if { [dict get $options -code] == 4 } {
                    lappend result {}
                } else {
                    return {*}$options $value
                }
            } else {
                lappend result $temp
            }
        }

        if {[llength $result] == [llength $list]} {
            return $result
        } else {
            return {}
        }
    }

    proc reduce { list iterator memo } {
        foreach item $list {
            set memo [yield 1 $iterator $memo $item]
        }
        return $memo
    }

    # Executes the passed iterator with each element of the passed list.
    # Returns true if the passed block never returns a 'falsy' value.
    #
    # When no explicit iterator is passed, all? will return true
    # if none of the list elements is a falsy value.
    proc all? { list {iterator {{x} { return $x }}} } {
        _::each $list {{e} {
            upvar iterator iterator
            if { [string is false [_::yield 2 $iterator $e]] } {
                return -code return false
            }
        }}

        return true
    }
    interp alias {} ::_::every? {} ::_::all?
    namespace export all? every?

    # Executes the passed iterator with each element of the passed list.
    # Returns true if the passed block returns at least one value that
    # is not 'falsy'.
    #
    # When no explicit iterator is passed, any? will return true
    # if at least one of the list elements is not a falsy value.
    proc any? { list {iterator {{x} { return $x }}} } {
        _::each $list {{e} {
            upvar iterator iterator
            if { ![string is false [_::yield 2 $iterator $e]] } {
                return -code return true
            }
        }}

        return false
    }
    interp alias {} ::_::some? {} ::_::any?
    namespace export some? any?

    # Returns a sorted copy of list. Sorting is based on the return
    # values of the execution of the iterator for each item.
    proc sort_by { list iterator } {
        set list_to_sort [_::map $list {{item} {
            upvar iterator iterator
            list [_::yield 2 $iterator $item] $item
        }}]

        set sorted_list [lsort $list_to_sort]

        _::map $sorted_list {{pair} {
            lindex $pair 1
        }}
    }

    proc take_while { list iterator } {
        set result [list]

        foreach item $list {
            if { ![yield 1 $iterator $item] } {
                break
            }

            lappend result $item
        }

        return $item
    }

    proc group_by { list iterator } {
        set result [dict create]

        foreach item $list {
            dict lappend result [yield 1 $iterator $item] $item
        }

        return $result
    }
}