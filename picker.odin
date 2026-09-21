package editor

import fmt     "core:fmt"
import os      "core:os"
import slice   "core:slice"
import strings "core:strings"
import unicode "core:unicode"
import utf8    "core:unicode/utf8"
import vmem    "core:mem/virtual"

Picker_Symbol :: struct {
	location: Location,
}

Picker_File :: struct {
	path: Normalized_Path,
	type: os.File_Type,
}

Picker :: struct {
	mode:         Picker_Mode,
	input:        Input_Line,
	items:        [dynamic]Picker_Item,
	active:       int,
	matching:     int,
	arena:        vmem.Arena,

	active_anim:  Animation(f32),

	files:        []Picker_File,
	symbols:      []Picker_Symbol,
	diagnostics:  []Diagnostic,

	rect:         Animation(Rect),
	preview_rect: Animation(Rect),
}

Picker_Mode :: enum {
	Files,
	Files_Recursive,
	Global_Search,
	Symbols,
	Diagnostics,
	Commands,
	Buffers,
	Jumplist,
}

Picker_Item :: struct {
	name:  string,
	score: int,
	id:    int,
}

picker_destroy :: proc(picker: ^Picker) {
	input_line_destroy(picker.input)
	delete(picker.items)
	vmem.arena_destroy(&picker.arena)
}

picker_open :: proc(editor: ^Editor, mode: Picker_Mode, path: string = "", fused_locations: []Fused_Location = {}) {
	input_line_reset(&editor.picker.input)
	vmem.arena_free_all(&editor.picker.arena)
	allocator := vmem.arena_allocator(&editor.picker.arena)

	clear(&editor.picker.items)

	switch mode {
	case .Global_Search:
	case .Files:
		path := path
		err: os.Error
		if path == "" {
			path, err = os.get_working_directory(context.temp_allocator)
			if err != nil {
				editor_set_status(editor, "Failed to get current working directory: %v", err)
				break
			}
		}
		files := os.read_all_directory_by_path(path, context.temp_allocator) or_break
		for file, i in files {
			editor.picker.files[i].path = normalize_path(file.fullpath, allocator)
		}
		if err != nil {
			editor_set_status(editor, "Failed to read directory: %v", err)
		}
	case .Files_Recursive:
		path := path
		err: os.Error
		if path == "" {
			path, err = os.get_working_directory(context.temp_allocator)
			if err != nil {
				editor_set_status(editor, "Failed to get current working directory: %v", err)
				break
			}
		}

		path, err = os.get_absolute_path(path, context.temp_allocator)
		if err != nil {
			editor_set_status(editor, "Failed to get absolute path: %v", err)
			break
		}

		w := os.walker_create(path)
		defer os.walker_destroy(&w)

		files := make([dynamic]Picker_File, allocator)
		clear(&editor.picker.items)
		for info in os.walker_walk(&w) {
			_ = os.walker_error(&w) or_break

			if info.type == .Directory {
				if strings.has_suffix(info.fullpath, ".git") {
					os.walker_skip_dir(&w)
				}

				continue
			}

			name := strings.trim_prefix(info.fullpath, path)
			name  = strings.trim_prefix(name, "/")
			name  = strings.clone(name, allocator)

			append(&editor.picker.items, Picker_Item {
				name = name,
				id   = len(files),
			})

			append(&files, Picker_File {
				path = normalize_path(info.fullpath, allocator),
				type = info.type,
			})
		}
		editor.picker.files = files[:]
	case .Symbols:
		assert(len(fused_locations) != 0)

		symbols := make([]Picker_Symbol, len(fused_locations), allocator)
		resize(&editor.picker.items, len(fused_locations))
		for &l, i in symbols {
			l.location = fused_locations[i]
			if l.location == {} {
				l.location = { uri = fused_locations[i].targetUri, range = fused_locations[i].targetRange, }
			}

			l.location.uri = uri_clone(l.location.uri, allocator)

			path := uri_to_path(l.location.uri, context.temp_allocator) or_else "invalid path"
			name := fmt.aprintf("%s:%d", path, l.location.range.start.line + 1, allocator = allocator)

			editor.picker.items[i] = {
				name = name,
				id   = i,
			}
		}

		editor.picker.symbols = symbols
	case .Diagnostics:
		diagnostics := make([]Diagnostic, len(editor.buffer.diagnostics), allocator)
		resize(&editor.picker.items, len(diagnostics))
		for &d, i in diagnostics {
			diagnostic := editor.buffer.diagnostics[i]
			d = {
				start   = diagnostic.start,
				end     = diagnostic.end,
				code    = strings.clone(diagnostic.code,    allocator),
				message = strings.clone(diagnostic.message, allocator),
			}

			editor.picker.items[i] = {
				name = fmt.aprintf("%s:%s", d.code, d.message, allocator = allocator),
				id   = i,
			}
		}

		editor.picker.diagnostics = diagnostics
	case .Commands:
		resize(&editor.picker.items, len(Command) + len(Motion) + len(Argument_Motion) + len(Selection_Motion) + len(Primary_Motion))
		i := 0
		for command in Command {
			editor.picker.items[i] = {
				name = fmt.aprint(":", command_to_name_table[command], sep = "", allocator = allocator),
				id   = i,
			}
			i += 1
		}
		for motion in Motion {
			editor.picker.items[i] = {
				name = motion_to_name_table[motion],
				id   = i,
			}
			i += 1
		}
		for motion in Argument_Motion {
			editor.picker.items[i] = {
				name = argument_motion_to_name_table[motion],
				id   = i,
			}
			i += 1
		}
		for motion in Selection_Motion {
			editor.picker.items[i] = {
				name = selection_motion_to_name_table[motion],
				id   = i,
			}
			i += 1
		}
		for motion in Primary_Motion {
			editor.picker.items[i] = {
				name = primary_motion_to_name_table[motion],
				id   = i,
			}
			i += 1
		}
	case .Buffers:
		resize(&editor.picker.items, len(editor.buffers))
		for b, i in editor.buffers {
			editor.picker.items[i] = {
				name = string(b.path),
				id   = i,
			}
		}
	case .Jumplist:
		resize(&editor.picker.items, len(editor.jumplist.entries))
		for b, i in editor.jumplist.entries {
			editor.picker.items[i] = {
				name = b.content,
				id   = i,
			}
		}
	}

	editor.mode        = .Picker
	editor.picker.mode = mode

	picker_update(editor)
}

