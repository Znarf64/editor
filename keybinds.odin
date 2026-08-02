package editor

import runtime "base:runtime"

import fmt     "core:fmt"
import strings "core:strings"
import slice   "core:slice"
import vmem    "core:mem/virtual"

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

// this is a bit dumb, we should just have a proper data structure to store selections
deduplicate_selections :: proc(editor: ^Editor) {
	n := len(editor.selections)
	if n <= 1 {
		return
	}

	Entry :: struct {
		min, max:   Offset,
		orig_index: int,
	}

	entries := make([]Entry, n, context.temp_allocator)
	for s, i in editor.selections {
		entries[i] = { min = min(s.cursor, s.anchor), max = max(s.cursor, s.anchor), orig_index = i, }
	}

	slice.sort_by(entries, proc(a, b: Entry) -> bool {
		return a.min < b.min
	})

	index_map      := make([]int, n, context.temp_allocator)
	new_selections := make([dynamic]Selection, 0, n, context.temp_allocator)

	cur                      := entries[0]
	cur_sel                  := editor.selections[cur.orig_index]
	index_map[cur.orig_index] = 0

	for e in entries[1:] {
		if e.min <= cur.max {
			new_min                := min(cur.min, e.min)
			new_max                := max(cur.max, e.max)
			cur.min, cur.max        = new_min, new_max
			cur_sel.anchor          = new_min
			cur_sel.cursor          = new_max
			cur_sel.target_cursor   = new_max
			index_map[e.orig_index] = len(new_selections) // will point to current slot
		} else {
			append(&new_selections, cur_sel)
			cur                       = e
			cur_sel                   = editor.selections[cur.orig_index]
			index_map[cur.orig_index] = len(new_selections)
		}
	}

	append(&new_selections, cur_sel)

	editor.primary = index_map[editor.primary]

	resize(&editor.selections, len(new_selections))
	copy(editor.selections[:], new_selections[:])
}

action_apply :: proc(editor: ^Editor, action: Action, keybind: Keybind) {
	strings.builder_reset(&editor.status)
	switch v in action {
	case Motion:
		if editor.repeat_count == 0 {
			editor.repeat_count = 1
		}
		for &selection, i in editor.selections {
			motion_apply(editor, &selection, v, i == editor.primary)
		}
	case Command:
		command_execute(editor, v)
		editor.repeat_count = 0
	case Argument_Motion:
		editor.leader.motion = v
		strings.write_string(&editor.leader.sequence, keybind_to_string(keybind, &editor.leader.arena))
	case Leader_Binds:
		editor.leader.title  = v.title
		editor.leader.binds  = v.binds
		editor.leader.active = true
		strings.write_string(&editor.leader.sequence, keybind_to_string(keybind, &editor.leader.arena))
	case []Action:
		for action in v {
			action_apply(editor, action, keybind)
		}
	}
	for selection in editor.new_selections {
		if selection.primary {
			editor.primary = len(editor.selections)
		}
		selection              := selection
		selection.target_cursor = selection.cursor
		append(&editor.selections, selection)
	}
	clear(&editor.new_selections)
	editor.repeat_count = 0
	deduplicate_selections(editor)
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

@(require_results)
keybind_to_string :: proc(bind: Keybind, arena: ^vmem.Arena) -> string {
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

	return strings.concatenate(strs[:i], vmem.arena_allocator(arena))
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

@(require_results)
action_to_string :: proc(action: Action, arena: ^vmem.Arena) -> string {
	switch v in action {
	case []Action:
		strs := make([]string, len(v))
		for &str, i in strs {
			str = action_to_string(v[i], arena)
		}
		return strings.concatenate(strs, vmem.arena_allocator(arena))
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
