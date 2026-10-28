extends MultiMeshInstance3D
## Scattered cumulus clouds made of soft billboard sprites (cloud_puff.png).
## They give a sense of speed and altitude when flying past.

@export var cloud_count := 80
@export var area := 11000.0
@export var min_altitude := 1300.0
@export var max_altitude := 2200.0
@export var noise_seed := 5


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load("res://assets/textures/cloud_puff.png")
	material.albedo_color = Color(1.0, 0.98, 0.96, 0.92)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Fade puffs out when the camera flies right through them.
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = 40.0
	material.distance_fade_max_distance = 260.0
	var quad := QuadMesh.new()
	quad.material = material

	var transforms: Array[Transform3D] = []
	for i in cloud_count:
		var center := Vector3(
			rng.randf_range(-area, area) * 0.5,
			rng.randf_range(min_altitude, max_altitude),
			rng.randf_range(-area, area) * 0.5
		)
		# Each cloud is a cluster of puffs, wider than tall, flatter underneath.
		for j in rng.randi_range(8, 14):
			var offset := Vector3(rng.randf_range(-380, 380), rng.randf_range(-40, 110), rng.randf_range(-240, 240))
			var size := rng.randf_range(220.0, 420.0) * (1.0 - absf(offset.x) / 900.0)
			transforms.append(Transform3D(Basis.from_scale(Vector3.ONE * size), center + offset))

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
