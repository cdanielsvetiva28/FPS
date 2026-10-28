extends Node3D
## Places Weatherline pylons (see docs/STORY.md) on the flight terrain: the
## Blender lattice tower scaled up to about 400 m, with a blinking beacon.

const PYLON := preload("res://assets/models/props/weatherline_pylon.glb")

@export var positions: Array[Vector2] = [
	Vector2(-2200, -1800), Vector2(2600, -900), Vector2(400, 1600), Vector2(-1500, 2400), Vector2(1800, -3200),
]
@export var scale_factor := 9.0

var _lights: Array[OmniLight3D] = []
var _time := 0.0


func _ready() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain
	for p in positions:
		var ground := maxf(terrain.height_at(p.x, p.y), 0.0) if terrain else 0.0
		var pylon := PYLON.instantiate() as Node3D
		pylon.position = Vector3(p.x, ground - 5.0, p.y)
		pylon.rotation.y = randf() * TAU
		pylon.scale = Vector3.ONE * scale_factor
		add_child(pylon)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.2, 0.1)
		light.light_energy = 8.0
		light.omni_range = 160.0
		light.position = pylon.position + Vector3.UP * 51.5 * scale_factor
		add_child(light)
		_lights.append(light)
	Prop.apply_detail(self)


func _process(delta: float) -> void:
	_time += delta
	var on := fmod(_time, 1.5) < 0.3
	for light in _lights:
		light.visible = on
