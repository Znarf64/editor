package editor

import runtime "base:runtime"

import os      "core:os"
import strings "core:strings"

// A normalized path used to uniquely identify files, `'/'` is used as the separator regardless of the platform
Normalized_Path :: distinct string

// TODO: resolve symlinks
@(require_results)
normalize_path :: proc(path: string, allocator: runtime.Allocator) -> Normalized_Path {
	path := os.clean_path(path, context.temp_allocator) or_else panic("Failed to normalize path")

	when os.Path_Separator != '/' {
		path = os.replace_path_separators(path, '/', context.temp_allocator) or_else panic("Failed to replace path separators")
	}

	w := os.get_working_directory(context.temp_allocator) or_else panic("Failed to get working directory")

	if !os.is_absolute_path(path) {
		path = os.join_path({ w, path, }, context.temp_allocator) or_else panic("Failed to join paths")
	}

	if len(path) > len(w) && strings.has_prefix(path, w) && path[len(w)] == '/' {
		path = path[len(w) + 1:]
	}

	return Normalized_Path(strings.clone(path, allocator))
}

@(require_results)
path_clone :: proc(path: Normalized_Path, allocator: runtime.Allocator) -> Normalized_Path {
	return Normalized_Path(strings.clone(string(path)))
}

@(require_results)
path_is_absolute :: proc(path: Normalized_Path) -> bool {
	return os.is_absolute_path(string(path))
}
