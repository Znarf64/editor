package editor

import ease    "core:math/ease"
import fmt     "core:fmt"
import la      "core:math/linalg"
import mem     "core:mem"
import os      "core:os"
import regex   "core:text/regex"
import slice   "core:slice"
import strconv "core:strconv"
import strings "core:strings"
import time    "core:time"
import unicode "core:unicode"
import utf8    "core:unicode/utf8"
import vmem    "core:mem/virtual"

Draw_Command_Rect :: struct {
	rect:          Rect,
	color:         [4]f32,
	border_radius: f32,
	border_width:  f32,
	border_color:  [4]f32,
	shadow_width:  f32,
}

Draw_Command_Text :: struct {
	position: [2]f32,
	text:     string,
	color:    [4]f32,
}

Draw_Command :: union {
	Draw_Command_Rect,
	Draw_Command_Text,
}

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

Position :: struct {
	line, column: int,
}

Selection :: struct {
	cursor:        Offset,
	anchor:        Offset,
	anim:          Animation(Rect),
	target_cursor: Offset, // The offset of the position that dicatates the visual target column, so effective the offset that resulted from the last horizontal movement
}

Mode :: enum {
	Normal,
	Insert,
	Visual,
	Prompt,
	Picker,
}

Picker_Mode :: enum {
	Files,
	Global_Search,
	Symbols,
	Commands,
}

Prompt_Mode :: enum {
	Command,
	Search,
	Keep,
	Select,
}

Leader_Entry :: struct {
	bind, action: string,
}

Editor :: struct {
	mode:           Mode,

	primary:        int,
	selections:     [dynamic]Selection,
	new_selections: [dynamic]Selection,

	visible_lines:  int,
	screen_size:    [2]f32,

	repeat_count:   int,

	scroll:         int,
	scroll_anim:    Animation(f32),

	leader:         struct {
		active:      bool,
		sequence:    strings.Builder,
		binds:       Keybinds,
		motion:      Argument_Motion,
		title:       string,
		entries:     []Leader_Entry,
		size:        [2]f32,
		binds_width: f32,
		rect:        Animation(Rect),
		alpha:       Animation(f32),
		arena:       vmem.Arena,
	},

	picker:         struct {
		mode:  Picker_Mode,
		input: strings.Builder,
		rect:  Animation(Rect),
	},

	prompt:         Prompt,

	btree:          BTree,

	config:         Config,

	font:           Font,
}

Prompt :: struct {
	mode:  Prompt_Mode,
	input: strings.Builder,
}

