package editor

Theme :: [Style]struct { fg, bg: [4]f32, }

Config :: struct {
	animations:            bool,
	relative_line_numbers: bool,
	theme:                 Theme,
}

load_config :: proc(config: ^Config) -> (ok: bool) {
	// config.theme = {
	// 	.Invalid    = { fg = {}, },
	// 	.Whitespace = { fg = {}, },
	// 	.Ident      = { fg = { 0.9, 0.9, 0.9, 1, }, },
	// 	.Keyword    = { fg = { 0.3, 0.6, 0.9, 1, }, },
	// 	.Comment    = { fg = { 0.5, 0.5, 0.5, 1, }, bg = { 0.2, 0.2, 0.2, 1, }, },
	// 	.String     = { fg = { 0.4, 0.9, 0.5, 1, }, },
	// 	.Number     = { fg = { 0.9, 0.3, 0.3, 1, }, },
	// 	.Constant   = { fg = { 0.9, 0.3, 0.3, 1, }, },
	// 	.Operator   = { fg = { 0.9, 0.3, 0.3, 1, }, },
	// 	.Type       = { fg = { 0.9, 0.7, 0.5, 1, }, },
	// }

	config.theme = {
		.Invalid    = { fg = {}, },
		.Whitespace = { fg = {}, },
		.Ident      = { fg = color_from_hex_rgba(0xABB2BFFF), },
		.Cursor     = { fg = color_from_hex_rgba(0x1E2128FF), bg = color_from_hex_rgba(0xABB2BFFF), },
		.Keyword    = { fg = color_from_hex_rgba(0x62AEEFFF), },
		.Function   = { fg = color_from_hex_rgba(0x62AEEFFF), },
		.Comment    = { fg = color_from_hex_rgba(0xABB2BFFF), bg = color_from_hex_rgba(0x32363DFF), },
		.String     = { fg = color_from_hex_rgba(0x98C379FF), },
		.Number     = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Directive  = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Constant   = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Operator   = { fg = color_from_hex_rgba(0xE06B74FF), },
		.Type       = { fg = color_from_hex_rgba(0xE5C07AFF), },
		.Background = { bg = color_from_hex_rgba(0x1E2128FF), },
	}

	config.animations            = true
	config.relative_line_numbers = true

	return true
}
