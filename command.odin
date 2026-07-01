package editor

Command :: enum {
	Page_Up,
	Page_Down,

	Character_Down,
	Character_Up,
	Character_Left,
	Character_Right,

	Delete_Character,
	Replace_Character,

	Select_Word_Forward,
	Select_Word_Backward,

	Search,

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
}