FONT_HEIGHT :: 12

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)

		context.allocator = mem.tracking_allocator(&track)

		defer for _, leak in track.allocation_map {
			fmt.println(leak.location, "leaked", leak.size, "bytes")
		}

		defer for bad_free in track.bad_free_array {
			fmt.eprintln(bad_free.location, "allocation was freed badly")
		}
	}

	backend := backend_init()
	if backend == nil {
		fmt.eprintln("Failed to initialize backend")
		os.exit(1)
	}
	defer backend->destroy()

	editor: Editor
	editor.selections     = make([dynamic]Selection, 1)
	editor.new_selections = make([dynamic]Selection)
	defer {
		delete(editor.selections)
		delete(editor.new_selections)
		strings.builder_destroy(&editor.leader.sequence)
		strings.builder_destroy(&editor.picker.input)
		strings.builder_destroy(&editor.prompt.input)
	}

	err := vmem.arena_init_growing(&editor.leader.arena)
	assert(err == nil)

	font_ok := font_init(&editor.font, #load("font.ttf"), FONT_HEIGHT, context.allocator)
	assert(font_ok)
	defer font_destroy(editor.font)

	start_time := time.now()
	prev_time: f64

	config_ok := load_config(&editor.config)
	if !config_ok {
		fmt.eprintln("Failed to load config")
	}
	defer config_destroy(&editor.config)

	when true {
		// S :: #load("/home/znarf/source/odin/src/check_expr.cpp", string)
		S :: #load(#file, string)
		N :: 200 when ODIN_OPTIMIZATION_MODE == .Speed else 50
		editor.btree = btree_build(strings.repeat(S, N, context.temp_allocator), context.allocator, editor.config.tab_width)
	} else {
		editor.btree = btree_build("Hello World!\n\n", context.allocator, editor.config.tab_width)
	}
	defer btree_destroy(editor.btree)

	last_print_time    := time.now()
	frames_since_print := 0

	instance_buffer := make([dynamic]Instance, context.allocator)
	defer delete(instance_buffer)

	main_loop: for {
		frames_since_print += 1
		if time.since(last_print_time) > time.Second {
			backend->set_title(fmt.tprintf("%v FPS", frames_since_print))
			frames_since_print = 0
			last_print_time    = time.now()
		}

		prev_primary := editor.selections[editor.primary]
		prev_scroll  := editor.scroll

		consumed_codepoint_event: int

		for event in backend->poll_events() {
			switch e in event {
			case Event_Window_Close:
				break main_loop
			case Event_Window_Resize:
				editor.screen_size = ([2]f32)(e.size)

			case Event_Input_Key:
				if e.action == .Up {
					break
				}

				if editor.mode == .Prompt {
					#partial switch e.key {
					case .Escape:
						editor.mode = .Normal
						strings.builder_reset(&editor.prompt.input)
					case .Enter:
						prompt_apply(&editor)
						editor.mode = .Normal
						strings.builder_reset(&editor.prompt.input)
					case .Backspace:
						strings.pop_rune(&editor.prompt.input)
					}
					break
				}

				defer if !editor.leader.active && editor.leader.motion == nil {
					strings.builder_reset(&editor.leader.sequence)
					editor.leader.entries = {}
					vmem.arena_free_all(&editor.leader.arena)
				}

				if editor.leader.motion != nil {
					if e.key == .Escape {
						editor.leader.motion = nil
						editor.repeat_count  = 0
					}
					break
				}

				if e.key >= ._0 && e.key <= ._9 && e.modifiers == {} {
					editor.repeat_count *= 10
					editor.repeat_count += int(e.key - ._0)
					break
				}

				binds                := editor.leader.binds if editor.leader.active else editor.config.keybinds[editor.mode]
				editor.leader.active  = false
				editor.leader.entries = {}
				keybind              := Keybind {
					modifiers = e.modifiers,
					key       = e.key,
				}
				action, ok := binds[keybind]
				if !ok {
					editor.repeat_count = 0
					break
				}

				consumed_codepoint_event = e.id // ignore any codepoint events generated by the same keypress

				action_apply(&editor, action, keybind)
			case Event_Input_Codepoint:
				if e.source == consumed_codepoint_event {
					break
				}
				if editor.leader.motion != nil {
					argument_motion_apply(&editor, editor.leader.motion, e.codepoint)
					editor.leader.motion = nil
					editor.leader.active = false
					strings.builder_reset(&editor.leader.sequence)
					break
				}
				#partial switch editor.mode {
				case .Prompt:
					strings.write_rune(&editor.prompt.input, e.codepoint)
				case .Picker:
					strings.write_rune(&editor.picker.input, e.codepoint)
				case .Insert:
					argument_motion_apply(&editor, .Insert_Character, e.codepoint)
				}
			case Event_Input_Mouse_Move:
			case Event_Input_Mouse_Button:
			case Event_Input_Scroll:
				editor.scroll -= int(e.delta.y * 5)
			}
		}

		primary := &editor.selections[editor.primary]

		if prev_scroll != editor.scroll {
			primary_position := btree_offset_to_position(&editor.btree, primary.cursor)
			if primary_position.line < editor.scroll + 5 || primary_position.line > editor.scroll + editor.visible_lines - 5 {
				primary_position.line -= prev_scroll - editor.scroll
				_                      = position_to_offset_normalized(&editor, primary_position, true, primary)
				primary.anchor         = primary.cursor
			}
		}

		if prev_primary != primary^ {
			primary_line := btree_offset_to_line(&editor.btree, primary.cursor)
			if editor.scroll < primary_line - editor.visible_lines + 5 {
				editor.scroll = primary_line - editor.visible_lines + 5
			}

			if editor.scroll > primary_line - 5 {
				editor.scroll = primary_line - 5
			}
		}

		editor.scroll = clamp(editor.scroll, 0, int(editor.btree.lines - 1))
		animation_set_target(&editor.scroll_anim, f32(editor.scroll))

		current_time := time.duration_seconds(time.since(start_time))
		delta_time   := current_time - prev_time
		prev_time     = current_time

		clear(&instance_buffer)

		render(&editor, &instance_buffer, f32(delta_time))

		backend->draw(editor.font, instance_buffer[:], editor.config.theme[.Background].bg)
		free_all(context.temp_allocator)
	}
}

Rect :: struct {
	min, max: [2]f32,
}

