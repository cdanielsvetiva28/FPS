class_name PlayerJet
extends Aircraft
## The player's fighter: mouse-and-keyboard flight, cannon, lock-on missiles,
## flares, and chase / cockpit cameras.
##
## The mouse moves a virtual stick that slowly re-centres, so small mouse
## movements make small corrections and big sweeps make hard turns.

signal target_changed(target: Aircraft)
signal hit_confirmed(killed: bool)

const MISSILE_SCENE := preload("res://scenes/flight/missile.tscn")
const ENGINE_SOUND := preload("res://assets/sounds/jet_engine.wav")
const CANNON_SOUND := preload("res://assets/sounds/cannon_shot.wav")
const LOCK_SEEK_SOUND := preload("res://assets/sounds/lock_seek.wav")
const LOCK_SOLID_SOUND := preload("res://assets/sounds/lock_solid.wav")
## Where the two missiles hang under the wings (matches the jet model).
const PYLON_OFFSETS: Array[Vector3] = [Vector3(3.4, -0.6, 1.6), Vector3(-3.4, -0.6, 1.6)]

@export_group("Controls")
@export var mouse_sensitivity := 0.004
## How fast the virtual stick returns to centre (per second).
@export var stick_recenter := 2.2
@export var invert_pitch := false
## Throttle change per second while holding W/S.
@export var throttle_rate := 0.6

@export_group("Weapons")
@export var gun_damage := 6.0
@export var gun_rounds_per_second := 20.0
@export var gun_ammo := 1600
@export var gun_spread_degrees := 0.35
@export var missile_ammo := 60
@export var missile_reload_time := 2.5
@export var lock_range := 3200.0
@export var lock_cone_degrees := 30.0
@export var lock_time := 0.8
@export var flare_count := 24
@export var flare_cooldown := 3.0

@export_group("Camera")
@export var chase_offset := Vector3(0.0, 5.0, 21.0)
@export var cockpit_offset := Vector3(0.0, 1.25, -3.4)

@onready var camera: Camera3D = $Camera
@onready var model: Node3D = $Model
@onready var engine_audio: AudioStreamPlayer = $EngineAudio

## x = roll, y = pitch (mouse down = positive).
var stick := Vector2.ZERO
var target: Aircraft
## 0..1; missiles home in once it reaches 1.
var lock_progress := 0.0
var gun_ammo_left := 0
var missiles_left := 0
var flares_left := 0
var cockpit_view := false
## Set when the player flies into the ground, for the mission's death message.
var crashed := false

var _pylon_timers: Array[float] = [0.0, 0.0]
var _pylon_meshes: Array[Node3D] = []
var _next_pylon := 0
var _gun_cooldown := 0.0
var _flare_timer := 0.0
var _lock_beep_timer := 0.0
var _lock_tone: AudioStreamPlayer
var _canopy: Node3D
var _camera_rotation := Quaternion.IDENTITY
var _bullets: BulletManager
var _terrain: Terrain


func _ready() -> void:
	super()
	add_to_group("player_jet")
	gun_ammo_left = gun_ammo
	missiles_left = missile_ammo
	flares_left = flare_count
	for mesh_name in ["Missile_R", "Missile_L"]:
		_pylon_meshes.append(model.find_child(mesh_name, true, false) as Node3D)
	_canopy = model.find_child("Canopy", true, false) as Node3D

	camera.top_level = true
	_camera_rotation = global_basis.get_rotation_quaternion()
	_update_camera(1.0)
	camera.make_current()

	engine_audio.stream = Game.looping(ENGINE_SOUND)
	engine_audio.play()
	_lock_tone = AudioStreamPlayer.new()
	_lock_tone.stream = Game.looping(LOCK_SOLID_SOUND)
	_lock_tone.volume_db = -14.0
	add_child(_lock_tone)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if is_destroyed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		stick += (event as InputEventMouseMotion).relative * mouse_sensitivity
		stick = stick.limit_length(1.0)
	elif event.is_action_pressed("switch_target"):
		_cycle_target()
	elif event.is_action_pressed("camera_toggle"):
		cockpit_view = not cockpit_view
	elif event.is_action_pressed("flares"):
		_deploy_flares()


