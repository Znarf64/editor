package editor

import os      "core:os"
import strings "core:strings"

Command :: distinct string

command_execute :: proc(editor: ^Editor, command: Command) {
	command, _, args := strings.partition(string(command), " ")

	switch command {
	case "o", "open":
		buffer_init(editor, &editor.buffer, strings.clone(args), context.allocator)
	case "q", "quit":
		os.exit(0)
	}
}
