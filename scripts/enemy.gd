class_name Enemy
extends CharacterBody3D
## Hostile soldier AI.
##
## States:
##   IDLE         Stand guard at its post, or walk a patrol route.
##   INVESTIGATE  Walk to a heard noise (or last-seen position) and look around.
##   COMBAT       Player spotted: face them, keep distance, strafe, fire in bursts.
##                Chases the last-known position when sight is lost.
##   DEAD
##
## Enemies see in a cone (`field_of_view_degrees`) with a line-of-sight check,
## hear gunfire through `Game.noise_made`, and alert nearby allies on contact.

signal died

enum State { IDLE, INVESTIGATE, COMBAT, DEAD }

const AMMO_PICKUP := preload("res://scenes/pickups/ammo_pickup.tscn")
const HEALTH_PICKUP := preload("res://scenes/pickups/health_pickup.tscn")
## Hits above this height (relative to the feet) count as headshots.
const HEAD_HEIGHT := 1.4

@export var max_health := 100.0
@export var headshot_multiplier := 2.5
## Optional: a node whose Node3D children are patrol waypoints, in order.
@export var patrol_route: NodePath
@export var patrol_wait_time := 2.0
@export_range(0.0, 1.0) var health_drop_chance := 0.35

@export_group("Movement")
@export var patrol_speed := 2.0
@export var combat_speed := 3.8
@export var turn_speed := 8.0

@export_group("Senses")
@export var sight_range := 30.0
@export_range(10.0, 360.0) var field_of_view_degrees := 120.0
## Delay between spotting the player and the first shot.
@export var reaction_time := 0.7
## Seconds without seeing the player before giving up the chase.
@export var forget_time := 6.0
## Allies within this distance join the fight when this enemy spots the player.
@export var alert_allies_radius := 15.0

@export_group("Combat")
@export var damage := 7.0
@export var burst_size := 3
@export var burst_interval := 0.12
@export var burst_cooldown_min := 1.0
@export var burst_cooldown_max := 1.8
## Base inaccuracy. Spread also grows with distance and with the player's speed.
@export var base_spread_degrees := 1.5
@export var preferred_distance_min := 6.0
@export var preferred_distance_max := 16.0
@export var max_shot_range := 60.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var body_visual: Node3D = $Body
@onready var torso: MeshInstance3D = $Body/Torso
@onready var head_mesh: MeshInstance3D = $Body/Head
@onready var muzzle: Marker3D = $Body/Gun/Muzzle
@onready var muzzle_flash: OmniLight3D = $Body/Gun/Muzzle/MuzzleFlash
@onready var eyes: Marker3D = $Eyes
@onready var alert_label: Label3D = $AlertLabel
@onready var collision: CollisionShape3D = $CollisionShape3D

static var _tracer_mesh: BoxMesh

var state := State.IDLE
var health := 0.0

var _player: Player
var _can_see_player := false
var _last_known_position := Vector3.ZERO
var _time_since_seen := INF
var _perception_timer := 0.0

var _home_position := Vector3.ZERO
var _home_yaw := 0.0
var _patrol_points: Array[Vector3] = []
var _patrol_index := 0
var _wait_timer := 0.0

var _investigate_arrived := false
var _investigate_timer := 0.0

var _burst_left := 0
var _shot_timer := 0.0
var _burst_timer := 0.0
var _strafe_direction := 0.0
var _strafe_timer := 0.0

var _last_nav_target := Vector3.INF
var _material: StandardMaterial3D
var _base_color: Color


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_home_position = global_position
	_home_yaw = rotation.y

	if not patrol_route.is_empty():
		var route := get_node_or_null(patrol_route)
		if route:
			for point in route.get_children():
				if point is Node3D:
					_patrol_points.append((point as Node3D).global_position)

	# Own copy of the material so hit flashes only affect this enemy.
	_material = torso.get_active_material(0).duplicate() as StandardMaterial3D
	torso.material_override = _material
	head_mesh.material_override = _material
	_base_color = _material.albedo_color

	muzzle_flash.visible = false
	alert_label.visible = false
	_player = get_tree().get_first_node_in_group("player") as Player
	Game.noise_made.connect(_on_noise_made)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = 0.15
		_update_perception()
	_time_since_seen = 0.0 if _can_see_player else _time_since_seen + delta

	match state:
		State.IDLE:
			_process_idle(delta)
		State.INVESTIGATE:
			_process_investigate(delta)
		State.COMBAT:
			_process_combat(delta)

	move_and_slide()


