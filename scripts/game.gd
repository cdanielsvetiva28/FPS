extends Node
## Global game services (autoloaded as `Game`): default input bindings,
## controller detection, pausing, scene changes, noise events, HUD messages,
## on-screen notices, rumble and one-shot sounds.

signal paused_changed(paused: bool)
## Emitted when something loud happens, e.g. the player firing. Enemies within
## `radius` of `position` react to it.
signal noise_made(position: Vector3, radius: float)
signal message_posted(text: String)
## The player switched between keyboard/mouse and a controller.
signal input_device_changed(using_controller: bool)

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }

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
	"interact": [KEY_E],
	"retry_mission": [KEY_R],
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
	"gun": [MOUSE_BUTTON_LEFT],
	"fire_missile": [MOUSE_BUTTON_RIGHT],
}
## Controller buttons. Godot uses one layout for every controller; the
## comments give the PlayStation name (Xbox name in brackets).
const DEFAULT_JOY_BUTTONS := {
	# On foot (Call of Duty style)
	"jump": [JOY_BUTTON_A],  # Cross (A)
	"crouch_toggle": [JOY_BUTTON_B],  # Circle (B)
	"reload": [JOY_BUTTON_X],  # Square (X)
	"interact": [JOY_BUTTON_X],  # Square, hold (X)
	"next_weapon": [JOY_BUTTON_Y],  # Triangle (Y)
	"sprint_toggle": [JOY_BUTTON_LEFT_STICK],  # L3
	"weapon_1": [JOY_BUTTON_DPAD_UP],
	"weapon_2": [JOY_BUTTON_DPAD_LEFT],
	"weapon_3": [JOY_BUTTON_DPAD_RIGHT],
	"pause": [JOY_BUTTON_START],  # Options (Menu)
	"menu": [JOY_BUTTON_BACK],  # Share / Create (View)
	"retry_mission": [JOY_BUTTON_Y],  # Triangle (Y), on the death screen
	# In the air (Ace Combat style)
	"gun": [JOY_BUTTON_X],  # Square (X)
	"fire_missile": [JOY_BUTTON_B],  # Circle (B)
	"switch_target": [JOY_BUTTON_Y],  # Triangle (Y)
	"flares": [JOY_BUTTON_A],  # Cross (A)
	"yaw_left": [JOY_BUTTON_LEFT_SHOULDER],  # L1 (LB)
	"yaw_right": [JOY_BUTTON_RIGHT_SHOULDER],  # R1 (RB)
	"camera_toggle": [JOY_BUTTON_RIGHT_STICK],  # R3
}
## Controller sticks and triggers: action -> [axis, direction].
const DEFAULT_JOY_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],  # L2
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],  # R2
	# Flight: left stick flies the plane, triggers are throttle.
	"stick_left": [JOY_AXIS_LEFT_X, -1.0],
	"stick_right": [JOY_AXIS_LEFT_X, 1.0],
	"stick_up": [JOY_AXIS_LEFT_Y, -1.0],
	"stick_down": [JOY_AXIS_LEFT_Y, 1.0],
	"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0],  # R2
	"brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],  # L2
}

## Button names shown in on-screen prompts, per input device.
const PROMPTS := {
	"confirm": {"keyboard": "Click", "playstation": "Cross", "xbox": "A"},
	"menu": {"keyboard": "M", "playstation": "Create", "xbox": "View"},
	"pause": {"keyboard": "Esc", "playstation": "Options", "xbox": "Menu"},
	"interact": {"keyboard": "E", "playstation": "Square", "xbox": "X"},
	"restart": {"keyboard": "R", "playstation": "Triangle", "xbox": "Y"},
}

## True while the player is using a controller (switches back on any
## keyboard/mouse input). Used for button prompts and rumble.
var using_controller := false
## The controller in use, or -1.
var active_joypad := -1
## The Interactable whose prompt is showing, if any (so the shared
## Square/X button interacts instead of reloading).
var interaction_focus: Node = null
## Graphics preset, applied by each scene's WorldEnvironment (see
## quality_environment.gd). Saved in user://settings.cfg.
var graphics_quality := Quality.HIGH

var _notice_layer: CanvasLayer
var _notice_label: Label
var _notice_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_bindings()
	_load_settings()
	_build_notice_ui()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# A controller that was already plugged in at launch.
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		active_joypad = pads[0]
		_set_using_controller(true)
		notify.call_deferred("%s ready" % controller_display_name(active_joypad))


func _input(event: InputEvent) -> void:
	# Follow whichever device the player last touched.
	if event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		active_joypad = event.device
		_set_using_controller(true)
	elif event is InputEventKey or event is InputEventMouseButton \
			or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0):
		_set_using_controller(false)


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
	elif get_tree().paused and _is_resume_press(event):
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
	if value and active_joypad >= 0:
		Input.stop_joy_vibration(active_joypad)
	paused_changed.emit(value)


