package editor

import runtime "base:runtime"

import ease    "core:math/ease"
import fmt     "core:fmt"
import la      "core:math/linalg"
import mem     "core:mem"
import os      "core:os"
import slice   "core:slice"
import strconv "core:strconv"
import strings "core:strings"
import time    "core:time"
import unicode "core:unicode"
import utf8    "core:unicode/utf8"
import vmem    "core:mem/virtual"

import regex   "vendor/regex"

Draw_Command_Rect :: struct {
	rect:          Rect,
	color:         [4]f32,
	border_radius: f32,
	border_width:  f32,
	border_color:  [4]f32,
	shadow_width:  f32,
}

Draw_Command_Char :: struct {
	position: [2]f32,
	char:     rune,
	color:    [4]f32,
}

Draw_Command_Clip :: distinct Rect

Draw_Command_Blur :: struct {
	radius: f32, // 0 = disable blur
}

DRAW_COMMAND_CLIP_DISABLE :: Draw_Command_Clip { min = min(f32), max = max(f32), }

Draw_Command :: union {
	Draw_Command_Rect,
	Draw_Command_Char,
	Draw_Command_Clip,
	Draw_Command_Blur,
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

Prompt_Mode :: enum {
	Command,
	Search,
	Keep,
	Select,
}

Leader_Entry :: struct {
	bind, action: string,
}

New_Selection :: struct {
	using selection: Selection,
	primary:         bool,
}

Buffer :: struct {
	path:          string,
	btree:         BTree,
	primary:       int,
	selections:    [dynamic]Selection,
	scroll:        int,
	scroll_anim:   Animation(f32),
	visible_lines: int,
}

buffer_init :: proc(editor: ^Editor, buffer: ^Buffer, path: string, allocator: runtime.Allocator) {
	path := os.get_absolute_path(path, context.temp_allocator) or_else panic("")
	self := os.get_working_directory(context.temp_allocator)   or_else panic("")
	path  = os.get_relative_path(self, path, allocator)        or_else panic("")

	data   := os.read_entire_file(path, context.temp_allocator) or_else { '\n', }
	buffer^ = {
		selections = make([dynamic]Selection, 1, allocator),
		path       = path,
		btree      = btree_build(string(data), allocator, editor.config.tab_width),
	}
}

buffer_destroy :: proc(buffer: Buffer) {
	btree_destroy(buffer.btree)
	delete(buffer.selections)
	delete(buffer.path)
}

Editor :: struct {
	backend:       ^Backend,

	mode:           Mode,

	buffer:         Buffer,

	new_selections: [dynamic]New_Selection,

	repeat_count:   int,

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

	picker:         Picker,

	clipboard:      strings.Builder,

	status:         strings.Builder,

	prompt:         Prompt,

	config:         Config,

	font:           Font,
}

Prompt :: struct {
	mode:    Prompt_Mode,
	input:   strings.Builder,
	history: [Prompt_Mode][dynamic]string,
	arena:   vmem.Arena,
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

	editor: Editor
	editor.backend = backend_init()
	if editor.backend == nil {
		fmt.eprintln("Failed to initialize backend")
		os.exit(1)
	}
	editor.new_selections = make([dynamic]New_Selection)

	err := vmem.arena_init_growing(&editor.prompt.arena)
	assert(err == nil)
	err = vmem.arena_init_growing(&editor.leader.arena)
	assert(err == nil)

	defer {
		editor.backend->destroy()
		for h in editor.prompt.history {
			delete(h)
		}
		vmem.arena_destroy(&editor.prompt.arena)
		vmem.arena_destroy(&editor.leader.arena)
		delete(editor.new_selections)
		strings.builder_destroy(&editor.leader.sequence)
		strings.builder_destroy(&editor.prompt.input)
		strings.builder_destroy(&editor.status)
		strings.builder_destroy(&editor.clipboard)
		picker_destroy(&editor.picker)
	}

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

	buffer_init(&editor, &editor.buffer, #file, context.allocator)
	defer buffer_destroy(editor.buffer)

	last_print_time    := time.now()
	frames_since_print := 0

	draw_commands := make([dynamic]Draw_Command, context.allocator)
	defer delete(draw_commands)

	screen_size: [2]f32

	main_loop: for {
		frames_since_print += 1
		if time.since(last_print_time) > time.Second {
			editor.backend->set_title(fmt.tprintf("%v FPS", frames_since_print))
			frames_since_print = 0
			last_print_time    = time.now()
		}

		prev_scroll := editor.buffer.scroll

		consumed_codepoint_event: int

		for event in editor.backend->poll_events() {
			switch e in event {
			case Event_Window_Close:
				break main_loop
			case Event_Window_Resize:
				screen_size = ([2]f32)(e.size)

			case Event_Input_Key:
				if e.action == .Up {
					break
				}

				if editor.mode == .Prompt {
					#partial switch e.key {
					case .Escape:
						editor.mode = .Normal
					case .Enter:
						prompt_apply(&editor)
						editor.mode = .Normal
					case .Backspace:
						strings.pop_rune(&editor.prompt.input)
					}
					break
				}

				if editor.mode == .Picker {
					#partial switch e.key {
					case .Escape:
						editor.mode = .Normal
					case .Enter:
						picker_submit(&editor)
					case .Backspace:
						@(require_results)
						is_word :: proc(r: rune) -> bool {
							return r == '_' || unicode.is_letter(r) || unicode.is_number(r)
						}

						r, w := strings.pop_rune(&editor.picker.input)
						(w != 0) or_break

						if e.modifiers & { .Control, .Alt, } == {} {
							picker_update(&editor)
							break
						}

						for !is_word(r) {
							r, w = strings.pop_rune(&editor.picker.input)
							(w != 0) or_break
						}
						for is_word(r) {
							r, w = strings.pop_rune(&editor.picker.input)
							(w != 0) or_break
						}
						if !is_word(r) && w != 0 {
							strings.write_rune(&editor.picker.input, r)
						}
						picker_update(&editor)
					case .Down, .Tab:
						editor.picker.active += 1
						if editor.picker.active >= len(editor.picker.matches) {
							editor.picker.active = 0
						}
					case .Up:
						editor.picker.active -= 1
						if editor.picker.active < 0 {
							editor.picker.active = len(editor.picker.matches) - 1
						}
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
					argument_motion_apply(&editor.buffer, editor.leader.motion, e.codepoint)
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
					picker_update(&editor)
				case .Insert:
					argument_motion_apply(&editor.buffer, .Insert_Character, e.codepoint)
				}
			case Event_Input_Mouse_Move:
			case Event_Input_Mouse_Button:
			case Event_Input_Scroll:
				editor.buffer.scroll -= int(e.delta.y * 5)
			}
		}

		primary := &editor.buffer.selections[editor.buffer.primary]

		if prev_scroll != editor.buffer.scroll {
			primary_position := btree_offset_to_position(&editor.buffer.btree, primary.cursor)
			if primary_position.line < editor.buffer.scroll + 5 || primary_position.line > editor.buffer.scroll + editor.buffer.visible_lines - 5 {
				primary_position.line -= prev_scroll - editor.buffer.scroll
				_                      = position_to_offset_normalized(&editor.buffer, primary_position, true, primary)
				primary.anchor         = primary.cursor
			}
		}

		{
			primary_line := btree_offset_to_line(&editor.buffer.btree, primary.cursor)
			if editor.buffer.scroll < primary_line - editor.buffer.visible_lines + 5 {
				editor.buffer.scroll = primary_line - editor.buffer.visible_lines + 5
			}

			if editor.buffer.scroll > primary_line - 5 {
				editor.buffer.scroll = primary_line - 5
			}
		}

		editor.buffer.scroll = clamp(editor.buffer.scroll, 0, int(editor.buffer.btree.lines - 1))
		animation_set_target(&editor.buffer.scroll_anim, f32(editor.buffer.scroll))

		current_time := time.duration_seconds(time.since(start_time))
		delta_time   := current_time - prev_time
		prev_time     = current_time

		clear(&draw_commands)

		render(&editor, &draw_commands, f32(delta_time), screen_size)

		editor.backend->draw(editor.font, draw_commands[:], editor.config.theme[.Background].bg)
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

@(require_results)
rect_inflate :: proc(rect: Rect, v: [2]f32) -> Rect {
	return {
		min = rect.min - v,
		max = rect.max + v,
	}
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

render :: proc(editor: ^Editor, commands: ^[dynamic]Draw_Command, delta_time: f32, screen_size: [2]f32) {
	padding: f32 = 10
	status_bar_height := FONT_HEIGHT + padding * 2 + 2

	render_buffer(editor, &editor.buffer, commands, delta_time, { min = padding, max = screen_size - { padding, status_bar_height, }, }, padding)

	draw_rect(commands,
		offset = { 0, screen_size.y - FONT_HEIGHT - padding * 2, },
		size   = { screen_size.x, FONT_HEIGHT + padding * 2, },
		color  = editor.config.theme[.Background].bg,
	)
	draw_rect(commands,
		offset = { 0, screen_size.y - FONT_HEIGHT - padding * 2 - 2, },
		size   = { screen_size.x, 2, },
		color  = color_from_hex_rgba(0x32363DFF),
	)

	{
		buffer           := editor.buffer
		primary          := buffer.selections[buffer.primary]
		primary_position := btree_offset_to_position(&buffer.btree, primary.cursor)

		{
			x := screen_size.x - padding
			if strings.builder_len(editor.leader.sequence) != 0 {
				str := strings.to_string(editor.leader.sequence)
				x   -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })
			}

			if editor.repeat_count > 0 {
				@(static)
				buf: [32]byte

				str := strconv.write_int(buf[:], i64(editor.repeat_count), base = 10)
				x   -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })
			}

			if x != screen_size.x - padding {
				x -= padding
			}

			{
				center := screen_size.x / 2
				w      := measure_text(&editor.font, buffer.path)
				draw_text(&editor.font, commands, buffer.path, editor.config.theme[.Ident].fg, { center - w / 2, screen_size.y - padding, })
			}

			{
				@(static)
				buf: [32]byte
				str: string

				str = strconv.write_int(buf[:], i64(primary_position.column + 1), base = 10)
				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })

				str = ":"

				x -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })

				str = strconv.write_int(buf[:], i64(primary_position.line + 1), base = 10)
				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })

				x -= padding

				str = "sel"

				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })

				x -= padding

				str = strconv.write_int(buf[:], i64(len(buffer.selections)), base = 10)
				x  -= measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, editor.config.theme[.Ident].fg, { x, screen_size.y - padding, })
			}
		}
	}

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
			draw_rect(commands,
				offset = { x - padding, screen_size.y - FONT_HEIGHT - padding * 2, },
				size   = { w, FONT_HEIGHT, } + padding * 2,
				color  = style.bg,
			)
		}
		draw_text(
			&editor.font,
			commands,
			mode_text,
			editor.config.theme[mode_style].fg,
			{ x, screen_size.y - padding, },
		)

		x += w + padding

		if style.bg != 0 {
			x += padding
		}
	}

	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round(((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale)),
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
			commands,
			mode_string,
			editor.config.theme[.Ident].fg,
			{ x, screen_size.y - padding, },
		)

		text := strings.to_string(editor.prompt.input)
		if text == "" {
			history := editor.prompt.history[editor.prompt.mode]
			if len(history) != 0 {
				text = history[len(history) - 1]
			}
		}
		w := draw_text(
			&editor.font,
			commands,
			text,
			editor.config.theme[.Ident].fg,
			{ x, screen_size.y - padding, },
		)

		if strings.builder_len(editor.prompt.input) == 0 {
			w = 0
		}
		draw_rect(commands,
			offset = { x + w, screen_size.y - FONT_HEIGHT - padding + f32(editor.font.descender) * editor.font.scale, },
			size   = { 2, cell_size.y, },
			color  = editor.config.theme[.Ident].fg,
		)
	} else {
		draw_text(
			&editor.font,
			commands,
			strings.to_string(editor.status),
			editor.config.theme[.Ident].fg,
			{ x, screen_size.y - padding, },
		)
	}

	if editor.config.blur_strength != 0 {
		append(commands, Draw_Command_Blur{ radius = f32(editor.config.blur_strength), })
	}

	leader_target_rect := Rect {
		min = (screen_size - 20 - { 0, FONT_HEIGHT + padding * 2, }) - editor.leader.size,
		max = (screen_size - 20 - { 0, FONT_HEIGHT + padding * 2, }),
	}
	if editor.leader.active {
		animation_set_target(&editor.leader.rect, leader_target_rect)
	} else {
		center := rect_center(leader_target_rect)
		animation_set_target(&editor.leader.rect, Rect{ min = center, max = center, })
	}

	leader_rect := animation_update(&editor.leader.rect, delta_time, editor.config.popup_animation_speed)
	draw_rect(commands,
		offset        = leader_rect.min,
		size          = rect_size(leader_rect),
		color         = editor.config.theme[.Popup_Background].fg,
		border_color  = editor.config.theme[.Popup_Border].fg,
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,
	)

	animation_set_target(&editor.leader.alpha, editor.leader.active && editor.leader.rect.t == 1 ? 1 : 0)
	leader_alpha := animation_update(&editor.leader.alpha, delta_time, editor.config.popup_animation_speed)

	if editor.leader.active {
		x := leader_rect.min.x + padding
		y := leader_rect.min.y + padding

		text_color := editor.config.theme[.Ident].fg * { 1, 1, 1, leader_alpha, }

		draw_text(&editor.font, commands, editor.leader.title, text_color, { x, y + FONT_HEIGHT, })
		y += FONT_HEIGHT + padding

		draw_rect(commands,
			offset = { x, y, },
			size   = { rect_size(leader_rect).x - padding * 2, 2, },
			color  = color_from_hex_rgba(0x32363DFF) * { 1, 1, 1, leader_alpha, },
		)
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
			draw_text(&editor.font, commands, entry.bind, text_color, { x, y + FONT_HEIGHT, })
			x := x + editor.leader.binds_width + padding
			x += draw_text(&editor.font, commands, "󰁔", text_color, { x, y + FONT_HEIGHT, }) + padding

			draw_text(&editor.font, commands, entry.action, text_color, { x, y + FONT_HEIGHT, })

			y += FONT_HEIGHT + padding
		}
	} else {
		editor.leader.alpha.target  = 0
		editor.leader.alpha.current = 0
		editor.leader.alpha.t       = 1
	}

	picker_render(editor, commands, delta_time, padding, screen_size)
}

