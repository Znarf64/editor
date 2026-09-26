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
}

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
measure_multiline_text :: proc(font: ^Font, text: string) -> (w, h: f32) {
	line_height := la.round(((f32(font.ascender) - f32(font.descender)) * font.scale))
	max_w: f32
	for r in text {
		if r == '\n' {
			h    += line_height
			max_w = max(max_w, w)
			w     = 0
		} else {
			w += get_glyph_info(font, r).x_advance
		}
	}

	if w != 0 {
		h += line_height
	}

	return max_w, h
}

@(require_results)
measure_text :: proc(font: ^Font, text: $S/string) -> (w: f32) {
	text := string(text)

	for r in text {
		w += get_glyph_info(font, r).x_advance
	}

	return w
}

draw_text :: proc(font: ^Font, commands: ^[dynamic]Draw_Command, text: $S/string, color: [4]f32, position: [2]f32) -> (width: f32) {
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
get_font_path_from_config :: proc(config: Font_Config) -> (path: string, ok: bool) {
	if config == {} {
		return
	}

	if config.path != "" {
		return config.path, true
	}

	conf := fc.InitLoadConfigAndFonts()
	defer fc.Fini()
	defer fc.ConfigDestroy(conf)

	pattern := fc.PatternCreate()
	defer fc.PatternDestroy(pattern)

	if config.family != "" {
		_ = fc.PatternAddString(pattern, fc.FAMILY, strings.clone_to_cstring(config.family, context.temp_allocator))
	}

	if config.style != "" {
		_ = fc.PatternAddString(pattern, fc.STYLE, strings.clone_to_cstring(config.style, context.temp_allocator))
	}

	if weight, ok := config.weight.?; ok {
		_ = fc.PatternAddInteger(pattern, fc.WEIGHT, i32(weight))
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

	os := fc.ObjectSetBuild(fc.FAMILY, fc.STYLE, fc.FILE, nil)
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
		_ = fc.PatternGet(font, fc.FILE, 0, &v)

		return strings.clone_from_cstring(cstring(v.u.f), context.temp_allocator), true
	}

	return
}

@(rodata)
FALLBACK_FONT_DATA := #load("font.ttf")

@(require_results)
font_init :: proc(font: ^Font, config: Font_Config, allocator: runtime.Allocator) -> bool {
	data := FALLBACK_FONT_DATA
	if path, ok := get_font_path_from_config(config); ok {
		data = os.read_entire_file(path, allocator) or_else FALLBACK_FONT_DATA
	}

	font.ttf_font = ttf.load(data) or_return
	font.scale    = ttf.font_height_to_scale(font^, config.size)
	font.glyphs   = make(map[rune]Glyph_Info, allocator)
	return true
}

font_destroy :: proc(font: Font) {
	delete(font.glyphs)
	if raw_data(font.data) != raw_data(FALLBACK_FONT_DATA) {
		delete(font.data)
	}
}
