package editor

import runtime "base:runtime"

import os      "core:os"
import strconv "core:strconv"
import strings "core:strings"
import vmem    "core:mem/virtual"
import reflect "core:reflect"

Command :: enum {
	Open = 1,
	Write,
	Quit,
	Split_Vertical,
	Split_Horizontal,
	Config_Reload,
	Config_Open,
	Config_Option_Set,
	Config_Option_Get,
	New,
	Go_To_Line,
}

Prepared_Command :: struct {
	command: Command,
	args:    []string,
}

command_to_name_table:   [Command]string
command_from_name_table: map[string]Command

@(init)
command_tables_init :: proc "contextless" () {
	context = runtime.default_context()

	for info, command in command_info_table {
		name, _ := reflect.enum_name_from_value(command)
		name     = strings.to_lower(name)
		name, _  = strings.replace(name, "_", "-", -1)
		command_to_name_table[command] = name
		command_from_name_table[name]  = command

		for alias in info.aliases {
			command_from_name_table[alias] = command
		}
	}
}

command_execute :: proc(editor: ^Editor, command: Prepared_Command) {
	switch command.command {
	case .Open:
		file_open(editor, normalize_path(command.args[0], context.temp_allocator))
	case .Quit:
		window_close(editor)
	case .New:
		buffer := new(Buffer)
		buffer_init_with_data(editor, buffer, "<scratch>", "\n")
		editor_open_buffer(editor, buffer)
	case .Write:
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
	case .Split_Vertical:
		window_split(editor, vertical = true)
	case .Split_Horizontal:
		window_split(editor, vertical = false)
	case .Config_Reload:
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
	case .Config_Open:
		dir, err := os.user_config_dir(context.temp_allocator)
		if err != nil {
			editor_set_status(editor, "Failed to get config directory")
			return
		}
		path := os.join_path({ dir, "editor", "config.ini" }, context.temp_allocator) or_else panic("Failed to concatenate path")
		file_open(editor, normalize_path(path, context.temp_allocator))
	case .Config_Option_Set:
		key   := command.args[0]
		value := command.args[1]
		section: string
		if last_dot := strings.last_index(key, "."); last_dot != -1 {
			section = key[:last_dot]
			key     = key[last_dot + 1:]
		}
		if !config_value_set(&editor.config, section, key, value) {
			editor_set_status(editor, "Failed to set config value in section `%s`: `%s = %s`", section, key, value)
		}
	case .Config_Option_Get:
		editor_set_status(editor, "unimplemented")
	case .Go_To_Line:
		line_number, _     := strconv.parse_int(command.args[0])
		editor.repeat_count = line_number
		action_apply(editor, .Go_To_Line, {})
	case:
		editor_set_status(editor, "Invalid command: '%s'", command)
	}
}

@(require_results)
parse_command :: proc(text: string, allocator: runtime.Allocator) -> (command: Prepared_Command, ok: bool) {
	if line_number, ok := strconv.parse_int(text); ok {
		args   := make([]string, 1, allocator)
		args[0] = text
		return { command = .Go_To_Line, args = args, }, true
	}

	cmd, _, args   := strings.partition(text, " ")
	command.command = command_from_name_table[cmd] or_return
	if len(args) != 0 {
		command.args = strings.split(args, " ", allocator)
	}

	info := command_info_table[command.command]

	if len(command.args) < info.args[0] || len(command.args) > info.args[1] {
		return
	}

	ok = true
	return
}

Command_Info :: struct {
	description: string,
	aliases:     []string,
	args:        [2]int,
}

@(rodata)
command_info_table: [Command]Command_Info = {
	.Open              = { aliases = { "o",   }, args = 1,         },
	.Write             = { aliases = { "w",   }, args = { 0, 1, }, },
	.Quit              = { aliases = { "q",   },                   },
	.Split_Vertical    = { aliases = { "vs",  }, args = { 0, 1, }, },
	.Split_Horizontal  = { aliases = { "hs",  }, args = { 0, 1, }, },
	.Config_Reload     = {                                         },
	.Config_Open       = {                                         },
	.Config_Option_Set = { aliases = { "set", }, args = 2,         },
	.Config_Option_Get = { aliases = { "get", }, args = 1,         },
	.New               = { aliases = { "n",   },                   },
	.Go_To_Line        = { aliases = { "g",   }, args = 1,         },
}
