package editor

import runtime "base:runtime"

import fmt   "core:fmt"
import slice "core:slice"

import gl "vendor:OpenGL"

import ttf "vendor/ttf_odin"

Opengl_Renderer :: struct {
	vao, vbo:        u32,
	instance_vbo:    u32,
	instance_buffer: [dynamic]Opengl_Instance,
	program:         u32,
	font:            Opengl_Font,
	resolution:      [2]int,
}

Opengl_Font :: struct {
	using font: Font,
	atlas:      u32,
	baked:      map[rune]Baked_Glyph,
	skyline:    [dynamic]int,
}

Baked_Glyph :: struct {
	min, max:  [2]int,
	offset:    [2]int,
	x_advance: f32,
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
opengl_renderer_init :: proc(
	renderer: ^Opengl_Renderer,
	set_proc_address: gl.Set_Proc_Address_Type,
	allocator := context.allocator,
) -> bool {
	gl.load_up_to(4, 5, set_proc_address)

	when ODIN_DEBUG {
		gl.Enable(gl.DEBUG_OUTPUT)
		gl.DebugMessageCallback(
			proc "c" (
				source:    u32,
				type:      u32,
				id:        u32,
				severity:  u32,
				length:    i32,
				message:   cstring,
				userParam: rawptr,
			) {
				if id == 131185 {
					return
				}

				source_string: string
				switch source {
				case gl.DEBUG_SOURCE_API:
					source_string = "API"
				case gl.DEBUG_SOURCE_WINDOW_SYSTEM:
					source_string = "Window System"
				case gl.DEBUG_SOURCE_SHADER_COMPILER:
					source_string = "Shader Compiler"
				case gl.DEBUG_SOURCE_THIRD_PARTY:
					source_string = "Third Party"
				case gl.DEBUG_SOURCE_APPLICATION:
					source_string = "Application"
				case gl.DEBUG_SOURCE_OTHER:
					source_string = "Other"
				}

				type_string: string
				switch type {
				case gl.DEBUG_TYPE_ERROR:
					type_string = "Error"
				case gl.DEBUG_TYPE_DEPRECATED_BEHAVIOR:
					type_string = "Deprecated_Behavior"
				case gl.DEBUG_TYPE_UNDEFINED_BEHAVIOR:
					type_string = "Undefined_Behavior"
				case gl.DEBUG_TYPE_PORTABILITY:
					type_string = "Portability"
				case gl.DEBUG_TYPE_PERFORMANCE:
					type_string = "Performance"
				case gl.DEBUG_TYPE_MARKER:
					type_string = "Marker"
				case gl.DEBUG_TYPE_OTHER:
					type_string = "Other"
				}

				level_string: string
				switch severity {
				case gl.DEBUG_SEVERITY_NOTIFICATION:
					level_string = "DEBUG"
				case gl.DEBUG_SEVERITY_LOW:
					level_string = "INFO "
				case gl.DEBUG_SEVERITY_MEDIUM:
					level_string = "WARN "
				case gl.DEBUG_SEVERITY_HIGH:
					level_string = "ERROR"
				}

				context = runtime.default_context()
				fmt.eprintfln(
					"[%s][Source: '%s': Type: '%s']: %v (Code: %d)",
					level_string,
					source_string,
					type_string,
					message,
					id,
				)
			},
			nil,
		)
	}

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

	gl.CreateBuffers(1, &renderer.vbo)
	gl.NamedBufferStorage(renderer.vbo, size_of(Vertex) * len(vertex_buffer), &vertex_buffer[0], gl.DYNAMIC_STORAGE_BIT)

	gl.CreateBuffers(1, &renderer.instance_vbo)
	gl.NamedBufferStorage(renderer.instance_vbo, OPENGL_DRAW_BATCH_SIZE * size_of(Opengl_Instance), nil, gl.DYNAMIC_STORAGE_BIT)

	gl.CreateVertexArrays(1, &renderer.vao)

	gl.VertexArrayVertexBuffer(renderer.vao, 0, renderer.vbo,          0, size_of(Vertex))
	gl.VertexArrayVertexBuffer(renderer.vao, 1, renderer.instance_vbo, 0, size_of(Opengl_Instance))

	gl.VertexArrayBindingDivisor(renderer.vao, 1, 1)

	for i in 0 ..= 8 {
		gl.EnableVertexArrayAttrib(renderer.vao, u32(i))
	}

	gl.VertexArrayAttribFormat(renderer.vao, 0, 2, gl.FLOAT, false, 0)

	gl.VertexArrayAttribFormat(renderer.vao, 1, 2, gl.FLOAT, false, u32(offset_of(Opengl_Instance, offset)))
	gl.VertexArrayAttribFormat(renderer.vao, 2, 2, gl.FLOAT, false, u32(offset_of(Opengl_Instance, size)))
	gl.VertexArrayAttribFormat(renderer.vao, 3, 3, gl.FLOAT, false, u32(offset_of(Opengl_Instance, texture)))
	gl.VertexArrayAttribFormat(renderer.vao, 4, 4, gl.FLOAT, false, u32(offset_of(Opengl_Instance, color)))
	gl.VertexArrayAttribFormat(renderer.vao, 5, 3, gl.FLOAT, false, u32(offset_of(Opengl_Instance, border_radius)))
	gl.VertexArrayAttribFormat(renderer.vao, 6, 3, gl.FLOAT, false, u32(offset_of(Opengl_Instance, border_width)))
	gl.VertexArrayAttribFormat(renderer.vao, 7, 4, gl.FLOAT, false, u32(offset_of(Opengl_Instance, border_color)))
	gl.VertexArrayAttribFormat(renderer.vao, 8, 3, gl.FLOAT, false, u32(offset_of(Opengl_Instance, shadow_width)))

	gl.VertexArrayAttribBinding(renderer.vao, 0, 0)
	for i in 1 ..= 8 {
		gl.VertexArrayAttribBinding(renderer.vao, u32(i), 1)
	}

	gl.BindVertexArray(renderer.vao)

	renderer.instance_buffer = make([dynamic]Opengl_Instance, 0, OPENGL_DRAW_BATCH_SIZE, allocator)

	renderer.program = gl.load_shaders_source(#load("shaders/main.vert"), #load("shaders/main.frag")) or_else panic("Failed to compile shader")
	gl.UseProgram(renderer.program)

	gl.CreateTextures(gl.TEXTURE_2D, 1, &renderer.font.atlas)
	gl.TextureStorage2D(renderer.font.atlas, 1, gl.RGB8, 1024, 1024)
	renderer.font.skyline = make([dynamic]int, 1024, allocator)
	renderer.font.baked   = make(map[rune]Baked_Glyph, allocator)

	gl.BindTextureUnit(0, renderer.font.atlas)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.PixelStorei(gl.PACK_ALIGNMENT,   1)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

	return true
}

opengl_renderer_resize :: proc(renderer: ^Opengl_Renderer, size: [2]int) {
	renderer.resolution = size
}

opengl_renderer_destroy :: proc(renderer: Opengl_Renderer) {
	renderer := renderer

	delete(renderer.instance_buffer)
	delete(renderer.font.skyline)
	delete(renderer.font.baked)

	gl.DeleteVertexArrays(1, &renderer.vao)
	gl.DeleteBuffers(1, &renderer.vbo)
	gl.DeleteBuffers(1, &renderer.instance_vbo)
	gl.DeleteProgram(renderer.program)
	gl.DeleteTextures(1, &renderer.font.atlas)
}

opengl_renderer_draw :: proc(renderer: ^Opengl_Renderer, font: Font, commands: []Draw_Command, background_color: [4]f32) {
	renderer.font.font = font

	gl.ClearColor(**background_color)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	gl.Uniform2f(0, f32(renderer.resolution.x), f32(renderer.resolution.y))
	gl.Viewport(0, 0, i32(renderer.resolution.x), i32(renderer.resolution.y))

	flush :: proc(renderer: ^Opengl_Renderer) {
		if len(renderer.instance_buffer) == 0 {
			return
		}

		for {
			n := min(len(renderer.instance_buffer), OPENGL_DRAW_BATCH_SIZE)
			gl.NamedBufferSubData(renderer.instance_vbo, 0, n * size_of(Opengl_Instance), raw_data(renderer.instance_buffer))
			gl.DrawArraysInstanced(gl.TRIANGLES, 0, 6, i32(n))

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

	gl.Disable(gl.SCISSOR_TEST)

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
		case Draw_Command_Clip:
			flush(renderer)

			if v == DRAW_COMMAND_CLIP_DISABLE {
				gl.Disable(gl.SCISSOR_TEST)
				break
			}

			rect := v
			rect.min.y, rect.max.y = f32(renderer.resolution.y) - v.max.y, f32(renderer.resolution.y) - v.min.y

			gl.Scissor(i32(rect.min.x), i32(rect.min.y), i32(rect.max.x - rect.min.x), i32(rect.max.y - rect.min.y))
			gl.Enable(gl.SCISSOR_TEST)
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
	gl.TextureSubImage2D(
		font.atlas,
		0,
		i32(pos.x),
		i32(pos.y),
		i32(size.x),
		i32(size.y),
		gl.RED,
		gl.UNSIGNED_BYTE,
		raw_data(pixels),
	)

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
