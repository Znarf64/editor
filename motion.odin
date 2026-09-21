package editor

import runtime "base:runtime"

import reflect "core:reflect"
import strings "core:strings"
import unicode "core:unicode"
import utf8    "core:unicode/utf8"
import vmem    "core:mem/virtual"

// A motion applied only to the primary selection
Primary_Motion :: enum {
	Show_Hover_Information,
	Show_Code_Actions,
	Go_To_Definition,

	Jumplist_Forward,
	Jumplist_Backward,

	Search_Next,
	Search_Previous,
	Set_Search,
}

// A motion applied to every selection
Selection_Motion :: enum {
	Cursor_Page_Up = 1,
	Cursor_Page_Down,
	Cursor_Half_Page_Up,
	Cursor_Half_Page_Down,

	Go_To_Matching,
	Match_In_Word,
	Match_In_Long_Word,
	Match_In_Paragraph,
	Match_In_Change,
	Match_Around_Paragraph,
	Match_Around_Word,

	Match_In_Curly,
	Match_In_Paren,
	Match_In_Bracket,
	Match_In_Angled,
	Match_In_Quote,
	Match_In_Single_Quote,
	Match_Around_Curly,
	Match_Around_Paren,
	Match_Around_Bracket,
	Match_Around_Angled,
	Match_Around_Quote,
	Match_Around_Single_Quote,

	Go_To_Line,
	Go_To_File_End,
	Go_To_Line_Start,
	Go_To_Line_End,
	Go_To_Line_Start_Non_Whitespace,

	Character_Down,
	Character_Up,
	Character_Left,
	Character_Right,

	Select_All,
	Select_Line,
	Select_Word_Forward,
	Select_Word_End_Forward,
	Select_Word_Backward,
	Select_Long_Word_Forward,
	Select_Long_Word_End_Forward,
	Select_Long_Word_Backward,

	Case_Swap,

	Case_To_Lower,
	Case_To_Upper,
	Case_To_Caml,
	Case_To_Pascal,
	Case_To_Snake,
	Case_To_Screaming_Snake,

	Delete,

	Paste,
	Paste_Before,
	Paste_System_Before,
	Yank,
	Paste_System,
	Yank_System,

	Insert,
	Append,
	Visual,
	Normal,

	Change,

	Insert_Newline,
	Insert_Tab,

	Indent,
	Outdent,

	Selections_Align,

	Open_Below,
	Open_Above,

	Collapse_Selection,
	Keep_Primary_Selection,
	Create_Selection_Below,

	Toggle_Comment,

	Keep_Selections,
	Select,

	Flip_Selection,

	Split_Lines,
}

// A motion independent of selections
Motion :: enum {
	View_Line_Down,
	View_Line_Up,
	View_Page_Up,
	View_Page_Down,
	View_Half_Page_Up,
	View_Half_Page_Down,

	Open_File,
	Search_Global,
	Search_Symbols,
	Command_Palette,
	Diagnostics,
	Buffers,
	Jumplist,

	Window_Focus_Left,
	Window_Focus_Right,
	Window_Focus_Above,
	Window_Focus_Below,
	Window_Move_Left,
	Window_Move_Right,
	Window_Move_Above,
	Window_Move_Below,
	Window_Transpose,

	Save,
	Save_As,

	Close_File,

	Search,
	Command,
}

Argument_Motion :: enum {
	Insert_Character,
	Replace,
	Find,
	Find_Backward,

	Surround_Add,
	Surround_Delete,
	Surround_Replace,
}

motion_from_name_table: map[string]Motion
motion_to_name_table:   [Motion]string

argument_motion_from_name_table: map[string]Argument_Motion
argument_motion_to_name_table:   [Argument_Motion]string

selection_motion_from_name_table: map[string]Selection_Motion
selection_motion_to_name_table:   [Selection_Motion]string

primary_motion_from_name_table: map[string]Primary_Motion
primary_motion_to_name_table:   [Primary_Motion]string

@(require_results)
canonicalize_motion_name :: proc(s: string, b: ^strings.Builder) -> string {
	strings.builder_reset(b)

	for r in s {
		r := unicode.to_lower(r)
		if r == ' ' || r == '_' {
			r = '-'
		}
		strings.write_rune(b, r)
	}

	return strings.to_string(b^)
}