picker_focus_next :: proc(editor: ^Editor) {
	editor.picker.active += 1
	if editor.picker.active >= editor.picker.matching {
		editor.picker.active = 0
	}
}

picker_focus_prev :: proc(editor: ^Editor, n := 1) {
	editor.picker.active -= 1
	if editor.picker.active < 0 {
		editor.picker.active = editor.picker.matching - 1
	}
}

picker_update :: proc(editor: ^Editor) {
	pattern := input_line_get_text(editor.picker.input)

	editor.picker.active = 0

	editor.picker.matching = 0
	for &item in editor.picker.items {
		item.score = item_match_score(item.name, pattern)
		if item.score >= 0 {
			editor.picker.matching += 1
		}
	}

	slice.sort_by(editor.picker.items[:], proc(a, b: Picker_Item) -> bool {
		a_score := a.score >= 0 ? a.score : max(int)
		b_score := b.score >= 0 ? b.score : max(int)
		if a_score != b_score {
			return a_score < b_score
		}

		return a.name < b.name
	})
}

picker_submit :: proc(editor: ^Editor) {
	picker := &editor.picker

	if picker.matching == 0 {
		editor.mode = .Normal
		return
	}

	active := picker.items[picker.active].id

	switch picker.mode {
	case .Global_Search:
		editor.mode = .Normal
	case .Files, .Files_Recursive:
		file := picker.files[active]
		if file.type == .Directory {
			picker_open(editor, .Files, strings.clone(string(file.path), context.temp_allocator))
		} else {
			file_open(editor, file.path)
		}
	case .Symbols:
		symbol := picker.symbols[active]

		path := uri_to_path(symbol.location.uri, context.temp_allocator) or_break

		if symbol.location.range.end.character > 0 {
			symbol.location.range.end.character -= 1
		}

		start := lsp_position_to_index(&editor.buffer.btree, symbol.location.range.start)
		end   := lsp_position_to_index(&editor.buffer.btree, symbol.location.range.end)

		editor_go_to(editor, normalize_path(path, context.temp_allocator), start, end)

		editor.mode = .Normal
	case .Diagnostics:
		diagnostic := picker.diagnostics[active]
		editor_go_to(editor, editor.buffer.path, diagnostic.start, diagnostic.end)

		editor.mode = .Normal
	case .Commands:
		editor.mode = .Normal
	case .Buffers:
		editor_open_buffer(editor, editor.buffers[active])
	case .Jumplist:
		entry := editor.jumplist.entries[active]
		editor_go_to(editor, entry.path, entry.start, entry.end)
	}
}

@(require_results)
item_match_score :: proc(item, pattern: string) -> int {
	if len(pattern) == 0 {
		return 1
	}

	has_upper: bool
	for r in pattern {
		if unicode.is_upper(r) {
			has_upper = true
			break
		}
	}

	item := item
	if !has_upper {
		item = strings.to_lower(item, context.temp_allocator)
	}

	if i := strings.index(item, pattern); i != -1 {
		return i + 1
	}

	score := 10000
	for f in pattern {
		i := strings.index_rune(item, f)
		if i == -1 {
			return -1
		}
		score += i * i
		item   = item[i + 1:]
	}
	return score
}

