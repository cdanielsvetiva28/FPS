class_name HUD
extends CanvasLayer
## Heads-up display: crosshair, hit marker, ammo counter and pause hint.

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var hitmarker: Label = $Hitmarker
@onready var pause_label: Label = $PauseLabel

var _hitmarker_tween: Tween


func _process(_delta: float) -> void:
	pause_label.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func set_ammo(in_magazine: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_magazine, reserve]


func set_reloading(reloading: bool) -> void:
	reload_label.visible = reloading


func show_hitmarker(killed: bool) -> void:
	hitmarker.modulate = Color(1.0, 0.25, 0.25) if killed else Color.WHITE
	if _hitmarker_tween:
		_hitmarker_tween.kill()
	_hitmarker_tween = create_tween()
	_hitmarker_tween.tween_property(hitmarker, "modulate:a", 0.0, 0.25)
