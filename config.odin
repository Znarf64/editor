package editor

Theme :: struct {
	
}

Editor_Config :: struct {
	animations: bool,
}

Config :: struct {
	editor: Editor_Config,
	theme:  Theme,
}

load_config :: proc() -> (config: Config, ok: bool) {
	return
}