@(require_results)
next_column_after_tab :: proc(column, tab_width: int) -> int {
	column := column + 1
	for column % tab_width != 0 {
		column += 1
	}
	return column
}

editor_set_status :: proc(editor: ^Editor, format: string, args: ..any) {
	strings.builder_reset(&editor.status)
	fmt.sbprintf(&editor.status, format, ..args)
}

regex_search :: proc(editor: ^Editor, buffer: ^Buffer, pattern_string: string) -> (ok: bool) {
	pattern, err := regex.create(pattern_string, flags = { .Unicode, }, permanent_allocator = context.temp_allocator)
	if err != nil {
		editor_set_status(editor, "Failed to parse regex: %v", err)
		return
	}

	defer if !ok {
		editor_set_status(editor, "Not found")
	}

	selection  := &buffer.selections[buffer.primary]
	start      := max(selection.cursor, selection.anchor)
	b          := strings.builder_make(0, int(buffer.btree.bytes - start), context.temp_allocator)
	btree_to_string(&buffer.btree, &b, start)

	iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
	capture: regex.Capture
	capture, _, ok = regex.match(&iter)

	if ok && capture.pos[0][0] == 0 {
		capture, _, ok = regex.match(&iter)
	}

	if ok {
		_, n                   := utf8.decode_last_rune(capture.groups[0])
		selection.anchor        = Offset(capture.pos[0][0])     + start
		selection.cursor        = Offset(capture.pos[0][1] - n) + start
		selection.target_cursor = selection.cursor
		return
	}

	if start == 0 {
		return
	}

	strings.builder_reset(&b)
	strings.builder_grow(&b, int(start))
	btree_to_string(&buffer.btree, &b, end = start)

	capture = regex.match(pattern, strings.to_string(b), context.temp_allocator) or_return

	_, n                   := utf8.decode_last_rune(capture.groups[0])
	selection.anchor        = Offset(capture.pos[0][0])
	selection.cursor        = Offset(capture.pos[0][1] - n)
	selection.target_cursor = selection.cursor

	editor_set_status(editor, "Wrapped around document")

	return true
}

