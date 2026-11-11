package editor

import runtime "base:runtime"

import strings "core:strings"

@(require_results)
which :: proc(name: string, allocator: runtime.Allocator) -> (path: string, ok: bool) {
	if !strings.contains(name, "/") {
		return strings.clone(name, allocator), true
	}

	return _which(name, allocator)
}
