package editor

import os      "core:os"
import strings "core:strings"

Command :: distinct string

command_execute :: proc(editor: ^Editor, command: Command) {
	command, _, args := strings.partition(string(command), " ")

	switch command {
	case "o", "open":
		buffer_destroy(&editor.buffer)
		buffer_init(editor, &editor.buffer, args, context.allocator)
	case "q", "quit":
		os.exit(0)
	case "n", "new":
		buffer_destroy(&editor.buffer)
		editor.buffer = {
			selections = make([dynamic]Selection, 1, context.allocator),
			btree      = btree_build("\n", context.allocator, editor.config.tab_width),
		}
	case "w", "write":
		buffer := &editor.buffer
		if strings.contains(buffer.path, "test/") {
			b := strings.builder_make(context.temp_allocator)
			btree_to_string(&buffer.btree, &b)
			_ = os.write_entire_file(buffer.path, b.buf[:])

			editor_set_status(editor, "'%s' written.", buffer.path)
		} else {
			editor_set_status(editor, "NOTHING WRITTEN")
		}
		if lsp := editor_get_lsp_server(editor, buffer.language); lsp != nil {
			lsp_save(lsp, &editor.buffer)
		}
	}
}
