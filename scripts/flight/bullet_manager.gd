class_name BulletManager
extends MultiMeshInstance3D
## Every cannon round in the air, simulated and drawn in one place.
## Rounds are glowing tracers that fly in straight lines and hit aircraft
## they pass close to.

signal bullet_hit(shooter: Aircraft, target: Aircraft)

const MAX_BULLETS := 800

var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _life := PackedFloat32Array()
var _teams := PackedInt32Array()
var _damage := PackedFloat32Array()
## Untyped: a shooter may be destroyed while its rounds are still flying.
var _shooters: Array = []
var _terrain: Terrain


func _ready() -> void:
	add_to_group("bullets")
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	var tracer := BoxMesh.new()
	tracer.size = Vector3(0.3, 0.3, 16.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.45)
	tracer.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tracer
	multimesh.instance_count = MAX_BULLETS
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func fire(shooter: Aircraft, from: Vector3, velocity: Vector3, damage: float, lifetime := 1.5) -> void:
	if _positions.size() >= MAX_BULLETS:
		return
	_positions.append(from)
	_velocities.append(velocity)
	_life.append(lifetime)
	_teams.append(shooter.team)
	_damage.append(damage)
	_shooters.append(shooter)


func _process(delta: float) -> void:
	var aircraft := get_tree().get_nodes_in_group("aircraft")
	var i := 0
	while i < _positions.size():
		_life[i] -= delta
		var start := _positions[i]
		var end := start + _velocities[i] * delta
		var done := _life[i] <= 0.0
		if not done:
			for node in aircraft:
				var target := node as Aircraft
				if target.team != _teams[i] and not target.is_destroyed \
						and Missile._segment_distance(target.global_position, start, end) < target.hit_radius:
					var shooter: Aircraft = _shooters[i] if is_instance_valid(_shooters[i]) else null
					target.take_damage(_damage[i], shooter)
					bullet_hit.emit(shooter, target)
					done = true
					break
		if not done and _terrain and end.y < _terrain.height_at(end.x, end.z):
			done = true
		if done:
			_remove(i)
			continue
		_positions[i] = end
		i += 1
	_draw_tracers()


func _remove(i: int) -> void:
	var last := _positions.size() - 1
	_positions[i] = _positions[last]
	_velocities[i] = _velocities[last]
	_life[i] = _life[last]
	_teams[i] = _teams[last]
	_damage[i] = _damage[last]
	_shooters[i] = _shooters[last]
	_positions.resize(last)
	_velocities.resize(last)
	_life.resize(last)
	_teams.resize(last)
	_damage.resize(last)
	_shooters.resize(last)


func _draw_tracers() -> void:
	var count := _positions.size()
	multimesh.visible_instance_count = count
	for i in count:
		var direction := _velocities[i].normalized()
		var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
		multimesh.set_instance_transform(i, Transform3D(Basis.looking_at(direction, up), _positions[i]))
