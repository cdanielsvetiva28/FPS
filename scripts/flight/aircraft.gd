class_name Aircraft
extends Node3D
## Shared arcade flight model, health and destruction for every jet.
##
## Aircraft aren't physics bodies: they fly along their nose (-Z) at `speed`,
## and collisions (bullets, missiles, terrain) are simple distance checks.
## Subclasses call `fly()` every frame with stick inputs in -1..1.

signal destroyed(aircraft: Aircraft)
signal damaged(amount: float)

const EXPLOSION_SCENE := preload("res://scenes/flight/explosion.tscn")

enum Team { HALVARD, SEVRIN }

@export var display_name := "Fighter"
@export var team := Team.HALVARD
@export var max_health := 100.0
## Bullets and missiles hit within this distance of the aircraft's centre.
@export var hit_radius := 9.0
## Distance from the centreline to each wingtip, for vapour trails.
@export var wingtip_span := 5.5

@export_group("Flight Model")
## Below this the aircraft stalls and the nose drops.
@export var stall_speed := 75.0
@export var cruise_speed := 200.0
@export var max_speed := 340.0
## How quickly speed approaches the throttle setting (m/s²).
@export var engine_acceleration := 45.0
## Rotation rates at full stick, in radians per second.
@export var pitch_rate := 1.5
@export var roll_rate := 3.2
@export var yaw_rate := 0.45

var health := 0.0
var speed := 200.0
## 0 = idle, 1 = full afterburner.
var throttle := 0.5
var velocity := Vector3.ZERO
var is_destroyed := false

var _afterburners: Array[Node3D] = []
var _damage_smoke: CPUParticles3D
var _vapor_trails: Array[CPUParticles3D] = []


func _ready() -> void:
	add_to_group("aircraft")
	health = max_health
	speed = cruise_speed
	velocity = -global_basis.z * speed
	var model := get_node_or_null("Model")
	if model:
		for node in model.find_children("Afterburner*", "", true, false):
			_afterburners.append(node as Node3D)
	_damage_smoke = _make_damage_smoke()
	add_child(_damage_smoke)
	for side: float in [-1.0, 1.0]:
		var trail := _make_vapor_trail()
		trail.position = Vector3(side * wingtip_span, 0.1, 3.5)
		add_child(trail)
		_vapor_trails.append(trail)


## Applies stick inputs (each -1..1) and moves the aircraft. Call once per frame.
## pitch > 0 = nose up, roll > 0 = roll right, yaw > 0 = nose right.
func fly(pitch: float, roll: float, yaw: float, delta: float) -> void:
	# Less control authority at low speed.
	var authority := clampf((speed - stall_speed * 0.6) / (cruise_speed - stall_speed * 0.6), 0.25, 1.0)
	rotate_object_local(Vector3.RIGHT, clampf(pitch, -1.0, 1.0) * pitch_rate * authority * delta)
	rotate_object_local(Vector3.FORWARD, clampf(roll, -1.0, 1.0) * roll_rate * authority * delta)
	rotate_object_local(Vector3.UP, -clampf(yaw, -1.0, 1.0) * yaw_rate * authority * delta)

	# Banking turns the nose gently toward the low wing, like real lift does.
	rotate(Vector3.UP, global_basis.x.y * 0.5 * authority * delta)

	# Speed follows the throttle; climbing bleeds speed, diving builds it.
	var target_speed := lerpf(stall_speed + 25.0, max_speed, throttle)
	speed = move_toward(speed, target_speed, engine_acceleration * delta)
	speed -= -global_basis.z.y * 9.8 * 0.9 * delta
	speed = clampf(speed, stall_speed * 0.5, max_speed * 1.2)

	# Stall: the nose drops toward the ground until speed recovers.
	if speed < stall_speed:
		var severity := (stall_speed - speed) / stall_speed
		var forward := -global_basis.z
		var axis := forward.cross(Vector3.DOWN)
		if axis.length() > 0.01:
			rotate(axis.normalized(), severity * 1.5 * delta)

	transform.basis = transform.basis.orthonormalized()
	velocity = -global_basis.z * speed
	global_position += velocity * delta
	_update_afterburners()
	# Wingtip vapour in hard, fast turns.
	var pulling_hard := absf(pitch) > 0.55 and speed > 170.0
	for trail in _vapor_trails:
		trail.emitting = pulling_hard


## `source` is whoever fired. If it has a `notify_hit(killed)` method (the
## player does), it's told about the hit, for hit markers.
func take_damage(amount: float, source: Node = null) -> void:
	if is_destroyed:
		return
	health -= amount
	damaged.emit(amount)
	_damage_smoke.emitting = health < max_health * 0.5
	if health <= 0.0:
		destroy()
	if is_instance_valid(source) and source.has_method("notify_hit"):
		source.call("notify_hit", is_destroyed)


func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	health = 0.0
	var explosion: Explosion = EXPLOSION_SCENE.instantiate()
	explosion.size = 1.0
	explosion.position = global_position
	get_tree().current_scene.add_child(explosion)
	remove_from_group("aircraft")
	destroyed.emit(self)
	_on_destroyed()


## Override for what happens to the aircraft itself (hide, free, ...).
func _on_destroyed() -> void:
	queue_free()


func forward() -> Vector3:
	return -global_basis.z


## Angle in radians between the nose and a world position.
func angle_to_point(point: Vector3) -> float:
	return forward().angle_to(point - global_position)


func _update_afterburners() -> void:
	# Stretch the afterburner cones with throttle; hide them at low power.
	var flame := clampf((throttle - 0.55) / 0.45, 0.0, 1.0)
	for burner in _afterburners:
		burner.visible = flame > 0.05
		burner.scale = Vector3(1.0, 1.0, lerpf(0.3, 1.0, flame))


func _make_vapor_trail() -> CPUParticles3D:
	var trail := CPUParticles3D.new()
	trail.emitting = false
	trail.amount = 60
	trail.lifetime = 0.7
	trail.local_coords = false
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	trail.mesh = mesh
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.5
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.55))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	trail.color_ramp = ramp
	return trail


func _make_damage_smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 40
	smoke.lifetime = 1.6
	smoke.local_coords = false
	smoke.position = Vector3(0, 0.5, 6)
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	smoke.mesh = mesh
	smoke.gravity = Vector3(0, 2, 0)
	smoke.initial_velocity_min = 0.0
	smoke.initial_velocity_max = 2.0
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.25, 0.24, 0.23, 0.7))
	ramp.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	smoke.color_ramp = ramp
	return smoke
