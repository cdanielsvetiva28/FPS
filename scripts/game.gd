extends Node
## Global game services (autoloaded as `Game`): default input bindings,
## pausing, restarting, gunfire noise and HUD messages.

signal paused_changed(paused: bool)
## Emitted when something loud happens, e.g. the player firing. Enemies within
## `radius` of `position` react to it.
signal noise_made(position: Vector3, radius: float)
signal message_posted(text: String)

## Default keyboard bindings. Any that are missing from the Input Map are added
## at startup, so the game stays playable even if the project's map is broken.
const DEFAULT_KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"reload": [KEY_R],
	"pause": [KEY_ESCAPE],
	"toggle_fullscreen": [KEY_F11],
}
const DEFAULT_MOUSE_BUTTONS := {
	"fire": [MOUSE_BUTTON_LEFT],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_bindings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
	elif event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event is InputEventMouseButton and event.is_pressed():
		set_paused(false)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Pause when the window loses focus (alt-tab, clicking the editor, ...).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not get_tree().paused:
		set_paused(true)


func set_paused(value: bool) -> void:
	get_tree().paused = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	paused_changed.emit(value)


func restart() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func make_noise(position: Vector3, radius: float) -> void:
	noise_made.emit(position, radius)


func post_message(text: String) -> void:
	message_posted.emit(text)


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _ensure_input_bindings() -> void:
	var added: PackedStringArray = []
	for action: String in DEFAULT_KEYS:
		for keycode: int in DEFAULT_KEYS[action]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode as Key
			if _add_binding(action, key_event):
				added.append("%s=%s" % [action, OS.get_keycode_string(keycode as Key)])
	for action: String in DEFAULT_MOUSE_BUTTONS:
		for button: int in DEFAULT_MOUSE_BUTTONS[action]:
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = button as MouseButton
			if _add_binding(action, mouse_event):
				added.append("%s=mouse %d" % [action, button])
	if not added.is_empty():
		print("Game: added default input bindings: ", ", ".join(added))


func _add_binding(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	if InputMap.action_has_event(action, event):
		return false
	InputMap.action_add_event(action, event)
	return true