func take_damage(amount: float, from_position := Vector3.ZERO, hit_position := Vector3.ZERO) -> bool:
	if state == State.DEAD:
		return false

	if hit_position != Vector3.ZERO and hit_position.y - global_position.y > HEAD_HEIGHT:
		amount *= headshot_multiplier
	health -= amount
	_material.albedo_color = Color.WHITE
	create_tween().tween_property(_material, "albedo_color", _base_color, 0.15)

	if health <= 0.0:
		_die()
		return true

	# Getting shot reveals roughly where the shooter is.
	if from_position != Vector3.ZERO and not _can_see_player:
		_last_known_position = from_position
	_enter_combat()
	return false


## Called by allies (or anything else) to send this enemy to check a position.
func alert(spot: Vector3) -> void:
	if state == State.DEAD or state == State.COMBAT:
		return
	_investigate(spot)


# --- States ---------------------------------------------------------------

func _process_idle(delta: float) -> void:
	if _patrol_points.is_empty():
		# Stand guard: return to post and face the original direction.
		if _flat_distance(global_position, _home_position) > 1.0:
			_navigate_to(_home_position, patrol_speed, delta)
		else:
			_stop(delta)
			rotation.y = lerp_angle(rotation.y, _home_yaw, minf(2.0 * delta, 1.0))
		return

	if _wait_timer > 0.0:
		_wait_timer -= delta
		_stop(delta)
		return

	var point := _patrol_points[_patrol_index]
	if _flat_distance(global_position, point) < 0.8:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		_wait_timer = patrol_wait_time
		return
	_navigate_to(point, patrol_speed, delta)


func _process_investigate(delta: float) -> void:
	_investigate_timer += delta
	if not _investigate_arrived:
		# Give up walking after a while in case the spot is unreachable.
		if _flat_distance(global_position, _last_known_position) < 1.5 or _investigate_timer > 15.0:
			_investigate_arrived = true
			_investigate_timer = 0.0
		else:
			_navigate_to(_last_known_position, patrol_speed * 1.5, delta)
		return

	# Look around for a few seconds, then go back to normal duty.
	_stop(delta)
	rotation.y += delta * 1.2
	if _investigate_timer > 5.0:
		state = State.IDLE
		alert_label.visible = false


func _process_combat(delta: float) -> void:
	if _player == null or _player.is_dead:
		_stop(delta)
		return

	if not _can_see_player:
		# Hunt: go to where the player was last seen or heard.
		if _flat_distance(global_position, _last_known_position) > 1.5:
			_navigate_to(_last_known_position, combat_speed, delta)
		else:
			_stop(delta)
		if _time_since_seen > forget_time:
			_investigate(_last_known_position)
		return

	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	_face_direction(to_player, delta)

	if distance > preferred_distance_max:
		_navigate_to(_player.global_position, combat_speed, delta, false)
	else:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.2, 2.5)
			_strafe_direction = [-1.0, 0.0, 1.0].pick_random()
		var move := global_transform.basis.x * _strafe_direction
		if distance < preferred_distance_min:
			move -= to_player.normalized()
		move.y = 0.0
		_set_horizontal_velocity(move.normalized() * combat_speed * 0.6, delta)

	_update_shooting(delta, to_player)


func _investigate(spot: Vector3) -> void:
	state = State.INVESTIGATE
	_last_known_position = spot
	_investigate_arrived = false
	_investigate_timer = 0.0
	_show_alert("?", Color(1.0, 0.85, 0.2), 0.0)


func _enter_combat() -> void:
	if state == State.COMBAT:
		return
	state = State.COMBAT
	_burst_left = 0
	_burst_timer = reaction_time
	_show_alert("!", Color(1.0, 0.2, 0.15), 1.2)
	for node in get_tree().get_nodes_in_group("enemies"):
		var ally := node as Enemy
		if ally and ally != self and global_position.distance_to(ally.global_position) <= alert_allies_radius:
			ally.alert(_last_known_position)


