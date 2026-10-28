extends Node
## Global game services (autoloaded as `Game`): default input bindings,
## pausing, restarting, noise events, HUD messages and one-shot sounds.

signal paused_changed(paused: bool)
## Emitted when something loud happens, e.g. the player firing. Enemies within
## `radius` of `position` react to it.
signal noise_made(position: Vector3, radius: float)
signal message_posted(text: String)

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Default keyboard bindings. Any that are missing from the Input Map are added
## at startup, so the game stays playable even if the project's map is broken.
const DEFAULT_KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"crouch_toggle": [KEY_C],
	"reload": [KEY_R],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"last_weapon": [KEY_Q],
	"pause": [KEY_ESCAPE],
	"toggle_fullscreen": [KEY_F11],
	"menu": [KEY_M],
	# Flight
	"throttle_up": [KEY_W],
	"throttle_down": [KEY_S],
	"yaw_left": [KEY_A],
	"yaw_right": [KEY_D],
	"roll_left": [KEY_Q],
	"roll_right": [KEY_E],
	"flares": [KEY_F],
	"switch_target": [KEY_SPACE, KEY_TAB],
	"camera_toggle": [KEY_V],
}
const DEFAULT_MOUSE_BUTTONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
	"next_weapon": [MOUSE_BUTTON_WHEEL_DOWN],
	"previous_weapon": [MOUSE_BUTTON_WHEEL_UP],
	"fire_missile": [MOUSE_BUTTON_RIGHT],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_bindings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
	elif not _can_pause():
		return
	elif event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event.is_action_pressed("menu"):
		go_to_menu()
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event is InputEventMouseButton and event.is_pressed():
		set_paused(false)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Pause when the window loses focus (alt-tab, clicking the editor, ...).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not get_tree().paused \
			and _can_pause():
		set_paused(true)


func set_paused(value: bool) -> void:
	get_tree().paused = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	paused_changed.emit(value)


func restart() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func go_to_menu() -> void:
	get_tree().paused = false
	paused_changed.emit(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func play_scene(path: String) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(path)


## Returns a copy of a WAV stream that loops over its whole length.
func looping(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return stream
	var copy := wav.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = int(copy.get_length() * copy.mix_rate)
	return copy


func make_noise(position: Vector3, radius: float) -> void:
	noise_made.emit(position, radius)


func post_message(text: String) -> void:
	message_posted.emit(text)


## Plays a non-positional sound (the player's own gun, UI, ...).
func play_sound(stream: AudioStream, volume_db := 0.0, pitch_variation := 0.05) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Plays a sound at a point in the world (enemy gunfire, impacts, ...).
func play_sound_at(stream: AudioStream, at: Vector3, volume_db := 0.0, pitch_variation := 0.05, max_distance := 80.0) -> void:
	var scene := get_tree().current_scene
	if stream == null or scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.max_distance = max_distance
	player.unit_size = 6.0
	player.position = at
	scene.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Menus (scenes in the "menu" group) don't pause.
func _can_pause() -> bool:
	var scene := get_tree().current_scene
	return scene != null and not scene.is_in_group("menu")


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
