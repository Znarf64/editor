#+vet explicit-allocators
package editor

import log     "core:log"
import os      "core:os"
import strings "core:strings"
import slice   "core:slice"
import utf8    "core:unicode/utf8"
import vmem    "core:mem/virtual"

Buffer :: struct {
	path:              Normalized_Path,
	btree:             BTree,

	undo_stack:        [dynamic]Undo_Action,
	undo_arena:        vmem.Arena,

	views:             [dynamic]^Buffer_View,

	uri:               Uri,
	language:          Language,
	diagnostics:       []Diagnostic,
	diagnostics_arena: vmem.Arena,
	version:           int,
}

Buffer_View :: struct {
	using buffer: ^Buffer,

	selections:    [dynamic]Selection,
	primary:       int,
	scroll:        int,
	scroll_anim:   Animation(f32),
	visible_lines: int,
}

buffer_view_free :: proc(view: ^Buffer_View) {
	index, found := slice.linear_search(view.buffer.views[:], view)
	assert(found)
	unordered_remove(&view.buffer.views, index)
	delete(view.selections)
	free(view, context.allocator)
}

@(require_results)
buffer_view_clone :: proc(view: Buffer_View) -> ^Buffer_View {
	view           := new_clone(view, context.allocator)
	view.selections = slice.clone_to_dynamic(view.selections[:], context.allocator)
	append(&view.buffer.views, view)
	return view
}

@(require_results)
buffer_view_new :: proc(buffer: ^Buffer) -> ^Buffer_View {
	view := new_clone(Buffer_View {
		buffer     = buffer,
		selections = make([dynamic]Selection, 1, context.allocator),
	}, context.allocator)
	append(&buffer.views, view)
	return view
}

buffer_init :: proc(editor: ^Editor, buffer: ^Buffer, path: Normalized_Path, language: Language = "") {
	data := os.read_entire_file(string(path), context.temp_allocator) or_else { '\n', }
	b    := strings.builder_make(0, len(data), context.temp_allocator)
	// iterating byte-wise is fine here
	for x in data {
		if x == '\r' {
			continue // nope
		}
		strings.write_byte(&b, x)
	}
	if len(data) == 0 || data[len(data) - 1] != '\n' {
		strings.write_byte(&b, '\n')
	}
	buffer_init_with_data(editor, buffer, path, strings.to_string(b), language)
}

buffer_init_with_data :: proc(editor: ^Editor, buffer: ^Buffer, path: Normalized_Path, data: string, language: Language = "") {
	path := path_clone(path, context.allocator)
	log.infof("Opening file '%s'", path)

	language := language
	if language == "" {
		language = get_language_from_extension(editor, path)
	}

	buffer^ = {
		path       = path,
		uri        = uri_from_path(path, context.allocator),
		btree      = btree_build(string(data), context.allocator),
		undo_stack = make([dynamic]Undo_Action, context.allocator),
		views      = make([dynamic]^Buffer_View, context.allocator),
		language   = language,
	}
	vmem.arena_init_growing(&buffer.diagnostics_arena) or_else panic("Failed to initialize arena")
	vmem.arena_init_growing(&buffer.undo_arena       ) or_else panic("Failed to initialize arena")

	if lsp := editor_get_lsp_server(editor, language); lsp != nil {
		lsp_open_file(lsp, buffer.uri, data)
	}
	append(&editor.buffers, buffer)
}

buffer_destroy :: proc(buffer: ^Buffer) {
	vmem.arena_destroy(&buffer.diagnostics_arena)
	vmem.arena_destroy(&buffer.undo_arena)
	delete(buffer.undo_stack)
	delete(buffer.views)
	btree_destroy(buffer.btree)
	delete(string(buffer.path), context.allocator)
	delete(string(buffer.uri), context.allocator)
}

Undo_Action_Remove :: struct {
	start: Index,
	s:     string,
}

Undo_Action_Insert :: struct {
	start, end: Index,
}

Undo_Action :: union {
	Undo_Action_Insert,
	Undo_Action_Remove,
}

