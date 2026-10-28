class_name Explosion
extends Node3D
## Fireball, smoke, debris, a light flash and a boom. Frees itself when done.

const SOUND := preload("res://assets/sounds/explosion.wav")

## Scales the whole effect: 1 = aircraft, 0.4 = missile hitting the ground.
@export var size := 1.0

@onready var fire: CPUParticles3D = $Fire
@onready var smoke: CPUParticles3D = $Smoke
@onready var debris: CPUParticles3D = $Debris
@onready var flash: OmniLight3D = $Flash


func _ready() -> void:
	scale = Vector3.ONE * size
	for particles: CPUParticles3D in [fire, smoke, debris]:
		particles.emitting = true
	flash.omni_range = 120.0 * size
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.6)
	Game.play_sound_at(SOUND, global_position, 6.0 * size, 0.1, 3000.0)
	await get_tree().create_timer(4.0, false).timeout
	queue_free()
