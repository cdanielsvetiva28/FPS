class_name Impact
extends Node3D
## Bullet impact: decal, sparks and dust on surfaces; a red puff on characters.

const SURFACE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/impact_1.wav"),
	preload("res://assets/sounds/impact_2.wav"),
	preload("res://assets/sounds/impact_3.wav"),
]

@export var lifetime := 10.0

## Set before adding to the tree.
var hit_character := false

@onready var decal: Decal = $Decal
@onready var sparks: CPUParticles3D = $Sparks
@onready var dust: CPUParticles3D = $Dust


func _ready() -> void:
	if hit_character:
		decal.visible = false
		sparks.color = Color(0.45, 0.04, 0.03)
		dust.color = Color(0.35, 0.03, 0.02, 0.8)
	else:
		Game.play_sound_at(SURFACE_SOUNDS.pick_random(), global_position, -10.0)
	sparks.emitting = true
	dust.emitting = true

	await get_tree().create_timer(1.0 if hit_character else lifetime, false).timeout
	queue_free()


## Orients the impact so its local Y axis points out of the surface.
## Call before adding to the tree; the parent is assumed to sit at the origin.
func place(point: Vector3, normal: Vector3) -> void:
	var up := normal.normalized()
	var helper := Vector3.FORWARD if absf(up.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := helper.cross(up).normalized()
	var z := x.cross(up).normalized()
	var orientation := Basis(x, up, z).rotated(up, randf() * TAU)
	transform = Transform3D(orientation, point + up * 0.005)
