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

	Find,

	Go_To_Matching,

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
	Select_Word_Forward,
	Select_Word_End_Forward,
	Select_Word_Backward,

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

	Replace,
	Delete,

	Paste,
	Yank,

	Insert,
	Visual,
	Normal,

	Insert_At_Line_Start,
	Open_Below,
	Open_Above,
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

	.Find                            = "find",

	.Go_To_Matching                  = "go to matching",

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
	.Select_Word_Forward             = "select word forward",
	.Select_Word_End_Forward         = "select word end forward",
	.Select_Word_Backward            = "select word backward",

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

	.Replace                         = "replace",
	.Delete                          = "delete",

	.Paste                           = "paste",
	.Yank                            = "yank",

	.Insert                          = "insert",
	.Visual                          = "visual",
	.Normal                          = "normal",

	.Insert_At_Line_Start            = "insert at line start",
	.Open_Below                      = "open below",
	.Open_Above                      = "open above",
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

normalize_cursor_position :: proc(editor: ^Editor, vertical_move: bool) {
	if editor.cursor.column < 0 {
		editor.cursor.column = 0
	}

	if editor.cursor.line < 0 {
		editor.cursor.line = 0
	}

	if editor.cursor.line >= editor.rope.lines {
		editor.cursor.line = editor.rope.lines - 1
	}

	iter := rope_iterator(&editor.rope, line = editor.cursor.line)
	for r in rope_iter(&iter) {
		if r == '\t' {
			next_column := (iter.column + 1 + 3) & -4
			if editor.cursor.column > iter.column && editor.cursor.column < next_column {
				editor.cursor.column = iter.column
				break
			}
		}
		if r == '\n' {
			if editor.cursor.column > iter.column {
				editor.cursor.column = iter.column
			} else if vertical_move {
				editor.cursor.column = min(editor.cursor.target_column, iter.column)
			}

			break
		}
	}

	if !vertical_move {
		editor.cursor.target_column = editor.cursor.column
	}
}

motion_apply_queued :: proc(editor: ^Editor, motion: Motion, arg: rune) {
	vertical_move: bool
	defer normalize_cursor_position(editor, vertical_move)

	#partial switch motion {
	case .Find:
		iter := rope_iterator(&editor.rope, line = editor.cursor.line)
		for r in rope_iter(&iter) {
			if iter.column == editor.cursor.column {
				break
			}
			if r == '\n' {
				break
			}
		}

		for r in rope_iter(&iter) {
			if r == arg {
				editor.cursor = { line = iter.line, column = iter.column, }
				break
			}
		}
	}
}

