package editor

import runtime "base:runtime"

import os      "core:os"
import strconv "core:strconv"
import strings "core:strings"
import utf8    "core:unicode/utf8"

Uri :: distinct string

@(require_results)
uri_from_path :: proc(path: Normalized_Path, allocator: runtime.Allocator) -> (uri: Uri) {
	b := strings.builder_make(0, len(path) + 7, allocator)
	strings.write_string(&b, "file://")
	if !path_is_absolute(path) {
		wd := os.get_working_directory(context.temp_allocator) or_else panic("Failed to get working directory")
		if ODIN_OS == .Windows {
			strings.write_string(&b, "/")
		}
		strings.write_string(&b, wd)
		strings.write_string(&b, "/")
	}
	strings.write_string(&b, string(path))
	return Uri(strings.to_string(b))
}

@(require_results)
uri_to_path :: proc(uri: Uri, allocator: runtime.Allocator) -> (path: string, ok: bool) {
	when ODIN_OS == .Windows {
		FILE_PREFIX :: "file:///"
	} else {
		FILE_PREFIX :: "file://"
	}
	if !strings.has_prefix(string(uri), FILE_PREFIX) {
		return
	}
	uri := strings.trim_prefix(string(uri), FILE_PREFIX)
	b   := strings.builder_make(0, len(uri), allocator)

	for len(uri) > 0 {
		r, n := utf8.decode_rune(uri)
		if r == utf8.RUNE_ERROR {
			return
		}
		uri = uri[n:]

		switch r {
		case '%':
			if len(uri) < 2 {
				return
			}
			value := strconv.parse_int(uri[:2], base = 16) or_return
			strings.write_byte(&b, byte(value))
			uri = uri[2:]
		case '\\':
			strings.write_rune(&b, '/')
		case:
			strings.write_rune(&b, r)
		}
	}

	return strings.to_string(b), true
}

@(require_results)
uri_clone :: proc(uri: Uri, allocator: runtime.Allocator) -> Uri {
	return Uri(strings.clone(string(uri), allocator))
}
