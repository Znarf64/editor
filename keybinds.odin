package editor

import runtime "base:runtime"

import strings "core:strings"

Key :: enum {
	Escape,
	Enter,

	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,

	_0,
	_1,
	_2,
	_3,
	_4,
	_5,
	_6,
	_7,
	_8,
	_9,
}

Modifier :: enum {
	Shift,
	Alt,
	Control,
}

Modifiers :: bit_set[Modifier]

Keybind :: struct {
	modifiers: Modifiers,
	key:       Key,
}

Action :: union {
	Keybinds,
	Command,
	Motion,
}

Keybinds :: distinct map[Keybind]Action

modifier_names: [Modifier]string = {
	.Shift   = "S",
	.Alt     = "A",
	.Control = "C",
}

key_names: [Key]string = {
	.Escape = "escape",
	.Enter  = "enter",
	.A      = "A",
	.B      = "B",
	.C      = "C",
	.D      = "D",
	.E      = "E",
	.F      = "F",
	.G      = "G",
	.H      = "H",
	.I      = "I",
	.J      = "J",
	.K      = "K",
	.L      = "L",
	.M      = "M",
	.N      = "N",
	.O      = "O",
	.P      = "P",
	.Q      = "Q",
	.R      = "R",
	.S      = "S",
	.T      = "T",
	.U      = "U",
	.V      = "V",
	.W      = "W",
	.X      = "X",
	.Y      = "Y",
	.Z      = "Z",
	._0     = "0",
	._1     = "1",
	._2     = "2",
	._3     = "3",
	._4     = "4",
	._5     = "5",
	._6     = "6",
	._7     = "7",
	._8     = "8",
	._9     = "9",
}

// may allocate using context.temp_allocator
@(require_results)
keybind_to_string :: proc(bind: Keybind) -> string {
	key := key_names[bind.key]
	if card(bind.modifiers) == 0 {
		return key
	}

	strs: [3 + len(Modifier) * 2]string
	i:    int

	strs[i] = "<"
	i      += 1

	for mod in bind.modifiers {
		strs[i] = modifier_names[mod]
		i      += 1

		strs[i] = "-"
		i      += 1
	}

	strs[i] = key
	i      += 1

	strs[i] = ">"
	i      += 1

	return strings.concatenate(strs[:i], context.temp_allocator)
}

@(require_results)
parse_key :: proc(s: string) -> (key: Key, ok: bool) {
	for name, k in key_names {
		if strings.equal_fold(name, s) {
			key = k
			ok  = true
			return
		}
	}
	return
}

@(require_results)
parse_keybind :: proc(s: ^string) -> (bind: Keybind, ok: bool) {
	if len(s^) == 0 {
		return
	}

	if s[0] == '<' {
		n := strings.index(s^, ">")
		if n == -1 {
			return
		}
		x := s[1:n + 1]

		defer s^ = s[n + 1:]

		iterate_parts: for part in strings.split_iterator(&x, "-") {
			if end := strings.index(part, ">"); end != -1 {
				bind.key = parse_key(part[:end]) or_return
				ok       = true
				return
			} else {
				for name, mod in modifier_names {
					if part == name {
						if mod in bind.modifiers {
							return
						}
						bind.modifiers |= { mod, }
						continue iterate_parts
					}
				}
				return
			}
		}
	} else {
		bind.key, ok = parse_key(s[:1])
		return
	}

	unreachable()
}
