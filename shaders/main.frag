#version 450

layout (location = 0) in vec2  v_position;
layout (location = 1) in vec2  v_size;
layout (location = 2) in vec3  v_texture;
layout (location = 3) in vec4  v_color;
layout (location = 4) in float v_border_radius;
layout (location = 5) in float v_border_width;
layout (location = 6) in vec4  v_border_color;
layout (location = 7) in float v_shadow_width;

layout (location = 0) out vec4 f_color;

layout (binding  = 0) uniform sampler2D u_texture_font;
layout (binding  = 1) uniform sampler2D u_texture_blur;
layout (binding  = 2) uniform sampler2D u_texture_noise;

layout (location = 1) uniform bool      u_enable_blur;
layout (location = 2) uniform float     u_noise_strength = 0.005;

float sdf_rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
	f_color = vec4(1.0);

	float shadow_strength = 1.0 - (sdf_rounded_box(v_position - v_size / 2.0 - v_shadow_width / 2.0, v_size / 2.0 - v_shadow_width / 2.0, v_border_radius) - 0.5) / v_shadow_width;
	shadow_strength = smoothstep(0.0, 1.0, shadow_strength);

	vec4 shadow = vec4(0.0, 0.0, 0.0, 0.3) * shadow_strength;

	float d = sdf_rounded_box(v_position - v_size / 2.0, v_size / 2.0, v_border_radius) - 0.5;
	float border_weight = 0.0;

	if (v_border_width != 0.0) {
		if (d > 0.0) {
			f_color = shadow;
			return;
		} else if (d > -1.0) {
			shadow.rgb = mix(v_border_color.rgb, shadow.rgb, shadow_strength);
			f_color = mix(shadow, v_border_color, -d);
			return;
		} else if (d > -v_border_width) {
			border_weight = 1.0;
		} else if (d > -v_border_width - 1.0) {
			border_weight = d + v_border_width + 1.0;
		}
	} else {
		if (d > 0.0) {
			f_color.a = 0.0;
			return;
		} else if (d > -1.0) {
			f_color.a = -d;
		}
	}

	f_color *= v_color;

	if (v_texture.z != 0.0) {
		vec2 texel = v_texture.xy / vec2(textureSize(u_texture_font, 0));
		f_color.a *= texture(u_texture_font, texel).r;
	}

	f_color = mix(f_color, v_border_color, border_weight);

	if (u_enable_blur && f_color.a != 0) {
		vec2  texel = gl_FragCoord.xy / vec2(textureSize(u_texture_blur,  0));
		float noise = texture(u_texture_noise, gl_FragCoord.xy / vec2(textureSize(u_texture_noise, 0))).r;
		f_color.rgb = mix(texture(u_texture_blur, texel).rgb, f_color.rgb, f_color.a) + vec3(noise - 0.5) * u_noise_strength;
		f_color.a   = 1;
	}
}