@(require_results)
rect_from_min_max :: proc(min, max: [2]f32) -> Rect {
	return { min = min, max = max,  }
}

@(require_results)
rect_center :: proc(rect: Rect) -> [2]f32 {
	return (rect.min + rect.max) / 2
}

@(require_results)
rect_size :: proc(rect: Rect) -> [2]f32 {
	return rect.max - rect.min
}

Animation :: struct(T: typeid) {
	origin:  T,
	target:  T,
	current: T,
	t:       f32,
}

@(require_results)
animation_update :: proc(anim: ^Animation($T), delta_time, speed: f32) -> T {
	if speed <= 0 {
		return anim.target
	}
	anim.t = clamp(anim.t + speed * f32(delta_time), 0, 1)
	when T == Rect {
		anim.current = transmute(Rect)la.lerp(transmute([4]f32)anim.origin, transmute([4]f32)anim.target, ease.quartic_out(anim.t))
	} else {
		anim.current = la.lerp(anim.origin, anim.target, ease.quartic_out(anim.t))
	}
	return anim.current
}

animation_set_target :: proc(anim: ^Animation($T), target: T) {
	if anim.target == target {
		return
	}
	anim.origin = anim.current
	anim.target = target
	anim.t      = 0
}

render :: proc(editor: ^Editor, instance_buffer: ^[dynamic]Instance, delta_time: f32) {
	text_buffer := make([dynamic]Instance, context.temp_allocator)

	cell_size: [2]f32 = {
		la.round(get_baked_glyph(&editor.font, 0).x_advance),
		la.round(((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale)),
	}

	padding: f32 = 10
	line_digits  := max(1, int(la.ceil(la.log10(f32(editor.btree.lines)))))
	lines_width  := cell_size.x * f32(line_digits)
	gutter_width := lines_width + padding + 2 + padding

	editor.visible_lines = int(la.ceil((editor.screen_size.y - FONT_HEIGHT - padding * 2) / cell_size.y))

	scroll := animation_update(&editor.scroll_anim, delta_time, editor.config.scroll_animation_speed)

	position: Position = {
		line   = int(la.floor(scroll)),
		column = 0,
	}

	iter := btree_iterator(&editor.btree, line = position.line)

	offset := iter.next_offset

	b := strings.builder_make(context.temp_allocator)

	for r in btree_iter(&iter) {
		if iter.line > int(la.ceil(scroll)) + editor.visible_lines {
			break
		}
		strings.write_rune(&b, r)
	}

	primary          := editor.selections[editor.primary]
	primary_position := btree_offset_to_position(&editor.btree, primary.cursor)

	text := strings.to_string(b)

	highlighter: Highlighter = {
		text     = text,
		keywords = editor.config.styles,
	}

	cursors := make(map[Offset]int, context.temp_allocator)
	for selection, i in editor.selections {
		cursors[selection.cursor] = i
	}

	render_text: for {
		start := highlighter.pos
		style := highlighter_advance(&highlighter)
		if style == .Invalid {
			break
		}

		start_column := position.column

		for char, sub_offset in text[start:highlighter.pos] {
			defer position = position_after(position, char, editor.config.tab_width)

			offset := offset + Offset(start + sub_offset)

			draw_gutter: if position.column == 0 {
				y := cell_size.y * (f32(position.line) - scroll) + FONT_HEIGHT + padding

				if y < 0 {
					break draw_gutter
				}

				l := position.line
				if editor.config.relative_line_numbers && primary_position.line != position.line {
					l = abs(primary_position.line - position.line) - 1
				}

				@(static)
				line_number_buf: [32]byte
				str := strconv.write_int(line_number_buf[:], i64(l + 1), base = 10)
				w   := measure_text(&editor.font, str)
				draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { lines_width - w + padding, y, })

				append(instance_buffer, Instance {
					offset = {
						gutter_width - cell_size.x + padding,
						cell_size.y * (f32(position.line) - scroll) - la.round(f32(editor.font.descender) * editor.font.scale),
					},
					size   = { 2, cell_size.y, },
					color  = editor.config.theme[.Ident].fg,
				})
			}

			style := style
			if id, ok := cursors[offset]; ok {
				if id == editor.primary {
					style = .Cursor
				} else {
					style = .Cursor_Secondary
				}
			}

			for selection in editor.selections {
				@(require_results)
				offset_in_selection :: proc(selection: Selection, offset: Offset) -> bool {
					@(require_results)
					offset_in_range :: proc(start, end, offset: Offset) -> bool {
						return start <= offset && offset <= end
					}
					return offset_in_range(selection.anchor, selection.cursor, offset) || offset_in_range(selection.cursor, selection.anchor, offset)
				}

				if offset_in_selection(selection, offset) {
					next_column := position_after(position, char, editor.config.tab_width).column
					append(instance_buffer, Instance {
						offset        = {
							f32(position.column) * cell_size.x + gutter_width,
							cell_size.y * (f32(position.line - 1) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale),
						} + padding,
						size          = cell_size * { f32(max(1, next_column - position.column)), 1, },
						color         = editor.config.theme[.Selection].bg,
						border_radius = 0,
					})
				}
			}

			if unicode.is_space(char) {
				continue
			}

			x := f32(position.column) * cell_size.x + padding + gutter_width
			y := cell_size.y * (f32(position.line) - scroll) + FONT_HEIGHT + padding
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

			// TODO: line wrapping
		}

		if editor.config.theme[style].bg != 0 {
			append(instance_buffer, Instance {
				offset        = {
					f32(start_column) * cell_size.x + gutter_width,
					cell_size.y * (f32(position.line - 1) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale),
				} + padding,
				size          = { f32(position.column - start_column) * cell_size.x, cell_size.y, },
				color         = editor.config.theme[style].bg,
				border_radius = 0,
			})
		}
	}

	for &selection, i in editor.selections {
		line := btree_offset_to_line(&editor.btree, offset = selection.cursor)
		iter := btree_iterator(&editor.btree, line = line)

		for iter.offset != selection.cursor {
			_ = btree_iter(&iter) or_else panic("offset out of range")
		}

		position    := iter.position
		_, _         = btree_iter(&iter)
		next_column := iter.column
		width       := max(next_column - position.column, 1)

		offset := [2]f32 {
			f32(position.column) * cell_size.x + gutter_width,
			cell_size.y * f32(position.line - 1) + la.round(f32(editor.font.ascender) * editor.font.scale),
		} + padding

		size   := cell_size
		size.x *= f32(width)

		target := Rect{ min = offset, max = offset + size, }

		if selection.anim == {} {
			center                    := rect_center(target)
			selection.anim.current.min = center
			selection.anim.current.max = center
		}

		animation_set_target(&selection.anim, target)

		style := Style_Key.Cursor_Secondary
		if i == editor.primary {
			style = .Cursor
		}

		cursor_rect := animation_update(&selection.anim, delta_time, editor.config.cursor_animation_speed)
		append(instance_buffer, Instance {
			offset        = cursor_rect.min - { 0, scroll * cell_size.y, },
			size          = rect_size(cursor_rect),
			color         = editor.config.theme[style].bg,
			border_radius = 2,
		})
	}

	append(instance_buffer, ..text_buffer[:])
	clear(&text_buffer)

	append(instance_buffer, Instance {
		offset = { 0, editor.screen_size.y - FONT_HEIGHT - padding * 2, },
		size   = { editor.screen_size.x, FONT_HEIGHT + padding * 2, },
		color  = editor.config.theme[.Background].bg,
	})
	append(instance_buffer, Instance {
		offset = { 0, editor.screen_size.y - FONT_HEIGHT - padding * 2 - 2, },
		size   = { editor.screen_size.x, 2, },
		color  = color_from_hex_rgba(0x32363DFF),
	})

	mode_text: string
	mode_style: Style_Key
	#partial switch editor.mode {
	case .Normal:
		mode_text  = "NORMAL"
		mode_style = .Indicator_Normal
	case .Visual:
		mode_text  = "VISUAL"
		mode_style = .Indicator_Visual
	case .Insert:
		mode_text  = "INSERT"
		mode_style = .Indicator_Insert
	}

	x := padding

	if mode_text != "" {
		w     := measure_text(&editor.font, mode_text)
		style := editor.config.theme[mode_style]
		if style.bg != 0 {
			append(instance_buffer, Instance {
				offset = { x - padding, editor.screen_size.y - FONT_HEIGHT - padding * 2, },
				size   = { w, FONT_HEIGHT, } + padding * 2,
				color  = style.bg,
			})
		}
		draw_text(
			&editor.font,
			instance_buffer,
			mode_text,
			editor.config.theme[mode_style].fg,
			{ x, editor.screen_size.y - padding, },
		)

		x += w + padding

		if style.bg != 0 {
			x += padding
		}
	}

	{
		x := editor.screen_size.x - padding
		if strings.builder_len(editor.leader.sequence) != 0 {
			str := strings.to_string(editor.leader.sequence)
			x   -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })
		}

		if editor.repeat_count > 0 {
			@(static)
			buf: [32]byte

			str := strconv.write_int(buf[:], i64(editor.repeat_count), base = 10)
			x   -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })
		}

		if x != editor.screen_size.x - padding {
			x -= padding
		}

		{
			@(static)
			buf: [32]byte
			str: string

			str = strconv.write_int(buf[:], i64(primary_position.column + 1), base = 10)
			x  -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })

			str = ":"

			x -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })

			str = strconv.write_int(buf[:], i64(primary_position.line + 1), base = 10)
			x  -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })

			x -= padding

			str = "sel"

			x  -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })

			x -= padding

			str = strconv.write_int(buf[:], i64(len(editor.selections)), base = 10)
			x  -= measure_text(&editor.font, str)
			draw_text(&editor.font, instance_buffer, str, editor.config.theme[.Ident].fg, { x, editor.screen_size.y - padding, })
		}
	}

	if editor.mode == .Prompt {
		mode_string: string
		switch editor.prompt.mode {
		case .Command:
			mode_string = ":"
		case .Search:
			mode_string = "search: "
		case .Keep:
			mode_string = "keep: "
		case .Select:
			mode_string = "select: "
		}

		x := x + draw_text(
			&editor.font,
			instance_buffer,
			mode_string,
			editor.config.theme[.Ident].fg,
			{ x, editor.screen_size.y - padding, },
		)

		w := draw_text(
			&editor.font,
			instance_buffer,
			strings.to_string(editor.prompt.input),
			editor.config.theme[.Ident].fg,
			{ x, editor.screen_size.y - padding, },
		)

		append(instance_buffer, Instance {
			offset = { x + w, editor.screen_size.y - FONT_HEIGHT - padding + f32(editor.font.descender) * editor.font.scale, },
			size   = { 2, cell_size.y, },
			color  = editor.config.theme[.Ident].fg,
		})
	}

	if editor.mode == .Picker {
		rect := rect_from_min_max(40, editor.screen_size - 40 - { 0, FONT_HEIGHT + padding * 2, })
		animation_set_target(&editor.picker.rect, rect)
	} else {
		center := rect_center(rect_from_min_max(40, editor.screen_size - 40))
		animation_set_target(&editor.picker.rect, Rect{ min = center, max = center, })
	}

	leader_target_rect := Rect {
		min = (editor.screen_size - 20 - { 0, FONT_HEIGHT + padding * 2, }) - editor.leader.size,
		max = (editor.screen_size - 20 - { 0, FONT_HEIGHT + padding * 2, }),
	}
	if editor.leader.active {
		animation_set_target(&editor.leader.rect, leader_target_rect)
	} else {
		center := rect_center(leader_target_rect)
		animation_set_target(&editor.leader.rect, Rect{ min = center, max = center, })
	}

	leader_rect := animation_update(&editor.leader.rect, delta_time, editor.config.popup_animation_speed)
	append(instance_buffer, Instance {
		offset        = leader_rect.min,
		size          = rect_size(leader_rect),
		color         = editor.config.theme[.Background].bg,
		border_color  = color_from_hex_rgba(0x32363DFF),
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,
	})

	animation_set_target(&editor.leader.alpha, editor.leader.active && editor.leader.rect.t == 1 ? 1 : 0)
	leader_alpha := animation_update(&editor.leader.alpha, delta_time, editor.config.popup_animation_speed)

	if editor.leader.active {
		x := leader_rect.min.x + padding
		y := leader_rect.min.y + padding

		text_color := editor.config.theme[.Ident].fg * { 1, 1, 1, leader_alpha, }

		draw_text(&editor.font, instance_buffer, editor.leader.title, text_color, { x, y + FONT_HEIGHT, })
		y += FONT_HEIGHT + padding

		append(instance_buffer, Instance {
			offset = { x, y, },
			size   = { rect_size(leader_rect).x - padding * 2, 2, },
			color  = color_from_hex_rgba(0x32363DFF) * { 1, 1, 1, leader_alpha, },
		})
		y += padding + 2

		if len(editor.leader.entries) == 0 && len(editor.leader.binds) != 0 {
			allocator            := vmem.arena_allocator(&editor.leader.arena)
			editor.leader.entries = make([]Leader_Entry, len(editor.leader.binds), allocator)

			binds_width:   f32
			actions_width: f32

			i := 0
			for bind, action in editor.leader.binds {
				editor.leader.entries[i] = {
					bind   = keybind_to_string(bind,  &editor.leader.arena),
					action = action_to_string(action, &editor.leader.arena),
				}
				binds_width   = max(binds_width,   measure_text(&editor.font, editor.leader.entries[i].bind  ))
				actions_width = max(actions_width, measure_text(&editor.font, editor.leader.entries[i].action))

				i += 1
			}

			editor.leader.binds_width = binds_width

			editor.leader.size = padding + [2]f32 {
				binds_width + padding + cell_size.x + padding + actions_width,
				FONT_HEIGHT + padding + 2 + padding + f32(len(editor.leader.entries)) * (FONT_HEIGHT + padding) - padding,
			} + padding

			slice.sort_by(editor.leader.entries, proc(a, b: Leader_Entry) -> bool {
				return a.bind < b.bind
			})
		}

		for entry in editor.leader.entries {
			draw_text(&editor.font, instance_buffer, entry.bind, text_color, { x, y + FONT_HEIGHT, })
			x := x + editor.leader.binds_width + padding
			x += draw_text(&editor.font, instance_buffer, "󰁔", text_color, { x, y + FONT_HEIGHT, }) + padding

			draw_text(&editor.font, instance_buffer, entry.action, text_color, { x, y + FONT_HEIGHT, })

			y += FONT_HEIGHT + padding
		}
	} else {
		editor.leader.alpha.target  = 0
		editor.leader.alpha.current = 0
		editor.leader.alpha.t       = 1
	}

	picker_rect := animation_update(&editor.picker.rect, delta_time, editor.config.popup_animation_speed)

	append(instance_buffer, Instance {
		offset        = picker_rect.min,
		size          = rect_size(picker_rect),
		color         = color_from_hex_rgba(0x1E2128FF),
		border_color  = color_from_hex_rgba(0x32363DFF),
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,
	})

	if editor.mode == .Picker {
		draw_text(
			&editor.font,
			instance_buffer,
			strings.to_string(editor.picker.input),
			editor.config.theme[.Ident].fg,
			picker_rect.min + padding + { 0, FONT_HEIGHT, },
		)
	}
}

