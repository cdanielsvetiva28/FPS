// Flight terrain: blends grass, sand, rock and snow by height and slope.
// Textures are sampled at two scales to hide tiling; rock uses triplanar
// mapping so cliffs don't stretch.
shader_type spatial;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Textures repeat every 1 / tile_scale metres.
uniform float tile_scale = 0.05;
uniform float beach_height = 10.0;
uniform float snow_height = 680.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 two_scale(sampler2D tex, vec2 uv) {
	return mix(texture(tex, uv).rgb, texture(tex, uv * 0.11).rgb, 0.45);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
}

void fragment() {
	vec2 uv = world_position.xz * tile_scale;
	float height = world_position.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	// Large-scale variation from the vertex colours, so the land isn't uniform.
	float variation = dot(COLOR.rgb, vec3(0.333));

	vec3 grass = two_scale(grass_texture, uv) * mix(0.8, 1.15, variation * 2.0);
	vec3 sand = two_scale(sand_texture, uv);
	vec3 rock = triplanar(rock_texture, world_position * tile_scale * 0.7, world_normal);
	vec3 snow = two_scale(snow_texture, uv);

	vec3 color = grass;
	color = mix(color, sand, 1.0 - smoothstep(beach_height - 6.0, beach_height + 4.0, height));
	// Rock on steep slopes and high up; snow on the peaks (but not on cliffs).
	float rockiness = max(smoothstep(0.28, 0.45, slope), smoothstep(420.0, 600.0, height) * 0.8);
	color = mix(color, rock, rockiness);
	float snowiness = smoothstep(snow_height - 80.0, snow_height + 60.0, height) * (1.0 - smoothstep(0.35, 0.55, slope));
	color = mix(color, snow, snowiness);

	ALBEDO = color;
	ROUGHNESS = mix(0.95, 0.6, snowiness);
}
