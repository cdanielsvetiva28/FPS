class_name Player
extends CharacterBody3D
## First-person player controller: mouse look, walk/sprint/crouch, jump,
## head bob, footsteps, recoil, health and death.

signal health_changed(current: float, maximum: float)
## Emitted on every hit, with the world position the damage came from.
signal damaged(from_position: Vector3)
signal died

const FOOTSTEP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/footstep_1.wav"),
	preload("res://assets/sounds/footstep_2.wav"),
	preload("res://assets/sounds/footstep_3.wav"),
	preload("res://assets/sounds/footstep_4.wav"),
]
const LAND_SOUND := preload("res://assets/sounds/land.wav")
const HURT_SOUND := preload("res://assets/sounds/player_hurt.wav")

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var crouch_speed := 2.6
@export var jump_velocity := 4.8
## How quickly the player reaches target speed on the ground (higher = snappier).
@export var ground_acceleration := 14.0
## How much the player can steer while airborne.
@export var air_acceleration := 3.0

@export_group("Crouch")
@export var standing_height := 1.8
@export var crouching_height := 1.1
@export var standing_eye_height := 1.6
@export var crouching_eye_height := 0.95
## How quickly the player crouches and stands (per second).
@export var crouch_transition_speed := 7.0

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var max_pitch_degrees := 89.0

@export_group("Controller")
## Turn speed at full right-stick tilt, in radians per second (yaw, pitch).
@export var stick_look_speed := Vector2(3.2, 2.4)
## Higher = finer control near the centre of the stick.
@export var stick_response_curve := 1.8
@export var invert_stick_look := false
## How much looking slows down while the crosshair is over an enemy.
@export_range(0.0, 1.0) var aim_slowdown := 0.45

@export_group("Head Bob")
@export var bob_frequency := 2.2
@export var bob_amplitude := 0.05

@export_group("Health")
@export var max_health := 100.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapons: WeaponHolder = $Head/Camera3D/WeaponHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var health := 0.0
var is_dead := false
var is_crouching := false
var is_sprinting := false
## 0 = standing, 1 = fully crouched.
var crouch_amount := 0.0

var _crouch_toggled := false
## Controller sprint: click L3 once and keep running until you stop.
var _sprint_latched := false
var _capsule: CapsuleShape3D
var _stand_check_shape: CapsuleShape3D
var _bob_time := 0.0
var _step_distance := 0.0
var _fall_speed := 0.0


func _ready() -> void:
	add_to_group("player")
	health = max_health
	# Own copy, since crouching resizes it (and the scene's copy is shared on restart).
	_capsule = (collision_shape.shape as CapsuleShape3D).duplicate()
	collision_shape.shape = _capsule
	_stand_check_shape = CapsuleShape3D.new()
	_stand_check_shape.radius = _capsule.radius - 0.02
	_stand_check_shape.height = standing_height - 0.1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# Look a little slower while aiming down sights.
		var sensitivity := mouse_sensitivity * lerpf(1.0, 0.65, weapons.aim_amount)
		rotate_y(-motion.relative.x * sensitivity)
		head.rotate_x(-motion.relative.y * sensitivity)
		_clamp_pitch()
	elif event.is_action_pressed("crouch_toggle"):
		_crouch_toggled = not _crouch_toggled
	elif event.is_action_pressed("sprint_toggle"):
		_sprint_latched = true
		_crouch_toggled = false


func _process(delta: float) -> void:
	if is_dead or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# Right-stick look. The curve gives fine control near the centre.
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.12)
	if look == Vector2.ZERO:
		return
	var curved := look.normalized() * pow(look.length(), stick_response_curve)
	var speed := stick_look_speed * lerpf(1.0, 0.55, weapons.aim_amount)
	if _crosshair_over_enemy():
		speed *= 1.0 - aim_slowdown
	rotate_y(-curved.x * speed.x * delta)
	head.rotate_x((curved.y if invert_stick_look else -curved.y) * speed.y * delta)
	_clamp_pitch()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	_update_crouch(delta)

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		if is_crouching:
			_crouch_toggled = false  # Jump stands you up instead.
		else:
			velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Not normalized, so a half-tilted stick walks at half speed.
	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	# Sprint only forward, and not while crouching, aiming or shooting.
	var can_sprint := input_dir.y < -0.3 and not is_crouching \
		and not Input.is_action_pressed("aim") and not Input.is_action_pressed("fire")
	if not can_sprint:
		_sprint_latched = false
	is_sprinting = can_sprint and (Input.is_action_pressed("sprint") or _sprint_latched)
	var target_speed := walk_speed
	if is_sprinting:
		target_speed = sprint_speed
	elif is_crouching:
		target_speed = crouch_speed
	target_speed *= lerpf(1.0, 0.6, weapons.aim_amount)

	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	var weight := minf(acceleration * delta, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * target_speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * target_speed, weight)

	var was_on_floor := is_on_floor()
	_fall_speed = -velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor and _fall_speed > 4.0:
		Game.play_sound(LAND_SOUND, linear_to_db(clampf(_fall_speed / 10.0, 0.3, 1.0)))
		Game.rumble(0.2, 0.3, 0.1)

	_update_footsteps(delta)
	_update_head_bob(delta)


