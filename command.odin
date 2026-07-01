package editor

Command :: enum {
	Cursor_Half_Page_Up,
	Cursor_Half_Page_Down,

	Go_To_File_Start,
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
	Search_Global,
	Search_Symbols,
	Command_Palette,

	Save,
	Save_As,

	Open_File,
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

command_apply :: proc(editor: ^Editor, command: Command) -> (repeat: bool) {
	switch command {
	case .Cursor_Half_Page_Up:
		return true
	case .Cursor_Half_Page_Down:
		return true

	case .Go_To_File_Start:
		editor.cursor = {}
	case .Go_To_File_End:
	case .Go_To_Line_Start:
	case .Go_To_Line_End:
	case .Go_To_Line_Start_Non_Whitespace:

	case .Character_Down:
		editor.cursor.line   += 1
		return true
	case .Character_Up:
		editor.cursor.line   -= 1
		return true
	case .Character_Left:
		editor.cursor.column -= 1
		return true
	case .Character_Right:
		editor.cursor.column += 1
		return true

	case .Select_All:
	case .Select_Word_Forward:
		return true
	case .Select_Word_Backward:
		return true

	case .Search:
		editor.mode = .Prompt
	case .Search_Global:
		editor.mode   = .Picker
		editor.picker = .Global_Search
	case .Search_Symbols:
		editor.mode   = .Picker
		editor.picker = .Symbols
	case .Command_Palette:
		editor.mode   = .Picker
		editor.picker = .Commands

	case .Save:
	case .Save_As:

	case .Open_File:
		rect := rect_from_min_max(40, editor.screen_size - 40)
		animation_begin(&editor.file_picker.rect, rect)

		editor.mode   = .Picker
		editor.picker = .Files
	case .Close_File:

	case .Case_Swap:

	case .Case_To_Lower:
	case .Case_To_Upper:
	case .Case_To_Caml:
	case .Case_To_Pascal:
	case .Case_To_Snake:
	case .Case_To_Screaming_Snake:

	case .Replace:
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

	return false
}