regex_search_reverse :: proc(editor: ^Editor, buffer: ^Buffer, pattern_string: string) -> (ok: bool) {
	pattern, err := regex.create(pattern_string, flags = { .Unicode, .Reverse_Pattern, }, permanent_allocator = context.temp_allocator)
	if err != nil {
		editor_set_status(editor, "Failed to parse regex: %v", err)
		return
	}

	defer if !ok {
		editor_set_status(editor, "Not found")
	}

	selection  := &buffer.selections[buffer.primary]
	start      := min(selection.cursor, selection.anchor)
	b          := strings.builder_make(0, int(buffer.btree.bytes - start), context.temp_allocator)
	btree_to_string(&buffer.btree, &b, end = start, reverse = true)

	iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
	capture: regex.Capture
	capture, _, ok = regex.match(&iter)

	if ok && capture.pos[0][0] == 0 {
		capture, _, ok = regex.match(&iter)
	}

	if ok {
		_, n                   := utf8.decode_rune(capture.groups[0])
		selection.cursor        = start - Offset(capture.pos[0][0] + n)
		selection.anchor        = start - Offset(capture.pos[0][1])
		selection.target_cursor = selection.cursor
		return
	}

	strings.builder_reset(&b)
	strings.builder_grow(&b, int(start))
	btree_to_string(&buffer.btree, &b, start = start, reverse = true)

	capture = regex.match(pattern, strings.to_string(b), context.temp_allocator) or_return

	_, n                   := utf8.decode_last_rune(capture.groups[0])
	selection.anchor        = buffer.btree.bytes - Offset(capture.pos[0][1])
	selection.cursor        = buffer.btree.bytes - Offset(capture.pos[0][0] + n)
	selection.target_cursor = selection.cursor

	editor_set_status(editor, "Wrapped around document")

	return true
}

