package editor

import "core:slice"

import glodin "vendor/glodin"
import ttf    "vendor/ttf_odin"

Baked_Glyph :: struct {
	min, max:  [2]int,
	offset:    [2]int,
	x_advance: f32,
}

Font :: struct {
	using ttf_font: ttf.Font,
	atlas:          glodin.Texture,
	baked:          map[rune]Baked_Glyph,
	skyline:        [dynamic]int,
	scale:          f32,
}

@(require_results)
get_baked_glyph :: proc(font: ^Font, r: rune) -> Baked_Glyph {
	if b, ok := font.baked[r]; ok {
		return b
	}

	glyph  := ttf.get_codepoint_glyph(font.ttf_font, r)
	shape  := ttf.get_glyph_shape(font, glyph, context.temp_allocator)
	rect   := ttf.get_bitmap_rect(font, shape, font.scale)
	size   := rect.max - rect.min
	pixels := make([][1]u8, size.x * size.y, context.temp_allocator)
	ttf.render_shape_bitmap(font, shape, font.scale, slice.to_bytes(pixels), subpixel = false)

	@(require_results)
	pack_rect :: proc(font: ^Font, size: [2]int) -> (pos: [2]int = max(int)) {
		find_spot: for x in 0 ..< len(font.skyline) - size.x {
			if font.skyline[x] >= pos.y || font.skyline[x] + size.y >= len(font.skyline) {
				continue
			}
			for x2 in x ..< x + size.x {
				if font.skyline[x2] > font.skyline[x] {
					continue find_spot
				}
			}

			pos.x = x
			pos.y = font.skyline[x]
		}

		if pos != -1 {
			for x in pos.x ..< pos.x + size.x {
				font.skyline[x] = pos.y + size.y
			}
		}

		return pos
	}

	pos := pack_rect(font, size + 1)
	glodin.set_texture_data(font.atlas, pixels, pos.x, pos.y, size.x, size.y)

	x_advance, _ := ttf.get_glyph_horizontal_metrics(font, glyph)

	b := Baked_Glyph {
		min       = pos,
		max       = pos + size,
		offset    = { rect.min.x, -rect.max.y, },
		x_advance = f32(x_advance) * font.scale,
	}

	font.baked[r] = b
	return b
}

@(require_results)
measure_text :: proc(font: ^Font, text: string) -> (w: f32) {
	for r in text {
		w += get_baked_glyph(font, r).x_advance
	}

	return w
}

draw_text :: proc(font: ^Font, instance_buffer: ^[dynamic]Instance, text: string, color: [4]f32, position: [2]f32) {
	position := position

	for r in text {
		g := get_baked_glyph(font, r)

		append(instance_buffer, Instance {
			offset  = position + ([2]f32)(g.offset),
			size    = ([2]f32)(g.max - g.min),
			texture = { **([2]f32)(g.min), 1, },
			color   = color,
		})

		position.x += g.x_advance
	}
}

@(require_results)
font_init :: proc(font: ^Font, data: []byte, font_height: int) -> bool {
	font.ttf_font = ttf.load(data) or_return
	font.atlas    = glodin.create_texture(1024, 1024, format = .RGB8, mag_filter = .Nearest, min_filter = .Nearest)
	font.skyline  = make([dynamic]int, 1024)
	font.scale    = ttf.font_height_to_scale(font^, f32(font_height))
	font.baked    = make(map[rune]Baked_Glyph)
	return true
}

font_destroy :: proc(font: Font) {
	glodin.destroy(font.atlas)
}
