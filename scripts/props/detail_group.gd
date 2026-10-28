extends Node3D
## Applies Prop texture detail to every model under this node. Use it for
## scenery without collision (backdrop rocks, distant pylons, trees).


func _ready() -> void:
	Prop.apply_detail(self)
