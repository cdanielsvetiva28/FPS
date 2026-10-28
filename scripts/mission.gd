extends CanvasLayer
## Mission state (autoloaded as `Mission`): objectives with on-screen
## waypoints, checkpoints, and campaign progress saved to disk.
##
## A mission script typically does:
##
##     if Mission.begin("first_light", "First Light"):
##         _restore(Mission.checkpoint)        # Retrying from a checkpoint.
##     Mission.add_objective("breach", "Breach the compound", $BreachMarker)
##     ...
##     Mission.complete_objective("breach")
##     Mission.save_checkpoint({"player_position": ...})
##     ...
##     Mission.complete_mission()
##
## Checkpoints live in memory for the current mission: dying and retrying
## reloads the scene, and the mission script restores itself from the data.

signal objective_added(id: String)
signal objective_completed(id: String)
signal mission_completed(mission_id: String)

const SAVE_PATH := "user://stormline_save.json"
const OBJECTIVE_SOUND := preload("res://assets/sounds/objective_complete.wav")
const ACTIVE_COLOR := Color(1.0, 0.85, 0.45)
const DONE_COLOR := Color(0.55, 1.0, 0.6, 0.8)

var mission_id := ""
var title := ""
## Whatever the mission saved at its last checkpoint; empty if none.
var checkpoint: Dictionary = {}
## Campaign progress, saved to disk: {"completed": {mission_id: true}}.
var progress: Dictionary = {"completed": {}}

## Each: {"id", "text", "done", "target" (Node3D or null)}.
var _objectives: Array[Dictionary] = []
var _list: VBoxContainer
var _title_label: Label
var _overlay: Control


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_load_progress()


## Starts (or restarts) a mission. Returns true when retrying from a checkpoint,
## in which case the caller should restore itself from `checkpoint`.
func begin(id: String, mission_title: String) -> bool:
	if id != mission_id:
		checkpoint = {}
	mission_id = id
	title = mission_title
	_objectives.clear()
	_refresh()
	return not checkpoint.is_empty()


## Leaves the current mission (e.g. back to the main menu).
func leave() -> void:
	mission_id = ""
	title = ""
	checkpoint = {}
	_objectives.clear()
	_refresh()


func add_objective(id: String, text: String, target: Node3D = null) -> void:
	if _find(id) >= 0:
		return
	_objectives.append({"id": id, "text": text, "done": false, "target": target})
	_refresh()
	objective_added.emit(id)


func set_objective_text(id: String, text: String) -> void:
	var i := _find(id)
	if i >= 0:
		_objectives[i]["text"] = text
		_refresh()


func set_objective_target(id: String, target: Node3D) -> void:
	var i := _find(id)
	if i >= 0:
		_objectives[i]["target"] = target


## `quiet` skips the sound (used when restoring from a checkpoint).
func complete_objective(id: String, quiet := false) -> void:
	var i := _find(id)
	if i < 0 or _objectives[i]["done"]:
		return
	_objectives[i]["done"] = true
	_refresh()
	if not quiet:
		Game.play_sound(OBJECTIVE_SOUND, -6.0, 0.0)
	objective_completed.emit(id)
	# Completed objectives linger briefly, then drop off the list.
	get_tree().create_timer(4.0).timeout.connect(_remove_done.bind(id))


func is_objective_completed(id: String) -> bool:
	var i := _find(id)
	return i >= 0 and _objectives[i]["done"]


func has_objective(id: String) -> bool:
	return _find(id) >= 0


func save_checkpoint(data: Dictionary) -> void:
	checkpoint = data.duplicate(true)
	Game.notify("Checkpoint")


## Reloads the mission, from the last checkpoint or from the start.
func retry(from_checkpoint := true) -> void:
	if not from_checkpoint:
		checkpoint = {}
	Game.restart()


func complete_mission() -> void:
	progress["completed"][mission_id] = true
	checkpoint = {}
	_save_progress()
	mission_completed.emit(mission_id)


func is_mission_completed(id: String) -> bool:
	return progress["completed"].get(id, false)


func _find(id: String) -> int:
	for i in _objectives.size():
		if _objectives[i]["id"] == id:
			return i
	return -1


func _remove_done(id: String) -> void:
	var i := _find(id)
	if i >= 0 and _objectives[i]["done"]:
		_objectives.remove_at(i)
		_refresh()


# --- Save file -------------------------------------------------------------------

func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary and (data as Dictionary).get("completed") is Dictionary:
		progress = data


func _save_progress() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(progress, "\t"))


# --- UI ----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_overlay.queue_redraw()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_title_label.text = title.to_upper()
	_title_label.visible = not _objectives.is_empty()
	for objective in _objectives:
		var label := Label.new()
		var done: bool = objective["done"]
		label.text = ("[done]  " if done else ">  ") + str(objective["text"])
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", DONE_COLOR if done else Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_list.add_child(label)


## Waypoint markers for active objectives that have a target.
func _draw_waypoints() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var font := ThemeDB.fallback_font
	var screen := _overlay.size
	for objective in _objectives:
		var target: Variant = objective["target"]
		if objective["done"] or not is_instance_valid(target):
			continue
		var world: Vector3 = (target as Node3D).global_position + Vector3.UP * 1.5
		var distance := camera.global_position.distance_to(world)
		var behind := camera.is_position_behind(world)
		var p := camera.unproject_position(world)
		var margin := 40.0
		var on_screen := not behind and Rect2(Vector2.ZERO, screen).grow(-margin).has_point(p)
		if not on_screen:
			# Pin to the screen edge, pointing the right way even when behind.
			var local := camera.global_basis.inverse() * (world - camera.global_position)
			var direction := Vector2(local.x, -local.y).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.DOWN
			var half := screen * 0.5 - Vector2(margin, margin)
			var scale_to_edge := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
			p = screen * 0.5 + direction * scale_to_edge
		var d := 9.0
		var diamond := PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)])
		_overlay.draw_colored_polygon(diamond, Color(ACTIVE_COLOR, 0.9))
		diamond.append(diamond[0])
		_overlay.draw_polyline(diamond, Color(0, 0, 0, 0.8), 1.5)
		var text := "%d m" % roundi(distance) if distance < 10000.0 else "%.1f km" % (distance / 1000.0)
		_overlay.draw_string(font, p + Vector2(-40, 26), text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, ACTIVE_COLOR)


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_waypoints)
	add_child(_overlay)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -560.0
	box.offset_right = -30.0
	box.offset_top = 20.0
	box.offset_bottom = 200.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", ACTIVE_COLOR)
	_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_title_label.add_theme_constant_override("outline_size", 4)
	box.add_child(_title_label)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_list)
