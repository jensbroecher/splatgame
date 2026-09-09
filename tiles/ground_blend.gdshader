shader_type spatial;
render_mode cull_disabled, specular_disabled;

// World-space terrain blend. Each GridMap cell is one terrain id; fragments
// interpolate the four surrounding cell centres so edges mix two materials
// and corners mix the two (or three) that meet there.

uniform sampler2D terrain_ids : filter_nearest, repeat_disable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_forest : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cobble : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 map_origin = vec2(-14.0, -14.0);
uniform float cell_size = 2.0;
uniform float uv_scale = 0.12;
uniform float blend_width = 0.1;

varying vec3 v_world;

int fetch_id(ivec2 c) {
	ivec2 sz = textureSize(terrain_ids, 0);
	c = clamp(c, ivec2(0), sz - ivec2(1));
	return int(texelFetch(terrain_ids, c, 0).r * 2.0 + 0.5);
}

vec3 sample_terrain(int id, vec2 uv) {
	vec3 grass = texture(tex_grass, uv).rgb;
	vec3 forest = texture(tex_forest, uv).rgb * 1.12;
	vec3 cobble = texture(tex_cobble, uv).rgb;
	vec3 out_rgb = grass;
	if (id == 1) {
		out_rgb = forest;
	} else if (id == 2) {
		out_rgb = cobble;
	}
	return out_rgb;
}

float sample_rough(int id) {
	float r = 0.92;
	if (id == 1) {
		r = 0.95;
	} else if (id == 2) {
		r = 0.72;
	}
	return r;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (v_world.xz - map_origin) / max(cell_size, 0.001);
	vec2 grid = p - vec2(0.5);
	vec2 c0 = floor(grid);
	vec2 f = fract(grid);
	float w = clamp(blend_width, 0.02, 0.49);
	vec2 b = smoothstep(vec2(0.5 - w), vec2(0.5 + w), f);
	ivec2 i00 = ivec2(c0);
	int id00 = fetch_id(i00);
	int id10 = fetch_id(i00 + ivec2(1, 0));
	int id01 = fetch_id(i00 + ivec2(0, 1));
	int id11 = fetch_id(i00 + ivec2(1, 1));
	vec2 uv = v_world.xz * uv_scale;
	vec3 t00 = sample_terrain(id00, uv);
	vec3 t10 = sample_terrain(id10, uv);
	vec3 t01 = sample_terrain(id01, uv);
	vec3 t11 = sample_terrain(id11, uv);
	vec3 t0 = mix(t00, t10, b.x);
	vec3 t1 = mix(t01, t11, b.x);
	ALBEDO = mix(t0, t1, b.y);
	float r0 = mix(sample_rough(id00), sample_rough(id10), b.x);
	float r1 = mix(sample_rough(id01), sample_rough(id11), b.x);
	ROUGHNESS = mix(r0, r1, b.y);
	METALLIC = 0.0;
}