motion_apply :: proc(editor: ^Editor, motion: Motion) {
	vertical_move: bool
	defer normalize_cursor_position(editor, vertical_move)

	switch motion {
	case .Find:
		editor.queued = .Find
	case .Cursor_Half_Page_Up:
		editor.cursor.line -= editor.visible_lines / 2
		vertical_move       = true
	case .Cursor_Half_Page_Down:
		editor.cursor.line += editor.visible_lines / 2
		vertical_move       = true
	case .Cursor_Page_Up:
		editor.cursor.line -= editor.visible_lines
		vertical_move       = true
	case .Cursor_Page_Down:
		editor.cursor.line += editor.visible_lines
		vertical_move       = true

	case .View_Half_Page_Up:
		editor.scroll -= editor.visible_lines / 2
	case .View_Half_Page_Down:
		editor.scroll += editor.visible_lines / 2
	case .View_Page_Up:
		editor.scroll -= editor.visible_lines
	case .View_Page_Down:
		editor.scroll += editor.visible_lines

	case .Go_To_Matching:
		iter := rope_iterator(&editor.rope, line = editor.cursor.line)
		start: rune
		for r in rope_iter(&iter) {
			if iter.column == editor.cursor.column {
				start = r
				break
			}

			if r == '\n' {
				unreachable()
			}
		}

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

		if back {

		}

		depth := 1

		for r in rope_iter(&iter) {
			if r == delim {
				depth -= 1
			} else if r == start {
				depth += 1
			}

			if depth == 0 {
				break
			}
		}

		editor.cursor = { line = iter.line, column = iter.column, }

	case .Go_To_Line:
		editor.cursor = { line = editor.repeat_count - 1, }
	case .Go_To_File_End:
		editor.cursor = { column = 0, line = editor.rope.lines - 1, }
	case .Go_To_Line_Start:
		editor.cursor.column = 0
	case .Go_To_Line_End:
		iter := rope_iterator(&editor.rope, line = editor.cursor.line)
		for r in rope_iter(&iter) {
			if r == '\n' {
				editor.cursor.column = iter.column - 1
				break
			}
		}
	case .Go_To_Line_Start_Non_Whitespace:
		iter   := rope_iterator(&editor.rope, line = editor.cursor.line)
		column := 0
		for r in rope_iter(&iter) {
			if r == '\t' {
				column = (column + 1 + 3) & -4
			} else {
				column += 1
			}
			if r == '\n' || !unicode.is_space(r) {
				break
			}
		}
		editor.cursor.column = column - 1

	case .Character_Down:
		editor.cursor.line   += editor.repeat_count
		vertical_move         = true
	case .Character_Up:
		editor.cursor.line   -= editor.repeat_count
		vertical_move         = true
	case .Character_Left:
		editor.cursor.column -= editor.repeat_count
		for editor.cursor.column < 0 {
			editor.cursor.line -= 1

			iter := rope_iterator(&editor.rope, line = editor.cursor.line)
			for r in rope_iter(&iter) {
				if r == '\n' {
					break
				}
			}
			editor.cursor.column += iter.column + 1
		}
	case .Character_Right:
		iter := rope_iterator(&editor.rope, line = editor.cursor.line, column = editor.cursor.column)
		n    := editor.repeat_count
		for _ in rope_iter(&iter) {
			n -= 1
			if n == 0 {
				break
			}
		}
		editor.cursor.position = iter.position

	case .Select_All:
	case .Select_Word_End_Forward:
		iter := rope_iterator(&editor.rope, line = editor.cursor.line)
		for r in rope_iter(&iter) {
			if iter.column == editor.cursor.column {
				break
			}
			if r == '\n' {
				return
			}
		}

		for r in rope_iter(&iter) {
			if !unicode.is_space(r) {
				break
			}
		}

		for r in rope_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			}
		}

		editor.cursor.column = iter.column
	case .Select_Word_Forward:
		iter := rope_iterator(&editor.rope, line = editor.cursor.line)
		for r in rope_iter(&iter) {
			if iter.column == editor.cursor.column {
				break
			}
			if r == '\n' {
				return
			}
		}

		for r in rope_iter(&iter) {
			if !unicode.is_space(r) {
				break
			}
		}

		for r in rope_iter(&iter) {
			if !unicode.is_letter(r) && !unicode.is_digit(r) && r != '_' {
				break
			}
		}

		editor.cursor.column = iter.column
	case .Select_Word_Backward:

	case .Search:
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
	case .Save_As:

	case .Open_File:
		editor.mode        = .Picker
		editor.picker.mode = .Files
	case .Close_File:

	case .Case_Swap:

	case .Case_To_Lower:
	case .Case_To_Upper:
	case .Case_To_Caml:
	case .Case_To_Pascal:
	case .Case_To_Snake:
	case .Case_To_Screaming_Snake:

	case .Replace:
		// fmt.println(rope_get_character_at_line(editor.rope, editor.cursor.line)^)
		// fmt.println(rope_line_to_offset(editor.rope, editor.cursor.line))
	case .Delete:

	case .Paste:
	case .Yank:

	case .Insert:
		editor.mode = .Insert
	case .Visual:
		editor.mode = .Visual
	case .Normal:
		editor.mode = .Normal
	case .Insert_At_Line_Start:
		editor.mode = .Insert
	case .Open_Below:
		editor.mode = .Insert
	case .Open_Above:
		editor.mode = .Insert

	case:
	}
}
