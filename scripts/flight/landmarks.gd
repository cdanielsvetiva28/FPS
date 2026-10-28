extends Node3D
## Places Weatherline pylons (see docs/STORY.md) on the terrain: tall towers
## with a ring and a blinking warning light. Purely visual landmarks for now.

@export var positions: Array[Vector2] = [
	Vector2(-2200, -1800), Vector2(2600, -900), Vector2(400, 1600), Vector2(-1500, 2400), Vector2(1800, -3200),
]
@export var tower_height := 420.0

var _lights: Array[OmniLight3D] = []
var _time := 0.0


func _ready() -> void:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.57, 0.6)
	metal.metallic = 0.7
	metal.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.15, 0.1)

	for p in positions:
		var ground := maxf(terrain.height_at(p.x, p.y), 0.0) if terrain else 0.0
		var base := Vector3(p.x, ground, p.y)
		_add_mesh(_cylinder(30.0, 45.0, 40.0, metal), base + Vector3.UP * 20.0)
		_add_mesh(_cylinder(6.0, 16.0, tower_height, metal), base + Vector3.UP * (tower_height * 0.5))
		var ring := TorusMesh.new()
		ring.inner_radius = 55.0
		ring.outer_radius = 66.0
		ring.material = metal
		_add_mesh(ring, base + Vector3.UP * (tower_height - 40.0))
		var beacon := SphereMesh.new()
		beacon.radius = 5.0
		beacon.height = 10.0
		beacon.material = glow
		var top := base + Vector3.UP * (tower_height + 6.0)
		_add_mesh(beacon, top)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.2, 0.1)
		light.light_energy = 6.0
		light.omni_range = 120.0
		light.position = top
		add_child(light)
		_lights.append(light)


func _process(delta: float) -> void:
	_time += delta
	var on := fmod(_time, 1.5) < 0.3
	for light in _lights:
		light.visible = on


func _cylinder(top: float, bottom: float, height: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.material = material
	return mesh


func _add_mesh(mesh: Mesh, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)
