package editor

import os      "core:os"
import strconv "core:strconv"
import strings "core:strings"
import vmem    "core:mem/virtual"

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
		window_close(editor)
	case "n", "new":
		buffer := new(Buffer)
		buffer_init_with_data(editor, buffer, "<scratch>", "\n")
		editor_open_buffer(editor, buffer)
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
	case "vs", "vsplit":
		window_split(editor, vertical = true)
	case "hs", "hsplit":
		window_split(editor, vertical = false)
	case "config-reload":
		allocator   := vmem.arena_allocator(&editor.config.arena)
		source, err := os.read_entire_file("config.ini", allocator)
		if err != nil {
			editor_set_status(editor, "Failed to read config file")
			break
		}
		ok := load_config_file(&editor.config, string(source), allocator)
		if ok {
			editor_set_status(editor, "Config reloaded")
		} else {
			editor_set_status(editor, "Failed to reload config")
		}
	case:
		editor_set_status(editor, "invalid command: '%s'", command)
	}
}