@(init)
initialize_motion_names :: proc "contextless" () {
	context = runtime.default_context()

	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena)
	assert(err == nil)

	allocator := vmem.arena_allocator(&arena)

	motion_from_name_table = make(map[string]Motion, len(Motion), allocator)
	b                     := strings.builder_make(allocator)

	for field in reflect.enum_fields_zipped(Motion) {
		name                                     := canonicalize_motion_name(field.name, &b)
		name                                      = strings.clone(name, allocator)
		motion_from_name_table[name]              = Motion(field.value)
		motion_to_name_table[Motion(field.value)] = name
	}

	for field in reflect.enum_fields_zipped(Primary_Motion) {
		name                                                     := canonicalize_motion_name(field.name, &b)
		name                                                      = strings.clone(name, allocator)
		primary_motion_from_name_table[name]                      = Primary_Motion(field.value)
		primary_motion_to_name_table[Primary_Motion(field.value)] = name
	}

	for field in reflect.enum_fields_zipped(Selection_Motion) {
		name                                                         := canonicalize_motion_name(field.name, &b)
		name                                                          = strings.clone(name, allocator)
		selection_motion_from_name_table[name]                        = Selection_Motion(field.value)
		selection_motion_to_name_table[Selection_Motion(field.value)] = name
	}

	for field in reflect.enum_fields_zipped(Argument_Motion) {
		name                                                       := canonicalize_motion_name(field.name, &b)
		name                                                        = strings.clone(name, allocator)
		argument_motion_from_name_table[name]                       = Argument_Motion(field.value)
		argument_motion_to_name_table[Argument_Motion(field.value)] = name
	}

	return
}

@(require_results)
parse_motion :: proc(s: string) -> (motion: Action, ok: bool) {
	b         := strings.builder_make(0, len(s), context.temp_allocator)
	name      := canonicalize_motion_name(s, &b)

	motion, ok = motion_from_name_table[name]
	if ok {
		return
	}

	motion, ok = selection_motion_from_name_table[name]
	if ok {
		return
	}

	motion, ok = argument_motion_from_name_table[name]
	if ok {
		return
	}

	return primary_motion_from_name_table[name]
}

argument_motion_apply :: proc(editor: ^Editor, buffer: ^Buffer_View, motion: Argument_Motion, arg: rune) {
	for &selection in buffer.selections {
		argument_motion_apply_single(editor, buffer, &selection, motion, arg)
	}
}

argument_motion_apply_single :: proc(editor: ^Editor, buffer: ^Buffer_View, selection: ^Selection, motion: Argument_Motion, arg: rune) {
	vertical_move: bool
	defer if !vertical_move {
		selection.target_cursor = selection.cursor
	}

	switch motion {
	case .Find:
		selection.anchor = selection.cursor

		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		_, _  = btree_iter(&iter)
		for r in btree_iter(&iter) {
			if r == arg {
				selection.cursor = iter.index
				break
			}
		}
	case .Find_Backward:
		selection.anchor = selection.cursor

		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		_, _  = btree_iter(&iter, back = true)
		for r in btree_iter(&iter, back = true) {
			if r == arg {
				selection.cursor = iter.index
				break
			}
		}
	case .Replace:
	case .Insert_Character:
		buffer_insert(editor, buffer, selection.cursor, arg)
	case .Surround_Add:
		end := arg
		switch arg {
		case '(':
			end = ')'
		case '[':
			end = ']'
		case '{':
			end = '}'
		case '<':
			end = '>'
		}
		buffer_insert(editor, buffer, min(selection.cursor, selection.anchor),     arg)
		buffer_insert(editor, buffer, max(selection.cursor, selection.anchor) + 1, end)

		if selection.cursor < selection.anchor {
			selection.cursor -= 1
			selection.anchor += 1
		} else {
			selection.cursor += 1
			selection.anchor -= 1
		}
	case .Surround_Delete:
		unimplemented()
	case .Surround_Replace:
		unimplemented()
	}
}

