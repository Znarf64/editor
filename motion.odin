package editor

import fmt     "core:fmt"
import strings "core:strings"
import unicode "core:unicode"

Motion :: enum {
	Cursor_Page_Up = 1,
	Cursor_Page_Down,
	Cursor_Half_Page_Up,
	Cursor_Half_Page_Down,

	View_Page_Up,
	View_Page_Down,
	View_Half_Page_Up,
	View_Half_Page_Down,

	Go_To_Matching,
	Match_In_Word,
	Match_In_Long_Word,
	Match_In_Paragraph,
	Match_In_Change,

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

	Search,
	Command,

	Open_File,
	Search_Global,
	Search_Symbols,
	Command_Palette,

	Save,
	Save_As,

	Close_File,

	Case_Swap,

	Case_To_Lower,
	Case_To_Upper,
	Case_To_Caml,
	Case_To_Pascal,
	Case_To_Snake,
	Case_To_Screaming_Snake,

	Delete,

	Paste,
	Yank,

	Insert,
	Append,
	Visual,
	Normal,

	Change,

	Insert_Newline,
	Insert_Tab,

	Indent,
	Outdent,

	Open_Below,
	Open_Above,

	Show_Hover_Information,
	Show_Code_Actions,

	Collapse_Selection,
	Keep_Primary_Selection,
	Create_Selection_Below,

	Align_Selections,

	Toggle_Comment,

	Keep_Selections,
	Select,

	Flip_Selection,
}

Motion_Info :: struct {
	name:        string,
	description: string,
}

@(rodata)
motion_descriptions: [Motion]string = {
	.Cursor_Page_Up                  = "cursor page up",
	.Cursor_Page_Down                = "cursor page down",
	.Cursor_Half_Page_Up             = "cursor half page up",
	.Cursor_Half_Page_Down           = "cursor half page down",

	.View_Page_Up                    = "view page up",
	.View_Page_Down                  = "view page down",
	.View_Half_Page_Up               = "view half page up",
	.View_Half_Page_Down             = "view half page down",

	.Go_To_Matching                  = "go to matching",

	.Match_In_Word                   = "match in word",
	.Match_In_Long_Word              = "match in long word",
	.Match_In_Paragraph              = "match in paragraph",
	.Match_In_Change                 = "match in change",

	.Go_To_Line                      = "go to line",
	.Go_To_File_End                  = "go to file end",
	.Go_To_Line_Start                = "go to line start",
	.Go_To_Line_End                  = "go to line end",
	.Go_To_Line_Start_Non_Whitespace = "go to line start non whitespace",

	.Character_Down                  = "character down",
	.Character_Up                    = "character up",
	.Character_Left                  = "character left",
	.Character_Right                 = "character right",

	.Select_All                      = "select all",
	.Select_Line                     = "select line",
	.Select_Word_Forward             = "select word forward",
	.Select_Word_End_Forward         = "select word end forward",
	.Select_Word_Backward            = "select word backward",
	.Select_Long_Word_Forward        = "select long word forward",
	.Select_Long_Word_End_Forward    = "select long word end forward",
	.Select_Long_Word_Backward       = "select long word backward",

	.Search                          = "search",
	.Command                         = "command",

	.Open_File                       = "open file",
	.Search_Global                   = "search global",
	.Search_Symbols                  = "search symbols",
	.Command_Palette                 = "command palette",

	.Save                            = "save",
	.Save_As                         = "save as",

	.Close_File                      = "close file",

	.Case_Swap                       = "case swap",

	.Case_To_Lower                   = "case to lower",
	.Case_To_Upper                   = "case to upper",
	.Case_To_Caml                    = "case to caml",
	.Case_To_Pascal                  = "case to pascal",
	.Case_To_Snake                   = "case to snake",
	.Case_To_Screaming_Snake         = "case to screaming snake",

	.Delete                          = "delete",

	.Paste                           = "paste",
	.Yank                            = "yank",

	.Insert                          = "insert",
	.Append                          = "append",
	.Visual                          = "visual",
	.Normal                          = "normal",

	.Change                          = "change",

	.Insert_Newline                  = "insert newline",
	.Insert_Tab                      = "insert tab",

	.Open_Below                      = "open below",
	.Open_Above                      = "open above",

	.Indent                          = "indent",
	.Outdent                         = "outdent",

	.Show_Hover_Information          = "show hover information",
	.Show_Code_Actions               = "show code actions",

	.Collapse_Selection              = "collapse selection",
	.Keep_Primary_Selection          = "keep primary selection",

	.Create_Selection_Below          = "create selection below",

	.Align_Selections                = "align selections",

	.Toggle_Comment                  = "toggle comment",

	.Keep_Selections                 = "keep selections",

	.Select                          = "select",

	.Flip_Selection                  = "flip selection",
}

