package editor

import ease    "core:math/ease"
import fmt     "core:fmt"
import la      "core:math/linalg"
import strings "core:strings"
import time    "core:time"
import unicode "core:unicode"

import glfw "vendor:glfw"

import glodin "vendor/glodin"
import input  "vendor/input"

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

FONT_HEIGHT :: 10

main :: proc() {
	glfw_ok := glfw.Init()
	assert(bool(glfw_ok), "Failed to initialize glfw")
	defer glfw.Terminate()

	window := glfw.CreateWindow(900, 600, "Hello Editor", nil, nil)
	defer glfw.DestroyWindow(window)

	glodin.init_glfw(window)
	defer glodin.uninit()

	input.init(window)

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

	// uniforms.atlas_size = ATLAS_SIZE

	font: Font
	font_ok := font_init(&font, #load("font.ttf"), FONT_HEIGHT)
	assert(font_ok)
	defer font_destroy(font)

	fmt.println(get_baked_glyph(&font, '0'))
	fmt.println(get_baked_glyph(&font, '1'))

	file_picker: struct {
		left, right: Animation(Rect),
		color:       Animation([4]f32),
		active:      bool,
	}

	command_palette: struct {
		rect:   Animation(Rect),
		active: bool,
	}

	prompt: struct {
		command: strings.Builder,
		active:  bool,
	}

	start_time := time.now()
	prev_time: f64

	glodin.enable(.Blend)

	// S :: #load("/home/znarf/source/odin/src/check_expr.cpp", string)
	S :: #load(#file, string)
	rope := rope_from_string(S, context.allocator) or_else panic("")

	scroll: Animation(f32)

	color_from_hex_rgba :: proc(hex: u32) -> (rgba: [4]f32) {
		for i in 0 ..< u32(4) {
			rgba[i] = f32((hex >> ((3 - i) * 8)) & 0xFF) / 255.999
		}
		return
	}

	// // theme: [Style]struct {
	// // 	fg, bg: [4]f32,
	// // } = {
	// // 	.Invalid    = { fg = {}, },
	// // 	.Whitespace = { fg = {}, },
	// // 	.Ident      = { fg = { 0.9, 0.9, 0.9, 1, }, },
	// // 	.Keyword    = { fg = { 0.3, 0.6, 0.9, 1, }, },
	// // 	.Comment    = { fg = { 0.5, 0.5, 0.5, 1, }, bg = { 0.2, 0.2, 0.2, 1, }, },
	// // 	.String     = { fg = { 0.4, 0.9, 0.5, 1, }, },
	// // 	.Number     = { fg = { 0.9, 0.3, 0.3, 1, }, },
	// // 	.Constant   = { fg = { 0.9, 0.3, 0.3, 1, }, },
	// // 	.Operator   = { fg = { 0.9, 0.3, 0.3, 1, }, },
	// // 	.Type       = { fg = { 0.9, 0.7, 0.5, 1, }, },
	// // }

	theme: [Style]struct {
		fg, bg: [4]f32,
	} = {
		.Invalid    = { fg = {}, },
		.Whitespace = { fg = {}, },
		.Ident      = { fg = color_from_hex_rgba(0xABB2BFFF), },
		.Cursor     = { fg = color_from_hex_rgba(0x1E2128FF), bg = color_from_hex_rgba(0xABB2BFFF), },
		.Keyword    = { fg = color_from_hex_rgba(0x62AEEFFF), },
		.Function   = { fg = color_from_hex_rgba(0x62AEEFFF), },
		.Comment    = { fg = color_from_hex_rgba(0xABB2BFFF), bg = color_from_hex_rgba(0x32363DFF), },
		.String     = { fg = color_from_hex_rgba(0x98C379FF), },
		.Number     = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Directive  = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Constant   = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Operator   = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Type       = { fg = color_from_hex_rgba(0xE5C07AFF), },
		.Background = { bg = color_from_hex_rgba(0x1E2128FF), },
	}

	styles: map[string]Style

	keywords := []string{ "import", "foreign", "package", "when", "where", "if", "else", "for", "switch", "in", "not_in", "do", "case", "break", "continue", "fallthrough", "defer", "return", "proc", "struct", "union", "enum", "bit_set", "bit_field", "map", "dynamic", "auto_cast", "cast", "transmute", "distinct", "using", "context", "or_else", "or_return", "or_break", "or_continue", "asm", "matrix", }
	types := []string{ "bool", "b8", "b16", "b32", "b64", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "i128", "u128", "rune", "f16", "f32", "f64", "complex32", "complex64", "complex128", "quaternion64", "quaternion128", "quaternion256", "int", "uint", "uintptr", "rawptr", "string", "cstring", "string16", "cstring16", "any", "typeid", "i16le", "u16le", "i32le", "u32le", "i64le", "u64le", "i128le", "u128le", "i16be", "u16be", "i32be", "u32be", "i64be", "u64be", "i128be", "u128be", "f16le", "f32le", "f64le", "f16be", "f32be", "f64be", }
	constants := []string{ "true", "false", "nil", }

	for k in keywords {
		styles[k] = .Keyword
	}
	for t in types {
		styles[t] = .Type
	}
	for c in constants {
		styles[c] = .Constant
	}

	cursor: struct {
		line, column: int,
		// rect: Animation(Rect),
	}

	Mode :: enum {
		Normal,
		Insert,
		Visual,
		Prompt,
	}
	mode: Mode

	last_print_time    := time.now()
	frames_since_print := 0

	text_buffer: [dynamic]Instance

	for !glfw.WindowShouldClose(window) {
		frames_since_print += 1
		if time.since(last_print_time) > time.Second {
			glfw.SetWindowTitle(window, fmt.ctprintf("%v", frames_since_print))
			frames_since_print = 0
			last_print_time    = time.now()
		}

		x, y        := glfw.GetFramebufferSize(window)
		screen_size := [2]f32{ f32(x), f32(y), }

		current_time := time.duration_seconds(time.since(start_time))
		delta_time   := current_time - prev_time
		prev_time     = current_time

		clear(&instance_buffer)

		switch mode {
		case .Insert:
		case .Visual:
		case .Normal:
			if y := input.get_scroll().y; y != 0 {
				animation_begin(&scroll, min(0, scroll.target + y * FONT_HEIGHT * 5))
			}

			if input.get_key(.Left_Control) || input.get_key(.Right_Control) {
				if input.get_key_down(.D, true) {
					animation_begin(&scroll, min(0, scroll.target - screen_size.y / 2))
				}
				if input.get_key_down(.U, true) {
					animation_begin(&scroll, min(0, scroll.target + screen_size.y / 2))
				}

				if input.get_key_down(.F) {
					command_palette.active ~= true

					rect := rect_from_min_max(200, screen_size - 200)

					if !command_palette.active {
						rect = rect_center(rect).xyxy
					}

					animation_begin(&command_palette.rect, rect)
				}
			}

			if input.get_key_down(.J, true) || input.get_key_down(.Down, true) {
				cursor.line        += 1
				// cursor.rect.t       = 0
				// cursor.rect.origin  = cursor.rect.current
 				// animation_begin(&scroll, min(0, scroll.target - FONT_SIZE * 5))
			}
			if input.get_key_down(.K, true) || input.get_key_down(.Up, true) {
				cursor.line        -= 1
				// cursor.rect.t       = 0
				// cursor.rect.origin  = cursor.rect.current
 				// animation_begin(&scroll, min(0, scroll.target + FONT_SIZE * 5))
			}

			if input.get_key_down(.H, true) || input.get_key_down(.Left, true) {
				cursor.column      -= 1
				// cursor.rect.t       = 0
				// cursor.rect.origin  = cursor.rect.current
 			}
			if input.get_key_down(.L, true) || input.get_key_down(.Right, true) {
				cursor.column      += 1
				// cursor.rect.t       = 0
				// cursor.rect.origin  = cursor.rect.current
 			}

			if input.get_key_down(.G) {
				if input.get_key_down(.Left_Shift) || input.get_key_down(.Right_Shift) {
				} else {
					animation_begin(&scroll, 0)
				}
			}

			if input.get_key_down(.Space) {
				file_picker.active ~= true

				left_rect  := rect_from_min_max(40, { screen_size.x / 2 - 10, screen_size.y - 40, })
				right_rect := rect_from_min_max({ screen_size.x / 2 + 10, 40, }, screen_size - 40)

				if !file_picker.active {
					left_rect  = rect_center(left_rect).xyxy
					right_rect = rect_center(right_rect).xyxy
				}

				animation_begin(&file_picker.left,  left_rect)
				animation_begin(&file_picker.right, right_rect)
			}

			if input.get_key_down(.F1) {
				command_palette.active ~= true

				rect := rect_from_min_max(200, screen_size - 200)

				if !command_palette.active {
					rect = rect_center(rect).xyxy
				}

				animation_begin(&command_palette.rect, rect)
			}

			if input.get_key_down(.Slash) {
				mode = .Prompt
			}
		case .Prompt:
			if input.get_key_down(.Backspace, true) {
				delete: if input.get_key(.Left_Control) || input.get_key(.Right_Control) {
					r, w := strings.pop_rune(&prompt.command)
					if w == 0 {
						break delete
					}

					if !unicode.is_alpha(r) && !unicode.is_number(r) do for {
						r, w := strings.pop_rune(&prompt.command)
						if w == 0 {
							break
						}
						if unicode.is_alpha(r) || unicode.is_number(r) {
							break
						}
					}

					for {
						r, w := strings.pop_rune(&prompt.command)
						if w == 0 {
							break
						}
						if !unicode.is_alpha(r) && !unicode.is_number(r) {
							strings.write_rune(&prompt.command, r)
							break
						}
					}
				} else {
					strings.pop_rune(&prompt.command)
				}
			}

			strings.write_string(&prompt.command, strings.to_string(input.text_input))

			if input.get_key_down(.Escape) || input.get_key_down(.Enter) {
				strings.builder_reset(&prompt.command)
				mode = .Normal
			}
		}

		scroll := animation_update(&scroll, f32(delta_time), 5)

		{
			text := rope_to_string(rope, context.temp_allocator)

			highlighter: Highlighter = {
				text     = text,
				keywords = styles,
			}

			line, column: int
			cell_size: [2]f32 = { get_baked_glyph(&font, 0).x_advance, (FONT_HEIGHT - f32(font.descender) * font.scale) * 1.2, }

			// cursor_rect := animation_update(&cursor.rect, f32(delta_time), 10)
			// append(&instance_buffer, Instance {
			// 	offset        = cursor_rect.xy,
			// 	size          = cursor_rect.zw - cursor_rect.xy,
			// 	color         = theme[.Cursor].bg,
			// 	border_radius = 2,
			// })

			render: for {
				start := highlighter.pos
				style := highlighter_advance(&highlighter)
				if style == .Invalid {
					break
				}

				start_column := column

				for char in text[start:highlighter.pos] {
					style := style
					if line == cursor.line && column == cursor.column {
						// min := [2]f32 { f32(column) * cell_size.x + 10, cell_size.y * f32(line) + FONT_HEIGHT + scroll - 15, }
						// cursor.rect.target = { **min, **(min + { cell_size.x, FONT_HEIGHT, }), }

						append(&instance_buffer, Instance {
							offset        = { f32(column) * cell_size.x + 10, cell_size.y * f32(line) + scroll, },
							size          = { cell_size.x, FONT_HEIGHT - f32(font.descender) * font.scale, },
							color         = theme[.Cursor].bg,
							border_radius = 2,
						})

						style = .Cursor
					}

					switch char {
					case '\t':
						// advance by one, round up to next multiple of four
						column = (column + 1 + 3) & -4
						continue
					case '\n':
						if theme[style].bg != 0 {
							append(&instance_buffer, Instance {
								offset        = { f32(start_column) * cell_size.x + 10, cell_size.y * f32(line) + FONT_HEIGHT + scroll - 15, },
								size          = { f32(column - start_column) * cell_size.x, FONT_HEIGHT, },
								color         = theme[style].bg,
								border_radius = 2,
							})
							start_column = 0
						}

						column = 0
						line  += 1
						continue
					case ' ':
						column += 1
						continue
					}

					x := f32(column) * cell_size.x + 10
					y := cell_size.y * f32(line) + FONT_HEIGHT + scroll
					if y < 0 {
						continue
					}
					if y > screen_size.y {
						break render
					}

					g := get_baked_glyph(&font, char)

					append(&text_buffer, Instance {
						offset  = { x, y, } + g.offset,
						size    = ([2]f32)(g.max - g.min),
						texture = { **([2]f32)(g.min), 1, },
						color   = theme[style].fg,
					})

					column += 1

					if x + cell_size.x * 2 > screen_size.x {
						column = 1
						line  += 1
					}
				}

				if theme[style].bg != 0 {
					append(&instance_buffer, Instance {
						offset        = { f32(start_column) * cell_size.x + 10, cell_size.y * f32(line) + scroll - 2, },
						size          = { f32(column - start_column) * cell_size.x, cell_size.y + 0.5, },
						color         = theme[style].bg,
						border_radius = 2,
					})
					// append(&instance_buffer, Instance {
					// 	offset        = { f32(start_column) * cell_size.x + 10, cell_size.y * f32(line) + FONT_HEIGHT + scroll - 15, },
					// 	size          = { f32(column - start_column) * cell_size.x, FONT_HEIGHT + 0.5 /* inflate this enough that connecting lines will reliably connect without gaps */, },
					// 	color         = theme[style].bg,
					// 	border_radius = 2,
					// })
				}
			}

			append(&instance_buffer, ..text_buffer[:])
			clear(&text_buffer)
		}

		append(&instance_buffer, Instance {
			offset       = { 0, screen_size.y - FONT_HEIGHT, },
			size         = { screen_size.x, FONT_HEIGHT, },
			color        = color_from_hex_rgba(0x1E2128FF),
			border_color = color_from_hex_rgba(0x32363DFF),
			border_width = 2,
		})

		w := measure_text(&font, strings.to_string(prompt.command))
		draw_text(&font, &instance_buffer, strings.to_string(prompt.command), theme[.Ident].fg, { 0, screen_size.y, })

		append(&instance_buffer, Instance {
			offset = { w, screen_size.y - FONT_HEIGHT, },
			size   = { 2, FONT_HEIGHT, },
			color  = theme[.Ident].fg,
		})

		left  := animation_update(&file_picker.left,  f32(delta_time), 4)
		right := animation_update(&file_picker.right, f32(delta_time), 4)

		append(&instance_buffer, Instance {
			offset        = left.xy,
			size          = rect_size(left),
			color         = color_from_hex_rgba(0x1E2128FF),
			border_color  = color_from_hex_rgba(0x32363DFF),
			border_radius = 8,
			border_width  = 2,
			shadow_width  = 16,
		})
		append(&instance_buffer, Instance {
			offset        = right.xy,
			size          = rect_size(right),
			color         = color_from_hex_rgba(0x1E2128FF),
			border_color  = color_from_hex_rgba(0x32363DFF),
			border_radius = 8,
			border_width  = 2,
			shadow_width  = 16,
		})

		render_rect := animation_update(&command_palette.rect, f32(delta_time), 4)

		append(&instance_buffer, Instance {
			offset        = render_rect.xy,
			size          = rect_size(render_rect),
			color         = color_from_hex_rgba(0x1E2128FF),
			border_color  = color_from_hex_rgba(0x32363DFF),
			border_radius = 8,
			border_width  = 2,
			shadow_width  = 16,
		})

		instance_mesh := glodin.create_instanced_mesh(quad, instance_buffer[:])
		defer glodin.destroy(instance_mesh)

		uniforms.screen_size = screen_size
		uniforms.atlas_size  = 1024

		glodin.clear_color({}, theme[.Background].bg)
		glodin.set_uniform(program, "font_texture", font.atlas)

		glodin.draw({}, program, instance_mesh)

		glfw.SwapBuffers(window)
		input.poll()
		glfw.PollEvents()
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
