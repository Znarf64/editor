package editor

import runtime "base:runtime"

import strings "core:strings"

Key :: enum {
	Escape,
	Enter,
	Space,
	Backspace,
	Delete,
	Tab,
	Left,
	Right,
	Up,
	Down,
	Page_Up,
	Page_Down,

	Apostrophe,
	Comma,
	Minus,
	Period,
	Slash,
	Semicolon,
	Equal,
	Left_Bracket,
	Backslash,
	Right_Bracket,
	Grave_Accent,

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

Leader_Binds :: struct {
	title: string,
	binds: Keybinds,
}

Action :: union {
	[]Action,
	Leader_Binds,
	Command,
	Motion,
	Argument_Motion,
}

action_apply :: proc(editor: ^Editor, action: Action, keybind: Keybind) {
	switch v in action {
	case Motion:
		if editor.repeat_count == 0 {
			editor.repeat_count = 1
		}
		for &selection in editor.selections {
			motion_apply(editor, &selection, v)
		}
		editor.repeat_count = 0
	case Command:
		command_execute(editor, v)
		editor.repeat_count = 0
	case Argument_Motion:
		editor.leader.motion = v
		strings.write_string(&editor.leader.sequence, keybind_to_string(keybind))
	case Leader_Binds:
		editor.leader.title  = v.title
		editor.leader.binds  = v.binds
		editor.leader.active = true
		strings.write_string(&editor.leader.sequence, keybind_to_string(keybind))
	case []Action:
		for action in v {
			action_apply(editor, action, keybind)
		}
	}
}

Keybinds :: distinct map[Keybind]Action

modifier_names: [Modifier]string = {
	.Shift   = "S",
	.Alt     = "A",
	.Control = "C",
}

key_names: [Key]string = {
	.Escape        = "escape",
	.Enter         = "enter",
	.Space         = "space",
	.Backspace     = "backspace",
	.Delete        = "delete",
	.Tab           = "tab",
	.Left          = "left",
	.Right         = "right",
	.Up            = "up",
	.Down          = "down",
	.Page_Up       = "page_up",
	.Page_Down     = "page_down",

	.Apostrophe    = "apostrophe",
	.Comma         = "comma",
	.Minus         = "minus",
	.Period        = "period",
	.Slash         = "slash",
	.Semicolon     = "semicolon",
	.Equal         = "equal",
	.Left_Bracket  = "left_bracket",
	.Backslash     = "backslash",
	.Right_Bracket = "right_bracket",
	.Grave_Accent  = "grave_accent",

	.A = "a",
	.B = "b",
	.C = "c",
	.D = "d",
	.E = "e",
	.F = "f",
	.G = "g",
	.H = "h",
	.I = "i",
	.J = "j",
	.K = "k",
	.L = "l",
	.M = "m",
	.N = "n",
	.O = "o",
	.P = "p",
	.Q = "q",
	.R = "r",
	.S = "s",
	.T = "t",
	.U = "u",
	.V = "v",
	.W = "w",
	.X = "x",
	.Y = "y",
	.Z = "z",

	._0 = "0",
	._1 = "1",
	._2 = "2",
	._3 = "3",
	._4 = "4",
	._5 = "5",
	._6 = "6",
	._7 = "7",
	._8 = "8",
	._9 = "9",
}

// may allocate using context.temp_allocator
@(require_results)
keybind_to_string :: proc(bind: Keybind) -> string {
	key := key_names[bind.key]
	if card(bind.modifiers) == 0 {
		return key
	}

	strs: [1 + len(Modifier) * 2]string
	i:    int

	for mod in bind.modifiers {
		strs[i] = modifier_names[mod]
		i      += 1

		strs[i] = "-"
		i      += 1
	}

	strs[i] = key
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
parse_modifier :: proc(s: string) -> (modifier: Modifier, ok: bool) {
	for name, mod in modifier_names {
		if strings.equal_fold(name, s) {
			modifier = mod
			ok       = true
			return
		}
	}
	return
}

@(require_results)
parse_keybind :: proc(s: string) -> (bind: Keybind, ok: bool) {
	s := s
	for strings.contains(s, "-") {
		mod: string
		mod, _, s = strings.partition(s, "-")

		m := parse_modifier(mod) or_return

		if m in bind.modifiers {
			return
		}

		bind.modifiers |= { m, }
	}

	bind.key, ok = parse_key(s)
	return
}

// may allocate using context.temp_allocator
@(require_results)
action_to_string :: proc(action: Action) -> string {
	switch v in action {
	case []Action:
		strs := make([]string, len(v))
		for &str, i in strs {
			str = action_to_string(v[i])
		}
		return strings.concatenate(strs, context.temp_allocator)
	case Leader_Binds:
		return v.title
	case Command:
		return string(v)
	case Motion:
		return motion_descriptions[v]
	case Argument_Motion:
		return argument_motion_descriptions[v]
	}

	return ""
}