Argument_Motion :: enum {
	Insert_Character,
	Replace,
	Find,
	Find_Backward,
}

@(rodata)
argument_motion_descriptions: [Argument_Motion]string = {
	.Insert_Character = "insert character",
	.Find             = "find",
	.Find_Backward    = "find backward",
	.Replace          = "replace",
}

@(require_results)
parse_argument_motion :: proc(s: string) -> (motion: Argument_Motion, ok: bool) {
	b := strings.builder_make(0, len(s), context.temp_allocator)
	for r in s {
		r := unicode.to_lower(r)
		if r == '-' || r == '_' {
			r = ' '
		}
		strings.write_rune(&b, r)
	}

	s := strings.to_string(b)

	for name, m in argument_motion_descriptions {
		if name == s {
			return m, true
		}
	}

	return
}

@(require_results)
parse_motion :: proc(s: string) -> (motion: Motion, ok: bool) {
	b := strings.builder_make(0, len(s), context.temp_allocator, )
	for r in s {
		r := unicode.to_lower(r)
		if r == '-' || r == '_' {
			r = ' '
		}
		strings.write_rune(&b, r)
	}

	s := strings.to_string(b)

	for name, m in motion_descriptions {
		if name == s {
			return m, true
		}
	}

	return
}

argument_motion_apply :: proc(editor: ^Editor, motion: Argument_Motion, arg: rune) {
	for &selection in editor.selections {
		argument_motion_apply_single(editor, &selection, motion, arg)
	}
}

argument_motion_apply_single :: proc(editor: ^Editor, selection: ^Selection, motion: Argument_Motion, arg: rune) {
	vertical_move: bool
	defer if !vertical_move {
		selection.target_cursor = selection.cursor
	}

	switch motion {
	case .Find:
		selection.anchor = selection.cursor

		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		_, _  = btree_iter(&iter)
		for r in btree_iter(&iter) {
			if r == arg {
				selection.cursor = iter.offset
				break
			}
		}
	case .Find_Backward:
		selection.anchor = selection.cursor

		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		_, _  = btree_iter(&iter, back = true)
		for r in btree_iter(&iter, back = true) {
			if r == arg {
				selection.cursor = iter.offset
				break
			}
		}
	case .Replace:
	case .Insert_Character:
		selection.cursor += btree_insert(&editor.btree, selection.cursor, arg)
	}
}

@(require_results)
position_to_offset_normalized :: proc(editor: ^Editor, position: Position, vertical_move: bool, selection: ^Selection) -> bool {
	position := Position {
		line   = clamp(position.line, 0, int(editor.btree.lines) - 1),
		column = max(position.column, 0),
	}
	if vertical_move {
		position.column = btree_offset_to_position(&editor.btree, selection.target_cursor).column
	}
	iter := btree_iterator(&editor.btree, line = position.line)
	for r in btree_iter(&iter) {
		if position_after(iter.position, r, editor.config.tab_width).column > position.column || r == '\n' {
			break
		}
	}
	selection.cursor = iter.offset

	return vertical_move
}

