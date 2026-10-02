package editor

import strings "core:strings"
import vmem    "core:mem/virtual"

Jumplist_Entry :: struct {
	using range: Range,
	path:        Normalized_Path,
	content:     string,
}

Jumplist :: struct {
	entries: [dynamic]Jumplist_Entry,
	cursor:  int,
	arena:   vmem.Arena `fmt:"-"`,
}

jumplist_init :: proc(jumplist: ^Jumplist) {
	vmem.arena_init_growing(&jumplist.arena) or_else panic("Failed to initialize arena")
}

jumplist_destroy :: proc(jumplist: ^Jumplist) {
	vmem.arena_destroy(&jumplist.arena)
	delete(jumplist.entries)
}

jumplist_add :: proc(editor: ^Editor, selection: Selection) {
	// we should be using a linear allocator that we can reset to some point since entries will become irrelevant in a linear fashion
	allocator := vmem.arena_allocator(&editor.jumplist.arena)

	resize(&editor.jumplist.entries, editor.jumplist.cursor)
	editor.jumplist.cursor += 1

	start := min(selection.anchor, selection.cursor)
	end   := max(selection.anchor, selection.cursor)

	b := strings.builder_make(allocator)
	btree_to_string(&editor.buffer.btree, &b, start, end + 1)

	append(&editor.jumplist.entries, {
		path    = editor.buffer.path,
		start   = start,
		end     = end,
		content = strings.to_string(b),
	})
}

jumplist_forward :: proc(editor: ^Editor) {
	if editor.jumplist.cursor >= len(editor.jumplist.entries) - 1 {
		editor_set_status(editor, "End of jumplist")
		return
	}

	editor.jumplist.cursor += 1
	entry                  := editor.jumplist.entries[editor.jumplist.cursor]

	editor_go_to(editor, entry.path, entry.start, entry.end)
}

jumplist_backward :: proc(editor: ^Editor) {
	if editor.jumplist.cursor == 0 {
		editor_set_status(editor, "End of jumplist")
		return
	}

	editor.jumplist.cursor -= 1
	entry                  := editor.jumplist.entries[editor.jumplist.cursor]

	editor_go_to(editor, entry.path, entry.start, entry.end)
}


