package editor

import ease    "core:math/ease"
import fmt     "core:fmt"
import la      "core:math/linalg"
import os      "core:os"
import strings "core:strings"
import strconv "core:strconv"
import time    "core:time"

import glodin "vendor/glodin"

Instance :: struct {
	offset:        [2]f32,
	size:          [2]f32,
	texture:       [3]f32,
	color:         [4]f32,
	border_radius: f32,
	border_width:  f32,
	border_color:  [4]f32,
	shadow_width:  f32,
}

Cursor :: struct {
	line, column: int,
}

Mode :: enum {
	Normal,
	Insert,
	Visual,
	Prompt,
	Picker,
}

Picker :: enum {
	Files,
	Global_Search,
	Symbols,
	Commands,
}

Editor :: struct {
	cursor:        Cursor,
	mode:          Mode,

	visible_lines: int,
	screen_size:   [2]f32,

	repeat_count:  int,

	scroll_anim:   Animation(f32),
	cursor_anim:   Animation(Rect),

	picker:        struct {
		kind:  Picker,
		input: strings.Builder,
		rect:  Animation(Rect),
	},

	prompt:        struct {
		input: strings.Builder,
	},

	rope:          Rope,

	config:        Config,

	sub_menu:      Maybe(Keybinds), // used for multi key binds, ie. vim "leader" binds

	font:          Font,
}

FONT_HEIGHT :: 12

