class_name Weapon
extends Node3D
## Hitscan weapon: fires a ray from the centre of the screen and handles ammo,
## reloading, recoil and simple hit effects.
##
## Anything the ray hits that has a `take_damage(amount: float) -> bool` method
## takes damage. The method should return true when the hit killed it.

signal ammo_changed(in_magazine: int, reserve: int)
signal reload_state_changed(reloading: bool)
signal hit_confirmed(killed: bool)

@export var damage := 25.0
@export var rounds_per_second := 9.0
@export var magazine_size := 30
@export var reserve_ammo := 120
@export var reload_time := 1.5
@export var max_range := 200.0

@export_group("Feel")
## How far the gun model kicks back per shot, in metres.
@export var recoil_kick := 0.04
## How far the gun model tips up per shot, in degrees.
@export var recoil_pitch_degrees := 4.0
## How quickly the gun model settles back after recoil.
@export var recoil_recovery := 12.0
@export var muzzle_flash_time := 0.05
@export var impact_lifetime := 8.0

@onready var ray: RayCast3D = $RayCast3D
@onready var model: Node3D = $GunModel
@onready var muzzle_flash: OmniLight3D = $GunModel/MuzzleFlash

var ammo_in_magazine := 0
var is_reloading := false
## Set when the mouse is re-captured so the click that did it doesn't shoot.
var block_until_release := false

var _cooldown := 0.0
var _model_rest_position: Vector3
var _model_rest_rotation: Vector3
var _impact_mesh: SphereMesh


func _ready() -> void:
	ammo_in_magazine = magazine_size
	ray.target_position = Vector3(0.0, 0.0, -max_range)
	if owner is CollisionObject3D:
		ray.add_exception(owner as CollisionObject3D)

	_model_rest_position = model.position
	_model_rest_rotation = model.rotation
	muzzle_flash.visible = false

	var impact_material := StandardMaterial3D.new()
	impact_material.albedo_color = Color(0.05, 0.05, 0.05)
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = 0.03
	_impact_mesh.height = 0.06
	_impact_mesh.material = impact_material

	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_model_pose(delta)

	if block_until_release:
		if not Input.is_action_pressed("fire"):
			block_until_release = false
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_pressed("fire"):
		_try_fire()


func reload() -> void:
	if is_reloading or ammo_in_magazine == magazine_size or reserve_ammo <= 0:
		return
	is_reloading = true
	reload_state_changed.emit(true)

	await get_tree().create_timer(reload_time).timeout

	var taken := mini(magazine_size - ammo_in_magazine, reserve_ammo)
	ammo_in_magazine += taken
	reserve_ammo -= taken
	is_reloading = false
	reload_state_changed.emit(false)
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


func _try_fire() -> void:
	if is_reloading or _cooldown > 0.0:
		return
	if ammo_in_magazine <= 0:
		reload()
		return

	_cooldown = 1.0 / rounds_per_second
	ammo_in_magazine -= 1
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)
	_play_fire_effects()

	ray.force_raycast_update()
	if not ray.is_colliding():
		return

	_spawn_impact(ray.get_collision_point(), ray.get_collision_normal())
	var collider := ray.get_collider()
	if collider != null and collider.has_method("take_damage"):
		var killed: bool = collider.call("take_damage", damage)
		hit_confirmed.emit(killed)


func _play_fire_effects() -> void:
	model.position.z += recoil_kick
	model.rotation.x += deg_to_rad(recoil_pitch_degrees)

	muzzle_flash.visible = true
	get_tree().create_timer(muzzle_flash_time).timeout.connect(func() -> void: muzzle_flash.visible = false)


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var impact := MeshInstance3D.new()
	impact.mesh = _impact_mesh
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(impact)
	impact.global_position = point + normal * 0.005
	get_tree().create_timer(impact_lifetime).timeout.connect(impact.queue_free)


func _update_model_pose(delta: float) -> void:
	var target_rotation := _model_rest_rotation
	if is_reloading:
		# Tip the gun down and roll it while reloading.
		target_rotation += Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(25.0))

	var weight := minf(recoil_recovery * delta, 1.0)
	model.position = model.position.lerp(_model_rest_position, weight)
	model.rotation = model.rotation.lerp(target_rotation, weight)
