package editor

import fmt     "core:fmt"
import strings "core:strings"
import unicode "core:unicode"
import vmem    "core:mem/virtual"

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
	Match_Around_Paragraph,

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

	Search,
	Search_Next,
	Search_Previous,
	Set_Search,
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

	Selections_Align,

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
	.Match_Around_Paragraph          = "match around paragraph",

	.Match_In_Change                 = "match in change",
	.Match_In_Curly                  = "match in curly",
	.Match_In_Paren                  = "match in paren",
	.Match_In_Bracket                = "match in bracket",
	.Match_In_Angled                 = "match in angled",
	.Match_In_Quote                  = "match in quote",
	.Match_In_Single_Quote           = "match in single quote",
	.Match_Around_Curly              = "match around curly",
	.Match_Around_Paren              = "match around paren",
	.Match_Around_Bracket            = "match around bracket",
	.Match_Around_Angled             = "match around angled",
	.Match_Around_Quote              = "match around quote",
	.Match_Around_Single_Quote       = "match around single quote",

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
	.Search_Next                     = "search next",
	.Search_Previous                 = "search previous",
	.Set_Search                      = "set search",
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

	.Selections_Align                = "selections align",

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
		editor_insert(editor, selection.cursor, arg)
	}
}

editor_insert :: proc {
	editor_insert_rune,
	editor_insert_string,
}

_editor_insert :: proc(editor: ^Editor, arg: $T, offset: Offset) -> Offset {
	n := btree_insert(&editor.btree, offset, arg)
	for &selection in editor.selections {
		if selection.cursor >= offset {
			selection.cursor += n
		}
		if selection.anchor >= offset {
			selection.anchor += n
		}
	}
	return n
}

editor_insert_rune   :: proc(editor: ^Editor, offset: Offset, r: rune)   -> Offset {
	return _editor_insert(editor, r, offset)
}

editor_insert_string :: proc(editor: ^Editor, offset: Offset, s: string) -> Offset {
	return _editor_insert(editor, s, offset)
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

	case .Match_In_Paragraph, .Match_Around_Paragraph:
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

		if motion == .Match_In_Paragraph {
			selection.cursor = iter.offset - 1
		} else {
			selection.cursor = iter.offset
		}

	case .Match_In_Curly, .Match_In_Paren, .Match_In_Bracket, .Match_In_Angled, .Match_In_Quote, .Match_In_Single_Quote:
		motion_apply(editor, selection, motion + .Match_Around_Paren - .Match_In_Paren)
		selection.cursor -= 1
		selection.anchor += 1

	case .Match_Around_Curly, .Match_Around_Paren, .Match_Around_Bracket, .Match_Around_Angled, .Match_Around_Quote, .Match_Around_Single_Quote:
		back := btree_iterator(&editor.btree, offset = selection.cursor)
		iter := btree_iterator(&editor.btree, offset = selection.cursor)

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

		selection.anchor = back.offset

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

		selection.cursor = iter.offset

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

		selection.anchor = 0
		for r in btree_iter(&back, back = true) {
			if r == '\n' {
				selection.anchor = back.offset + 1
				break
			}
		}

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
		selection.cursor = iter.next_offset

		for r in btree_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			} else {
				selection.cursor = iter.offset
			}
		}

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

	case .Search_Next:
		history := editor.prompt.history[.Search]
		if len(history) == 0 {
			break
		}
		regex_search(editor, history[len(history) - 1])
	case .Search_Previous:
		history := editor.prompt.history[.Search]
		if len(history) == 0 {
			break
		}
		regex_search_reverse(editor, history[len(history) - 1])
	case .Set_Search:
		if selection != &editor.selections[editor.primary] {
			break
		}
		start := min(selection.anchor, selection.cursor)
		end   := max(selection.anchor, selection.cursor)
		b     := strings.builder_make(0, int(end - start), context.temp_allocator)
		iter  := btree_iterator(&editor.btree, offset = min(selection.anchor, selection.cursor))

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
			if iter.offset > max(selection.anchor, selection.cursor) {
				if is_word_class(r) != is_word_class(prev) {
					strings.write_string(&b, "\\b")
				}
				break
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
	case .Search:
		strings.builder_reset(&editor.prompt.input)
		editor.mode        = .Prompt
		editor.prompt.mode = .Search
	case .Command:
		strings.builder_reset(&editor.prompt.input)
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
		editor_insert(editor, selection.cursor, '\n')
	case .Insert_Tab:
		editor_insert(editor, selection.cursor, '\t')

	case .Open_Below:
		iter := btree_iterator(&editor.btree, offset = selection.cursor)
		for r in btree_iter(&iter) {
			if r == '\n' {
				break
			}
		}

		editor_insert(editor, iter.offset, '\n')
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
			editor_insert(editor, offset, '\t')
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

	case .Selections_Align:
		max_column := -1
		for selection in editor.selections {
			max_column = max(max_column, btree_offset_to_position(&editor.btree, selection.cursor).column)
		}

		column := btree_offset_to_position(&editor.btree, selection.cursor).column
		for _ in column ..< max_column {
			editor_insert(editor, selection.cursor, ' ')
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
