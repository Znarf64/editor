package editor

import strings "core:strings"
import vmem    "core:mem/virtual"

import regex   "vendor/regex"

Prompt_Mode :: enum {
	Command,
	Search,
	Keep,
	Select,
}

Prompt :: struct {
	mode:           Prompt_Mode,
	input:          Input_Line,
	history:        [Prompt_Mode][dynamic]string,
	history_cursor: int,
	arena:          vmem.Arena,
}

prompt_init :: proc(prompt: ^Prompt) {
	prompt.history_cursor = -1
	vmem.arena_init_growing(&prompt.arena) or_else panic("Failed to initialize arena")
}

prompt_destroy :: proc(prompt: ^Prompt) {
	for h in prompt.history {
		delete(h)
	}
	vmem.arena_destroy(&prompt.arena)
	input_line_destroy(prompt.input)
}

prompt_apply :: proc(editor: ^Editor) {
	history := &editor.prompt.history[editor.prompt.mode]
	if len(editor.prompt.input.buffer) == 0 {
		if len(history) != 0 {
			append(&editor.prompt.input.buffer, history[len(history) - 1])
		}
	} else {
		append(history, strings.clone(input_line_get_text(editor.prompt.input), vmem.arena_allocator(&editor.prompt.arena)))
	}

	input := input_line_get_text(editor.prompt.input)

	switch editor.prompt.mode {
	case .Select:
		pattern := regex_create(editor, input) or_break

		b := strings.builder_make(context.temp_allocator)
		for selection, i in editor.buffer.selections {
			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor) + 1

			strings.builder_grow(&b, int(end - start))
			btree_to_string(&editor.buffer.btree, &b, start, end)

			regex_iter := regex.create_iterator(strings.to_string(b), pattern, permanent_allocator = context.temp_allocator)
			for capture, capture_i in regex.match(&regex_iter) {
				start_offset := btree_index_to_offset(&editor.buffer.btree, start)
				append(&editor.new_selections, {
					anchor  = btree_offset_to_index(&editor.buffer.btree, _Offset(capture.pos[0][0]) + start_offset),
					cursor  = btree_offset_to_index(&editor.buffer.btree, _Offset(capture.pos[0][1]) + start_offset) - 1,
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
			deduplicate_selections(editor.buffer)
		}
	case .Keep:
		pattern := regex_create(editor, input) or_break

		b := strings.builder_make(context.temp_allocator)

		for i := len(editor.buffer.selections) - 1; i >= 0; i -= 1 {
			selection := editor.buffer.selections[i]

			start := min(selection.cursor, selection.anchor)
			end   := max(selection.cursor, selection.anchor) + 1

			strings.builder_grow(&b, int(end - start))
			btree_to_string(&editor.buffer.btree, &b, start, end)

			_, ok := regex.match(pattern, strings.to_string(b), context.temp_allocator)
			if ok {
				append(&editor.new_selections, {
					anchor  = selection.anchor,
					cursor  = selection.cursor,
					primary = i == editor.buffer.primary,
				})
			}
			strings.builder_reset(&b)
		}

		if len(editor.new_selections) != 0 {
			editor.buffer.primary = 0
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
			deduplicate_selections(editor.buffer)
		}
	case .Search:
		regex_search(editor, editor.buffer, input)
	case .Command:
		command, ok := parse_command(input_line_get_text(editor.prompt.input), context.temp_allocator)
		if !ok {
			editor_set_status(editor, "Failed to parse command")
			break
		}
		command_execute(editor, command)
	}
	input_line_reset(&editor.prompt.input)
}
