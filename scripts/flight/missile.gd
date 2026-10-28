class_name Missile
extends Node3D
## Guided air-to-air missile. Steers toward a lead point on its target with a
## limited turn rate, so a hard enough turn (or a flare) makes it miss.

const LAUNCH_SOUND := preload("res://assets/sounds/missile_launch.wav")
const EXPLOSION_SCENE := preload("res://scenes/flight/explosion.tscn")

@export var damage := 70.0
@export var max_speed := 650.0
@export var acceleration := 380.0
## Radians per second. Lower = easier to outturn.
@export var turn_rate := 2.4
@export var lifetime := 9.0
@export var proximity_radius := 15.0
## The seeker gives up if the target gets this far off the missile's nose.
@export var seeker_angle_degrees := 75.0

## An Aircraft or a Flare. Null for an unguided (dumb-fire) shot.
var target: Node3D
var shooter: Aircraft
var team := Aircraft.Team.HALVARD
var speed := 0.0

var _age := 0.0
var _exploded := false
var _terrain: Terrain

@onready var trail: CPUParticles3D = $Trail


## Call before adding to the tree. The missile drops from below the shooter.
func setup(from: Aircraft, at: Node3D, offset: Vector3) -> void:
	shooter = from
	target = at
	team = from.team
	speed = from.speed + 15.0
	transform = from.global_transform.translated_local(offset)


func _ready() -> void:
	add_to_group("missiles")
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	Game.play_sound_at(LAUNCH_SOUND, global_position, 0.0, 0.08, 1500.0)


func _process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		_detonate()
		return
	speed = minf(speed + acceleration * delta, max_speed)

	if _has_target():
		var aim := _lead_point()
		var to_aim := aim - global_position
		if forward().angle_to(to_aim) > deg_to_rad(seeker_angle_degrees):
			target = null  # Overshot or out-turned: the seeker loses it.
		else:
			_turn_toward(to_aim.normalized(), delta)

	var step := forward() * speed * delta
	_check_hits(global_position, global_position + step)
	if _exploded:
		return
	global_position += step

	if _terrain and global_position.y < _terrain.height_at(global_position.x, global_position.z):
		_detonate()


func forward() -> Vector3:
	return -global_basis.z


## True while this missile is guiding on `aircraft`.
func is_tracking(aircraft: Aircraft) -> bool:
	return _has_target() and target == aircraft


func _has_target() -> bool:
	if not is_instance_valid(target):
		return false
	var aircraft := target as Aircraft
	return aircraft == null or not aircraft.is_destroyed


func _lead_point() -> Vector3:
	var target_velocity: Variant = target.get("velocity")
	var aim := target.global_position
	if target_velocity is Vector3:
		var time_to_target := minf(global_position.distance_to(aim) / maxf(speed, 1.0), 3.0)
		aim += (target_velocity as Vector3) * time_to_target * 0.8
	return aim


func _turn_toward(direction: Vector3, delta: float) -> void:
	var current := forward()
	var angle := current.angle_to(direction)
	var axis := current.cross(direction)
	if angle < 0.0001 or axis.length() < 0.0001:
		return
	global_rotate(axis.normalized(), minf(angle, turn_rate * delta))


func _check_hits(from: Vector3, to: Vector3) -> void:
	# Guided: only the target (aircraft or flare) can set it off.
	if _has_target():
		if _segment_distance(target.global_position, from, to) < proximity_radius:
			var aircraft := target as Aircraft
			if aircraft:
				aircraft.take_damage(damage, _shooter_or_null())
			else:
				target.queue_free()  # A flare soaked it up.
			_detonate()
		return
	# Unguided: anything on the other team that it passes close to.
	for node in get_tree().get_nodes_in_group("aircraft"):
		var aircraft := node as Aircraft
		if aircraft.team != team and _segment_distance(aircraft.global_position, from, to) < aircraft.hit_radius * 1.3:
			aircraft.take_damage(damage, _shooter_or_null())
			_detonate()
			return


func _shooter_or_null() -> Aircraft:
	return shooter if is_instance_valid(shooter) else null


func _detonate() -> void:
	if _exploded:
		return
	_exploded = true
	var explosion: Explosion = EXPLOSION_SCENE.instantiate()
	explosion.size = 0.35
	explosion.position = global_position
	get_tree().current_scene.add_child(explosion)
	# Leave the smoke trail behind to fade out on its own.
	trail.emitting = false
	trail.reparent(get_tree().current_scene)
	get_tree().create_timer(trail.lifetime + 0.5, false).timeout.connect(trail.queue_free)
	queue_free()


static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + ab * t)
