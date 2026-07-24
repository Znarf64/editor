package editor

import runtime "base:runtime"

import ttf "vendor/ttf_odin"

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
measure_text :: proc(font: ^Font, text: string) -> (w: f32) {
	for r in text {
		w += get_glyph_info(font, r).x_advance
	}

	return w
}

draw_text :: proc(font: ^Font, commands: ^[dynamic]Draw_Command, text: string, color: [4]f32, position: [2]f32) -> (width: f32) {
	pos := position
	for r in text {
		info := get_glyph_info(font, r)

		append(commands, Draw_Command_Char {
			position = pos,
			char     = r,
			color    = color,
		})

		pos.x += info.x_advance
	}

	return pos.x - position.x
}

@(require_results)
font_init :: proc(font: ^Font, data: []byte, font_height: int, allocator: runtime.Allocator) -> bool {
	font.ttf_font = ttf.load(data) or_return
	font.scale    = ttf.font_height_to_scale(font^, f32(font_height))
	font.glyphs   = make(map[rune]Glyph_Info, allocator)
	return true
}

font_destroy :: proc(font: Font) {
	delete(font.glyphs)
}
