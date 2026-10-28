class_name Interactable
extends Area3D
## Something the player uses by looking at it and holding interact
## (E / Square). Shows a prompt with a progress bar while held.
##
## Give it a CollisionShape3D child for the area the player must stand in.

signal used

## Finishes the prompt "Hold E to ...".
@export var prompt := "use"
@export var hold_time := 1.5
@export var enabled := true
## Can be used again after it's been used.
@export var reusable := false

var _player: Node3D
var _progress := 0.0
var _layer: CanvasLayer
var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("player"):
			_player = body)
	body_exited.connect(func(body: Node3D) -> void:
		if body == _player:
			_player = null)
	_build_ui()


func _process(delta: float) -> void:
	var available := enabled and _player != null and _player_is_looking()
	_layer.visible = available
	if Game.interaction_focus == self and not available:
		Game.interaction_focus = null
	if not available:
		_progress = 0.0
		return
	Game.interaction_focus = self
	_label.text = "Hold %s to %s" % [Game.prompt("interact"), prompt]
	if Input.is_action_pressed("interact"):
		_progress += delta / hold_time
		if _progress >= 1.0:
			_progress = 0.0
			enabled = reusable
			Game.interaction_focus = null
			used.emit()
	else:
		_progress = 0.0
	_bar.value = _progress * 100.0


func _player_is_looking() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var to_object := (global_position - camera.global_position).normalized()
	return (-camera.global_basis.z).dot(to_object) > 0.75


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	_layer.visible = false
	add_child(_layer)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -200.0
	box.offset_right = 200.0
	box.offset_top = 60.0
	box.offset_bottom = 110.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.show_percentage = false
	box.add_child(_bar)
