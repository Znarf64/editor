package editor

import runtime "base:runtime"

import fmt     "core:fmt"
import os      "core:os"
import strconv "core:strconv"
import strings "core:strings"
import utf8    "core:unicode/utf8"

Uri :: distinct string

@(require_results)
uri_from_path :: proc(path: string, allocator: runtime.Allocator) -> (uri: Uri, ok: bool) {
	abs, err := os.get_absolute_path(path, context.temp_allocator)
	if err != nil {
		return
	}
	when ODIN_OS == .Windows {
		if colon := strings.index(abs, ":"); colon != -1 {
			abs = abs[colon + 1:]
		}
	}
	when os.Path_Separator != '/' {
		abs, err = os.replace_path_separators(abs, '/', context.temp_allocator)
		if err != nil {
			return
		}
	}
	return Uri(fmt.aprintf("file://%v", abs, allocator = allocator)), true
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
