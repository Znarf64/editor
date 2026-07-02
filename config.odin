package editor

import "base:runtime"

import "core:encoding/ini"
import "core:fmt"
import "core:strconv"
import "core:strings"

Theme :: [Style]struct { fg, bg: [4]f32, }

Config :: struct {
	animations:            bool,
	relative_line_numbers: bool,
	theme:                 Theme,
	keybinds:              [Mode]Keybinds,
	styles:                map[string]Style,
	languages:             []Language,
}

Language :: struct {
	name:       string,
	extensions: []string,
	keywords:   []string,
	constants:  []string,
	types:      []string,
}

load_config_file :: proc(config: ^Config, src: string) -> (ok: bool) {
	it := ini.iterator_from_string(src, {})

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

		switch it.section {
		case "theme":
			base, _, selector := strings.partition(key, ".")
			style: Style
			ti := runtime.type_info_base(type_info_of(Style))
			if e, ok := ti.variant.(runtime.Type_Info_Enum); ok {
				for name, i in e.names {
					if strings.equal_fold(base, name) {
						style = Style(e.values[i])
						break
					}
				}
			}

			value := strings.trim_prefix(value, "#")
			u: u32
			switch len(value) {
			case 6:
				u = (u32(strconv.parse_uint(value, 16) or_continue) << 8) | 0xFF
			case 8:
				u = u32(strconv.parse_uint(value, 16) or_continue)
			}

			color := color_from_hex_rgba(u)

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
			// fmt.printfln("%v: %v = %v", section, key, value)
		}
	}

	return true
}

load_config :: proc(config: ^Config) -> (ok: bool) {
	keywords := []string{ "import", "foreign", "package", "when", "where", "if", "else", "for", "switch", "in", "not_in", "do", "case", "break", "continue", "fallthrough", "defer", "return", "proc", "struct", "union", "enum", "bit_set", "bit_field", "map", "dynamic", "auto_cast", "cast", "transmute", "distinct", "using", "context", "or_else", "or_return", "or_break", "or_continue", "asm", "matrix", }
	types := []string{ "bool", "b8", "b16", "b32", "b64", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "i128", "u128", "rune", "f16", "f32", "f64", "complex32", "complex64", "complex128", "quaternion64", "quaternion128", "quaternion256", "int", "uint", "uintptr", "rawptr", "string", "cstring", "string16", "cstring16", "any", "typeid", "i16le", "u16le", "i32le", "u32le", "i64le", "u64le", "i128le", "u128le", "i16be", "u16be", "i32be", "u32be", "i64be", "u64be", "i128be", "u128be", "f16le", "f32le", "f64le", "f16be", "f32be", "f64be", }
	constants := []string{ "true", "false", "nil", }

	for k in keywords {
		config.styles[k] = .Keyword
	}
	for t in types {
		config.styles[t] = .Type
	}
	for c in constants {
		config.styles[c] = .Constant
	}

	config.animations            = true
	config.relative_line_numbers = true

	load_config_file(config, #load("config.ini"))

	return true
}
