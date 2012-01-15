lappend auto_path [file join [file dirname [info script]] ".."]
package require spec/autorun
package require underscore

describe "_::yield" {
    after each {
        if { [info exists ::yielded] } {
            unset ::yielded
        }

        if { [info exists ::level] } {
            unset ::level
        }

        if { [info exists ::yielded_args] } {
            unset ::yielded_args
        }
    }

    describe "when passed a proc name" {
        proc helper_proc {} {
            set ::yielded true
        }

        proc helper_proc_with_args { args } {
            set ::yielded_args $args
        }

        it "executes the passed proc" {
            _::yield 0 helper_proc
            expect $::yielded to be true
        }

        it "executes the passed proc with the passed arguments" {
            _::yield 0 helper_proc_with_args 1 2 3 4
            expect $::yielded_args to equal {1 2 3 4}
        }
    }

    describe "when passed a block" {
        it "yields the passed block" {
            _::yield 0 {{} {
                set ::yielded true
            }}

            expect $::yielded to be true
        }

        it "yields the passed block with the passed arguments" {
            _::yield 0 {{args} {
                set ::yielded_args $args
            }} 1 2 3 4

            expect $::yielded_args to equal {1 2 3 4}
        }

        it "yields the block in a seperate stack frame at the passed stack level" {
            _::yield 0 {{} {
                set ::level [info level]
            }}

            expect $::level to equal [expr { [info level] + 1 }]

            _::yield 1 {{} {
                set ::level [info level]
            }}

            expect $::level to equal [expr { [info level] }]
        }

        proc accepts_block { block } {
            _::yield 1 $block
        }

        it "allows accessing variables at the passed stack level using 'upvar'" {
            set test {1 2 3}

            _::yield 0 {{} {
                upvar test test
                set test {}
            }}
            expect $test to equal {}

            accepts_block {{} {
                upvar test test
                set test {1 2 3}
            }}
            expect $test to equal {1 2 3}
        }

        proc accepts_block_and_returns_executed { block } {
            _::yield 1 $block
            return "executed"
        }

        describe "calling return -code return inside a block" {
            proc helper_proc {} {
                accepts_block_and_returns_executed {{} {
                    return -code return "aborted"
                }}

                return "not aborted"
            }

            it "returns from the calling stack level" {
                set return_value [helper_proc]
                expect $return_value to equal "aborted"
            }
        }
    }
}


describe "_::all?" {
    it "always returns true on an empty list" {
        expect [_::all? {}] to be true
        expect [_::all? {} {{e} { return false }}] to be true
    }

    describe "with no block" {
        it "returns true if no element is falsy" {
            expect [_::all? {1 2 -1}] to be true
            expect [_::all? {a b c}] to be true
        }

        it "returns false if at least one element is falsy" {
            expect [_::all? {1 2 0 -1}] to be false
            # This might seem weird, but "f" is a falsy value in Tcl
            expect [_::all? {a b c f}] to be false
            expect [_::all? {true false true}] to be false
        }
    }

    describe "with a block" {
        it "returns true if the block never returns a falsy value" {
            expect [_::all? {false} {{item} { return true }}] to be true
            expect [_::all? {1 2 -1} {{item} { return true }}] to be true
            expect [_::all? {1 2 -1} {{item} { expr { $item < 5 } }}] to be true
            expect [_::all? {1 2 -1} {{item} { expr { 5 } }}] to be true
        }

        it "returns false if the block returns at least one falsy value" {
            expect [_::all? {true} {{item} { return false }}] to be false
            expect [_::all? {1 2 -1} {{item} { expr { $item > 2 } }}] to be false
            expect [_::all? {1 2 -1} {{item} { expr { 0 } }}] to be false

        }

        it "returns as early as possible" {
            set yielded [list]

            _::all? { 1 2 3 false 5 6 7 } {{item} {
                upvar yielded yielded
                lappend yielded $item
                return $item
            }}

            expect $yielded to equal {1 2 3 false}
        }
    }
}

describe "_::each" {
    proc each_with_non_local_return {} {
        _::each { 1 2 3 } {{x} {
            if { $x == 2 } {
                return -code return "non-local return"
            } else {
                expr { $x * $x }
            }
        }}
    }

    it "allows non-local returns" {
        expect [each_with_non_local_return] to equal "non-local return"
    }
}

describe "_::any?" {
    it "always returns false on an empty list" {
        expect [_::any? {}] to be false
        expect [_::any? {} {{e} { return true }}] to be false
    }

    describe "with no block" {
        it "returns true if at least one element is not falsy" {
            expect [_::any? {1 2 -1}] to be true
            expect [_::any? {a b c}] to be true
            expect [_::any? {false 0 true}] to be true
        }

        it "returns false if all elements are falsy" {
            expect [_::any? {false}] to be false
            # This might seem weird, but "f" is a falsy value in Tcl
            expect [_::any? {f}] to be false
            expect [_::any? {false 0 fal fa f}] to be false
        }
    }

    describe "with a block" {
        it "returns true if at least one element is not falsy" {
            expect [_::any? {false} {{item} { return true }}] to be true
            expect [_::any? {false} {{item} { return 1 }}] to be true

            expect [_::any? {1 2 -1} {{item} { return "test" }}] to be true
            expect [_::any? {1 2 -1} {{item} { expr { $item < 1 } }}] to be true
            expect [_::any? {1 2 -1} {{item} { expr { 5 } }}] to be true
        }

        it "returns false if the block never returns a non-falsy value" {
            expect [_::any? {true test 1234} {{item} { return false }}] to be false
            expect [_::any? {1 2 -1} {{item} { return 0 }}] to be false
            expect [_::any? {1 2 -1} {{item} { expr { $item < -10 } }}] to be false
        }

        it "returns as early as possible" {
            set yielded [list]

            _::any? { 1 2 3 false 5 6 7 } {{item} {
                upvar yielded yielded
                lappend yielded $item
                return $item
            }}

            expect $yielded to equal {1}
        }
    }
}

describe "_::first" {
    describe "when passed no number" {
        it "returns the first element from the passed list" {
            expect [_::first {1 2 3 4}] to equal 1
        }
    }

    describe "when passed a number" {
        it "returns the first n elements from the passed list" {
            expect [_::first {1 2 3 4} 0] to equal {}
            expect [_::first {1 2 3 4} 3] to equal {1 2 3}
            expect [_::first {1 2 3 4} 5] to equal {1 2 3 4}
        }
    }

    it "can be passed to _::map" {
        expect [_::map {{1 2 3} {1 2 3}} _::first] to equal {1 1}
    }
}

describe "_::initial" {
    describe "when passed no number" {
        it "returns everything but the last element from the passed list" {
            expect [_::initial {1 2 3 4}] to equal {1 2 3}
        }
    }

    describe "when passed a number" {
        it "returns everything but the last n elements from the passed list" {
            expect [_::initial {1 2 3 4} 0] to equal {1 2 3 4}
            expect [_::initial {1 2 3 4} 2] to equal {1 2}
            expect [_::initial {1 2 3 4} 5] to equal {}
        }
    }

    it "can be passed to _::map" {
        expect [_::map {{1 2 3} {1 2 3}} _::initial] to equal {{1 2} {1 2}}
    }
}

describe "_::times" {
    it "executes the passed block n times" {
        set result [list]
        _::times 0 {{n} {
            upvar result result
            lappend result $n
        }}
        expect $result to equal [list]

        set result [list]
        _::times 3 {{n} {
            upvar result result
            lappend result $n
        }}
        expect $result to equal [list 0 1 2]
    }
}