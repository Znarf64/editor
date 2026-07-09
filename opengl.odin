package editor

import glodin "vendor/glodin"

Opengl_Renderer :: struct {
	quad:           glodin.Mesh,
	program:        glodin.Program,
	uniform_buffer: glodin.Uniform_Buffer,
	uniforms:      ^Uniforms,
	size:           [2]int,
}

Uniforms :: struct {
	screen_size: [2]f32,
}

@(require_results)
opengl_renderer_init :: proc(renderer: ^Opengl_Renderer) -> bool {
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
	renderer.quad           = glodin.create_mesh(vertex_buffer[:])
	renderer.uniform_buffer = glodin.create_uniform_buffer(Uniforms)
	renderer.uniforms       = glodin.map_uniform_buffer(^Uniforms, renderer.uniform_buffer)
	renderer.program        = glodin.create_program_hephaistos(#load("shader.hep"), shared_types = { Uniforms, }) or_else panic("Failed to load shader")

	glodin.set_uniform(renderer.program, "vertex_uniforms",   renderer.uniform_buffer)
	glodin.set_uniform(renderer.program, "fragment_uniforms", renderer.uniform_buffer)

	glodin.enable(.Blend)

	return true
}

opengl_renderer_resize :: proc(renderer: ^Opengl_Renderer, size: [2]int) {
	glodin.window_size_callback(size.x, size.y)
	renderer.size = size
}

opengl_renderer_destroy :: proc(renderer: Opengl_Renderer) {
	glodin.destroy(renderer.quad)
	glodin.destroy(renderer.program)
	glodin.destroy(renderer.uniform_buffer)

	glodin.uninit()
}

opengl_renderer_draw :: proc(renderer: Opengl_Renderer, font: Font, instances: []Instance, background_color: [4]f32) {
	instance_mesh := glodin.create_instanced_mesh(renderer.quad, instances[:])
	defer glodin.destroy(instance_mesh)

	renderer.uniforms.screen_size = ([2]f32)(renderer.size)

	glodin.clear_color({}, background_color)
	glodin.set_uniform(renderer.program, "font_texture", font.atlas)

	glodin.draw({}, renderer.program, instance_mesh)
}