prompt_apply :: proc(editor: ^Editor) {
	history := &editor.prompt.history[editor.prompt.mode]
	if strings.builder_len(editor.prompt.input) == 0 {
		if len(history) != 0 {
			strings.write_string(&editor.prompt.input, history[len(history) - 1])
		}
	} else {
		append(history, strings.clone(strings.to_string(editor.prompt.input), vmem.arena_allocator(&editor.prompt.arena)))
	}
	switch editor.prompt.mode {
	case .Select:
		pattern, err := regex.create(strings.to_string(editor.prompt.input), flags = { .Unicode, }, permanent_allocator = context.temp_allocator)
		if err != nil {
			fmt.println(err)
			break
		}

		b := strings.builder_make(context.temp_allocator)
		for selection, i in editor.buffer.selections {
			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor)

			strings.builder_grow(&b, int(end - start))
			btree_to_string(&editor.buffer.btree, &b, start, end)

			regex_iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
			for capture, capture_i in regex.match(&regex_iter) {
				append(&editor.new_selections, New_Selection {
					anchor  = start + Offset(capture.pos[0][0]),
					cursor  = start + btree_offset_before(&editor.buffer.btree, Offset(capture.pos[0][1])),
					primary = i == editor.buffer.primary && capture_i == 0,
				})
			}
			strings.builder_reset(&b)
		}

		if len(editor.new_selections) != 0 {
			clear(&editor.buffer.selections)
			reserve(&editor.buffer.selections, len(editor.new_selections))

			for selection in editor.new_selections {
				if selection.primary {
					editor.buffer.primary = len(editor.buffer.selections)
				}
				selection              := selection
				selection.target_cursor = selection.cursor
				append(&editor.buffer.selections, selection)
			}
			clear(&editor.new_selections)
			deduplicate_selections(&editor.buffer)
		}

		if err != nil {
			fmt.println(err)
		}
	case .Keep:
		pattern, err := regex.create(strings.to_string(editor.prompt.input), flags = { .Unicode, }, permanent_allocator = context.temp_allocator)
		if err != nil {
			fmt.println(err)
			break
		}

		b := strings.builder_make(context.temp_allocator)

		for i := len(editor.buffer.selections) - 1; i >= 0; i -= 1 {
			selection := editor.buffer.selections[i]

			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor)
			end    = btree_offset_after(&editor.buffer.btree, end)

			strings.builder_grow(&b, int(end - start))
			btree_to_string(&editor.buffer.btree, &b, start, end)

			_, ok := regex.match(pattern, strings.to_string(b), context.temp_allocator)
			if !ok {
				ordered_remove(&editor.buffer.selections, i)
				if i <= editor.buffer.primary {
					editor.buffer.primary -= 1
				}
			}
			strings.builder_reset(&b)
		}

		if err != nil {
			fmt.println(err)
		}
	case .Search:
		regex_search(editor, &editor.buffer, strings.to_string(editor.prompt.input))
	case .Command:
		command_execute(editor, Command(strings.to_string(editor.prompt.input)))
	}
	strings.builder_reset(&editor.prompt.input)
}