func restart() -> void:
	Radio.clear()
	interaction_focus = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func go_to_menu() -> void:
	Radio.clear()
	Mission.leave()
	get_tree().paused = false
	paused_changed.emit(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func play_scene(path: String) -> void:
	Radio.clear()
	Mission.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(path)


# --- Settings --------------------------------------------------------------------

func set_graphics_quality(quality: Quality) -> void:
	graphics_quality = quality
	_save_settings()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		graphics_quality = clampi(int(config.get_value("graphics", "quality", Quality.HIGH)), 0, 2) as Quality


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", graphics_quality)
	config.save(SETTINGS_PATH)


# --- Controllers ---------------------------------------------------------------

## "playstation", "xbox", or "keyboard" (when not using a controller).
func input_style() -> String:
	if not using_controller:
		return "keyboard"
	var name := Input.get_joy_name(active_joypad).to_lower()
	for hint in ["ps4", "ps5", "dualsense", "dualshock", "playstation", "sony", "wireless controller"]:
		if name.contains(hint):
			return "playstation"
	return "xbox"


## Button name for an on-screen prompt, e.g. prompt("confirm") -> "Cross".
func prompt(key: String) -> String:
	var names: Dictionary = PROMPTS.get(key, {})
	var style := input_style()
	var label: String = names.get(style, names.get("keyboard", key))
	# The PS4 calls its Create button "Share".
	if key == "menu" and style == "playstation" and _is_ps4():
		label = "Share"
	return label


func controller_display_name(device: int) -> String:
	var name := Input.get_joy_name(device)
	var lower := name.to_lower()
	if lower.contains("ps5") or lower.contains("dualsense"):
		return "DualSense (PS5) controller"
	if lower.contains("ps4") or lower.contains("dualshock"):
		return "DualShock 4 (PS4) controller"
	return name if not name.is_empty() else "Controller"


## Vibrates the active controller. Does nothing on keyboard and mouse.
func rumble(weak: float, strong: float, duration: float) -> void:
	if using_controller and active_joypad >= 0:
		Input.start_joy_vibration(active_joypad, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Shows a short notice at the top of the screen, in any scene.
func notify(text: String) -> void:
	_notice_label.text = text
	_notice_label.modulate.a = 1.0
	if _notice_tween:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(2.5)
	_notice_tween.tween_property(_notice_label, "modulate:a", 0.0, 0.6)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		active_joypad = device
		_set_using_controller(true)
		notify("%s connected" % controller_display_name(device))
		rumble(0.4, 0.2, 0.25)
	else:
		notify("Controller disconnected")
		if device == active_joypad:
			var pads := Input.get_connected_joypads()
			active_joypad = pads[0] if not pads.is_empty() else -1
			if active_joypad < 0:
				_set_using_controller(false)
				# Don't leave the player flying blind mid-mission.
				if _can_pause() and not get_tree().paused:
					set_paused(true)


func _set_using_controller(value: bool) -> void:
	if value == using_controller:
		return
	using_controller = value
	input_device_changed.emit(value)


func _is_ps4() -> bool:
	var lower := Input.get_joy_name(active_joypad).to_lower()
	return lower.contains("ps4") or lower.contains("dualshock")


func _is_resume_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.is_pressed():
		return true
	return event is InputEventJoypadButton and event.is_pressed() \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A


func _build_notice_ui() -> void:
	_notice_layer = CanvasLayer.new()
	_notice_layer.layer = 100
	add_child(_notice_layer)
	_notice_label = Label.new()
	_notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice_label.offset_left = -400.0
	_notice_label.offset_right = 400.0
	_notice_label.offset_top = 70.0
	_notice_label.offset_bottom = 110.0
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", 22)
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_notice_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_notice_label.add_theme_constant_override("outline_size", 6)
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.modulate.a = 0.0
	_notice_layer.add_child(_notice_label)


# --- Shared helpers ---------------------------------------------------------------

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
func play_sound_at(stream: AudioStream, at: Vector3, volume_db := 0.0, pitch_variation := 0.05,
		max_distance := 80.0) -> void:
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
	# Keyboard/mouse additions are reported (they'd mean the project's input
	# map is broken); controller bindings live here, so they're added silently.
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
	for action: String in DEFAULT_JOY_BUTTONS:
		for button: int in DEFAULT_JOY_BUTTONS[action]:
			var joy_button := InputEventJoypadButton.new()
			joy_button.device = -1
			joy_button.button_index = button as JoyButton
			_add_binding(action, joy_button)
	for action: String in DEFAULT_JOY_AXES:
		var axis_info: Array = DEFAULT_JOY_AXES[action]
		var joy_motion := InputEventJoypadMotion.new()
		joy_motion.device = -1
		joy_motion.axis = axis_info[0] as JoyAxis
		joy_motion.axis_value = axis_info[1]
		_add_binding(action, joy_motion)
	if not added.is_empty():
		print("Game: added default input bindings: ", ", ".join(added))


func _add_binding(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	if InputMap.action_has_event(action, event):
		return false
	InputMap.action_add_event(action, event)
	return true
