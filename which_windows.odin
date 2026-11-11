package editor

import runtime "base:runtime"

import strings "core:strings"

_which :: proc(name: string, allocator: runtime.Allocator) -> (path: string, ok: bool) {
	// TODO
	return strings.clone(name, allocator), true
}
