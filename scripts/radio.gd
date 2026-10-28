extends CanvasLayer
## Radio chatter with subtitles (autoloaded as `Radio`). Lines queue up and
## play one after another, in any mission, on foot or in the air.
##
##     Radio.say("SKYWARD", "Bandits inbound.")
##     Radio.say_lines(["LANTERN 1: On your six!", "WREN: I see him."])

signal line_started(callsign: String, text: String)

const CLICK_SOUND := preload("res://assets/sounds/radio_click.wav")
const FRIENDLY_COLOR := Color(0.55, 1.0, 0.6)
const ENEMY_COLOR := Color(1.0, 0.55, 0.3)
## Callsigns that start with these are shown in enemy colours.
const ENEMY_PREFIXES: Array[String] = ["STORMCROW", "SABLE", "SEVRIN", "ORLAN"]

var _queue: Array = []
var _timer := 0.0
var _panel: PanelContainer
var _callsign: Label
var _text: Label


func _ready() -> void:
	layer = 50
	_build_ui()


## Queues a line. Duration defaults to a reading time based on its length.
func say(callsign: String, text: String, duration := 0.0) -> void:
	if duration <= 0.0:
		duration = clampf(1.5 + text.length() * 0.055, 2.5, 7.5)
	_queue.append([callsign, text, duration])


## Queues several "CALLSIGN: text" lines.
func say_lines(lines: PackedStringArray) -> void:
	for line in lines:
		var split := line.find(": ")
		if split > 0:
			say(line.substr(0, split), line.substr(split + 2))
		else:
			say("", line)


func clear() -> void:
	_queue.clear()
	_timer = 0.0
	_panel.visible = false


func is_busy() -> bool:
	return _timer > 0.0 or not _queue.is_empty()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if _queue.is_empty():
		_panel.visible = false
		return
	var line: Array = _queue.pop_front()
	var callsign: String = line[0]
	_callsign.text = callsign
	_callsign.visible = not callsign.is_empty()
	_callsign.add_theme_color_override("font_color", ENEMY_COLOR if _is_enemy(callsign) else FRIENDLY_COLOR)
	_text.text = line[1]
	_timer = line[2]
	_panel.visible = true
	Game.play_sound(CLICK_SOUND, -10.0, 0.05)
	line_started.emit(callsign, line[1])


func _is_enemy(callsign: String) -> bool:
	for prefix in ENEMY_PREFIXES:
		if callsign.begins_with(prefix):
			return true
	return false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 40.0
	_panel.offset_top = -250.0
	_panel.offset_right = 640.0
	_panel.offset_bottom = -130.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.04, 0.02, 0.65)
	style.border_width_left = 3
	style.border_color = Color(FRIENDLY_COLOR, 0.8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(lines)
	_callsign = Label.new()
	_callsign.add_theme_font_size_override("font_size", 16)
	lines.add_child(_callsign)
	_text = Label.new()
	_text.custom_minimum_size = Vector2(560, 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 20)
	lines.add_child(_text)
	_panel.visible = false
