shader_type spatial;
render_mode cull_disabled, specular_disabled;

// World-space terrain. Solid tiles (0–2) blend a thin strip with neighbours.
// Ids 3+ are stamped mix tiles (diagonals / corners) that break the grid.

uniform sampler2D terrain_ids : filter_nearest, repeat_disable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_forest : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cobble : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 map_origin = vec2(-14.0, -14.0);
uniform float cell_size = 2.0;
uniform float elevation_step = 1.0;
uniform float uv_scale = 0.12;
uniform float blend_width = 0.1;

varying vec3 v_world;

// .x = terrain id (255 = empty), .y = GridMap cell.y
ivec2 fetch_cell(ivec2 c) {
	ivec2 sz = textureSize(terrain_ids, 0);
	if (c.x < 0 || c.y < 0 || c.x >= sz.x || c.y >= sz.y) {
		return ivec2(255, -999);
	}
	vec4 pix = texelFetch(terrain_ids, c, 0);
	int id = int(pix.r * 255.0 + 0.5);
	if (id == 255) {
		return ivec2(255, -999);
	}
	int hy = int(pix.g * 255.0 + 0.5) - 128;
	return ivec2(id, hy);
}

vec4 mat_grass(vec2 uv) {
	return vec4(texture(tex_grass, uv).rgb, 0.92);
}

vec4 mat_forest(vec2 uv) {
	return vec4(texture(tex_forest, uv).rgb * 1.12, 0.95);
}

vec4 mat_cobble(vec2 uv) {
	return vec4(texture(tex_cobble, uv).rgb, 0.72);
}

vec4 cell_sample(int id, vec2 uv, vec2 local) {
	vec4 grass = mat_grass(uv);
	vec4 forest = mat_forest(uv);
	vec4 cobble = mat_cobble(uv);
	float slash = smoothstep(-0.07, 0.07, local.x - local.y);
	float backslash = smoothstep(-0.07, 0.07, local.x + local.y - 1.0);
	// Quarter-circle from each cell corner (NE = +X/-Z in our local map).
	float ne = 1.0 - smoothstep(0.62, 0.88, length(local - vec2(1.0, 0.0)));
	float se = 1.0 - smoothstep(0.62, 0.88, length(local - vec2(1.0, 1.0)));
	float sw = 1.0 - smoothstep(0.62, 0.88, length(local - vec2(0.0, 1.0)));
	float nw = 1.0 - smoothstep(0.62, 0.88, length(local - vec2(0.0, 0.0)));
	vec4 r = grass;
	if (id == 1) {
		r = forest;
	} else if (id == 2) {
		r = cobble;
	} else if (id == 3) {
		r = mix(grass, cobble, slash);
	} else if (id == 4) {
		r = mix(grass, cobble, backslash);
	} else if (id == 5) {
		r = mix(grass, forest, slash);
	} else if (id == 6) {
		r = mix(grass, forest, backslash);
	} else if (id == 7) {
		r = mix(forest, cobble, slash);
	} else if (id == 8) {
		r = mix(forest, cobble, backslash);
	} else if (id == 9) {
		r = mix(grass, cobble, ne);
	} else if (id == 10) {
		r = mix(grass, cobble, se);
	} else if (id == 11) {
		r = mix(grass, cobble, sw);
	} else if (id == 12) {
		r = mix(grass, cobble, nw);
	} else if (id == 13) {
		r = mix(grass, forest, ne);
	} else if (id == 14) {
		r = mix(grass, forest, se);
	} else if (id == 15) {
		r = mix(grass, forest, sw);
	} else if (id == 16) {
		r = mix(grass, forest, nw);
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
	ivec2 i10 = i00 + ivec2(1, 0);
	ivec2 i01 = i00 + ivec2(0, 1);
	ivec2 i11 = i00 + ivec2(1, 1);
	vec2 uv = v_world.xz * uv_scale;
	ivec2 self_c = ivec2(floor(p));
	ivec2 self = fetch_cell(self_c);
	if (self.x == 255) {
		self_c = ivec2(floor(max(p - vec2(0.001), vec2(0.0))));
		self = fetch_cell(self_c);
	}
	vec4 t_self = cell_sample(self.x, uv, clamp(p - vec2(self_c), vec2(0.0), vec2(1.0)));
	ivec2 c00 = fetch_cell(i00);
	ivec2 c10 = fetch_cell(i10);
	ivec2 c01 = fetch_cell(i01);
	ivec2 c11 = fetch_cell(i11);
	vec4 t00 = t_self;
	vec4 t10 = t_self;
	vec4 t01 = t_self;
	vec4 t11 = t_self;
	if (c00.x != 255 && c00.y == self.y) {
		t00 = cell_sample(c00.x, uv, clamp(p - vec2(i00), vec2(0.0), vec2(1.0)));
	}
	if (c10.x != 255 && c10.y == self.y) {
		t10 = cell_sample(c10.x, uv, clamp(p - vec2(i10), vec2(0.0), vec2(1.0)));
	}
	if (c01.x != 255 && c01.y == self.y) {
		t01 = cell_sample(c01.x, uv, clamp(p - vec2(i01), vec2(0.0), vec2(1.0)));
	}
	if (c11.x != 255 && c11.y == self.y) {
		t11 = cell_sample(c11.x, uv, clamp(p - vec2(i11), vec2(0.0), vec2(1.0)));
	}
	vec4 t0 = mix(t00, t10, b.x);
	vec4 t1 = mix(t01, t11, b.x);
	vec4 t = mix(t0, t1, b.y);
	ALBEDO = t.rgb;
	ROUGHNESS = t.a;
	METALLIC = 0.0;
}
