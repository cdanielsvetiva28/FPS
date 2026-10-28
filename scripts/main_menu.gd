extends Control
## Title screen: pick a test mission.

const GROUND_TEST := "res://scenes/main.tscn"
const FLIGHT_TEST := "res://scenes/flight/flight_test.tscn"

@onready var ground_button: Button = $Center/Buttons/GroundButton
@onready var flight_button: Button = $Center/Buttons/FlightButton
@onready var quit_button: Button = $Center/Buttons/QuitButton


func _ready() -> void:
	add_to_group("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ground_button.pressed.connect(Game.play_scene.bind(GROUND_TEST))
	flight_button.pressed.connect(Game.play_scene.bind(FLIGHT_TEST))
	quit_button.pressed.connect(get_tree().quit)
	flight_button.grab_focus()
