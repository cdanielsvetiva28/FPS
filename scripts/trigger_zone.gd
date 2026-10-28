class_name TriggerZone
extends Area3D
## An invisible area that fires when the player enters it. Without any code it
## can play radio lines, complete an objective and save a checkpoint; mission
## scripts can also listen to `triggered`.
##
## Give it a CollisionShape3D child for its size.

signal triggered

## Fire only the first time the player enters.
@export var once := true
@export var objective_to_complete := ""
## Calls `save_checkpoint()` on the mission script (the scene's root), if it has one.
@export var checkpoint := false
## Lines as "CALLSIGN: text".
@export var radio_lines: PackedStringArray = []

var _fired := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or (once and _fired):
		return
	_fired = true
	if not radio_lines.is_empty():
		Radio.say_lines(radio_lines)
	if not objective_to_complete.is_empty():
		Mission.complete_objective(objective_to_complete)
	if checkpoint:
		var scene := get_tree().current_scene
		if scene.has_method("save_checkpoint"):
			scene.call("save_checkpoint")
	triggered.emit()