main :: proc() {
	backend: Backend
	backend_ok := backend_init(&backend)
	if !backend_ok {
		fmt.eprintln("Failed to initialize backend")
		os.exit(1)
	}
	defer backend->destroy()

	glodin.init(proc(rawptr, cstring) {})
	defer glodin.uninit()

	Vertex :: struct {
		position: [2]f32,
	}
	vertex_buffer := [6]Vertex {
		{ position = { 0, 0, }, },
		{ position = { 0, 1, }, },
		{ position = { 1, 1, }, },

		{ position = { 0, 0, }, },
		{ position = { 1, 0, }, },
		{ position = { 1, 1, }, },
	}
	quad := glodin.create_mesh(vertex_buffer[:])
	defer glodin.destroy(quad)

	instance_buffer := make([dynamic]Instance)

	Uniforms :: struct {
		screen_size: [2]f32,
		atlas_size:  [2]f32,
	}
	uniform_buffer := glodin.create_uniform_buffer(Uniforms)
	defer glodin.destroy(uniform_buffer)

	uniforms := glodin.map_uniform_buffer(^Uniforms, uniform_buffer)
	defer glodin.unmap_uniform_buffer(uniform_buffer)

	program := glodin.create_program_hephaistos(#load("shader.hep"), shared_types = { Uniforms, }) or_else panic("Failed to load shader")
	defer glodin.destroy(program)

	glodin.set_uniform(program, "vertex_uniforms",   uniform_buffer)
	glodin.set_uniform(program, "fragment_uniforms", uniform_buffer)

	editor: Editor

	editor.config.keybinds[.Normal][{ key = .H, }] = .Character_Left
	editor.config.keybinds[.Normal][{ key = .J, }] = .Character_Down
	editor.config.keybinds[.Normal][{ key = .K, }] = .Character_Up
	editor.config.keybinds[.Normal][{ key = .L, }] = .Character_Right

	editor.config.keybinds[.Normal][{ key = .W, }] = .Select_Word_Forward
	editor.config.keybinds[.Normal][{ key = .E, }] = .Select_Word_Backward

	editor.config.keybinds[.Normal][{ key = .I,                            }] = .Insert
	editor.config.keybinds[.Normal][{ key = .O,                            }] = .Open_Below
	editor.config.keybinds[.Normal][{ key = .O, modifiers = { .Shift,   }, }] = .Open_Above
	editor.config.keybinds[.Normal][{ key = .O, modifiers = { .Control, }, }] = .Open_File

	leader_g: Keybinds
	leader_g[{ key = .G, }] = .Go_To_File_Start
	leader_g[{ key = .E, }] = .Go_To_File_End
	leader_g[{ key = .H, }] = .Go_To_Line_Start
	leader_g[{ key = .L, }] = .Go_To_Line_End
	leader_g[{ key = .S, }] = .Go_To_Line_Start_Non_Whitespace

	editor.config.keybinds[.Normal][{ key = .G, }] = leader_g

	editor.config.keybinds[.Normal][{ key = .F, }] = .Search

	editor.config.keybinds[.Normal][{ key = .V, }] = .Visual

	editor.config.keybinds[.Insert][{ key = .Escape, }] = .Normal
	editor.config.keybinds[.Visual][{ key = .Escape, }] = .Normal
	editor.config.keybinds[.Prompt][{ key = .Escape, }] = .Normal
	editor.config.keybinds[.Picker][{ key = .Escape, }] = .Normal

	font_ok := font_init(&editor.font, #load("font.ttf"), FONT_HEIGHT)
	assert(font_ok)
	defer font_destroy(editor.font)

	start_time := time.now()
	prev_time: f64

	glodin.enable(.Blend)

	S :: #load("/home/znarf/source/odin/src/check_expr.cpp", string)
	// S :: #load(#file, string)
	editor.rope = rope_from_string(S, context.allocator) or_else panic("")

	config_ok := load_config(&editor.config)
	if !config_ok {
		fmt.eprintln("Failed to load config")
	}

	last_print_time    := time.now()
	frames_since_print := 0

	main_loop: for {
		frames_since_print += 1
		if time.since(last_print_time) > time.Second {
			backend->set_title(fmt.tprintf("%v FPS", frames_since_print))
			frames_since_print = 0
			last_print_time    = time.now()
		}

		prev_cursor := editor.cursor

		for event in backend->poll_events() {
			switch e in event {
			case Event_Window_Close:
				break main_loop
			case Event_Window_Resize:
				editor.screen_size = ([2]f32)(e.size)
				glodin.window_size_callback(e.size.x, e.size.y)

			case Event_Input_Key:
				if e.action == .Up {
					break
				}

				if e.key >= ._0 && e.key <= ._9 && e.modifiers == {} {
					editor.repeat_count *= 10
					editor.repeat_count += int(e.key - ._0)
					break
				}

				binds          := editor.sub_menu.? or_else editor.config.keybinds[editor.mode]
				editor.sub_menu = nil
				keybind        := Keybind {
					modifiers = e.modifiers,
					key       = e.key,
				}
				bind, ok := binds[keybind]
				if !ok {
					editor.repeat_count = 0
					break
				}

				switch v in bind {
				case Motion:
					if editor.repeat_count == 0 {
						editor.repeat_count = 1
					}
					motion_apply(&editor, v)
					editor.repeat_count = 0
				case Command:
					command_execute(&editor, v)
					editor.repeat_count = 0
				case Keybinds:
					editor.sub_menu = v
				}
			case Event_Input_Codepoint:
				if editor.mode == .Prompt {
					strings.write_rune(&editor.prompt.input, e.codepoint)
				}
				if editor.mode == .Picker {
					strings.write_rune(&editor.picker.input, e.codepoint)
				}
			case Event_Input_Mouse_Move:
			case Event_Input_Mouse_Button:
			case Event_Input_Scroll:
				animation_begin(&editor.scroll_anim, max(0, editor.scroll_anim.target - e.delta.y * 5))
			}
		}

		if prev_cursor != editor.cursor {
			editor.cursor_anim.origin = editor.cursor_anim.current
			editor.cursor_anim.t      = 0

			if editor.scroll_anim.target < f32(editor.cursor.line - editor.visible_lines + 5) {
				animation_begin(&editor.scroll_anim, f32(editor.cursor.line - editor.visible_lines + 5))
			}

			if editor.scroll_anim.target > f32(editor.cursor.line - 5) {
				animation_begin(&editor.scroll_anim, max(0, f32(editor.cursor.line - 5)))
			}
		}

		current_time := time.duration_seconds(time.since(start_time))
		delta_time   := current_time - prev_time
		prev_time     = current_time

		clear(&instance_buffer)

		render(&editor, &instance_buffer, f32(delta_time))

		instance_mesh := glodin.create_instanced_mesh(quad, instance_buffer[:])
		defer glodin.destroy(instance_mesh)

		uniforms.screen_size = editor.screen_size
		uniforms.atlas_size  = f32(len(editor.font.skyline))

		glodin.clear_color({}, editor.config.theme[.Background].bg)
		glodin.set_uniform(program, "font_texture", editor.font.atlas)

		glodin.draw({}, program, instance_mesh)

		backend->draw(instance_buffer[:])
		free_all(context.temp_allocator)
	}
}

Rect :: [4]f32

@(require_results)
rect_from_min_max :: proc(min, max: [2]f32) -> Rect {
	return { **min, **max,  }
}

@(require_results)
rect_center :: proc(rect: Rect) -> [2]f32 {
	return (rect.xy + rect.zw) / 2
}

@(require_results)
rect_size :: proc(rect: Rect) -> [2]f32 {
	return rect.zw - rect.xy
}

Animation :: struct(T: typeid) {
	origin:  T,
	target:  T,
	current: T,
	t:       f32,
}

@(require_results)
animation_update :: proc(anim: ^Animation($T), delta_time, speed: f32) -> T {
	anim.t      += speed * f32(delta_time)
	anim.t       = clamp(anim.t, 0, 1)
	anim.current = la.lerp(anim.origin, anim.target, ease.quartic_out(anim.t))
	return anim.current
}

animation_begin :: proc(anim: ^Animation($T), target: T) {
	anim.origin = anim.current
	anim.target = target
	anim.t      = 0
}

render :: proc(editor: ^Editor, instance_buffer: ^[dynamic]Instance, delta_time: f32) {
	text_buffer := make([dynamic]Instance, context.temp_allocator)

	text := rope_to_string(editor.rope, context.temp_allocator)

	highlighter: Highlighter = {
		text     = text,
		keywords = editor.config.styles,
	}

	line, column: int
	cell_size: [2]f32 = {
		la.round(get_baked_glyph(&editor.font, 0).x_advance),
		la.round(((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale)),
	}

	editor.visible_lines = int(editor.screen_size.y / cell_size.y)

	scroll := animation_update(&editor.scroll_anim, delta_time, 7.5)

	padding: f32 = 10
	gutter_width := cell_size.x * 6

	line_number_buf: [32]byte

	render_text: for {
		start := highlighter.pos
		style := highlighter_advance(&highlighter)
		if style == .Invalid {
			break
		}

		start_column := column

		for char in text[start:highlighter.pos] {
			if column == 0 {
				l := line
				if editor.config.relative_line_numbers && editor.cursor.line != line {
					l = abs(editor.cursor.line - line) - 1
				}
				str := strconv.write_int(line_number_buf[:], i64(l + 1), base = 10)
				w   := measure_text(&editor.font, str)
				draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { gutter_width - cell_size.x * 2 - w, cell_size.y * (f32(line) - scroll) + FONT_HEIGHT, } + padding)

				append(instance_buffer, Instance {
					offset = {
						gutter_width - cell_size.x + padding,
						cell_size.y * (f32(line) - scroll) - f32(editor.font.descender) * editor.font.scale,
					},
					size   = cell_size * { 0.25, 1, },
					color  = editor.config.theme[.Ident].fg,
				})
			}

			style := style
			if line == editor.cursor.line && column == editor.cursor.column {
				offset := [2]f32{
					f32(column) * cell_size.x + gutter_width,
					cell_size.y * (f32(line - 1) - scroll) + f32(editor.font.ascender) * editor.font.scale,
				} + padding
				editor.cursor_anim.target.xy = offset
				editor.cursor_anim.target.zw = offset + cell_size
				// append(instance_buffer, Instance {
				// 	offset        = {
				// 		f32(column) * cell_size.x + gutter_width,
				// 		cell_size.y * (f32(line - 1) - scroll) + f32(editor.font.ascender) * editor.font.scale,
				// 	} + padding,
				// 	size          = cell_size,
				// 	color         = editor.config.theme[.Cursor].bg,
				// 	border_radius = 2,
				// })

				style = .Cursor
			}

			switch char {
			case '\t':
				// advance by one, round up to next multiple of four
				column = (column + 1 + 3) & -4
				continue
			case '\n':
				// if editor.config.theme[style].bg != 0 {
				// 	append(instance_buffer, Instance {
				// 		offset        = {
				// 			f32(column) * cell_size.x + gutter_width,
				// 			cell_size.y * (f32(line) - scroll) + f32(editor.font.ascender) * editor.font.scale,
				// 		} + padding,
				// 		size          = cell_size,
				// 		color         = editor.config.theme[style].fg,
				// 	})
				// }

				column = 0
				line  += 1
				continue
			case ' ':
				column += 1
				continue
			}

			x := f32(column) * cell_size.x + padding + gutter_width
			y := cell_size.y * (f32(line) - scroll) + FONT_HEIGHT + padding
			if y < 0 {
				continue
			}
			if y > editor.screen_size.y {
				break render_text
			}

			g := get_baked_glyph(&editor.font, char)

			append(&text_buffer, Instance {
				offset  = { x, y, } + ([2]f32)(g.offset),
				size    = ([2]f32)(g.max - g.min),
				texture = { **([2]f32)(g.min), 1, },
				color   = editor.config.theme[style].fg,
			})

			column += 1

			// if x + cell_size.x * 2 > editor.screen_size.x {
			// 	column = 1
			// 	line  += 1
			// }
		}

		if editor.config.theme[style].bg != 0 {
			append(instance_buffer, Instance {
				offset        = {
					f32(start_column) * cell_size.x + gutter_width,
					cell_size.y * (f32(line - 1) - scroll) + f32(editor.font.ascender) * editor.font.scale,
				} + padding,
				size          = { f32(column - start_column) * cell_size.x, cell_size.y + 0.5, },
				color         = editor.config.theme[style].bg,
				border_radius = 0,
			})
		}
	}

	cursor_rect := animation_update(&editor.cursor_anim, delta_time, 15)
	append(instance_buffer, Instance {
		offset        = cursor_rect.xy,
		size          = cursor_rect.zw - cursor_rect.xy,
		color         = editor.config.theme[.Cursor].bg,
		border_radius = 2,
	})

	append(instance_buffer, ..text_buffer[:])
	clear(&text_buffer)

	append(instance_buffer, Instance {
		offset       = { 0, editor.screen_size.y - FONT_HEIGHT - padding * 2, },
		size         = { editor.screen_size.x, FONT_HEIGHT + padding * 2, },
		color        = color_from_hex_rgba(0x1E2128FF),
		border_color = color_from_hex_rgba(0x32363DFF),
		border_width = 2,
	})

	x := padding

	mode_text: string
	#partial switch editor.mode {
	case .Normal:
		mode_text = "NORMAL"
	case .Visual:
		mode_text = "VISUAL"
	case .Insert:
		mode_text = "INSERT"
	}

	if mode_text != "" {
		w := draw_text(
			&editor.font,
			instance_buffer,
			mode_text,
			editor.config.theme[.Ident].fg,
			{ x, editor.screen_size.y - padding, },
		)
		x += w
	}

	if editor.mode == .Prompt {
		w := draw_text(
			&editor.font,
			instance_buffer,
			strings.to_string(editor.prompt.input),
			editor.config.theme[.Ident].fg,
			{ x, editor.screen_size.y - padding, },
		)

		append(instance_buffer, Instance {
			offset = { x + w, editor.screen_size.y - FONT_HEIGHT - padding, },
			size   = { 2, FONT_HEIGHT, },
			color  = editor.config.theme[.Ident].fg,
		})
	}

	if editor.mode != .Picker && editor.picker.rect.target != 0 {
		rect := rect_from_min_max(40, editor.screen_size.x - 40)
		animation_begin(&editor.picker.rect, rect_center(rect).xyxy)
	}

	picker_rect := animation_update(&editor.picker.rect, delta_time, 4)

	append(instance_buffer, Instance {
		offset        = picker_rect.xy,
		size          = rect_size(picker_rect),
		color         = color_from_hex_rgba(0x1E2128FF),
		border_color  = color_from_hex_rgba(0x32363DFF),
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,
	})

	draw_text(
		&editor.font,
		instance_buffer,
		strings.to_string(editor.picker.input),
		editor.config.theme[.Ident].fg,
		picker_rect.xy + padding + { 0, FONT_HEIGHT, },
	)
}

@(require_results)
color_from_hex_rgba :: proc(hex: u32) -> (rgba: [4]f32) {
	for i in 0 ..< u32(4) {
		rgba[i] = f32((hex >> ((3 - i) * 8)) & 0xFF) / 255.999
	}
	return
}
