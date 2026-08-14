package editor

import os      "core:os"
import strings "core:strings"
import slice   "core:slice"
import unicode "core:unicode"
import utf8    "core:unicode/utf8"

Picker :: struct {
	mode:    Picker_Mode,
	input:   strings.Builder,
	rect:    Animation(Rect),
	rect2:   Animation(Rect),
	files:   []os.File_Info,
	matches: [dynamic]Picker_Match,
	active:  int,
}

Picker_Mode :: enum {
	Files,
	Files_Recursive,
	Global_Search,
	Symbols,
	Commands,
}

Picker_Match :: struct {
	name:  string,
	score: int,
	id:    int,
}

picker_destroy :: proc(picker: ^Picker) {
	os.file_info_slice_delete(picker.files, context.allocator)
	strings.builder_destroy(&picker.input)
	delete(picker.matches)
}

picker_open :: proc(editor: ^Editor, mode: Picker_Mode, path: string = "") {
	strings.builder_reset(&editor.picker.input)

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
		os.file_info_slice_delete(editor.picker.files, context.allocator)
		editor.picker.files, err = os.read_all_directory_by_path(path, context.allocator)
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
		os.file_info_slice_delete(editor.picker.files, context.allocator)

		path, err = os.get_absolute_path(path, context.temp_allocator)
		if err != nil {
			editor_set_status(editor, "Failed to get absolute path: %v", err)
			break
		}

		w := os.walker_create(path)
		defer os.walker_destroy(&w)

		files := make([dynamic]os.File_Info, context.allocator)
		for info in os.walker_walk(&w) {
			_ = os.walker_error(&w) or_break

			if strings.has_suffix(info.fullpath, ".git") {
				os.walker_skip_dir(&w)
				continue
			}

			if info.type == .Directory {
				continue
			}

			info     := os.file_info_clone(info, context.allocator) or_break
			info.name = strings.trim_prefix(info.fullpath, path)
			info.name = strings.trim_prefix(info.name, "/")
			append(&files, info)
		}
		editor.picker.files = files[:]
	case .Symbols:
	case .Commands:
	}
	editor.mode        = .Picker
	editor.picker.mode = mode

	picker_update(editor)
}

picker_update :: proc(editor: ^Editor) {
	pattern := strings.to_string(editor.picker.input)

	editor.picker.active = 0

	switch editor.picker.mode {
	case .Global_Search:
	case .Files, .Files_Recursive:
		clear(&editor.picker.matches)
		for file, i in editor.picker.files {
			score := item_match_score(file.name, pattern)
			if score <= 0 {
				continue
			}
			append(&editor.picker.matches, Picker_Match {
				name  = file.name,
				score = score,
				id    = i,
			})
		}
		slice.sort_by(editor.picker.matches[:], proc(a, b: Picker_Match) -> bool {
			if a.score != b.score {
				return a.score < b.score
			}

			return a.name < b.name
		})
	case .Symbols:
	case .Commands:
	}
}

picker_submit :: proc(editor: ^Editor) {
	picker := &editor.picker

	if len(picker.matches) == 0 {
		editor.mode = .Normal
		return
	}

	switch picker.mode {
	case .Global_Search:
		editor.mode = .Normal
	case .Files, .Files_Recursive:
		file := picker.files[picker.matches[picker.active].id]
		if file.type == .Directory {
			picker_open(editor, .Files, strings.clone(file.fullpath, context.temp_allocator))
		} else {
			buffer_destroy(editor.buffer)
			buffer_init(editor, &editor.buffer, file.fullpath, context.allocator)
			editor.mode = .Normal
		}
	case .Symbols:
		editor.mode = .Normal
	case .Commands:
		editor.mode = .Normal
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

	if editor.mode == .Picker {
		rect := rect_from_min_max(100, screen_size - 100 - { 0, FONT_HEIGHT + padding * 2, })
		animation_set_target(&picker.rect, rect)
	} else {
		center := rect_center(rect_from_min_max(100, screen_size - 100))
		animation_set_target(&picker.rect, Rect{ min = center, max = center, })
	}

	picker_rect := animation_update(&picker.rect, delta_time, editor.config.popup_animation_speed)

	draw_rect(commands,
		offset        = picker_rect.min,
		size          = rect_size(picker_rect),
		color         = editor.config.theme[.Popup_Background].fg,
		border_color  = editor.config.theme[.Popup_Border].fg,
		border_radius = 8,
		border_width  = 2,
		shadow_width  = 16,
	)

	clip_rect := rect_inflate(picker_rect, -2)
	if clip_rect.min.x >= clip_rect.max.x || clip_rect.min.y >= clip_rect.max.y {
		return
	}

	append(commands, Draw_Command_Clip(clip_rect))
	defer append(commands, DRAW_COMMAND_CLIP_DISABLE)

	if editor.mode == .Picker {
		draw_text(
			&editor.font,
			commands,
			strings.to_string(picker.input),
			editor.config.theme[.Ident].fg,
			picker_rect.min + padding + { 0, FONT_HEIGHT, },
		)

		draw_rect(commands,
			offset = picker_rect.min + padding + { 0, FONT_HEIGHT + padding, },
			size   = { picker_rect.max.x - picker_rect.min.x - padding * 2, 2, },
			color  = editor.config.theme[.Popup_Border].fg,
		)

		line_height := padding + FONT_HEIGHT

		x := picker_rect.min.x + padding
		y := picker_rect.min.y + line_height * 2 + padding + 2

		pattern := strings.to_string(picker.input)

		x += draw_text(&editor.font, commands, ">", editor.config.theme[.Ui_Focus].fg, { x, y + line_height * f32(picker.active), }) + padding

		has_upper: bool
		for r in pattern {
			if unicode.is_upper(r) {
				has_upper = true
				break
			}
		}

		for match, match_index in picker.matches {
			pos := [2]f32{ x, y, }

			item := match.name

			text_color := editor.config.theme[match_index == picker.active ? .Ui_Focus : .Ui_Text].fg

			defer y += line_height

			if !has_upper {
				lower  := strings.to_lower(match.name, context.temp_allocator)
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
