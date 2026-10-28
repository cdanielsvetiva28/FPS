class_name Flare
extends Node3D
## A burning decoy flare. Falls away from the aircraft; missiles that switch
## to it detonate on it instead.

const SOUND := preload("res://assets/sounds/flare.wav")

var velocity := Vector3.ZERO
var _age := 0.0


static func spawn(parent: Node, at: Vector3, initial_velocity: Vector3) -> Flare:
	var flare := Flare.new()
	flare.velocity = initial_velocity
	flare.position = at
	parent.add_child(flare)
	return flare


func _ready() -> void:
	add_to_group("flares")
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.9, 0.7)
	sphere.material = material
	glow.mesh = sphere
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 4.0
	light.omni_range = 30.0
	add_child(light)
	Game.play_sound_at(SOUND, global_position, -4.0, 0.15, 600.0)


func _process(delta: float) -> void:
	_age += delta
	velocity = velocity * (1.0 - 0.8 * delta) + Vector3.DOWN * 6.0 * delta
	global_position += velocity * delta
	var fade := clampf(1.0 - (_age - 3.0), 0.0, 1.0)
	scale = Vector3.ONE * maxf(fade, 0.01)
	if _age > 4.0:
		queue_free()