undo_register_remove :: proc(buffer: ^Buffer, start, end: Index) {
	b := strings.builder_make(vmem.arena_allocator(&buffer.undo_arena))
	btree_to_string(&buffer.btree, &b, start, end)
	append(&buffer.undo_stack, Undo_Action_Remove {
		start = start,
		s     = strings.to_string(b),
	})
}

undo_register_insert :: proc(buffer: ^Buffer, start: Index, s: string) {
	append(&buffer.undo_stack, Undo_Action_Insert {
		start = start,
		end   = start + Index(strings.rune_count(s)),
	})
}

undo_action :: proc(editor: ^Editor, buffer: ^Buffer_View, action: Undo_Action) {
	switch v in action {
	case Undo_Action_Insert:
		_buffer_remove(editor, buffer, v.start, v.end)
	case Undo_Action_Remove:
		_buffer_insert(editor, buffer, v.s, v.start)
	}
}

buffer_undo :: proc(editor: ^Editor, buffer: ^Buffer_View) -> bool {
	action := pop_safe(&buffer.undo_stack) or_return
	undo_action(editor, buffer, action)
	return true
}

buffer_redo :: proc(editor: ^Editor, buffer: ^Buffer_View) -> bool {
	return false
}

buffer_remove :: proc(editor: ^Editor, buffer: ^Buffer, start, end: Index) {
	undo_register_remove(buffer, start, end)
	_buffer_remove(editor, buffer, start, end)
}

_buffer_remove :: proc(editor: ^Editor, buffer: ^Buffer, start, end: Index) {
	buffer.version += 1
	if lsp := editor_get_lsp_server(editor, buffer.language); lsp != nil {
		lsp_apply_change(lsp, buffer, start, end, "", buffer.version)
	}

	btree_remove_range(&buffer.btree, start, end)
	for view in buffer.views {
		for &selection in view.selections {
			if selection.cursor > start {
				selection.cursor -= end - start
			}
			if selection.anchor > start {
				selection.anchor -= end - start
			}
		}
	}
}

buffer_insert :: proc {
	buffer_insert_rune,
	buffer_insert_string,
}

buffer_insert_rune :: proc(editor: ^Editor, buffer: ^Buffer_View, index: Index, r: rune) -> Index {
	buf, n := utf8.encode_rune(r)
	return buffer_insert_string(editor, buffer, index, string(buf[:n]))
}

buffer_insert_string :: proc(editor: ^Editor, buffer: ^Buffer_View, index: Index, s: string) -> Index {
	undo_register_insert(buffer, index, s)
	return _buffer_insert_string(editor, buffer, index, s)
}

_buffer_insert :: proc(editor: ^Editor, buffer: ^Buffer_View, arg: string, index: Index) -> Index {
	if lsp := editor_get_lsp_server(editor, buffer.language); lsp != nil {
		lsp_apply_change(lsp, buffer, index, index, arg, buffer.version)
		for char in (lsp.capabilities.signatureHelpProvider.? or_else {}).triggerCharacters {
			if strings.contains(arg, char) {
				lsp_get_signature_help(editor, buffer)
				break
			}
		}
		// needs_completion: bool
		// for char in s {
		// 	if char == '_' || unicode.is_letter(char) || unicode.is_digit(char) {
		// 		needs_completion = true
		// 		break
		// 	}
		// }
		// for char in (lsp.capabilities.completionProvider.? or_else {}).triggerCharacters {
		// 	if strings.contains(s, char) {
		// 		needs_completion = true
		// 		break
		// 	}
		// }
		// if needs_completion {
		// 	lsp_get_completion(editor, buffer)
		// }
	}

	runes, _ := btree_insert(&buffer.btree, index, arg)
	for view in buffer.views {
		for &selection in view.selections {
			if selection.cursor >= index {
				selection.cursor += runes
			}
			if selection.anchor >= index {
				selection.anchor += runes
			}
		}
	}
	for &diagnostic in buffer.diagnostics {
		if diagnostic.start >= index {
			diagnostic.start += runes
		}
		if diagnostic.end >= index {
			diagnostic.end += runes
		}
	}
	return runes
}

_buffer_insert_string :: proc(editor: ^Editor, buffer: ^Buffer_View, index: Index, s: string) -> Index {
	buffer.version += 1
	return _buffer_insert(editor, buffer, s, index)
}
