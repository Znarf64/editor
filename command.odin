package editor

import os      "core:os"
import strconv "core:strconv"
import strings "core:strings"

Command :: distinct string

command_execute :: proc(editor: ^Editor, command: Command) {
	command, _, args := strings.partition(string(command), " ")

	if line_number, ok := strconv.parse_int(command); ok {
		editor.repeat_count = line_number
		action_apply(editor, .Go_To_Line, {})
		return
	}

	switch command {
	case "o", "open":
		file_open(editor, normalize_path(args, context.temp_allocator))
	case "q", "quit":
		os.exit(0)
	case "n", "new":
		buffer := new(Buffer)
		buffer^ = {
			btree = btree_build("\n", context.allocator, editor.config.tab_width),
		}
		append(&editor.buffers, buffer)
		editor.buffer = {
			selections = make([dynamic]Selection, 1, context.allocator),
			buffer     = buffer,
		}
	case "w", "write":
		buffer := editor.buffer
		if strings.contains(string(buffer.path), "test/") {
			b := strings.builder_make(context.temp_allocator)
			btree_to_string(&buffer.btree, &b)
			_ = os.write_entire_file(string(buffer.path), b.buf[:])

			editor_set_status(editor, "'%s' written.", buffer.path)
		} else {
			editor_set_status(editor, "NOTHING WRITTEN")
		}
		if lsp := editor_get_lsp_server(editor, buffer.language); lsp != nil {
			lsp_save(lsp, editor.buffer)
		}
	case:
		editor_set_status(editor, "invalid command: '%s'", command)
	}
}
