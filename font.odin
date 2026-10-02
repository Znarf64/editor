package editor

import runtime "base:runtime"

import la      "core:math/linalg"
import os      "core:os"
import strings "core:strings"

import ttf     "vendor/ttf_odin"
import fc      "vendor/fontconfig"

Glyph_Info :: struct {
	size, offset: [2]int,
	x_advance:    f32,
}

Font :: struct {
	using ttf_font: ttf.Font,
	glyphs:         map[rune]Glyph_Info,
	scale:          f32,
	properties:     Font_Properties,
	kind:           Font_Kind,
}

Font_Kind :: enum {
	Ui,
	Code,
	Math,
}

Font_Property :: enum {
	Bold,
	Italic,
}

Font_Properties :: bit_set[Font_Property]

@(require_results)
get_glyph_info :: proc(font: ^Font, r: rune) -> Glyph_Info {
	if info, ok := font.glyphs[r]; ok {
		return info
	}

	glyph  := ttf.get_codepoint_glyph(font, r)
	header := ttf.get_glyph_header(font, glyph)

	info: Glyph_Info

	if header != nil {
		min, max: [2]int
		min.x = int(header.xMin)
		max.x = int(header.xMax)
		min.y = int(header.yMin)
		max.y = int(header.yMax)

		info.size   = max - min
		info.offset = min
	}

	x_advance, _  := ttf.get_glyph_horizontal_metrics(font, glyph)
	info.x_advance = f32(x_advance) * font.scale

	font.glyphs[r] = info
	return info
}

@(require_results)
measure_text :: proc(editor: ^Editor, kind: Font_Kind, text: $S/string, properties: Font_Properties = {}) -> (w: f32) {
	font := find_font(editor, kind, properties)
	text := string(text)

	for r in text {
		w += get_glyph_info(font, r).x_advance
	}

	return w
}

@(require_results)
find_font :: proc(editor: ^Editor, kind: Font_Kind, properties: Font_Properties) -> ^Font {
	best: ^Font
	score := max(int)

	for &font in editor.fonts {
		if font.kind != kind {
			continue
		}

		if font.properties == properties {
			return &font
		}

		font_score := card(font.properties ~ properties)
		if font_score < score {
			best  = &font
			score = font_score
		}
	}

	return best
}

draw_text :: proc(editor: ^Editor, commands: ^[dynamic]Draw_Command, kind: Font_Kind, text: $S/string, color: [4]f32, position: [2]f32, properties: Font_Properties = {}) -> (width: f32) {
	font := find_font(editor, kind, properties)
	text := string(text)

	line_height := la.round(((f32(font.ascender) - f32(font.descender)) * font.scale))
	pos := position
	for r in text {
		if r == '\n' {
			pos.y += line_height
			pos.x  = position.x
			continue
		}

		info := get_glyph_info(font, r)

		append(commands, Draw_Command_Char {
			position = pos,
			char     = r,
			color    = color,
			font     = font,
		})

		pos.x += info.x_advance
	}

	return pos.x - position.x
}

@(require_results)
get_font_path_from_config :: proc(config: Font_Config, properties: Font_Properties) -> (path: string, index: int, ok: bool) {
	if config == {} {
		return
	}

	if config.path != "" {
		return config.path, config.index, true
	}

	conf := fc.InitLoadConfigAndFonts()
	defer fc.Fini()
	defer fc.ConfigDestroy(conf)

	pattern := fc.PatternCreate()
	defer fc.PatternDestroy(pattern)

	if config.family != "" {
		_ = fc.PatternAddString(pattern, fc.FAMILY, strings.clone_to_cstring(config.family, context.temp_allocator))
	}

	if .Bold in properties {
		_ = fc.PatternAddInteger(pattern, fc.WEIGHT, fc.WEIGHT_BOLD)
	}

	if .Italic in properties {
		_ = fc.PatternAddInteger(pattern, fc.SLANT, fc.SLANT_ITALIC)
	}

	if pattern == nil {
		return
	}

	if !fc.ConfigSubstitute(conf, pattern, .Pattern) {
		return
	}
	fc.DefaultSubstitute(pattern)

	fs := fc.FontSetCreate()
	defer fc.FontSetDestroy(fs)

	os := fc.ObjectSetBuild(fc.FAMILY, fc.STYLE, fc.FILE, fc.INDEX, nil)
	defer fc.ObjectSetDestroy(os)

	result: fc.Result
	font_patterns := fc.FontSort(conf, pattern, true, nil, &result)
	defer fc.FontSetSortDestroy(font_patterns)

	if font_patterns == nil || font_patterns.nfont == 0 {
		return
	}

	font_pattern := fc.FontRenderPrepare(conf, pattern, font_patterns.fonts[0])
	if font_pattern == nil {
		return
	}

	if !fc.FontSetAdd(fs, font_pattern) {
		return
	}

	if fs == nil {
		return
	}

	if fs.nfont > 0 {
		font := fc.PatternFilter(fs.fonts[0], os)
		defer fc.PatternDestroy(font)

		v: fc.Value
		file_result := fc.PatternGet(font, fc.FILE, 0, &v)
		if file_result != .Match {
			return
		}

		index: i32
		index_result := fc.PatternGetInteger(font, fc.INDEX, 0, &index)

		return strings.clone_from_cstring(cstring(v.u.f), context.temp_allocator), int(index_result == .Match ? index : -1), true
	}

	return
}

@(rodata)
FALLBACK_FONT_DATA := #load("font.ttf")

@(require_results)
font_init :: proc(fonts: ^[dynamic]Font, config: Font_Config, allocator: runtime.Allocator, kind: Font_Kind) -> bool {
	@(require_results)
	init :: proc(config: Font_Config, kind: Font_Kind, properties: Font_Properties, allocator: runtime.Allocator) -> (font: Font, ok: bool) {
		data := FALLBACK_FONT_DATA
		path:  string
		index: int
		if path, index, ok = get_font_path_from_config(config, properties); ok {
			data = os.read_entire_file(path, allocator) or_else FALLBACK_FONT_DATA
		}

		font.ttf_font   = ttf.load(data, index) or_return
		font.scale      = ttf.font_height_to_scale(font, config.size)
		font.glyphs     = make(map[rune]Glyph_Info, allocator)
		font.properties = properties
		font.kind       = kind

		ok = true
		return
	}

	append(fonts, init(config, kind, {                 }, allocator) or_return)
	append(fonts, init(config, kind, {          .Bold, }, allocator) or_return)
	append(fonts, init(config, kind, { .Italic,        }, allocator) or_return)
	append(fonts, init(config, kind, { .Italic, .Bold, }, allocator) or_return)

	return true
}

font_destroy :: proc(font: Font) {
	delete(font.glyphs)
	if raw_data(font.data) != raw_data(FALLBACK_FONT_DATA) {
		delete(font.data)
	}
}
