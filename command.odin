package editor

import os      "core:os"
import strings "core:strings"

Command :: distinct string

command_execute :: proc(editor: ^Editor, command: Command) {
	command, _, args := strings.partition(string(command), " ")

	switch command {
	case "o", "open":
		buffer_destroy(&editor.buffer)
		buffer_init(editor, &editor.buffer, args, context.allocator, &editor.lsp)

		data := os.read_entire_file(args, context.temp_allocator) or_break

		if editor.lsp.initialized {
			lsp_open_file(&editor.lsp, args, string(data))
		}
	case "q", "quit":
		os.exit(0)
	case "n", "new":
		buffer_destroy(&editor.buffer)
		editor.buffer = {
			selections = make([dynamic]Selection, 1, context.allocator),
			btree      = btree_build("\n", context.allocator, editor.config.tab_width),
		}
	case "w", "write":
		if strings.contains(editor.buffer.path, "test/") {
			b := strings.builder_make(context.temp_allocator)
			btree_to_string(&editor.buffer.btree, &b)
			_ = os.write_entire_file(editor.buffer.path, b.buf[:])

			editor_set_status(editor, "'%s' written.", editor.buffer.path)
		} else {
			editor_set_status(editor, "NOTHING WRITTEN")
		}
		lsp_save(&editor.lsp, &editor.buffer)
	}
}
