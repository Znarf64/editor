#version 450

layout (location = 0) in vec2  a_position;
layout (location = 1) in vec2  i_offset;
layout (location = 2) in vec2  i_size;
layout (location = 3) in vec3  i_texture;
layout (location = 4) in vec4  i_color;
layout (location = 5) in float i_border_radius;
layout (location = 6) in float i_border_width;
layout (location = 7) in vec4  i_border_color;
layout (location = 8) in float i_shadow_width;

layout (location = 0) out vec2  v_position;
layout (location = 1) out vec2  v_size;
layout (location = 2) out vec3  v_texture;
layout (location = 3) out vec4  v_color;
layout (location = 4) out float v_border_radius;
layout (location = 5) out float v_border_width;
layout (location = 6) out vec4  v_border_color;
layout (location = 7) out float v_shadow_width;

layout (location = 0)
uniform vec2 u_screen_size;

void main() {
	v_texture       = vec3(i_texture.xy + a_position * i_size, i_texture.z);
	v_color         = i_color;
	v_size          = i_size;
	v_border_radius = i_border_radius;
	v_border_width  = i_border_width;
	v_border_color  = i_border_color;
	v_shadow_width  = i_shadow_width;

	v_position      = a_position * (i_size + i_shadow_width);

	gl_Position     = vec4(2 * (i_offset + v_position) / u_screen_size - 1, 0, 1);
	gl_Position.y  *= -1;
	return;
}
