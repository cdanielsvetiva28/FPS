class_name Target
extends AnimatableBody3D
## Shootable practice dummy. Flashes when hit, disappears when killed and
## respawns after a delay. Can optionally slide back and forth.

signal died

@export var max_health := 100.0
@export var respawn_time := 3.0
@export var hit_color := Color(1.0, 1.0, 1.0)

@export_group("Movement")
## Peak offset from the starting position. Leave at zero for a stationary target.
@export var move_offset := Vector3.ZERO
@export var move_speed := 1.5

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var health := 0.0

var _material: StandardMaterial3D
var _base_color: Color
var _start_position: Vector3
var _move_time := 0.0


func _ready() -> void:
	health = max_health
	_start_position = position
	# Give each target its own material so hit flashes don't affect the others.
	_material = mesh.get_active_material(0).duplicate() as StandardMaterial3D
	mesh.material_override = _material
	_base_color = _material.albedo_color


func _physics_process(delta: float) -> void:
	if move_offset == Vector3.ZERO:
		return
	_move_time += delta * move_speed
	position = _start_position + move_offset * sin(_move_time)


func take_damage(amount: float, _from_position := Vector3.ZERO, _hit_position := Vector3.ZERO) -> bool:
	if health <= 0.0:
		return false

	health -= amount
	_material.albedo_color = hit_color
	create_tween().tween_property(_material, "albedo_color", _base_color, 0.15)

	if health <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	died.emit()
	mesh.visible = false
	collision.set_deferred("disabled", true)

	await get_tree().create_timer(respawn_time, false).timeout

	health = max_health
	_material.albedo_color = _base_color
	mesh.visible = true
	collision.set_deferred("disabled", false)