func _process(delta: float) -> void:
	if _bullets == null:
		_bullets = get_tree().get_first_node_in_group("bullets") as BulletManager
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	if is_destroyed:
		_update_camera(delta)
		return

	throttle = clampf(throttle + Input.get_axis("throttle_down", "throttle_up") * throttle_rate * delta, 0.0, 1.0)
	stick = stick.move_toward(Vector2.ZERO, stick_recenter * delta)
	var pitch := stick.y if invert_pitch else -stick.y
	var roll := clampf(stick.x + Input.get_axis("roll_left", "roll_right"), -1.0, 1.0)
	fly(pitch, roll, Input.get_axis("yaw_left", "yaw_right"), delta)

	_check_ground_collision()
	if is_destroyed:
		return
	_update_targeting(delta)
	_update_weapons(delta)
	_update_camera(delta)
	_update_audio()


func is_locked() -> bool:
	return is_instance_valid(target) and not target.is_destroyed and lock_progress >= 1.0


## Height above whatever is below: ground or sea.
func clearance() -> float:
	if _terrain == null:
		return global_position.y
	return global_position.y - maxf(_terrain.height_at(global_position.x, global_position.z), 0.0)


func enemies() -> Array[Aircraft]:
	var result: Array[Aircraft] = []
	for node in get_tree().get_nodes_in_group("aircraft"):
		var aircraft := node as Aircraft
		if aircraft.team != team and not aircraft.is_destroyed:
			result.append(aircraft)
	return result


## Called by aircraft we damage (see Aircraft.take_damage).
func notify_hit(killed: bool) -> void:
	hit_confirmed.emit(killed)


func _on_destroyed() -> void:
	# Keep the node (and its camera) around; just hide the jet.
	model.visible = false
	engine_audio.stop()
	_lock_tone.stop()


func _check_ground_collision() -> void:
	if clearance() < 2.5:
		crashed = true
		destroy()


# --- Targeting -----------------------------------------------------------------

func _update_targeting(delta: float) -> void:
	if not is_instance_valid(target) or target.is_destroyed:
		_set_target(_best_target())
	if target == null:
		lock_progress = 0.0
	else:
		var in_range := global_position.distance_to(target.global_position) < lock_range
		var in_cone := angle_to_point(target.global_position) < deg_to_rad(lock_cone_degrees)
		if in_range and in_cone:
			lock_progress = minf(lock_progress + delta / lock_time, 1.0)
		else:
			lock_progress = maxf(lock_progress - delta * 2.0 / lock_time, 0.0)

	# Lock tones: beeping while acquiring, a solid tone once locked.
	if lock_progress >= 1.0:
		if not _lock_tone.playing:
			_lock_tone.play()
	else:
		_lock_tone.stop()
		if lock_progress > 0.0:
			_lock_beep_timer -= delta
			if _lock_beep_timer <= 0.0:
				_lock_beep_timer = 0.16
				Game.play_sound(LOCK_SEEK_SOUND, -12.0, 0.0)


func _set_target(new_target: Aircraft) -> void:
	if new_target == target:
		return
	target = new_target
	lock_progress = 0.0
	target_changed.emit(target)


