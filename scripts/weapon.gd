class_name Weapon
extends Node3D
## One gun: stats, firing, ammo, reloading and its first-person model.
## Lives under a WeaponHolder, which handles input, switching, aiming and sway.
##
## Shots are fired from the centre of the camera. Anything hit that has a
## `take_damage(amount: float, from_position: Vector3, hit_position: Vector3) -> bool`
## method takes damage; it should return true when the hit killed it.

signal ammo_changed(in_magazine: int, reserve: int)
signal reload_state_changed(reloading: bool)
signal hit_confirmed(killed: bool)

const IMPACT_SCENE := preload("res://scenes/effects/impact.tscn")

@export var weapon_name := "Rifle"

@export_group("Damage")
## Damage per bullet (per pellet for shotguns).
@export var damage := 24.0
@export var pellets := 1
@export var max_range := 200.0
## Damage starts dropping at this distance...
@export var falloff_start := 30.0
## ...and reaches `falloff_min_multiplier` of full damage here.
@export var falloff_end := 80.0
@export_range(0.0, 1.0) var falloff_min_multiplier := 0.5

@export_group("Handling")
@export var automatic := true
@export var rounds_per_second := 10.0
@export var magazine_size := 30
@export var reserve_ammo := 120
@export var max_reserve_ammo := 240
@export var reload_time := 1.6
## Enemies within this distance hear the shot.
@export var noise_radius := 35.0

@export_group("Accuracy")
## Half-angle of the spread cone when firing from the hip, standing still.
@export var hip_spread_degrees := 2.0
@export var aim_spread_degrees := 0.3
## Extra spread added per shot ("bloom"), which recovers over time.
@export var spread_per_shot := 0.6
@export var max_bloom_degrees := 5.0
## Bloom recovery, in degrees per second.
@export var bloom_recovery := 8.0
@export var moving_spread_degrees := 2.5
@export var airborne_spread_degrees := 6.0
@export_range(0.0, 1.0) var crouch_spread_multiplier := 0.6

@export_group("Recoil")
## Camera kick per shot, in degrees.
@export var camera_recoil_pitch := 0.8
@export var camera_recoil_yaw := 0.3
## How far the model kicks back per shot.
@export var model_kick := 0.05
@export var model_pitch_degrees := 4.0

@export_group("Aiming")
@export var aim_fov := 55.0
## Model position (holder space) that lines the sights up with the screen centre.
@export var aim_position := Vector3(0.0, -0.1, -0.25)
@export var hip_position := Vector3(0.17, -0.17, -0.38)

@export_group("Sounds")
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream
## Played shortly after each shot, e.g. a shotgun pump.
@export var cycle_sound: AudioStream
@export var cycle_delay := 0.25

@onready var model: Node3D = $Model
@onready var muzzle_flash: MeshInstance3D = $Model/Muzzle/Flash
@onready var muzzle_light: OmniLight3D = $Model/Muzzle/Light
## Optional part that slides back after each shot (pistol slide, shotgun pump).
@onready var cycle_part: Node3D = get_node_or_null("Model/CyclePart")

## Set by the WeaponHolder that owns this weapon.
var holder: WeaponHolder
var ammo_in_magazine := 0
var is_reloading := false
var bloom := 0.0

var _cooldown := 0.0
var _reload_id := 0
var _reload_pose := 0.0
var _kick_offset := 0.0
var _kick_pitch := 0.0


func _ready() -> void:
	ammo_in_magazine = magazine_size
	model.position = hip_position
	muzzle_flash.visible = false
	muzzle_light.visible = false


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	bloom = maxf(bloom - bloom_recovery * delta, 0.0)
	_update_pose(delta)


## Called by the holder every frame while fire is held.
func try_fire(just_pressed: bool) -> void:
	if is_reloading or _cooldown > 0.0:
		return
	if not automatic and not just_pressed:
		return
	if ammo_in_magazine <= 0:
		if just_pressed:
			Game.play_sound(empty_sound, -6.0)
			reload()
		return

	_cooldown = 1.0 / rounds_per_second
	ammo_in_magazine -= 1
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)

	var spread := current_spread_degrees()
	bloom = minf(bloom + spread_per_shot, max_bloom_degrees)
	_fire_rays(spread)
	_play_fire_effects()
	Game.make_noise(holder.player.global_position, noise_radius)


func reload() -> void:
	if is_reloading or ammo_in_magazine >= magazine_size or reserve_ammo <= 0:
		return
	is_reloading = true
	_reload_id += 1
	var reload_id := _reload_id
	reload_state_changed.emit(true)
	Game.play_sound(reload_sound, -4.0, 0.0)

	# `false`: don't let the timer run while the game is paused.
	await get_tree().create_timer(reload_time, false).timeout
	if reload_id != _reload_id:
		return  # Cancelled (e.g. switched weapons).

	var taken := mini(magazine_size - ammo_in_magazine, reserve_ammo)
	ammo_in_magazine += taken
	reserve_ammo -= taken
	is_reloading = false
	reload_state_changed.emit(false)
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_id += 1
	reload_state_changed.emit(false)


