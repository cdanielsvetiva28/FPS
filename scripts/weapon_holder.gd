class_name WeaponHolder
extends Node3D
## Holds the player's weapons (its Weapon children): input, switching,
## aim-down-sights, sway and bob. Re-emits the current weapon's signals so
## the HUD only has to connect once.
##
## The holder is scaled down (see player.tscn). Shrinking a view model toward
## the camera looks identical but stops it poking through walls.

signal ammo_changed(in_magazine: int, reserve: int)
signal reload_state_changed(reloading: bool)
signal hit_confirmed(killed: bool)
signal weapon_changed(weapon: Weapon)

const SWITCH_SOUND := preload("res://assets/sounds/weapon_switch.wav")

@export var switch_time := 0.35
## How quickly aiming down sights blends in and out (per second).
@export var aim_speed := 8.0
@export var sway_amount := 0.0012
@export var max_sway := 0.06

var player: Player
var camera: Camera3D
var weapons: Array[Weapon] = []
var current: Weapon
## 0 = hip fire, 1 = fully aimed down sights.
var aim_amount := 0.0

var _current_index := -1
var _previous_index := 0
var _switch_timer := 0.0
var _block_fire := false
var _sway := Vector2.ZERO
var _bob_time := 0.0
var _sprint_amount := 0.0
var _base_fov := 75.0


func _ready() -> void:
	player = owner as Player
	camera = get_parent() as Camera3D
	_base_fov = camera.fov
	for child in get_children():
		if child is Weapon:
			var weapon := child as Weapon
			weapon.holder = self
			weapon.visible = false
			weapon.set_process(false)
			weapons.append(weapon)
	Game.paused_changed.connect(_on_paused_changed)
	switch_to(0, true)


func _unhandled_input(event: InputEvent) -> void:
	if player.is_dead or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_sway += (event as InputEventMouseMotion).relative * sway_amount
	elif event.is_action_pressed("weapon_1"):
		switch_to(0)
	elif event.is_action_pressed("weapon_2"):
		switch_to(1)
	elif event.is_action_pressed("weapon_3"):
		switch_to(2)
	elif event.is_action_pressed("next_weapon"):
		switch_to(wrapi(_current_index + 1, 0, weapons.size()))
	elif event.is_action_pressed("previous_weapon"):
		switch_to(wrapi(_current_index - 1, 0, weapons.size()))
	elif event.is_action_pressed("last_weapon"):
		switch_to(_previous_index)


func _process(delta: float) -> void:
	if current == null or player.is_dead:
		return
	_switch_timer = maxf(_switch_timer - delta, 0.0)

	if _block_fire and not Input.is_action_pressed("fire"):
		_block_fire = false
	var can_act := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _switch_timer <= 0.0
	var wants_aim := can_act and Input.is_action_pressed("aim") and not player.is_sprinting and not current.is_reloading
	aim_amount = move_toward(aim_amount, 1.0 if wants_aim else 0.0, aim_speed * delta)
	camera.fov = lerpf(_base_fov, current.aim_fov, smoothstep(0.0, 1.0, aim_amount))

	if can_act and not player.is_sprinting:
		if Input.is_action_just_pressed("reload"):
			current.reload()
		if Input.is_action_pressed("fire") and not _block_fire:
			current.try_fire(Input.is_action_just_pressed("fire"))

	_update_motion(delta)


func switch_to(index: int, instant := false) -> void:
	if index < 0 or index >= weapons.size() or index == _current_index:
		return
	if current:
		current.cancel_reload()
		current.visible = false
		current.set_process(false)
		current.ammo_changed.disconnect(_on_ammo_changed)
		current.reload_state_changed.disconnect(_on_reload_state_changed)
		current.hit_confirmed.disconnect(_on_hit_confirmed)
		_previous_index = _current_index

	_current_index = index
	current = weapons[index]
	current.visible = true
	current.set_process(true)
	current.ammo_changed.connect(_on_ammo_changed)
	current.reload_state_changed.connect(_on_reload_state_changed)
	current.hit_confirmed.connect(_on_hit_confirmed)

	if not instant:
		_switch_timer = switch_time
		Game.play_sound(SWITCH_SOUND, -6.0)
	weapon_changed.emit(current)
	ammo_changed.emit(current.ammo_in_magazine, current.reserve_ammo)
	reload_state_changed.emit(false)


func current_spread_degrees() -> float:
	return current.current_spread_degrees() if current else 0.0


## Gives every weapon one magazine's worth of reserve ammo.
## Returns false if they were all full already.
func add_ammo_magazines(count := 1) -> bool:
	var took_any := false
	for weapon in weapons:
		if weapon.add_ammo(weapon.magazine_size * count):
			took_any = true
	return took_any


func _update_motion(delta: float) -> void:
	var steady := 1.0 - 0.85 * aim_amount

	# Sway: the gun lags behind mouse movement.
	_sway = _sway.limit_length(max_sway).lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))

	# Bob while walking.
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var bob := Vector3.ZERO
	if player.is_on_floor() and speed > 0.5:
		_bob_time += delta * speed * 1.4
		var strength := clampf(speed / player.walk_speed, 0.0, 1.6) * steady
		bob = Vector3(cos(_bob_time) * 0.012, -absf(sin(_bob_time)) * 0.012, 0.0) * strength

	# Sprint: lower and turn the gun.
	_sprint_amount = move_toward(_sprint_amount, 1.0 if player.is_sprinting else 0.0, delta * 6.0)
	var sprint := smoothstep(0.0, 1.0, _sprint_amount)

	# Switching: the gun drops out of view and comes back up.
	var equip := _switch_timer / switch_time if switch_time > 0.0 else 0.0

	position = bob + Vector3(-0.02, -0.03, 0.0) * sprint
	rotation = Vector3(
		_sway.y * steady - deg_to_rad(14.0) * sprint - deg_to_rad(45.0) * equip,
		_sway.x * steady + deg_to_rad(28.0) * sprint,
		deg_to_rad(12.0) * sprint
	)


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	ammo_changed.emit(in_magazine, reserve)


func _on_reload_state_changed(reloading: bool) -> void:
	reload_state_changed.emit(reloading)


func _on_hit_confirmed(killed: bool) -> void:
	hit_confirmed.emit(killed)


func _on_paused_changed(paused: bool) -> void:
	# The click that resumes the game shouldn't also fire.
	if not paused:
		_block_fire = true
