package editor

import os      "core:os"
import strings "core:strings"
import slice   "core:slice"
import unicode "core:unicode"

Picker :: struct {
	mode:    Picker_Mode,
	input:   strings.Builder,
	rect:    Animation(Rect),
	files:   []os.File_Info,
	matches: [dynamic]Picker_Match,
	active:  int,
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

picker_open :: proc(editor: ^Editor, mode: Picker_Mode) {
	strings.builder_reset(&editor.picker.input)

	switch mode {
	case .Global_Search:
	case .Files:
		working_directory, err := os.get_working_directory(context.temp_allocator)
		if err != nil {
			editor_set_status(editor, "Failed to get current working directory: %v", err)
		}
		os.file_info_slice_delete(editor.picker.files, context.allocator)
		editor.picker.files, err = os.read_all_directory_by_path(working_directory, context.allocator)
		if err != nil {
			editor_set_status(editor, "Failed to read directory: %v", err)
		}
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
	case .Files:
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
	case .Files:
		buffer_destroy(editor.buffer)
		buffer_init(editor, &editor.buffer, picker.files[picker.matches[picker.active].id].fullpath, context.allocator)
	case .Symbols:
	case .Commands:
	}

	editor.mode = .Normal
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

	score := 1
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

picker_render :: proc(editor: ^Editor, commands: ^[dynamic]Draw_Command, delta_time, padding: f32) {
	picker      := &editor.picker
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

		y := picker_rect.min.y + (padding + FONT_HEIGHT) * 2 + padding + 2

		pattern := strings.to_string(picker.input)

		for match, match_index in picker.matches {
			pos := [2]f32{ picker_rect.min.x + padding, y, }

			item := match.name

			text_color := editor.config.theme[match_index == picker.active ? .String : .Ident].fg

			for f in pattern {
				i := strings.index_rune(item, f)
				assert(i != -1)

				pos.x += draw_text(&editor.font, commands, item[:i],     text_color,                        pos)
				pos.x += draw_text(&editor.font, commands, item[i:][:1], editor.config.theme[.Function].fg, pos)

				item = item[i + 1:]
			}

			draw_text(&editor.font, commands, item, text_color, pos)

			y += padding + FONT_HEIGHT
		}
	}
}
