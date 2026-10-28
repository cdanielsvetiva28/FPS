extends MultiMeshInstance3D
## Scattered puffy cloud banks. Mostly there to give a sense of speed and
## altitude when flying past them.

@export var cloud_count := 70
@export var area := 11000.0
@export var min_altitude := 1300.0
@export var max_altitude := 2100.0
@export var noise_seed := 5


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 12
	puff.rings = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.97, 0.97, 1.0)
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = Color(0.35, 0.37, 0.42)
	puff.material = material

	var transforms: Array[Transform3D] = []
	for i in cloud_count:
		var center := Vector3(
			rng.randf_range(-area, area) * 0.5,
			rng.randf_range(min_altitude, max_altitude),
			rng.randf_range(-area, area) * 0.5
		)
		# Each cloud is a cluster of flattened puffs.
		for j in rng.randi_range(5, 9):
			var offset := Vector3(rng.randf_range(-260, 260), rng.randf_range(-30, 60), rng.randf_range(-160, 160))
			var radius := rng.randf_range(90.0, 190.0)
			var shape := Basis.from_scale(Vector3(radius * 1.4, radius * 0.6, radius))
			transforms.append(Transform3D(shape.rotated(Vector3.UP, rng.randf() * TAU), center + offset))

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = puff
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