@(require_results)
next_column_after_tab :: proc(column, tab_width: int) -> int {
	column := column + 1
	for column % tab_width != 0 {
		column += 1
	}
	return column
}

prompt_apply :: proc(editor: ^Editor) {
	switch editor.prompt.mode {
	case .Keep, .Select:
		pattern, err := regex.create(strings.to_string(editor.prompt.input), flags = { .Unicode, }, permanent_allocator = context.temp_allocator)
		if err != nil {
			fmt.println(err)
			break
		}

		b := strings.builder_make(context.temp_allocator)
		for selection in editor.selections {
			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor)

			strings.builder_grow(&b, int(end - start))

			start_time := time.now()

			iter := btree_iterator(&editor.btree, offset = start)
			for r in btree_iter(&iter) {
				if iter.offset > end {
					break
				}
				strings.write_rune(&b, r)
			}

			fmt.println("Selection to string:", time.since(start_time))

			start_time = time.now()

			capture, ok := regex.match(pattern, strings.to_string(b), context.temp_allocator)
			fmt.println(capture, ok, time.since(start_time))
			strings.builder_reset(&b)
		}

		if err != nil {
			fmt.println(err)
		}
	case .Search:
		pattern, err := regex.create(strings.to_string(editor.prompt.input), flags = { .Unicode, }, permanent_allocator = context.temp_allocator)
		if err != nil {
			fmt.println(err)
			break
		}

		b          := strings.builder_make(0, int(editor.btree.bytes), context.temp_allocator)
		start_time := time.now()

		iter := btree_iterator(&editor.btree)
		for r in btree_iter(&iter) {
			strings.write_rune(&b, r)
		}

		fmt.println("File to string:", time.since(start_time))

		start_time = time.now()

		capture, ok := regex.match(pattern, strings.to_string(b), context.temp_allocator)
		fmt.println("Search:", time.since(start_time))
		if ok {
			selection              := &editor.selections[editor.primary]
			_, n                   := utf8.decode_last_rune(capture.groups[0])
			selection.anchor        = Offset(capture.pos[0][0])
			selection.cursor        = Offset(capture.pos[0][1] - n)
			selection.target_cursor = selection.cursor
		}
	case .Command:
		unimplemented()
	}
}
