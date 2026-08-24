package test

import "core:fmt"

S :: struct {
	field1, field2: int,
}

main :: proc() {
	a, m: int
	s: S = {
		field1 = 69  + 1 * m,
		field2 = 420 * a,
	}
	fmt.println("Hello World")

	testing, another: int

	when (false || true) && false {
		testing = another
	}
}
