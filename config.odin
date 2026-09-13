package editor

import runtime "base:runtime"

import ini     "core:encoding/ini"
import log     "core:log"
import reflect "core:reflect"
import strconv "core:strconv"
import strings "core:strings"
import vmem    "core:mem/virtual"

Style_Key :: enum {
	Invalid = 0,
	Background,
	Popup_Background,
	Popup_Border,
	Statusline,
	Gutter,

	Error,
	Warning,
	Information,
	Hint,

	Ui_Focus,
	Ui_Highlight,
	Ui_Text,

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
	Cursor_Secondary,
	Selection,

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

	enable_animations:      bool,
	blur_strength:          int,
	relative_line_numbers:  bool,
	scroll_animation_speed: f32,
	cursor_animation_speed: f32,
	popup_animation_speed:  f32,
	tab_width:              int,
	scroll_scale:           f32,
	padding:                f32,

	theme:                  Theme,
	keybinds:               [Mode]Keybinds,
	languages:              map[string]Language_Config,
	colors:                 map[string][4]f32,
	leaders:                map[string]Leader_Binds,
}

Language_Config :: struct {
	extensions:      [dynamic]string,
	keywords:        [dynamic]string,
	constants:       [dynamic]string,
	types:           [dynamic]string,
	language_server: string,
}

@(require_results)
color_from_hex_rgba :: proc(hex: u32) -> (rgba: [4]f32) {
	for i in 0 ..< u32(4) {
		rgba[i] = f32((hex >> ((3 - i) * 8)) & 0xFF) / 255.999
	}
	return
}

@(require_results)
config_value_set :: proc(
	config: ^Config,
	section: string,
	key:     string,
	value:   string,
) -> bool {
	section, _, subsection := strings.partition(section, ".")

	allocator := vmem.arena_allocator(&config.arena)

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
			color = parse_color(value) or_return
		} else {
			color = config.colors[value]
		}

		switch selector {
		case "fg", "":
			config.theme[style].fg = color
		case "bg":
			config.theme[style].bg = color
		}
	case "editor":
		unmarshal_value :: proc(v: any, value: string) -> bool {
			switch &v in v {
			case f32:
				v = strconv.parse_f32(value) or_return
			case int:
				v = strconv.parse_int(value) or_return
			case bool:
				if strings.equal_fold(value, "true") {
					v = true
					return true
				}
				if strings.equal_fold(value, "false") {
					v = false
					return true
				}
				return false
			}
			return false
		}
		field := reflect.struct_field_value_by_name(config^, key)
		if field == nil {
			break
		}
		unmarshal_value(field, value) or_break
	case "language":
		_, language, new, _ := map_entry(&config.languages, subsection)
		if new {
			language.extensions = make([dynamic]string, allocator)
			language.keywords   = make([dynamic]string, allocator)
			language.constants  = make([dynamic]string, allocator)
			language.types      = make([dynamic]string, allocator)
		}

		switch key {
		case "constant":
			append(&language.constants, value)
		case "keyword":
			append(&language.keywords, value)
		case "type":
			append(&language.types, value)
		case "extension":
			append(&language.extensions, value)
		case "language_server":
			language.language_server = value
		case:
			return false
		}
	case "keybinds":
		mode: Mode
		switch subsection {
		case "normal":
			mode = .Normal
		case "insert":
			mode = .Insert
		case "visual":
			mode = .Visual
		case:
			return false
		}
		bind   := parse_keybind(key) or_return
		action := parse_action(value, config.leaders, allocator) or_return

		config.keybinds[mode][bind] = action
	case "colors":
		config.colors[key] = parse_color(value) or_return
	case "leader":
		if subsection not_in config.leaders {
			config.leaders[subsection] = {
				title = subsection,
				binds = make(Keybinds, allocator),
			}
		}
		bind   := parse_keybind(key) or_return
		action := parse_action(value, config.leaders, allocator) or_return
		leader := &config.leaders[subsection]
		leader.binds[bind] = action
	case:
		return false
	}

	return true
}

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

@(require_results)
config_value_get :: proc(config: ^Config, section, key: string, allocator: runtime.Allocator) -> string {
	unimplemented()
}

load_config_file :: proc(config: ^Config, src: string, allocator: runtime.Allocator) -> (ok: bool) {
	it := ini.iterator_from_string(src, {})

	config.colors    = make(map[string][4]f32,          allocator)
	config.leaders   = make(map[string]Leader_Binds,    allocator)
	config.languages = make(map[string]Language_Config, allocator)

	for key, value in ini.iterate(&it) {
		@(require_results)
		unquote :: proc(val: string, allocator: runtime.Allocator) -> (string, bool) {
			if len(val) > 0 && (val[0] == '"' || val[0] == '\'') {
				v, _, ok := strconv.unquote_string(val, allocator)
				if !ok {
					return val, false
				}
				return v, true
			}
			return val, true
		}

		value := unquote(value, allocator) or_continue
		key   := unquote(key,   allocator) or_continue

		if !config_value_set(config, it.section, key, value) {
			log.errorf("Failed to set config value in section `%s`: `%s = %s`", it.section, key, value)
		}
	}

	return true
}

@(require_results)
parse_action :: proc(s: string, leaders: map[string]Leader_Binds, allocator: runtime.Allocator) -> (action: Action, ok: bool) {
	if commas := strings.count(s, ","); commas != 0 {
		actions := make([]Action, commas + 1, allocator)
		s       := s
		i       := 0
		for s in strings.split_iterator(&s, ",") {
			actions[i] = parse_action(s, leaders, allocator) or_return
			i         += 1
		}

		action = actions
		ok     = true
		return
	}

	if leader := strings.trim_prefix(s, "leader."); leader != s {
		return leaders[leader]
	}
	if cmd := strings.trim_prefix(s, ":"); cmd != s {
		return parse_command(cmd, allocator)
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

	config.keybinds[.Normal][{ key = .Escape, }] = .Normal
	config.keybinds[.Insert][{ key = .Escape, }] = .Normal
	config.keybinds[.Visual][{ key = .Escape, }] = .Normal

	config.tab_width = 4

	return load_config_file(config, #load("config.ini"), allocator)
}

config_destroy :: proc(config: ^Config) {
	vmem.arena_destroy(&config.arena)
}
