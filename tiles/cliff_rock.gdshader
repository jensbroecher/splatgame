shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D tex_rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;

uniform float uv_scale = 0.5;
uniform float normal_depth = 1.3;
uniform float roughness_scale = 1.0;
uniform vec4 rock_tint : source_color = vec4(0.95, 0.93, 0.90, 1.0);
uniform float top_blend_height = 0.25;
uniform float top_blend_strength = 0.45;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_top_dist;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_top_dist = UV2.x;
}

void fragment() {
	vec3 n = abs(v_world_normal);
	vec3 weights = pow(n, vec3(4.0));
	float w_sum = weights.x + weights.y + weights.z;
	if (w_sum > 0.0001) {
		weights /= w_sum;
	} else {
		weights = vec3(0.0, 1.0, 0.0);
	}

	vec2 uv_x = vec2(v_world_pos.z, -v_world_pos.y) * uv_scale;
	vec2 uv_z = vec2(v_world_pos.x, -v_world_pos.y) * uv_scale;

	vec4 alb_x = texture(tex_rock_albedo, uv_x);
	vec4 alb_z = texture(tex_rock_albedo, uv_z);
	float wall_weight = max(weights.x + weights.z, 0.001);
	vec3 rock_alb = (alb_x.rgb * weights.x + alb_z.rgb * weights.z) / wall_weight;
	rock_alb *= rock_tint.rgb;

	vec3 norm_x = texture(tex_rock_normal, uv_x).rgb * 2.0 - 1.0;
	vec3 norm_z = texture(tex_rock_normal, uv_z).rgb * 2.0 - 1.0;
	float sx = v_world_normal.x >= 0.0 ? 1.0 : -1.0;
	float sz = v_world_normal.z >= 0.0 ? 1.0 : -1.0;
	vec3 w_norm_x = vec3(norm_x.z * sx, -norm_x.y, norm_x.x * sx);
	vec3 w_norm_z = vec3(norm_z.x * sz, -norm_z.y, norm_z.z * sz);
	vec3 world_rock_norm = normalize(w_norm_x * weights.x + w_norm_z * weights.z);
	world_rock_norm = normalize(mix(v_world_normal, world_rock_norm, clamp(normal_depth * 0.5, 0.0, 1.0)));

	float rough_x = texture(tex_rock_roughness, uv_x).r;
	float rough_z = texture(tex_rock_roughness, uv_z).r;
	float rock_rough = (rough_x * weights.x + rough_z * weights.z) / wall_weight;
	rock_rough *= roughness_scale;

	float moss_factor = 1.0 - smoothstep(0.0, top_blend_height, v_top_dist);
	moss_factor *= top_blend_strength;

	vec2 uv_grass = v_world_pos.xz * 0.12;
	vec3 grass_col = texture(tex_grass, uv_grass).rgb * vec3(0.85, 0.95, 0.8);

	vec3 final_albedo = mix(rock_alb, grass_col, moss_factor);

	ALBEDO = final_albedo;
	NORMAL = (VIEW_MATRIX * vec4(world_rock_norm, 0.0)).xyz;
	ROUGHNESS = mix(clamp(rock_rough, 0.4, 0.98), 0.9, moss_factor);
	METALLIC = 0.0;
}
