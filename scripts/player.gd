class_name Player
extends CharacterBody3D
## First-person player controller: mouse look, walk/sprint, jump and head bob.

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

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/Weapon

var _bob_time := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Click back into the game; don't let that same click fire the weapon.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		weapon.block_until_release = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotate_x(-motion.relative.y * mouse_sensitivity)
		var max_pitch := deg_to_rad(max_pitch_degrees)
		head.rotation.x = clampf(head.rotation.x, -max_pitch, max_pitch)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
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
