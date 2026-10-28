class_name Player
extends CharacterBody3D
## First-person player controller: mouse look, walk/sprint, jump, head bob,
## health and death.

signal health_changed(current: float, maximum: float)
## Emitted on every hit, with the world position the damage came from.
signal damaged(from_position: Vector3)
signal died

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.8
## How quickly the player reaches target speed on the ground (higher = snappier).
@export var ground_acceleration := 14.0
## How much the player can steer while airborne.
@export var air_acceleration := 3.0

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var max_pitch_degrees := 89.0

@export_group("Head Bob")
@export var bob_frequency := 2.2
@export var bob_amplitude := 0.05

@export_group("Health")
@export var max_health := 100.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/Weapon

var health := 0.0
var is_dead := false

var _bob_time := 0.0


func _ready() -> void:
	add_to_group("player")
	health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotate_x(-motion.relative.y * mouse_sensitivity)
		var max_pitch := deg_to_rad(max_pitch_degrees)
		head.rotation.x = clampf(head.rotation.x, -max_pitch, max_pitch)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Only sprint while moving forward.
	var sprinting := Input.is_action_pressed("sprint") and input_dir.y < 0.0
	var target_speed := sprint_speed if sprinting else walk_speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	var weight := minf(acceleration * delta, 1.0)

	velocity.x = lerpf(velocity.x, direction.x * target_speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * target_speed, weight)

	move_and_slide()
	_update_head_bob(delta)


func take_damage(amount: float, from_position := Vector3.ZERO, _hit_position := Vector3.ZERO) -> bool:
	if is_dead:
		return false
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	damaged.emit(from_position)
	if health <= 0.0:
		_die()
		return true
	return false


## Returns false (and does nothing) if already at full health.
func heal(amount: float) -> bool:
	if is_dead or health >= max_health:
		return false
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
	return true


func _die() -> void:
	is_dead = true
	weapon.visible = false
	weapon.set_process(false)
	died.emit()

	# Drop to the ground and tip over.
	var tween := create_tween().set_parallel()
	tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(head, "rotation:z", deg_to_rad(70.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _update_head_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.5:
		_bob_time += delta * horizontal_speed
		camera.position = Vector3(
			cos(_bob_time * bob_frequency * 0.5) * bob_amplitude,
			sin(_bob_time * bob_frequency) * bob_amplitude,
			0.0
		)
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, minf(delta * 10.0, 1.0))
