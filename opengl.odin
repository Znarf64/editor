package editor

import slice "core:slice"

import glodin "vendor/glodin"
import ttf    "vendor/ttf_odin"

Opengl_Renderer :: struct {
	quad:            glodin.Mesh,
	instance_mesh:   glodin.Instanced_Mesh,
	instance_buffer: [dynamic]Opengl_Instance,
	program:         glodin.Program,
	uniform_buffer:  glodin.Uniform_Buffer,
	font:            Opengl_Font,
	uniforms:       ^Opengl_Uniforms,
	size:            [2]int,
}

Opengl_Font :: struct {
	using font: Font,
	atlas:      glodin.Texture,
	baked:      map[rune]Baked_Glyph,
	skyline:    [dynamic]int,
}

Baked_Glyph :: struct {
	min, max:  [2]int,
	offset:    [2]int,
	x_advance: f32,
}

Opengl_Uniforms :: struct {
	screen_size: [2]f32,
}

Opengl_Instance :: struct {
	offset:        [2]f32,
	size:          [2]f32,
	texture:       [3]f32,
	color:         [4]f32,
	border_radius: f32,
	border_width:  f32,
	border_color:  [4]f32,
	shadow_width:  f32,
}

OPENGL_DRAW_BATCH_SIZE :: 1 << 12

@(require_results)
opengl_renderer_init :: proc(renderer: ^Opengl_Renderer, allocator := context.allocator) -> bool {
	glodin.init(proc(rawptr, cstring) {})

	Vertex :: struct {
		position: [2]f32,
	}
	vertex_buffer := [6]Vertex {
		{ position = { 0, 0, }, },
		{ position = { 0, 1, }, },
		{ position = { 1, 1, }, },

		{ position = { 0, 0, }, },
		{ position = { 1, 0, }, },
		{ position = { 1, 1, }, },
	}
	renderer.quad            = glodin.create_mesh(vertex_buffer[:])
	renderer.instance_buffer = make([dynamic]Opengl_Instance, OPENGL_DRAW_BATCH_SIZE, allocator)
	renderer.instance_mesh   = glodin.create_instanced_mesh_from_base(renderer.quad, renderer.instance_buffer[:])
	clear(&renderer.instance_buffer)
	renderer.uniform_buffer  = glodin.create_uniform_buffer(Opengl_Uniforms)
	renderer.uniforms        = glodin.map_uniform_buffer(^Opengl_Uniforms, renderer.uniform_buffer)
	Uniforms :: distinct Opengl_Uniforms
	renderer.program         = glodin.create_program_hephaistos(#load("shader.hep"), shared_types = { Uniforms, }) or_else panic("Failed to load shader")

	glodin.set_uniform(renderer.program, "vertex_uniforms",   renderer.uniform_buffer)
	glodin.set_uniform(renderer.program, "fragment_uniforms", renderer.uniform_buffer)

	renderer.font.atlas   = glodin.create_texture(1024, 1024, format = .RGB8, mag_filter = .Nearest, min_filter = .Nearest)
	renderer.font.skyline = make([dynamic]int, 1024, allocator)
	renderer.font.baked   = make(map[rune]Baked_Glyph, allocator)
	glodin.set_uniform(renderer.program, "font_texture", renderer.font.atlas)

	glodin.enable(.Blend)

	return true
}

opengl_renderer_resize :: proc(renderer: ^Opengl_Renderer, size: [2]int) {
	glodin.window_size_callback(size.x, size.y)
	renderer.size                 = size
	renderer.uniforms.screen_size = ([2]f32)(renderer.size)
}

opengl_renderer_destroy :: proc(renderer: Opengl_Renderer) {
	delete(renderer.instance_buffer)
	delete(renderer.font.skyline)
	delete(renderer.font.baked)

	glodin.destroy(renderer.quad)
	glodin.destroy(renderer.instance_mesh)
	glodin.destroy(renderer.program)
	glodin.destroy(renderer.uniform_buffer)
	glodin.destroy(renderer.font.atlas)

	glodin.uninit()
}

opengl_renderer_draw :: proc(renderer: ^Opengl_Renderer, font: Font, commands: []Draw_Command, background_color: [4]f32) {
	renderer.font.font = font

	glodin.clear_color({}, background_color)

	flush :: proc(renderer: ^Opengl_Renderer) {
		if len(renderer.instance_buffer) == 0 {
			return
		}

		for {
			n := min(len(renderer.instance_buffer), OPENGL_DRAW_BATCH_SIZE)
			glodin.set_instanced_mesh_data(renderer.instance_mesh, renderer.instance_buffer[:n])
			glodin.draw({}, renderer.program, renderer.instance_mesh, count = n)

			if len(renderer.instance_buffer) <= OPENGL_DRAW_BATCH_SIZE {
				clear(&renderer.instance_buffer)
				break
			} else {
				copy(renderer.instance_buffer[:], renderer.instance_buffer[OPENGL_DRAW_BATCH_SIZE:])
				resize(&renderer.instance_buffer, len(renderer.instance_buffer) - OPENGL_DRAW_BATCH_SIZE)
				if len(renderer.instance_buffer) < OPENGL_DRAW_BATCH_SIZE {
					break
				}
			}
		}
	}

	for command in commands {
		if len(renderer.instance_buffer) >= OPENGL_DRAW_BATCH_SIZE {
			flush(renderer)
		}

		switch v in command {
		case Draw_Command_Rect:
			append(&renderer.instance_buffer, Opengl_Instance {
				offset        = v.rect.min,
				size          = v.rect.max - v.rect.min,
				texture       = 0,
				color         = v.color,
				border_radius = v.border_radius,
				border_width  = v.border_width,
				border_color  = v.border_color,
				shadow_width  = v.shadow_width,
			})
		case Draw_Command_Char:
			g := get_baked_glyph(&renderer.font, v.char)
			append(&renderer.instance_buffer, Opengl_Instance {
				offset  = v.position + ([2]f32)(g.offset),
				size    = ([2]f32)(g.max - g.min),
				texture = { **([2]f32)(g.min), 1, },
				color   = v.color,
			})
		}
	}
	flush(renderer)
}

@(require_results)
get_baked_glyph :: proc(font: ^Opengl_Font, r: rune) -> Baked_Glyph {
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
	pack_rect :: proc(font: ^Opengl_Font, size: [2]int) -> (pos: [2]int = max(int)) {
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
