extends Control
## Title screen: pick a mission. Shows which missions are complete and which
## controller is connected. Works with mouse, keyboard or controller.

const MISSIONS := [
	{"id": "first_light", "button": "FlightButton", "label": "AIR — \"First Light\"",
		"scene": "res://scenes/flight/flight_test.tscn"},
	{"id": "compound_raid", "button": "GroundButton", "label": "GROUND — \"Compound Raid\"",
		"scene": "res://scenes/main.tscn"},
]

@onready var buttons: VBoxContainer = $Center/Buttons
@onready var quit_button: Button = $Center/Buttons/QuitButton
@onready var device_label: Label = $DeviceLabel


func _ready() -> void:
	add_to_group("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for mission: Dictionary in MISSIONS:
		var button := buttons.get_node(mission["button"]) as Button
		var done := Mission.is_mission_completed(mission["id"])
		button.text = mission["label"] + ("      COMPLETE" if done else "")
		button.pressed.connect(Game.play_scene.bind(mission["scene"]))
	quit_button.pressed.connect(get_tree().quit)
	(buttons.get_child(0) as Button).grab_focus()

	Game.input_device_changed.connect(func(_using: bool) -> void: _update_device_label())
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _update_device_label())
	_update_device_label()


func _update_device_label() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		device_label.text = "Keyboard & mouse      (plug in a controller any time)"
	else:
		var names: PackedStringArray = []
		for pad in pads:
			names.append(Game.controller_display_name(pad))
		device_label.text = "Controller: %s" % ", ".join(names)
