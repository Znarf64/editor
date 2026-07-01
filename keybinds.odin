package editor

import "vendor:glfw"

Key :: enum {
	A = glfw.KEY_A,
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

Keybinds :: map[Keybind]union{
	map[Keybind]Command,
	Command,
}
