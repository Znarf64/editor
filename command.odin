package editor

import os      "core:os"
import strings "core:strings"

Command :: distinct string

command_execute :: proc(editor: ^Editor, command: Command) {
	command, _, args := strings.partition(string(command), " ")

	switch command {
	case "o", "open":
		data := os.read_entire_file(args, context.temp_allocator) or_break
		editor.buffer = {
			btree      = btree_build(string(data), context.allocator, editor.config.tab_width),
			selections = make([dynamic]Selection, 1),
		}
	}
}
