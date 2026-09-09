shader_type canvas_item;

// Miniature / HD-2D tilt-shift: a sharp band across the stage, blur toward
// the top (horizon / backdrop) and bottom (foreground lip). Screen Y is a
// good stand-in for depth with a high-angle diorama camera, and unlike
// CameraAttributes DOF this still affects Gaussian splats (they do not write
// depth).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blur_px : hint_range(0.0, 16.0) = 5.5;
uniform float focus_y : hint_range(0.0, 1.0) = 0.58;
uniform float focus_width : hint_range(0.0, 0.5) = 0.14;
uniform float focus_falloff : hint_range(0.05, 0.8) = 0.26;
uniform float top_heaviness : hint_range(0.5, 2.5) = 1.35;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));
	float above = max(focus_y - UV.y, 0.0) * top_heaviness;
	float below = max(UV.y - focus_y, 0.0);
	float dist = max(above, below);
	float w = smoothstep(focus_width, focus_width + focus_falloff, dist);
	w = w * w;
	float radius = blur_px * w;

	vec4 center = texture(screen_texture, SCREEN_UV);
	vec2 r = texel * radius;
	vec4 acc = center * 0.18;
	acc += texture(screen_texture, SCREEN_UV + vec2(1.0, 0.0) * r) * 0.10;
	acc += texture(screen_texture, SCREEN_UV + vec2(-1.0, 0.0) * r) * 0.10;
	acc += texture(screen_texture, SCREEN_UV + vec2(0.0, 1.0) * r) * 0.10;
	acc += texture(screen_texture, SCREEN_UV + vec2(0.0, -1.0) * r) * 0.10;
	acc += texture(screen_texture, SCREEN_UV + vec2(0.72, 0.72) * r) * 0.08;
	acc += texture(screen_texture, SCREEN_UV + vec2(-0.72, 0.72) * r) * 0.08;
	acc += texture(screen_texture, SCREEN_UV + vec2(0.72, -0.72) * r) * 0.08;
	acc += texture(screen_texture, SCREEN_UV + vec2(-0.72, -0.72) * r) * 0.08;
	acc += texture(screen_texture, SCREEN_UV + vec2(1.6, 0.0) * r) * 0.025;
	acc += texture(screen_texture, SCREEN_UV + vec2(-1.6, 0.0) * r) * 0.025;
	acc += texture(screen_texture, SCREEN_UV + vec2(0.0, 1.6) * r) * 0.025;
	acc += texture(screen_texture, SCREEN_UV + vec2(0.0, -1.6) * r) * 0.025;
	COLOR = acc;
}
