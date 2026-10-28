class_name Terrain
extends MeshInstance3D
## Procedural island terrain: mountains in the middle, sea at the edges.
## Built at load time from noise. Aircraft don't collide with it physically;
## they compare their altitude against `height_at()`.

@export var size := 12000.0
## Grid cells per side. Higher = more detail, slower to build.
@export var resolution := 200
@export var max_height := 1100.0
@export var noise_seed := 2047

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _ready() -> void:
	add_to_group("terrain")
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.00022
	_noise.fractal_octaves = 5
	_detail.seed = noise_seed + 1
	_detail.frequency = 0.004
	_build_mesh()


## Ground height in metres at a world position. Below 0 is under the sea.
func height_at(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	# Ridged, peaky mountains with flatter lowlands.
	var h := pow(clampf((n - 0.32) / 0.68, 0.0, 1.0), 1.7) * max_height
	h += _detail.get_noise_2d(x, z) * 12.0
	# Fall off toward the edges so the island ends in sea.
	var edge := Vector2(x, z).length() / (size * 0.5)
	h *= clampf((1.0 - edge) * 2.5, 0.0, 1.0)
	return h - 40.0


func _build_mesh() -> void:
	var cell := size / resolution
	var half := size * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := resolution + 1
	vertices.resize(count * count)
	normals.resize(count * count)
	colors.resize(count * count)

	for zi in count:
		for xi in count:
			var x := xi * cell - half
			var z := zi * cell - half
			var h := height_at(x, z)
			var i := zi * count + xi
			vertices[i] = Vector3(x, h, z)
			var dx := height_at(x + cell, z) - height_at(x - cell, z)
			var dz := height_at(x, z + cell) - height_at(x, z - cell)
			var normal := Vector3(-dx, 2.0 * cell, -dz).normalized()
			normals[i] = normal
			colors[i] = _ground_color(h, normal.y)

	for zi in resolution:
		for xi in resolution:
			var a := zi * count + xi
			var b := a + 1
			var c := a + count
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Grass/sand/rock/snow blended by height and slope (shaders/terrain.gdshader).
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	for layer in ["grass", "sand", "rock", "snow"]:
		material.set_shader_parameter(layer + "_texture", load("res://assets/textures/%s_albedo.png" % layer))
	array_mesh.surface_set_material(0, material)
	mesh = array_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ground_color(height: float, flatness: float) -> Color:
	var sand := Color(0.76, 0.7, 0.52)
	var grass := Color(0.32, 0.42, 0.22)
	var forest := Color(0.18, 0.3, 0.16)
	var rock := Color(0.42, 0.39, 0.36)
	var snow := Color(0.95, 0.96, 0.98)
	var color: Color
	if height < 8.0:
		color = sand
	elif height < 250.0:
		color = grass.lerp(forest, clampf((height - 60.0) / 190.0, 0.0, 1.0))
	elif height < 650.0:
		color = forest.lerp(rock, clampf((height - 250.0) / 400.0, 0.0, 1.0))
	else:
		color = rock.lerp(snow, clampf((height - 650.0) / 200.0, 0.0, 1.0))
	# Steep slopes are bare rock.
	return color.lerp(rock, clampf((0.85 - flatness) * 3.0, 0.0, 1.0))
