package editor

import runtime "base:runtime"

import ini     "core:encoding/ini"
import fmt     "core:fmt"
import strconv "core:strconv"
import strings "core:strings"
import vmem    "core:mem/virtual"

Style_Key :: enum {
	Invalid = 0,
	Background,
	Whitespace,
	Ident,
	Keyword,
	Type,
	Comment,
	String,
	Number,
	Directive,
	Operator,
	Constant,
	Function,
	Cursor,

	Indicator_Normal,
	Indicator_Visual,
	Indicator_Insert,
}

Style :: struct {
	fg, bg: [4]f32,
}

Theme :: [Style_Key]Style

Config :: struct {
	arena:                  vmem.Arena,
	animations:             bool,
	relative_line_numbers:  bool,
	scroll_animation_speed: f32,
	cursor_animation_speed: f32,
	popup_animation_speed:  f32,
	theme:                  Theme,
	keybinds:               [Mode]Keybinds,
	styles:                 map[string]Style_Key,
	languages:              []Language,
}

Language :: struct {
	name:       string,
	extensions: []string,
	keywords:   []string,
	constants:  []string,
	types:      []string,
}

load_config_file :: proc(config: ^Config, src: string, allocator: runtime.Allocator) -> (ok: bool) {
	it := ini.iterator_from_string(src, {})

	colors  := make(map[string][4]f32,       context.temp_allocator)
	leaders := make(map[string]Leader_Binds, context.temp_allocator)

	@(require_results)
	parse_color :: proc(str: string) -> (color: [4]f32, ok: bool) {
		str := strings.trim_prefix(str, "#")
		u: u32
		switch len(str) {
		case 6:
			u = (u32(strconv.parse_uint(str, 16) or_return) << 8) | 0xFF
		case 8:
			u = u32(strconv.parse_uint(str, 16) or_return)
		case:
			return
		}

		return color_from_hex_rgba(u), true
	}

	for key, value in ini.iterate(&it) {
		@(require_results)
		unquote :: proc(val: string) -> (string, bool) {
			if len(val) > 0 && (val[0] == '"' || val[0] == '\'') {
				v, _, ok := strconv.unquote_string(val, context.temp_allocator)
				if !ok {
					return val, false
				}
				return v, true
			}
			return val, true
		}

		value := unquote(value) or_continue
		key   := unquote(key)   or_continue

		section, _, subsection := strings.partition(it.section, ".")

		switch section {
		case "theme":
			base, _, selector := strings.partition(key, ".")
			style: Style_Key
			ti := runtime.type_info_base(type_info_of(Style_Key))
			if e, ok := ti.variant.(runtime.Type_Info_Enum); ok {
				for name, i in e.names {
					if strings.equal_fold(base, name) {
						style = Style_Key(e.values[i])
						break
					}
				}
			} else {
				unreachable()
			}

			color: [4]f32
			if strings.has_prefix(value, "#") {
				color = parse_color(value) or_continue
			} else {
				color = colors[value]
			}

			switch selector {
			case "fg", "":
				config.theme[style].fg = color
			case "bg":
				config.theme[style].bg = color
			}
		case "editor":
			// fmt.printfln("%v: %v = %v", section, key, value)
		case "language":
			// fmt.printfln("%v: %v = %v", section, key, value)
		case "keybinds":
			mode: Mode
			switch subsection {
			case "normal":
				mode = .Normal
			case "insert":
				mode = .Insert
			case "visual":
				mode = .Visual
			case "prompt":
				mode = .Prompt
			case "picker":
				mode = .Picker
			}
			bind   := parse_keybind(key) or_continue
			action := parse_action(value, leaders) or_continue

			config.keybinds[mode][bind] = action
		case "colors":
			colors[key] = parse_color(value) or_continue
		case "leader":
			if subsection not_in leaders {
				leaders[subsection] = {
					title = subsection,
					binds = make(Keybinds, allocator),
				}
			}
			bind   := parse_keybind(key) or_continue
			action := parse_action(value, leaders) or_continue
			leader := &leaders[subsection]
			leader.binds[bind] = action
		}
	}

	return true
}

@(require_results)
parse_action :: proc(s: string, leaders: map[string]Leader_Binds) -> (action: Action, ok: bool) {
	if leader := strings.trim_prefix(s, "leader."); leader != s {
		return leaders[leader]
	}
	if cmd := strings.trim_prefix(s, ":"); cmd != s {
		return Command(cmd), true
	}
	return parse_motion(s)
}

@(require_results)
load_config :: proc(config: ^Config) -> (ok: bool) {
	err := vmem.arena_init_growing(&config.arena)
	assert(err == nil)

	allocator := vmem.arena_allocator(&config.arena)

	for &binds in config.keybinds {
		binds = make(Keybinds, allocator)
	}

	config.keybinds[.Insert][{ key = .Escape, }] = .Normal
	config.keybinds[.Visual][{ key = .Escape, }] = .Normal
	config.keybinds[.Prompt][{ key = .Escape, }] = .Normal
	config.keybinds[.Picker][{ key = .Escape, }] = .Normal

	keywords := []string{ "import", "foreign", "package", "when", "where", "if", "else", "for", "switch", "in", "not_in", "do", "case", "break", "continue", "fallthrough", "defer", "return", "proc", "struct", "union", "enum", "bit_set", "bit_field", "map", "dynamic", "auto_cast", "cast", "transmute", "distinct", "using", "context", "or_else", "or_return", "or_break", "or_continue", "asm", "matrix", }
	types := []string{ "bool", "b8", "b16", "b32", "b64", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "i128", "u128", "rune", "f16", "f32", "f64", "complex32", "complex64", "complex128", "quaternion64", "quaternion128", "quaternion256", "int", "uint", "uintptr", "rawptr", "string", "cstring", "string16", "cstring16", "any", "typeid", "i16le", "u16le", "i32le", "u32le", "i64le", "u64le", "i128le", "u128le", "i16be", "u16be", "i32be", "u32be", "i64be", "u64be", "i128be", "u128be", "f16le", "f32le", "f64le", "f16be", "f32be", "f64be", }
	constants := []string{ "true", "false", "nil", }

	config.styles = make(map[string]Style_Key, allocator)

	for k in keywords {
		config.styles[k] = .Keyword
	}
	for t in types {
		config.styles[t] = .Type
	}
	for c in constants {
		config.styles[c] = .Constant
	}

	config.animations             = true
	config.relative_line_numbers  = true
	config.scroll_animation_speed = 7.5
	config.cursor_animation_speed = 15
	config.popup_animation_speed  = 7.5

	load_config_file(config, #load("config.ini"), allocator)

	return true
}

config_destroy :: proc(config: ^Config) {
	vmem.arena_destroy(&config.arena)
}