func take_damage(amount: float, from_position := Vector3.ZERO, _hit_position := Vector3.ZERO) -> bool:
	if is_dead:
		return false
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	damaged.emit(from_position)
	Game.play_sound(HURT_SOUND, -4.0, 0.1)
	Game.rumble(0.3, 0.6, 0.2)
	if health <= 0.0:
		_die()
		return true
	return false


## Sets health directly (e.g. when restoring a checkpoint).
func set_health(value: float) -> void:
	health = clampf(value, 1.0, max_health)
	health_changed.emit(health, max_health)


## Returns false (and does nothing) if already at full health.
func heal(amount: float) -> bool:
	if is_dead or health >= max_health:
		return false
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
	return true


## Kicks the view up (and sideways) when firing. Angles in degrees.
func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	head.rotate_x(deg_to_rad(pitch_degrees))
	rotate_y(deg_to_rad(yaw_degrees))
	_clamp_pitch()


## The point enemies look and shoot at: upper chest, lower when crouching.
func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * (head.position.y - 0.25)


## Controller aim assist: true when an enemy is right under the crosshair.
func _crosshair_over_enemy() -> bool:
	if not Game.using_controller:
		return false
	var forward := -camera.global_basis.z
	for node in get_tree().get_nodes_in_group("enemies"):
		var to_enemy := (node as Node3D).global_position + Vector3.UP * 1.2 - camera.global_position
		var distance := to_enemy.length()
		# About half a body-width either side of the crosshair.
		if distance > 0.5 and distance < 80.0 and forward.angle_to(to_enemy) < atan(0.6 / distance):
			return true
	return false


func _clamp_pitch() -> void:
	var max_pitch := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x, -max_pitch, max_pitch)


func _update_crouch(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch") or _crouch_toggled
	if wants_crouch:
		is_crouching = true
	elif is_crouching and _has_headroom():
		is_crouching = false

	crouch_amount = move_toward(crouch_amount, 1.0 if is_crouching else 0.0, crouch_transition_speed * delta)
	var eased := smoothstep(0.0, 1.0, crouch_amount)
	# Shrink the capsule from the top, keeping the feet on the ground.
	var height := lerpf(standing_height, crouching_height, eased)
	_capsule.height = height
	collision_shape.position.y = height * 0.5
	head.position.y = lerpf(standing_eye_height, crouching_eye_height, eased)


## True if there's room to stand up (nothing overhead).
func _has_headroom() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_check_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (standing_height * 0.5 + 0.05))
	var exclude: Array[RID] = [get_rid()]
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _update_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 1.0:
		_step_distance = 0.0
		return
	_step_distance += speed * delta
	var stride := 2.3 if is_sprinting else (1.2 if is_crouching else 1.7)
	if _step_distance < stride:
		return
	_step_distance = 0.0

	var volume := -8.0
	if is_sprinting:
		volume = -4.0
		Game.make_noise(global_position, 10.0)  # Sprinting is loud enough for enemies to hear.
	elif is_crouching:
		volume = -18.0
	else:
		Game.make_noise(global_position, 4.0)
	Game.play_sound(FOOTSTEP_SOUNDS.pick_random(), volume, 0.08)


func _die() -> void:
	is_dead = true
	Game.rumble(0.6, 1.0, 0.6)
	weapons.visible = false
	weapons.set_process(false)
	died.emit()

	# Drop to the ground and tip over.
	var tween := create_tween().set_parallel()
	tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(head, "rotation:z", deg_to_rad(70.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _update_head_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var amplitude := bob_amplitude * lerpf(1.0, 0.2, weapons.aim_amount)
	if is_on_floor() and horizontal_speed > 0.5:
		_bob_time += delta * horizontal_speed
		camera.position = Vector3(
			cos(_bob_time * bob_frequency * 0.5) * amplitude,
			sin(_bob_time * bob_frequency) * amplitude,
			0.0
		)
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, minf(delta * 10.0, 1.0))