buffer_remove :: proc(buffer: ^Buffer_View, start, end: Index) {
	btree_remove_range(&buffer.btree, start, end)
	for &selection in buffer.selections {
		if selection.cursor >= start {
			selection.cursor -= start - end
		}
		if selection.anchor >= start {
			selection.anchor -= start - end
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
	_buffer_insert :: proc(buffer: ^Buffer_View, arg: string, index: Index) -> Index {
		runes, bytes := btree_insert(&buffer.btree, index, arg)
		for &selection in buffer.selections {
			if selection.cursor >= index {
				selection.cursor += runes
			}
			if selection.anchor >= index {
				selection.anchor += runes
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

	buffer.version += 1
	if lsp := editor_get_lsp_server(editor, buffer.language); lsp != nil {
		lsp_apply_change(lsp, buffer, index, index, s, buffer.version)
		for char in (lsp.capabilities.signatureHelpProvider.? or_else {}).triggerCharacters {
			if strings.contains(s, char) {
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
	return _buffer_insert(buffer, s, index)
}

@(require_results)
position_to_index_normalized :: proc(buffer: ^Buffer, position: Position, vertical_move: bool, selection: ^Selection, tab_width: int) -> bool {
	position := Position {
		line   = clamp(position.line, 0, int(buffer.btree.lines) - 1),
		column = max(position.column, 0),
	}
	if vertical_move {
		position.column = btree_index_to_position(&buffer.btree, selection.target_cursor, tab_width).column
	}
	line_start := btree_line_to_index(&buffer.btree, position.line)
	iter       := btree_iterator(&buffer.btree, line_start)

	p: Position
	for r, _ in btree_iter(&iter, &p, tab_width) {
		if p.column > position.column || r == '\n' {
			break
		}
	}
	selection.cursor = iter.index

	return vertical_move
}

motion_apply :: proc(editor: ^Editor, buffer: ^Buffer_View, motion: Motion) {
	switch motion {
	case .View_Line_Up:
		buffer.scroll -= editor.repeat_count
	case .View_Line_Down:
		buffer.scroll += editor.repeat_count
	case .View_Half_Page_Up:
		buffer.scroll -= buffer.visible_lines / 2
	case .View_Half_Page_Down:
		buffer.scroll += buffer.visible_lines / 2
	case .View_Page_Up:
		buffer.scroll -= buffer.visible_lines
	case .View_Page_Down:
		buffer.scroll += buffer.visible_lines

	case .Search:
		editor.mode        = .Prompt
		editor.prompt.mode = .Search
	case .Command:
		editor.mode        = .Prompt
		editor.prompt.mode = .Command

	case .Search_Global:
		picker_open(editor, .Global_Search)
	case .Search_Symbols:
		picker_open(editor, .Symbols)
	case .Command_Palette:
		picker_open(editor, .Commands)
	case .Diagnostics:
		picker_open(editor, .Diagnostics)
	case .Buffers:
		picker_open(editor, .Buffers)
	case .Jumplist:
		picker_open(editor, .Jumplist)

	case .Save:
		unimplemented()
	case .Save_As:
		unimplemented()

	case .Open_File:
		picker_open(editor, .Files_Recursive)
	case .Close_File:
		unimplemented()

	case .Window_Focus_Left:
		window_focus(editor, true, false)
	case .Window_Focus_Right:
		window_focus(editor, true, true)
	case .Window_Focus_Above:
		window_focus(editor, false, false)
	case .Window_Focus_Below:
		window_focus(editor, false, true)

	case .Window_Move_Left:
		window_move(editor, true, false)
	case .Window_Move_Right:
		window_move(editor, true, true)
	case .Window_Move_Above:
		window_move(editor, false, false)
	case .Window_Move_Below:
		window_move(editor, false, true)

	case .Window_Transpose:
		window_transpose(editor)
	}
}

primary_motion_apply :: proc(editor: ^Editor, buffer: ^Buffer_View, selection: ^Selection, motion: Primary_Motion) {
	defer selection.anchor = clamp(selection.anchor, 0, buffer.btree.chars)
	defer selection.cursor = clamp(selection.cursor, 0, buffer.btree.chars)

	switch motion {
	case .Show_Hover_Information:
		lsp_get_hover_information(editor, buffer)
	case .Go_To_Definition:
		jumplist_add(editor, selection^)
		lsp_go_to_definition(editor, buffer)
	case .Show_Code_Actions:
		unimplemented()

	case .Search_Next:
		history := editor.prompt.history[.Search]
		if len(history) == 0 {
			break
		}
		regex_search(editor, buffer, history[len(history) - 1])
	case .Search_Previous:
		history := editor.prompt.history[.Search]
		if len(history) == 0 {
			break
		}
		regex_search_reverse(editor, buffer, history[len(history) - 1])
	case .Set_Search:
		start := min(selection.anchor, selection.cursor)
		end   := max(selection.anchor, selection.cursor)
		b     := strings.builder_make(0, int(end - start), context.temp_allocator)
		iter  := btree_iterator(&buffer.btree, index = min(selection.anchor, selection.cursor))

		@(require_results)
		is_word_class :: #force_inline proc "contextless" (r: rune) -> bool {
			switch r {
			case '0'..='9', 'A'..='Z', '_', 'a'..='z':
				return true
			case:
				return false
			}
		}

		if prev, ok := btree_iter(&iter, back = true); ok {
			_, _      = btree_iter(&iter)
			first, _ := btree_iter(&iter)
			_, _      = btree_iter(&iter, back = true)

			if is_word_class(first) != is_word_class(prev) {
				strings.write_string(&b, "\\b")
			}
		}

		prev: rune
		for r in btree_iter(&iter) {
			if iter.index > max(selection.anchor, selection.cursor) {
				if is_word_class(r) != is_word_class(prev) {
					strings.write_string(&b, "\\b")
				}
				break
			}
			switch r {
			case '{', '}', '(', ')', '^', '|', '*', '+', '?', '[', ']', '.', '$':
				strings.write_string(&b, "\\")
			}
			strings.write_escaped_rune(&b, r, '\\')
			prev = r
		}

		s := strings.to_string(b)

		history := &editor.prompt.history[.Search]
		if len(history) != 0 && history[len(history) - 1] == s {
			break
		}
		append(history, strings.clone(s, vmem.arena_allocator(&editor.prompt.arena)))
	case .Jumplist_Forward:
		jumplist_forward(editor)
	case .Jumplist_Backward:
		jumplist_backward(editor)
	}
}

selection_motion_apply :: proc(editor: ^Editor, buffer: ^Buffer_View, selection: ^Selection, motion: Selection_Motion, primary: bool) {
	indent :: proc(editor: ^Editor, buffer: ^Buffer_View, index: Index, n: int) {
		N :: BTREE_LEAF_SIZE
		@(static, rodata)
		tab_buf: [N]u8 = '\t'

		n := n
		for n > 0 {
			buffer_insert(editor, buffer, index, string(tab_buf[:min(n, N)]))
			n -= N
		}
	}

	vertical_move: bool
	defer if !vertical_move {
		selection.target_cursor = selection.cursor
	}

	defer selection.anchor = clamp(selection.anchor, 0, buffer.btree.chars)
	defer selection.cursor = clamp(selection.cursor, 0, buffer.btree.chars)

	switch motion {
	case .Cursor_Half_Page_Up:
		position        := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		position.line   -= buffer.visible_lines / 2
		vertical_move    = position_to_index_normalized(buffer, position, true, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Cursor_Half_Page_Down:
		position        := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		position.line   += buffer.visible_lines / 2
		vertical_move    = position_to_index_normalized(buffer, position, true, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Cursor_Page_Up:
		position        := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		position.line   -= buffer.visible_lines
		vertical_move    = position_to_index_normalized(buffer, position, true, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Cursor_Page_Down:
		position        := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		position.line   += buffer.visible_lines
		vertical_move    = position_to_index_normalized(buffer, position, true, selection, editor.config.tab_width)
		selection.anchor = selection.cursor

	case .Go_To_Matching:
		iter  := btree_iterator(&buffer.btree, index = selection.cursor)
		start := btree_iter(&iter) or_break

		back := false

		delim := start
		switch start {
		case '(':
			delim = ')'
		case '{':
			delim = '}'
		case '[':
			delim = ']'
		case '"':
			delim = '"'
		case '\'':
			delim = '\''
		case '<':
			delim = '<'

		case ')':
			delim = '('
			back  = true
		case '}':
			delim = '{'
			back  = true
		case ']':
			delim = '['
			back  = true
		case '>':
			delim = '<'
			back  = true
		}

		depth := 1

		if back {
			_, _ = btree_iter(&iter, back = true)
		}

		for r in btree_iter(&iter, back) {
			if r == delim {
				depth -= 1
			} else if r == start {
				depth += 1
			}

			if depth == 0 {
				break
			}
		}

		selection.cursor = iter.index
		selection.anchor = selection.cursor

	case .Match_Around_Word:
		unimplemented()
	case .Match_In_Word:
		start_index := selection.cursor

		back := btree_iterator(&buffer.btree, index = start_index)
		iter := btree_iterator(&buffer.btree, index = start_index)

		for r in btree_iter(&back, back = true) {
			if !unicode.is_letter(r) && !unicode.is_number(r) && r != '_' {
				break
			}
			start_index = back.index
		}

		selection.anchor = start_index

		end_index := start_index
		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_number(r) && r != '_' {
				break
			}
			end_index = iter.index
		}

		selection.cursor = end_index

	case .Match_In_Long_Word:
		start_index := selection.cursor

		back := btree_iterator(&buffer.btree, index = start_index)
		iter := btree_iterator(&buffer.btree, index = start_index)

		for r in btree_iter(&back, back = true) {
			if unicode.is_space(r) {
				break
			}
			start_index = back.index
		}

		selection.anchor = start_index

		end_offset := start_index
		for r in btree_iter(&iter) {
			if unicode.is_space(r) {
				break
			}
			end_offset = iter.index
		}

		selection.cursor = end_offset

	case .Match_In_Paragraph, .Match_Around_Paragraph:
		back := btree_iterator(&buffer.btree, index = selection.cursor)
		iter := btree_iterator(&buffer.btree, index = selection.cursor)

		selection.anchor = 0
		last_was_newline: bool
		for r in btree_iter(&back, back = true) {
			if r == '\n' {
				if last_was_newline {
					selection.anchor = back.index + 2
					break
				}
				last_was_newline = true
			} else {
				last_was_newline = false
			}
		}

		last_was_newline = false
		for r in btree_iter(&iter) {
			if r == '\n' {
				if last_was_newline {
					break
				}
				last_was_newline = true
			} else {
				last_was_newline = false
			}
		}

		if motion == .Match_In_Paragraph {
			selection.cursor = iter.index - 1
		} else {
			selection.cursor = iter.index
		}

	case .Match_In_Curly, .Match_In_Paren, .Match_In_Bracket, .Match_In_Angled, .Match_In_Quote, .Match_In_Single_Quote:
		selection_motion_apply(editor, buffer, selection, motion + .Match_Around_Paren - .Match_In_Paren, primary)
		selection.cursor -= 1
		selection.anchor += 1

	case .Match_Around_Curly, .Match_Around_Paren, .Match_Around_Bracket, .Match_Around_Angled, .Match_Around_Quote, .Match_Around_Single_Quote:
		back := btree_iterator(&buffer.btree, index = selection.cursor)
		iter := btree_iterator(&buffer.btree, index = selection.cursor)

		start, end: rune
		#partial switch motion {
		case .Match_Around_Curly:
			start, end = '{', '}'
		case .Match_Around_Paren:
			start, end = '(', ')'
		case .Match_Around_Bracket:
			start, end = '[', ']'
		case .Match_Around_Angled:
			start, end = '<', '>'
		case .Match_Around_Quote:
			start, end = '"', '"'
		case .Match_Around_Single_Quote:
			start, end = '\'', '\''
		case:
			unreachable()
		}

		balance := 1
		for r in btree_iter(&back, back = true) {
			if r == start {
				balance -= 1
			} else if r == end {
				balance += 1
			}
			if balance == 0 {
				break
			}
		}

		selection.anchor = back.index

		balance = 1
		for r in btree_iter(&iter) {
			if r == end {
				balance -= 1
			} else if r == start {
				balance += 1
			}
			if balance == 0 {
				break
			}
		}

		selection.cursor = iter.index

	case .Match_In_Change:
		unimplemented()

	case .Go_To_Line:
		jumplist_add(editor, selection^)
		vertical_move    = position_to_index_normalized(buffer, { line = editor.repeat_count - 1, }, false, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Go_To_File_End:
		jumplist_add(editor, selection^)
		vertical_move    = position_to_index_normalized(buffer, { line = int(buffer.btree.lines) - 1, }, false, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Go_To_Line_Start:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				selection.cursor = iter.index + 1
				selection.anchor = selection.cursor
				return
			}
		}
		selection.cursor = 0
		selection.anchor = 0
	case .Go_To_Line_End:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		for r in btree_iter(&iter) {
			if r == '\n' {
				selection.cursor = iter.index - 1
				break
			}
		}
		selection.anchor = selection.cursor
	case .Go_To_Line_Start_Non_Whitespace:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		space_only := true
		for r in btree_iter(&iter, back = true) {
			is_space    := unicode.is_space(r)
			space_only &&= is_space
			if !is_space {
				selection.cursor = iter.index
				selection.anchor = selection.cursor
			}
			if r == '\n' {
				if space_only {
					iter := btree_iterator(&buffer.btree, index = selection.cursor)
					for r in btree_iter(&iter) {
						if !unicode.is_space(r) {
							selection.cursor = iter.index
							selection.anchor = selection.cursor
							return
						}
					}
				}
				return
			}
		}
		selection.cursor = 0
		selection.anchor = 0

	case .Character_Down:
		position        := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		position.line   += editor.repeat_count
		vertical_move    = position_to_index_normalized(buffer, position, true, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Character_Up:
		position        := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		position.line   -= editor.repeat_count
		vertical_move    = position_to_index_normalized(buffer, position, true, selection, editor.config.tab_width)
		selection.anchor = selection.cursor
	case .Character_Left:
		selection.cursor = selection.cursor - Index(editor.repeat_count)
		selection.anchor = selection.cursor
	case .Character_Right:
		selection.cursor = selection.cursor + Index(editor.repeat_count)
		selection.anchor = selection.cursor

	case .Select_Line:
		if selection.cursor < selection.anchor {
			selection.cursor, selection.anchor = selection.anchor, selection.cursor
		}

		prev := selection^

		back := btree_iterator(&buffer.btree, index = selection.anchor)
		iter := btree_iterator(&buffer.btree, index = selection.cursor)

		selection.anchor = 0
		for r in btree_iter(&back, back = true) {
			if r == '\n' {
				selection.anchor = back.index + 1
				break
			}
		}

		for r in btree_iter(&iter) {
			if r == '\n' {
				break
			}
		}
		selection.cursor = iter.index

		n := editor.repeat_count
		if prev != selection^ {
			n -= 1
		}

		for _ in 0 ..< n {
			for r in btree_iter(&iter) {
				if r == '\n' {
					break
				}
			}
		}
		selection.cursor = iter.index

	case .Select_All:
		selection.anchor = 0
		vertical_move    = position_to_index_normalized(buffer, { line = int(buffer.btree.lines) - 1, }, false, selection, editor.config.tab_width)
	case .Select_Word_End_Forward:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.index
		selection.cursor = iter.index + 1

		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			} else {
				selection.cursor = iter.index
			}
		}

	case .Select_Word_Forward:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.index

		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			}
		}

		selection.cursor = iter.index
	case .Select_Word_Backward:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		r    := btree_iter(&iter, back = true) or_break

		selection.anchor = selection.cursor

		if unicode.is_space(r) {
			for r in btree_iter(&iter, back = true) {
				if !unicode.is_space(r) {
					break
				}
			}
		}

		for r in btree_iter(&iter, back = true) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			}
		}

		_, _ = btree_iter(&iter)
		_, _ = btree_iter(&iter)

		selection.cursor = iter.index

	case .Select_Long_Word_Forward:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.index

		for r in btree_iter(&iter) {
			if unicode.is_space(r) {
				break
			}
		}

		selection.cursor = iter.index

	case .Select_Long_Word_End_Forward:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.index
		selection.cursor = iter.index + 1

		for r in btree_iter(&iter) {
			if unicode.is_space(r) {
				break
			} else {
				selection.cursor = iter.index
			}
		}

	case .Select_Long_Word_Backward:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		r    := btree_iter(&iter, back = true) or_break

		selection.anchor = selection.cursor

		if unicode.is_space(r) {
			for r in btree_iter(&iter, back = true) {
				if !unicode.is_space(r) {
					break
				}
			}
		}

		for r in btree_iter(&iter, back = true) {
			if unicode.is_space(r) {
				break
			}
		}

		_, _ = btree_iter(&iter)
		_, _ = btree_iter(&iter)

		selection.cursor = iter.index

	case .Case_Swap:
		unimplemented()
	case .Case_To_Lower:
		unimplemented()
	case .Case_To_Upper:
		unimplemented()
	case .Case_To_Caml:
		unimplemented()
	case .Case_To_Pascal:
		unimplemented()
	case .Case_To_Snake:
		unimplemented()
	case .Case_To_Screaming_Snake:
		unimplemented()

	case .Delete:
		start, end := min(selection.anchor, selection.cursor), max(selection.anchor, selection.cursor)
		buffer_remove(buffer, start, end + 1)

	case .Paste:
		end := max(selection.anchor, selection.cursor) + 1
		n   := buffer_insert(editor, buffer, end, strings.to_string(editor.clipboard))
		selection.anchor += n
		selection.cursor += n
	case .Paste_System:
		end := max(selection.anchor, selection.cursor) + 1
		s   := editor.backend->get_clipboard(context.temp_allocator)
		n   := buffer_insert(editor, buffer, end, s)
		selection.anchor += n
		selection.cursor += n
	case .Paste_Before:
		saved := selection^
		buffer_insert(editor, buffer, min(selection.anchor, selection.cursor), strings.to_string(editor.clipboard))
		selection^ = saved
	case .Paste_System_Before:
		saved := selection^
		buffer_insert(editor, buffer, min(selection.anchor, selection.cursor), editor.backend->get_clipboard(context.temp_allocator))
		selection^ = saved
	case .Yank, .Yank_System:
		primary or_break

		start := min(selection.anchor, selection.cursor)
		end   := max(selection.anchor, selection.cursor) + 1

		if motion == .Yank_System {
			b := strings.builder_make(0, int(end - start), context.temp_allocator)
			btree_to_string(&buffer.btree, &b, start, end)
			editor.backend->set_clipboard(strings.to_string(b))
			editor_set_status(editor, "yanked to system clipboard")
		} else {
			strings.builder_reset(&editor.clipboard)
			editor_set_status(editor, "yanked to clipboard")
			btree_to_string(&buffer.btree, &editor.clipboard, start, end)
		}

	case .Insert:
		if selection.cursor > selection.anchor {
			selection.cursor, selection.anchor = selection.anchor, selection.cursor
		}
		editor.mode = .Insert
	case .Append:
		if selection.cursor < selection.anchor {
			selection.cursor, selection.anchor = selection.anchor, selection.cursor
		}

		iter            := btree_iterator(&buffer.btree, index = selection.cursor)
		_                = btree_iter(&iter) or_break
		_                = btree_iter(&iter) or_break
		selection.cursor = iter.index

		editor.mode      = .Insert
	case .Visual:
		editor.mode = .Visual
	case .Normal:
		editor.mode = .Normal
	case .Insert_Newline:
		line := btree_index_to_line(&buffer.btree, selection.cursor)
		iter := btree_iterator(&buffer.btree, btree_line_to_index(&buffer.btree, line))

		indentation: int
		for r in btree_iter(&iter) {
			if r != '\t' {
				break
			}
			indentation += 1
		}

		switch r := btree_get_rune(buffer.btree, selection.cursor - 1); r {
		case '(', '{', '[':
			indentation += 1
		}

		buffer_insert(editor, buffer, selection.cursor, '\n')
		indent(editor, buffer, selection.cursor, indentation)
	case .Insert_Tab:
		buffer_insert(editor, buffer, selection.cursor, '\t')

	case .Open_Below:
		selection_motion_apply(editor, buffer, selection, .Go_To_Line_End,  primary)
		selection_motion_apply(editor, buffer, selection, .Character_Right, primary)
		selection_motion_apply(editor, buffer, selection, .Insert_Newline,  primary)
		editor.mode = .Insert

	case .Open_Above:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				break
			}
		}

		buffer_insert(editor, buffer, iter.index, '\n')

		if iter.index == 0 {
			selection.cursor = 0
			selection.anchor = 0
		} else {
			selection.cursor = iter.index + 1
			selection.anchor = selection.cursor
		}

		editor.mode = .Insert
	case .Change:
		start, end := min(selection.anchor, selection.cursor), max(selection.anchor, selection.cursor)
		buffer_remove(buffer, start, end + 1)
		editor.mode = .Insert

	case .Indent:
		start := min(selection.cursor, selection.anchor)
		iter  := btree_iterator(&buffer.btree, index = start)

		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				indent(editor, buffer, iter.index + 1, editor.repeat_count)
				break
			}
		}

		iter = btree_iterator(&buffer.btree, index = start)
		for r in btree_iter(&iter) {
			if iter.index >= max(selection.cursor, selection.anchor) {
				break
			}
			if r == '\n' {
				indent(editor, buffer, iter.index + 1, editor.repeat_count)
			}
		}
	case .Outdent:
		iter := btree_iterator(&buffer.btree, index = selection.cursor)
		index: Index
		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				index = iter.index + 1
				break
			}
		}
		for _ in 0 ..< editor.repeat_count {
			r := btree_get_rune(buffer.btree, index)
			if r == '\t' {
				buffer_remove(buffer, index, index + 1)
			} else {
				break
			}
		}

	case .Selections_Align:
		max_column := -1
		for selection in buffer.selections {
			max_column = max(max_column, btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width).column)
		}

		column := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width).column
		for _ in column ..< max_column {
			buffer_insert(editor, buffer, selection.cursor, ' ')
		}

	case .Collapse_Selection:
		selection.anchor = selection.cursor
	case .Keep_Primary_Selection:
		selection^ = buffer.selections[buffer.primary]
	case .Create_Selection_Below:
		position   := btree_index_to_position(&buffer.btree, selection.cursor, editor.config.tab_width)
		line_start := btree_line_to_index(&buffer.btree, position.line + 1)
		iter       := btree_iterator(&buffer.btree, line_start)
		p: Position
		for _ in 0 ..< editor.repeat_count {
			for _, p in btree_iter(&iter, &p, editor.config.tab_width) {
				if p.column == position.column {
					append(&editor.new_selections, New_Selection { cursor = iter.index, anchor = iter.index, primary = primary, })
					break
				}
			}
		}

	case .Toggle_Comment:
		unimplemented()
	case .Keep_Selections:
		editor.mode        = .Prompt
		editor.prompt.mode = .Keep
	case .Select:
		editor.mode        = .Prompt
		editor.prompt.mode = .Select

	case .Flip_Selection:
		selection.anchor, selection.cursor = selection.cursor, selection.anchor

	case .Split_Lines:
		start := min(selection.cursor, selection.anchor)
		end   := max(selection.cursor, selection.anchor)
		iter  := btree_iterator(&buffer.btree, index = start)

		for r in btree_iter(&iter) {
			if iter.index >= end {
				break
			}
			if r == '\n' {
				selection.anchor = start
				selection.cursor = iter.index

				start := iter.index + 1
				for r in btree_iter(&iter) {
					if iter.index >= end {
						break
					}
					if r == '\n' {
						append(&editor.new_selections, New_Selection {
							anchor = start,
							cursor = iter.index,
						})
						start = iter.index + 1
					}
				}

				append(&editor.new_selections, New_Selection {
					anchor = start,
					cursor = iter.index,
				})
				break
			}
		}
	case:
	}
}

@(require_results)
position_before :: proc(a, b: Position) -> bool {
	if a.line < b.line {
		return true
	}

	if a.line > b.line {
		return false
	}

	return a.column < b.column
}