func _die() -> void:
	state = State.DEAD
	remove_from_group("enemies")
	died.emit()

	collision.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	alert_label.visible = false
	muzzle_flash.visible = false
	_drop_loot()

	# Fall over backwards.
	var tween := create_tween().set_parallel()
	tween.tween_property(body_visual, "rotation:x", deg_to_rad(90.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(body_visual, "position:y", 0.4, 0.5)

	await get_tree().create_timer(15.0, false).timeout
	queue_free()


# --- Senses ---------------------------------------------------------------

func _update_perception() -> void:
	_can_see_player = false
	if _player == null or _player.is_dead:
		return

	var origin := eyes.global_position
	var target := _player.global_position + Vector3.UP * 1.4
	var to_target := target - origin
	var distance := to_target.length()
	if distance > sight_range:
		return

	# Outside combat, only see inside the view cone (but always notice
	# someone right next to us).
	if state != State.COMBAT and distance > 3.0:
		var forward := -global_transform.basis.z
		var flat := Vector3(to_target.x, 0.0, to_target.z).normalized()
		if forward.dot(flat) < cos(deg_to_rad(field_of_view_degrees * 0.5)):
			return

	var hit := _raycast(origin, target)
	if hit.is_empty() or hit["collider"] != _player:
		return

	_can_see_player = true
	_last_known_position = _player.global_position
	_enter_combat()


func _on_noise_made(noise_position: Vector3, radius: float) -> void:
	if state == State.DEAD or global_position.distance_to(noise_position) > radius:
		return
	if state == State.COMBAT:
		if not _can_see_player:
			_last_known_position = noise_position
		return
	_investigate(noise_position)


# --- Shooting -------------------------------------------------------------

func _update_shooting(delta: float, to_player: Vector3) -> void:
	var forward := -global_transform.basis.z
	var flat := Vector3(to_player.x, 0.0, to_player.z).normalized()
	if forward.dot(flat) < cos(deg_to_rad(20.0)) or to_player.length() > max_shot_range:
		return

	if _burst_left > 0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_fire_shot()
			_burst_left -= 1
			_shot_timer = burst_interval
	else:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_left = burst_size
			_shot_timer = 0.0
			_burst_timer = randf_range(burst_cooldown_min, burst_cooldown_max)


func _fire_shot() -> void:
	var origin := muzzle.global_position
	var target := _player.global_position + Vector3.UP * 1.2
	var distance := origin.distance_to(target)
	var player_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var spread := deg_to_rad(base_spread_degrees + distance * 0.12 + player_speed * 0.5)

	var direction := (target - origin).normalized()
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	direction = (direction + offset.normalized() * tan(spread) * randf()).normalized()

	var end := origin + direction * max_shot_range
	var hit := _raycast(origin, end)
	if not hit.is_empty():
		end = hit["position"]
		var player := hit["collider"] as Player
		if player:
			player.take_damage(damage, global_position, end)

	_spawn_tracer(origin, end)
	muzzle_flash.visible = true
	get_tree().create_timer(0.05).timeout.connect(func() -> void: muzzle_flash.visible = false)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	var direction := (to - from) / maxf(length, 0.001)
	if length < 0.5 or absf(direction.dot(Vector3.UP)) > 0.99:
		return

	if _tracer_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.85, 0.5, 0.7)
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(0.015, 0.015, 1.0)
		_tracer_mesh.material = material

	var tracer := MeshInstance3D.new()
	tracer.mesh = _tracer_mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	tracer.look_at(to, Vector3.UP)
	tracer.scale = Vector3(1.0, 1.0, length)
	get_tree().create_timer(0.06).timeout.connect(tracer.queue_free)


# --- Helpers --------------------------------------------------------------

func _navigate_to(target: Vector3, speed: float, delta: float, face_movement := true) -> void:
	# Only re-path when the destination has moved noticeably.
	if _last_nav_target.distance_to(target) > 1.0:
		nav_agent.target_position = target
		_last_nav_target = target

	var next := target
	if _navigation_ready() and not nav_agent.is_navigation_finished():
		next = nav_agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	if direction.length() < 0.1:
		# No usable path (e.g. navmesh not baked yet): head straight there.
		direction = target - global_position
		direction.y = 0.0
	if direction.length() < 0.1:
		_stop(delta)
		return

	direction = direction.normalized()
	_set_horizontal_velocity(direction * speed, delta)
	if face_movement:
		_face_direction(direction, delta)


func _navigation_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0


func _set_horizontal_velocity(target_velocity: Vector3, delta: float) -> void:
	var weight := minf(10.0 * delta, 1.0)
	velocity.x = lerpf(velocity.x, target_velocity.x, weight)
	velocity.z = lerpf(velocity.z, target_velocity.z, weight)


func _stop(delta: float) -> void:
	_set_horizontal_velocity(Vector3.ZERO, delta)


func _face_direction(direction: Vector3, delta: float) -> void:
	if Vector2(direction.x, direction.z).length() < 0.01:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var exclude: Array[RID] = [get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _show_alert(text: String, color: Color, duration: float) -> void:
	alert_label.text = text
	alert_label.modulate = color
	alert_label.visible = true
	if duration > 0.0:
		await get_tree().create_timer(duration, false).timeout
		if alert_label.text == text and state != State.DEAD:
			alert_label.visible = false


func _drop_loot() -> void:
	var scene := HEALTH_PICKUP if randf() < health_drop_chance else AMMO_PICKUP
	var pickup := scene.instantiate() as Node3D
	pickup.position = global_position
	get_tree().current_scene.add_child.call_deferred(pickup)