@(require_results)
position_after :: proc(position: Position, r: rune, tab_width: int) -> Position {
	position := position
	switch r {
	case 0:
	case '\n':
		position.line  += 1
		position.column = 0
	case '\t':
		position.column = next_column_after_tab(position.column, tab_width)
	case:
		position.column += 1
	}

	return position
}

@(require_results)
selection_contains :: proc(selection: Selection, offset: Offset) -> bool {
	return min(selection.anchor, selection.cursor) <= offset && offset <= max(selection.anchor, selection.cursor)
}

draw_rect :: proc(
	commands:     ^[dynamic]Draw_Command,
	offset:        [2]f32,
	size:          [2]f32,
	color:         [4]f32,
	border_radius: f32    = 0,
	border_width:  f32    = 0,
	border_color:  [4]f32 = 0,
	shadow_width:  f32    = 0,
) {
	append(commands, Draw_Command_Rect {
		rect          = rect_from_min_max(offset, offset + size),
		color         = color,
		border_radius = border_radius,
		border_width  = border_width,
		border_color  = border_color,
		shadow_width  = shadow_width,
	})
}

render_buffer :: proc(
	editor:    ^Editor,
	buffer:    ^Buffer,
	commands:  ^[dynamic]Draw_Command,
	delta_time: f32,
	rect:       Rect,
	padding:    f32,
) {
	if rect.max.x <= rect.min.x || rect.max.y <= rect.min.y {
		return
	}

	text_commands := make([dynamic]Draw_Command, context.temp_allocator)

	append(commands, Draw_Command_Clip(rect))
	defer append(commands, DRAW_COMMAND_CLIP_DISABLE)

	height := rect.max.y - rect.min.y

	cell_size: [2]f32 = {
		la.round(get_glyph_info(&editor.font, 0).x_advance),
		la.round(((f32(editor.font.ascender) - f32(editor.font.descender)) * editor.font.scale)),
	}

	line_digits  := int(la.ceil(la.log10(1 + f32(buffer.btree.lines))))
	lines_width  := cell_size.x * f32(line_digits) + padding
	gutter_width := lines_width + padding + 1 + padding

	buffer.visible_lines = max(1, int(la.floor(height / cell_size.y)))

	scroll := animation_update(&buffer.scroll_anim, delta_time, editor.config.scroll_animation_speed)

	primary          := buffer.selections[buffer.primary]
	primary_position := btree_offset_to_position(&buffer.btree, primary.cursor)

	first_visble_line := int(la.floor(scroll))
	last_visible_line := min(int(buffer.btree.lines), first_visble_line + buffer.visible_lines + 3)

	position: Position = {
		line = first_visble_line,
	}
	start_offset := btree_position_to_offset(&buffer.btree, position)
	end_offset   := btree_position_to_offset(&buffer.btree, { line = last_visible_line, })

	b := strings.builder_make(0, int(end_offset - start_offset), context.temp_allocator)
	btree_to_string(&buffer.btree, &b, start_offset, end_offset)
	text := strings.to_string(b)

	primary_match: Offset = -1
	find_primary_match: {
		iter  := btree_iterator(&buffer.btree, primary.cursor)
		start := btree_iter(&iter) or_break find_primary_match

		back := false
		delim: rune
		switch start {
		case '{':
			delim = '}'
		case '[':
			delim = ']'
		case '(':
			delim = ')'

		case '}':
			delim = '{'
			back  = true
		case ']':
			delim = '['
			back  = true
		case ')':
			delim = '('
			back  = true
		case:
			break find_primary_match
		}

		balance := 0 if back else 1
		for r in btree_iter(&iter, back = back) {
			if iter.offset < start_offset || iter.offset > end_offset {
				break
			}
			if r == delim {
				balance -= 1
			} else if r == start {
				balance += 1
			}
			if balance == 0 {
				primary_match = iter.offset
				break
			}
		}
	}

	highlighter: Highlighter = {
		text     = text,
		keywords = editor.config.styles,
	}

	cursors := make(map[Offset]int, context.temp_allocator)
	for selection, i in buffer.selections {
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

			offset := start_offset + Offset(start + sub_offset)

			draw_gutter: if position.column == 0 {
				y := cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale)

				if y < 0 {
					break draw_gutter
				}

				text_color := editor.config.theme[.Gutter].fg
				line       := position.line

				if color := editor.config.theme[.Gutter].bg; color != 0 {
					draw_rect(commands,
						offset = { 0, cell_size.y * (f32(position.line) - scroll), } + rect.min,
						size   = { gutter_width - cell_size.x, cell_size.y, },
						color  = color,
					)
				}

				if primary_position.line == position.line {
					text_color = editor.config.theme[.Cursor].bg
				} else if editor.config.relative_line_numbers {
					line = abs(primary_position.line - position.line) - 1
				}

				@(static)
				line_number_buf: [32]byte
				str := strconv.write_int(line_number_buf[:], i64(line + 1), base = 10)
				w   := measure_text(&editor.font, str)
				draw_text(&editor.font, commands, str, text_color, { lines_width - w, y, } + rect.min)

				draw_rect(commands,
					offset = {
						gutter_width - cell_size.x,
						cell_size.y * (f32(position.line) - scroll),
					} + rect.min,
					size   = { 1, cell_size.y, },
					color  = editor.config.theme[.Gutter].fg,
				)
			}

			style := style
			if id, ok := cursors[offset]; ok {
				if id == buffer.primary {
					style = .Cursor
				} else {
					style = .Cursor_Secondary
				}
			}

			next_column := position_after(position, char, editor.config.tab_width).column
			for selection in buffer.selections {
				if !selection_contains(selection, offset) {
					continue
				}

				draw_rect(commands,
					offset = {
						f32(position.column) * cell_size.x + gutter_width,
						cell_size.y * (f32(position.line) - scroll),
					} + rect.min,
					size   = cell_size * { f32(max(1, next_column - position.column)), 1, },
					color  = editor.config.theme[.Selection].bg,
				)
			}

			if offset == primary_match {
				draw_rect(commands,
					offset = {
						f32(position.column) * cell_size.x + gutter_width,
						cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender - editor.font.descender) * editor.font.scale) - 1,
					} + rect.min,
					size   = { cell_size.x * f32(max(1, next_column - position.column)), 1, },
					color  = editor.config.theme[.Cursor].bg,
				)
			}

			if unicode.is_space(char) {
				continue
			}

			x := f32(position.column) * cell_size.x + gutter_width
			y := cell_size.y * (f32(position.line) - scroll) + la.round(f32(editor.font.ascender) * editor.font.scale)

			append(&text_commands, Draw_Command_Char {
				position = { x, y, } + rect.min,
				color    = editor.config.theme[style].fg,
				char     = char,
			})

			// TODO: line wrapping
		}

		if editor.config.theme[style].bg != 0 {
			draw_rect(commands,
				offset = {
					f32(start_column) * cell_size.x + gutter_width,
					cell_size.y * (f32(position.line) - scroll),
				} + rect.min,
				size   = { f32(position.column - start_column) * cell_size.x, cell_size.y, },
				color  = editor.config.theme[style].bg,
			)
		}
	}

	for &selection, i in buffer.selections {
		line := btree_offset_to_line(&buffer.btree, offset = selection.cursor)
		iter := btree_iterator(&buffer.btree, line = line)

		for iter.offset != selection.cursor {
			_ = btree_iter(&iter) or_else panic("offset out of range")
		}

		position    := iter.position
		_, _         = btree_iter(&iter)
		next_column := iter.column
		width       := max(next_column - position.column, 1)

		offset := [2]f32 {
			f32(position.column) * cell_size.x + gutter_width,
			cell_size.y * f32(position.line),
		}

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
		if i == buffer.primary {
			style = .Cursor
		}

		cursor_rect := animation_update(&selection.anim, delta_time, editor.config.cursor_animation_speed)
		draw_rect(commands,
			offset        = cursor_rect.min - { 0, scroll * cell_size.y, } + rect.min,
			size          = rect_size(cursor_rect),
			color         = editor.config.theme[style].bg,
			border_radius = 2,
		)
	}

	append(commands, ..text_commands[:])
}
