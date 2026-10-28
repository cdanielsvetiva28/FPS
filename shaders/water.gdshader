// Sea: two scrolling normal maps for waves, colour by water depth
// (turquoise in the shallows, dark blue offshore) and foam at the shoreline.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.15);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.33, 0.36);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.97);
uniform sampler2D wave_normals : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float wave_scale = 0.006;
uniform float wave_speed = 0.015;
// Water deeper than this (metres) shows the full deep colour.
uniform float depth_fade = 30.0;
uniform float foam_depth = 2.5;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv_a = world.xz * wave_scale + TIME * wave_speed * vec2(1.0, 0.35);
	vec2 uv_b = world.xz * wave_scale * 2.7 - TIME * wave_speed * vec2(0.45, 1.0);
	NORMAL_MAP = mix(texture(wave_normals, uv_a).rgb, texture(wave_normals, uv_b).rgb, 0.5);
	NORMAL_MAP_DEPTH = 0.7;

	// How much water lies between the surface and the ground behind it.
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	behind.xyz /= behind.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);

	float deep = clamp(water_depth / depth_fade, 0.0, 1.0);
	vec3 color = mix(shallow_color, deep_color, deep);
	float foam = 1.0 - smoothstep(0.0, foam_depth, water_depth);
	foam *= 0.65 + 0.35 * sin(TIME * 1.3 + world.x * 0.04 + world.z * 0.03);

	ALBEDO = mix(color, foam_color, foam * 0.85);
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(0.7 + deep * 0.3 + foam, 0.0, 1.0);
}