motion_apply :: proc(editor: ^Editor, selection: ^Selection, motion: Motion) {
	vertical_move: bool
	defer if !vertical_move {
		selection.target_cursor = selection.cursor
	}

	switch motion {
	case .Cursor_Half_Page_Up:
		position        := btree_offset_to_position(&editor.btree, selection.cursor)
		position.line   -= editor.visible_lines / 2
		vertical_move = position_to_offset_normalized(editor, position, true, selection)
		selection.anchor = selection.cursor
	case .Cursor_Half_Page_Down:
		position        := btree_offset_to_position(&editor.btree, selection.cursor)
		position.line   += editor.visible_lines / 2
		vertical_move    = position_to_offset_normalized(editor, position, true, selection)
		selection.anchor = selection.cursor
	case .Cursor_Page_Up:
		position        := btree_offset_to_position(&editor.btree, selection.cursor)
		position.line   -= editor.visible_lines
		vertical_move    = position_to_offset_normalized(editor, position, true, selection)
		selection.anchor = selection.cursor
	case .Cursor_Page_Down:
		position        := btree_offset_to_position(&editor.btree, selection.cursor)
		position.line   += editor.visible_lines
		vertical_move    = position_to_offset_normalized(editor, position, true, selection)
		selection.anchor = selection.cursor

	case .View_Half_Page_Up:
		editor.scroll -= editor.visible_lines / 2
		vertical_move  = true
	case .View_Half_Page_Down:
		editor.scroll += editor.visible_lines / 2
		vertical_move  = true
	case .View_Page_Up:
		editor.scroll -= editor.visible_lines
		vertical_move  = true
	case .View_Page_Down:
		editor.scroll += editor.visible_lines
		vertical_move  = true

	case .Go_To_Matching:
		iter  := btree_iterator(&editor.btree, offset = selection.cursor)
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

		selection.cursor = iter.offset
		selection.anchor = selection.cursor

	case .Match_In_Word:
		start_offset := selection.cursor

		back := btree_iterator(&editor.btree, offset = start_offset)
		iter := btree_iterator(&editor.btree, offset = start_offset)

		for r in btree_iter(&back, back = true) {
			if !unicode.is_letter(r) && !unicode.is_number(r) && r != '_' {
				break
			}
			start_offset = back.offset
		}

		selection.anchor = start_offset

		end_offset := start_offset
		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_number(r) && r != '_' {
				break
			}
			end_offset = iter.offset
		}

		selection.cursor = end_offset

	case .Match_In_Long_Word:
		start_offset := selection.cursor

		back := btree_iterator(&editor.btree, offset = start_offset)
		iter := btree_iterator(&editor.btree, offset = start_offset)

		for r in btree_iter(&back, back = true) {
			if unicode.is_space(r) {
				break
			}
			start_offset = back.offset
		}

		selection.anchor = start_offset

		end_offset := start_offset
		for r in btree_iter(&iter) {
			if unicode.is_space(r) {
				break
			}
			end_offset = iter.offset
		}

		selection.cursor = end_offset

	case .Match_In_Paragraph:
		back := btree_iterator(&editor.btree, offset = selection.cursor)
		iter := btree_iterator(&editor.btree, offset = selection.cursor)

		last_was_newline: bool
		for r in btree_iter(&back, back = true) {
			if r == '\n' {
				if last_was_newline {
					break
				}
				last_was_newline = true
			} else {
				last_was_newline = false
			}
		}

		selection.anchor = back.offset + 2 // this is fine, since the last two characters will have been single-byte newline characters

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

		selection.cursor = iter.offset - 1

	case .Match_In_Change:
		unimplemented()

	case .Go_To_Line:
		vertical_move    = position_to_offset_normalized(editor, { line = editor.repeat_count - 1, }, false, selection)
		selection.anchor = selection.cursor
	case .Go_To_File_End:
		vertical_move    = position_to_offset_normalized(editor, { line = int(editor.btree.lines) - 1, }, false, selection)
		selection.anchor = selection.cursor
	case .Go_To_Line_Start:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				selection.cursor = iter.offset + 1
				selection.anchor = selection.cursor
				return
			}
		}
		selection.cursor = 0
		selection.anchor = 0
	case .Go_To_Line_End:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		for r in btree_iter(&iter) {
			if r == '\n' {
				selection.cursor = iter.offset - 1
				break
			}
		}
		selection.anchor = selection.cursor
	case .Go_To_Line_Start_Non_Whitespace:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		space_only := true
		for r in btree_iter(&iter, back = true) {
			is_space    := unicode.is_space(r)
			space_only &&= is_space
			if !is_space {
				selection.cursor = iter.offset
				selection.anchor = selection.cursor
			}
			if r == '\n' {
				if space_only {
					iter := btree_iterator(&editor.btree, offset = selection.cursor)
					for r in btree_iter(&iter) {
						if !unicode.is_space(r) {
							selection.cursor = iter.offset
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
		position        := btree_offset_to_position(&editor.btree, selection.cursor)
		position.line   += editor.repeat_count
		vertical_move    = position_to_offset_normalized(editor, position, true, selection)
		selection.anchor = selection.cursor
	case .Character_Up:
		position        := btree_offset_to_position(&editor.btree, selection.cursor)
		position.line   -= editor.repeat_count
		vertical_move    = position_to_offset_normalized(editor, position, true, selection)
		selection.anchor = selection.cursor
	case .Character_Left:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		for _ in 0 ..< editor.repeat_count {
			_ = btree_iter(&iter, back = true) or_break
		}
		selection.cursor = iter.offset
		selection.anchor = selection.cursor
	case .Character_Right:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		for _ in 0 ..= editor.repeat_count {
			_ = btree_iter(&iter) or_break
		}
		selection.cursor = iter.offset
		selection.anchor = selection.cursor

	case .Select_Line:
		if selection.cursor < selection.anchor {
			selection.cursor, selection.anchor = selection.anchor, selection.cursor
		}

		prev := selection^

		back := btree_iterator(&editor.btree, offset = selection.anchor)
		iter := btree_iterator(&editor.btree, offset = selection.cursor)

		for r in btree_iter(&back, back = true) {
			if r == '\n' {
				break
			}
		}
		selection.anchor = back.offset + 1

		for r in btree_iter(&iter) {
			if r == '\n' {
				break
			}
		}
		selection.cursor = iter.offset

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
		selection.cursor = iter.offset

	case .Select_All:
		selection.anchor = 0
		vertical_move    = position_to_offset_normalized(editor, { line = int(editor.btree.lines) - 1, }, false, selection)
	case .Select_Word_End_Forward:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.offset

		pos := iter.offset

		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			} else {
				pos = iter.offset
			}
		}

		selection.cursor = pos

	case .Select_Word_Forward:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.offset

		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			}
		}

		selection.cursor = iter.offset
	case .Select_Word_Backward:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
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

		selection.cursor = iter.offset

	case .Select_Long_Word_Forward:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.offset

		for r in btree_iter(&iter) {
			if unicode.is_space(r) {
				break
			}
		}

		selection.cursor = iter.offset

	case .Select_Long_Word_End_Forward:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		r    := btree_iter(&iter) or_break

		if unicode.is_space(r) {
			for r in btree_iter(&iter) {
				if !unicode.is_space(r) {
					break
				}
			}
		}
		selection.anchor = iter.offset

		pos := iter.offset

		for r in btree_iter(&iter) {
			if unicode.is_space(r) {
				break
			} else {
				pos = iter.offset
			}
		}

		selection.cursor = pos

	case .Select_Long_Word_Backward:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
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

		selection.cursor = iter.offset

	case .Search:
		strings.builder_reset(&editor.prompt.input)
		editor.mode        = .Prompt
		editor.prompt.mode = .Search
	case .Command:
		editor.mode        = .Prompt
		editor.prompt.mode = .Command

	case .Search_Global:
		editor.mode        = .Picker
		editor.picker.mode = .Global_Search
	case .Search_Symbols:
		editor.mode        = .Picker
		editor.picker.mode = .Symbols
	case .Command_Palette:
		editor.mode        = .Picker
		editor.picker.mode = .Commands

	case .Save:
		unimplemented()
	case .Save_As:
		unimplemented()

	case .Open_File:
		editor.mode        = .Picker
		editor.picker.mode = .Files
	case .Close_File:
		unimplemented()

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
		iter       := btree_iterator(&editor.btree, offset = end)
		_, _        = btree_iter(&iter)
		btree_remove_range(&editor.btree, start, iter.next_offset)

	case .Paste:
		unimplemented()
	case .Yank:
		unimplemented()

	case .Insert:
		if selection.cursor > selection.anchor {
			selection.cursor, selection.anchor = selection.anchor, selection.cursor
		}
		editor.mode = .Insert
	case .Append:
		if selection.cursor < selection.anchor {
			selection.cursor, selection.anchor = selection.anchor, selection.cursor
		}

		iter            := btree_iterator(&editor.btree, offset = selection.cursor)
		_                = btree_iter(&iter) or_break
		_                = btree_iter(&iter) or_break
		selection.cursor = iter.offset

		editor.mode      = .Insert
	case .Visual:
		editor.mode = .Visual
	case .Normal:
		editor.mode = .Normal
	case .Insert_Newline:
		btree_insert(&editor.btree, selection.cursor, '\n')
	case .Insert_Tab:
		btree_insert(&editor.btree, selection.cursor, '\t')

	case .Open_Below:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		for r in btree_iter(&iter) {
			if r == '\n' {
				break
			}
		}

		btree_insert(&editor.btree, iter.offset, '\n')
		selection.cursor = iter.offset + 1
		selection.anchor = selection.cursor

		editor.mode = .Insert

	case .Open_Above:
		editor.mode = .Insert
	case .Change:
		editor.mode = .Insert

	case .Indent:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		offset: Offset
		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				offset = iter.offset + 1
				break
			}
		}
		for _ in 0 ..< editor.repeat_count {
			btree_insert(&editor.btree, offset, '\t')
		}
		selection.cursor += Offset(editor.repeat_count)
	case .Outdent:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		offset: Offset
		for r in btree_iter(&iter, back = true) {
			if r == '\n' {
				offset = iter.offset + 1
				break
			}
		}
		for _ in 0 ..< editor.repeat_count {
			r := btree_get_rune(editor.btree, offset)
			if r == '\t' {
				btree_remove_range(&editor.btree, offset, offset + 1)
				selection.cursor -= 1
				selection.anchor -= 1
			} else {
				break
			}
		}

	case .Show_Hover_Information:
		unimplemented()
	case .Show_Code_Actions:
		unimplemented()
	case .Collapse_Selection:
		selection.anchor = selection.cursor
	case .Keep_Primary_Selection:
		selection^ = editor.selections[editor.primary]
	case .Create_Selection_Below:
		position := btree_offset_to_position(&editor.btree, selection.cursor)
		iter     := btree_iterator(&editor.btree, line = position.line + 1)
		for _ in 0 ..< editor.repeat_count {
			for _ in btree_iter(&iter) {
				if iter.column == position.column {
					append(&editor.new_selections, Selection { cursor = iter.offset, anchor = iter.offset, })
					break
				}
			}
		}

	case .Align_Selections:
		unimplemented()
	case .Toggle_Comment:
		unimplemented()
	case .Keep_Selections:
		editor.mode        = .Prompt
		editor.prompt.mode = .Keep
	case .Select:
		editor.mode        = .Prompt
		editor.prompt.mode = .Select

	case .Flip_Selection:
		selection.anchor, selection.cursor = selection.cursor , selection.anchor

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
