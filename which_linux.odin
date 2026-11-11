package editor

import runtime "base:runtime"

import linux   "core:sys/linux"
import os      "core:os"
import strings "core:strings"

_which :: proc(name: string, allocator: runtime.Allocator) -> (path: string, ok: bool) {
	path_env       := os.get_env("PATH", context.temp_allocator)
	path_dirs, err := os.split_path_list(path_env, context.temp_allocator)
	if err != nil {
		return
	}

	exe_builder := strings.builder_make(allocator)

	found: bool
	for dir in path_dirs {
		strings.builder_reset(&exe_builder)
		strings.write_string(&exe_builder, dir)
		strings.write_byte(&exe_builder, '/')
		strings.write_string(&exe_builder, name)

		exe_path := strings.to_cstring(&exe_builder)
		stat: linux.Statx
		if linux.statx(linux.AT_FDCWD, exe_path, {}, { .TYPE, .MODE, }, &stat) == .NONE && .IFREG in stat.mode && .IXUSR in stat.mode {
			found = true
			break
		}
	}

	if found {
		ok   = ok
		path = strings.to_string(exe_builder)
		return
	} else {
		strings.builder_destroy(&exe_builder)
		return
	}
}
