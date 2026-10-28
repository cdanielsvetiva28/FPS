extends Node3D
## Scatters pine forests over the terrain's lowlands, in clumps. Trees are
## drawn with MultiMeshes split into a grid of chunks, so far-away chunks are
## culled.

@export var tree_count := 7000
@export var chunks_per_side := 6
@export var min_height := 14.0
@export var max_height := 420.0
## Trees only grow on slopes gentler than this (1 = flat ground).
@export var min_flatness := 0.82
@export var visible_distance := 4500.0
@export var noise_seed := 11


func _ready() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain
	if terrain == null:
		return
	var tree_mesh := _load_tree_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var clumps := FastNoiseLite.new()
	clumps.seed = noise_seed
	clumps.frequency = 0.0012

	var half := terrain.size * 0.5
	var chunk_size := terrain.size / chunks_per_side
	var buckets: Array[Array] = []
	buckets.resize(chunks_per_side * chunks_per_side)
	for i in buckets.size():
		buckets[i] = []

	var attempts := 0
	var placed := 0
	while placed < tree_count and attempts < tree_count * 6:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if clumps.get_noise_2d(x, z) < 0.05:
			continue
		var h := terrain.height_at(x, z)
		if h < min_height or h > max_height:
			continue
		var dx := terrain.height_at(x + 6.0, z) - terrain.height_at(x - 6.0, z)
		var dz := terrain.height_at(x, z + 6.0) - terrain.height_at(x, z - 6.0)
		if Vector3(-dx, 12.0, -dz).normalized().y < min_flatness:
			continue
		var tree_scale := rng.randf_range(1.4, 2.6)
		var orientation := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * tree_scale)
		var cx := clampi(int((x + half) / chunk_size), 0, chunks_per_side - 1)
		var cz := clampi(int((z + half) / chunk_size), 0, chunks_per_side - 1)
		buckets[cz * chunks_per_side + cx].append(Transform3D(orientation, Vector3(x, h - 0.5, z)))
		placed += 1

	for bucket in buckets:
		if bucket.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = tree_mesh
		multimesh.instance_count = bucket.size()
		for i in bucket.size():
			multimesh.set_instance_transform(i, bucket[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.visibility_range_end = visible_distance
		instance.visibility_range_end_margin = 400.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(instance)


func _load_tree_mesh() -> Mesh:
	var model := (load("res://assets/models/props/pine_tree.glb") as PackedScene).instantiate()
	var mesh_instance := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := mesh_instance.mesh
	model.free()
	return mesh