picker_render :: proc(editor: ^Editor, commands: ^[dynamic]Draw_Command, delta_time, padding: f32, screen_size: [2]f32) {
	picker := &editor.picker

	// {
	// 	rect    := rect_from_min_max(100, { screen_size.x / 2 - 25, screen_size.y - 100, })
	// 	preview := rect_from_min_max({ screen_size.x / 2 + 25, 100, }, screen_size - 100)

	// 	if editor.mode != .Picker {
	// 		rect.min = rect_center(rect)
	// 		rect.max = rect.min

	// 		preview.min = rect_center(preview)
	// 		preview.max = preview.min
	// 	}

	// 	animation_set_target(&picker.rect, rect)
	// 	animation_set_target(&picker.preview_rect, preview)
	// }
	if editor.mode == .Picker {
		rect := rect_from_min_max(100, screen_size - 100)
		animation_set_target(&picker.rect, rect)
	} else {
		center := screen_size / 2
		animation_set_target(&picker.rect, Rect{ min = center, max = center, })
	}

	picker_rect := animation_update(&picker.rect, delta_time, editor.config.popup_animation_speed)
	// preview_rect := animation_update(&picker.preview_rect, delta_time, editor.config.popup_animation_speed)

	if rect_size(picker_rect) == 0 {
		return
	}

	draw_rect(commands,
		offset        = picker_rect.min,
		size          = rect_size(picker_rect),
		color         = editor.config.theme[.Popup_Background].fg,
		border_color  = editor.config.theme[.Popup_Border].fg,
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,
		blur_radius   = f32(editor.config.blur_strength),
	)

	// draw_rect(commands,
	// 	offset        = preview_rect.min,
	// 	size          = rect_size(preview_rect),
	// 	color         = editor.config.theme[.Popup_Background].fg,
	// 	border_color  = editor.config.theme[.Popup_Border].fg,
	// 	border_radius = 8,
	// 	border_width  = 2,
	// 	shadow_width  = 16,
	// 	blur_radius   = f32(editor.config.blur_strength),
	// )

	clip_rect := rect_inflate(picker_rect, -2)
	if clip_rect.min.x >= clip_rect.max.x || clip_rect.min.y >= clip_rect.max.y {
		return
	}

	append(commands, Draw_Command_Clip(clip_rect))
	defer append(commands, DRAW_COMMAND_CLIP_DISABLE)

	if editor.mode == .Picker {
		input_line_render(
			editor,
			commands,
			&picker.input,
			picker_rect.min + padding + { 0, FONT_HEIGHT, },
			delta_time,
		)

		draw_rect(commands,
			offset = picker_rect.min + padding + { 0, FONT_HEIGHT + padding, },
			size   = { picker_rect.max.x - picker_rect.min.x - padding * 2, 2, },
			color  = editor.config.theme[.Popup_Border].fg,
		)

		line_height := padding + FONT_HEIGHT

		x := picker_rect.min.x + padding
		y := picker_rect.min.y + line_height * 2 + padding + 2

		pattern := input_line_get_text(picker.input)

		animation_set_target(&picker.active_anim, f32(picker.active))
		active := animation_update(&picker.active_anim, delta_time, editor.config.cursor_animation_speed)

		x += draw_text(&editor.font, commands, ">", editor.config.theme[.Ui_Focus].fg, { x, y + line_height * active, }) + padding

		has_upper: bool
		for r in pattern {
			if unicode.is_upper(r) {
				has_upper = true
				break
			}
		}

		for item, item_index in picker.items[:picker.matching] {
			assert(item.score >= 0)

			pos := [2]f32{ x, y, }

			item := item.name

			text_color := editor.config.theme[item_index == picker.active ? .Ui_Focus : .Ui_Text].fg

			defer y += line_height

			if !has_upper {
				lower  := strings.to_lower(item, context.temp_allocator)
				offset := strings.index(lower, pattern)
				if offset != -1 {
					n     := len(pattern)
					pos.x += draw_text(&editor.font, commands, item[:offset],     text_color,                            pos)
					pos.x += draw_text(&editor.font, commands, item[offset:][:n], editor.config.theme[.Ui_Highlight].fg, pos)
					pos.x += draw_text(&editor.font, commands, item[offset:][n:], text_color,                            pos)
					continue
				}
			}

			for f in pattern {
				i := strings.index_rune(item, f)
				if !has_upper {
					l := unicode.to_upper(f)
					if f != l {
						// uint(-1) == max(uint)
						i = int(min(uint(i), uint(strings.index_rune(item, l))))
					}
				}
				assert(i != -1)

				_, n := utf8.decode_rune(item[i:])

				pos.x += draw_text(&editor.font, commands, item[:i],     text_color,                            pos)
				pos.x += draw_text(&editor.font, commands, item[i:][:n], editor.config.theme[.Ui_Highlight].fg, pos)

				item = item[i + n:]
			}

			draw_text(&editor.font, commands, item, text_color, pos)
		}
	}
}
