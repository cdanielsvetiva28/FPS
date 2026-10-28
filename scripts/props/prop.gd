class_name Prop
extends StaticBody3D
## Root of a prop scene: a Blender model (tools/blender/build_props.py) plus
## collision. On load it layers tileable textures over the model's flat
## colours, matched by material name, so containers get grime, barriers get
## concrete, sandbags get burlap and so on.

## Blender material name -> [texture name in assets/textures, has normal map, metres per tile].
const DETAIL := {
	"Paint": ["grime", false, 2.5],
	"Frame": ["grime", false, 2.0],
	"Concrete": ["concrete_floor", true, 1.5],
	"Burlap": ["fabric", true, 0.5],
	"BurlapDark": ["fabric", true, 0.5],
	"DrumPaint": ["grime", false, 1.2],
	"DrumRim": ["grime", false, 1.2],
	"Wood": ["wood_planks", true, 1.2],
	"WoodDark": ["wood_planks", true, 1.2],
	"Tin": ["grime", false, 2.0],
	"Galvanized": ["grime", false, 2.0],
	"Steel": ["grime", false, 4.0],
	"DarkSteel": ["grime", false, 4.0],
	"Stone": ["rock", true, 3.0],
	"Bark": ["wood_planks", false, 2.0],
}

## Detailed copies of imported materials, shared by every instance.
static var _cache := {}


func _ready() -> void:
	Prop.apply_detail(self)


## Applies texture detail to every mesh under `root`. Usable on any node.
static func apply_detail(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if source and DETAIL.has(source.resource_name):
				mesh_instance.set_surface_override_material(i, _detailed(source))


static func _detailed(source: BaseMaterial3D) -> BaseMaterial3D:
	var key := source.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var info: Array = DETAIL[source.resource_name]
	var material := source.duplicate() as BaseMaterial3D
	material.albedo_texture = load("res://assets/textures/%s_albedo.png" % info[0])
	if info[1]:
		material.normal_enabled = true
		material.normal_texture = load("res://assets/textures/%s_normal.png" % info[0])
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / float(info[2])
	_cache[key] = material
	return material