## Prefers enemies near the nose, then nearby ones.
func _best_target() -> Aircraft:
	var best: Aircraft = null
	var best_score := INF
	for enemy in enemies():
		var score := rad_to_deg(angle_to_point(enemy.global_position)) * 60.0 \
			+ global_position.distance_to(enemy.global_position)
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _cycle_target() -> void:
	var list := enemies()
	if list.is_empty():
		return
	list.sort_custom(func(a: Aircraft, b: Aircraft) -> bool:
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	var index := list.find(target)
	_set_target(list[(index + 1) % list.size()])


# --- Weapons -------------------------------------------------------------------

func _update_weapons(delta: float) -> void:
	_gun_cooldown -= delta
	_flare_timer -= delta
	for i in _pylon_timers.size():
		_pylon_timers[i] = maxf(_pylon_timers[i] - delta, 0.0)
		if _pylon_meshes[i]:
			_pylon_meshes[i].visible = _pylon_timers[i] <= 0.0 and missiles_left > i

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if Input.is_action_pressed("fire") and _gun_cooldown <= 0.0 and gun_ammo_left > 0:
		_fire_gun()
	if Input.is_action_just_pressed("fire_missile"):
		_fire_missile()


func _fire_gun() -> void:
	_gun_cooldown = 1.0 / gun_rounds_per_second
	gun_ammo_left -= 1
	var spread := deg_to_rad(gun_spread_degrees)
	var direction := (forward() + global_basis.x * randf_range(-spread, spread)
		+ global_basis.y * randf_range(-spread, spread)).normalized()
	var muzzle := global_position + forward() * 9.0 - global_basis.y * 0.3
	_bullets.fire(self, muzzle, direction * 1100.0 + velocity, gun_damage, 1.4)
	Game.play_sound(CANNON_SOUND, -12.0, 0.08)


func _fire_missile() -> void:
	if missiles_left <= 0:
		return
	# Alternate pylons; use whichever is loaded.
	var pylon := _next_pylon if _pylon_timers[_next_pylon] <= 0.0 else 1 - _next_pylon
	if _pylon_timers[pylon] > 0.0:
		return
	missiles_left -= 1
	_pylon_timers[pylon] = missile_reload_time
	_next_pylon = 1 - pylon

	var missile: Missile = MISSILE_SCENE.instantiate()
	missile.setup(self, target if is_locked() else null, PYLON_OFFSETS[pylon])
	get_tree().current_scene.add_child(missile)


func _deploy_flares() -> void:
	if _flare_timer > 0.0 or flares_left <= 0:
		return
	_flare_timer = flare_cooldown
	flares_left -= 1
	var scene := get_tree().current_scene
	var flares: Array[Flare] = []
	for i in 4:
		var side := 1.0 if i % 2 == 0 else -1.0
		var launch := velocity * 0.6 + global_basis.x * side * randf_range(15.0, 30.0) \
			- global_basis.y * randf_range(10.0, 25.0)
		flares.append(Flare.spawn(scene, global_position + global_basis.z * 4.0, launch))
	# Most missiles tracking us go for the flares instead.
	for node in get_tree().get_nodes_in_group("missiles"):
		var missile := node as Missile
		if missile.is_tracking(self) and missile.global_position.distance_to(global_position) < 3000.0 \
				and randf() < 0.8:
			missile.target = flares.pick_random()


# --- Camera & audio -------------------------------------------------------------

func _update_camera(delta: float) -> void:
	if cockpit_view and not is_destroyed:
		camera.global_transform = global_transform.translated_local(cockpit_offset)
		if _canopy:
			_canopy.visible = false
	else:
		if _canopy:
			_canopy.visible = true
		# The chase camera lags slightly behind the jet's rotation.
		_camera_rotation = _camera_rotation.slerp(global_basis.get_rotation_quaternion(), minf(5.0 * delta, 1.0))
		var camera_basis := Basis(_camera_rotation)
		var eye := global_position + camera_basis * chase_offset
		camera.global_transform = Transform3D(camera_basis, eye).looking_at(
			global_position + camera_basis * Vector3(0, 2, -60), camera_basis.y)
	# Widen the view at high speed for a sense of speed.
	var speed_factor := clampf((speed - cruise_speed) / (max_speed - cruise_speed), 0.0, 1.0)
	camera.fov = lerpf(70.0, 80.0, speed_factor)


func _update_audio() -> void:
	engine_audio.pitch_scale = 0.75 + throttle * 0.55
	engine_audio.volume_db = -14.0 + throttle * 7.0