## Returns false (and does nothing) if the reserve is already full.
func add_ammo(amount: int) -> bool:
	if reserve_ammo >= max_reserve_ammo:
		return false
	reserve_ammo = mini(reserve_ammo + amount, max_reserve_ammo)
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)
	return true


## Current spread cone half-angle, including movement, stance and bloom.
func current_spread_degrees() -> float:
	if holder == null:
		return hip_spread_degrees
	var player := holder.player
	var aim := holder.aim_amount
	var spread := lerpf(hip_spread_degrees, aim_spread_degrees, aim)

	var movement := 0.0
	if not player.is_on_floor():
		movement = airborne_spread_degrees
	else:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		movement = moving_spread_degrees * clampf(speed / player.walk_speed, 0.0, 1.5)
	spread += movement * (1.0 - 0.7 * aim) + bloom

	if player.is_crouching:
		spread *= crouch_spread_multiplier
	return spread


func _fire_rays(spread_degrees: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.global_position
	var view := camera.global_basis
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [holder.player.get_rid()]

	var hit_anything := false
	var killed := false
	for i in pellets:
		var direction := _random_direction_in_cone(view, deg_to_rad(spread_degrees))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range, 0xFFFFFFFF, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		var point: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		var damageable := collider != null and collider.has_method("take_damage")
		_spawn_impact(point, hit["normal"], damageable)
		if damageable:
			hit_anything = true
			var amount := damage * _falloff(origin.distance_to(point))
			if collider.call("take_damage", amount, origin, point):
				killed = true

	if hit_anything:
		hit_confirmed.emit(killed)


func _random_direction_in_cone(view: Basis, half_angle: float) -> Vector3:
	var forward := -view.z
	if half_angle <= 0.0:
		return forward
	# sqrt() spreads hits evenly over the cone's area instead of bunching at the centre.
	var angle := half_angle * sqrt(randf())
	var around := randf() * TAU
	var offset := (view.x * cos(around) + view.y * sin(around)) * tan(angle)
	return (forward + offset).normalized()


func _falloff(distance: float) -> float:
	if distance <= falloff_start:
		return 1.0
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 0.001), 0.0, 1.0)
	return lerpf(1.0, falloff_min_multiplier, t)


func _play_fire_effects() -> void:
	var aim := holder.aim_amount
	var recoil_scale := lerpf(1.0, 0.6, aim)
	if holder.player.is_crouching:
		recoil_scale *= 0.8
	holder.player.add_recoil(
		camera_recoil_pitch * recoil_scale,
		randf_range(-camera_recoil_yaw, camera_recoil_yaw) * recoil_scale
	)
	_kick_offset += model_kick * lerpf(1.0, 0.4, aim)
	_kick_pitch += deg_to_rad(model_pitch_degrees) * lerpf(1.0, 0.3, aim)

	Game.play_sound(fire_sound, -2.0)

	muzzle_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	muzzle_flash.visible = true
	muzzle_light.visible = true
	get_tree().create_timer(0.04).timeout.connect(_hide_muzzle_flash)

	if cycle_part:
		var tween := create_tween()
		if cycle_sound:
			tween.tween_interval(cycle_delay * 0.5)
		tween.tween_property(cycle_part, "position:z", 0.06, 0.06)
		tween.tween_property(cycle_part, "position:z", 0.0, 0.1)
	if cycle_sound:
		get_tree().create_timer(cycle_delay, false).timeout.connect(_play_cycle_sound)


func _play_cycle_sound() -> void:
	Game.play_sound(cycle_sound, -6.0, 0.03)


func _hide_muzzle_flash() -> void:
	muzzle_flash.visible = false
	muzzle_light.visible = false


func _spawn_impact(point: Vector3, normal: Vector3, hit_character: bool) -> void:
	var impact: Impact = IMPACT_SCENE.instantiate()
	impact.hit_character = hit_character
	impact.place(point, normal)
	get_tree().current_scene.add_child(impact)


func _update_pose(delta: float) -> void:
	var settle := minf(14.0 * delta, 1.0)
	_kick_offset = lerpf(_kick_offset, 0.0, settle)
	_kick_pitch = lerpf(_kick_pitch, 0.0, settle)
	_reload_pose = move_toward(_reload_pose, 1.0 if is_reloading else 0.0, delta * 5.0)

	var aim := holder.aim_amount if holder else 0.0
	var reload_ease := smoothstep(0.0, 1.0, _reload_pose)
	model.position = hip_position.lerp(aim_position, aim) \
		+ Vector3(0.0, -0.06 * reload_ease, _kick_offset)
	model.rotation = Vector3(
		_kick_pitch - deg_to_rad(30.0) * reload_ease,
		0.0,
		deg_to_rad(25.0) * reload_ease
	)
