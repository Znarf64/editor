package editor

import "core:fmt"

Motion :: enum {
	Cursor_Page_Up,
	Cursor_Page_Down,
	Cursor_Half_Page_Up,
	Cursor_Half_Page_Down,

	View_Page_Up,
	View_Page_Down,
	View_Half_Page_Up,
	View_Half_Page_Down,

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

motion_apply :: proc(editor: ^Editor, motion: Motion) {
	switch motion {
	case .Cursor_Half_Page_Up:
		editor.cursor.line -= editor.visible_lines / 2
	case .Cursor_Half_Page_Down:
		editor.cursor.line += editor.visible_lines / 2
	case .Cursor_Page_Up:
		editor.cursor.line -= editor.visible_lines
	case .Cursor_Page_Down:
		editor.cursor.line += editor.visible_lines

	case .View_Half_Page_Up:
		editor.scroll -= editor.visible_lines / 2
	case .View_Half_Page_Down:
		editor.scroll += editor.visible_lines / 2
	case .View_Page_Up:
		editor.scroll -= editor.visible_lines
	case .View_Page_Down:
		editor.scroll += editor.visible_lines

	case .Go_To_Line:
		editor.cursor = { line = editor.repeat_count - 1, }
	case .Go_To_File_End:
		editor.cursor = { column = 0, line = editor.rope.lines - 1, }
	case .Go_To_Line_Start:
		editor.cursor.column = 0
	case .Go_To_Line_End:
	case .Go_To_Line_Start_Non_Whitespace:

	case .Character_Down:
		editor.cursor.line   += editor.repeat_count
	case .Character_Up:
		editor.cursor.line   -= editor.repeat_count
	case .Character_Left:
		editor.cursor.column -= editor.repeat_count
	case .Character_Right:
		editor.cursor.column += editor.repeat_count

	case .Select_All:
	case .Select_Word_Forward:
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
