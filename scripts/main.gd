extends Node3D
## Ground test mission, "Compound Raid": breach the compound, clear it,
## download the pylon data and reach the extraction point. Uses the shared
## mission framework (Mission, Radio, TriggerZone, Interactable).

const MISSION_ID := "compound_raid"

@onready var player: Player = $Player
@onready var hud: HUD = $HUD
@onready var level: NavigationRegion3D = $Level
@onready var enemies_root: Node3D = $Enemies
@onready var breach_marker: Node3D = $Objectives/BreachMarker
@onready var breach_zone: TriggerZone = $Objectives/BreachZone
@onready var terminal: Interactable = $Objectives/Terminal
@onready var extraction_zone: TriggerZone = $Objectives/ExtractionZone

var _total_enemies := 0
var _dead_enemies: Array[String] = []
var _breached := false
var _data_downloaded := false
var _ended := false
var _can_restart := false


func _ready() -> void:
	hud.bind_player(player)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	breach_zone.triggered.connect(_on_breached)
	terminal.used.connect(_on_data_downloaded)
	extraction_zone.triggered.connect(_on_extraction_reached)

	if Mission.begin(MISSION_ID, "Compound Raid"):
		_restore(Mission.checkpoint)
	else:
		hud.show_banner("COMPOUND RAID", 3.0)
		Radio.say_lines([
			"OVERWATCH: Pathfinder, Overwatch. Sevrin squad holding the pylon depot. You're clear to move.",
			"MBEKI: Five hostiles, Sarge. Gap in the wall dead ahead. Let's go.",
		])

	for node in get_tree().get_nodes_in_group("enemies"):
		(node as Enemy).died.connect(_on_enemy_died.bind(str(node.name)))
	_total_enemies = get_tree().get_nodes_in_group("enemies").size() + _dead_enemies.size()
	_update_objectives()

	# CSG level geometry is generated at the end of the first frame, so bake
	# the navigation mesh after that.
	await get_tree().process_frame
	level.bake_navigation_mesh()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_restart:
		return
	if event.is_action_pressed("fire") or event.is_action_pressed("jump"):
		Mission.retry(true)
	elif event.is_action_pressed("retry_mission"):
		Mission.retry(false)
	elif event.is_action_pressed("menu"):
		Game.go_to_menu()


## Called by TriggerZones with "checkpoint" ticked, and after each objective.
func save_checkpoint() -> void:
	Mission.save_checkpoint({
		"position": player.global_position,
		"yaw": player.rotation.y,
		"health": player.health,
		"dead": _dead_enemies.duplicate(),
		"breached": _breached,
		"data": _data_downloaded,
	})


func _restore(data: Dictionary) -> void:
	player.global_position = data["position"]
	player.rotation.y = data["yaw"]
	player.set_health(data["health"])
	_breached = data["breached"]
	_data_downloaded = data["data"]
	terminal.enabled = not _data_downloaded
	for enemy_name: String in data["dead"]:
		var enemy := enemies_root.get_node_or_null(enemy_name)
		if enemy:
			enemy.remove_from_group("enemies")
			enemy.queue_free()
		_dead_enemies.append(enemy_name)
	Radio.say("MBEKI", "Back on your feet, Sarge. Let's finish this.")


## Adds whichever objectives are active now (completed ones aren't re-added).
func _update_objectives() -> void:
	if _ended:
		return
	var remaining := _total_enemies - _dead_enemies.size()
	if not _breached:
		Mission.add_objective("breach", "Breach the compound", breach_marker)
		return
	if remaining > 0:
		Mission.add_objective("clear", "")
		Mission.set_objective_text("clear", "Eliminate hostiles (%d/%d)" % [_dead_enemies.size(), _total_enemies])
	if not _data_downloaded:
		Mission.add_objective("data", "Download the pylon data", terminal)
	if remaining <= 0 and _data_downloaded:
		Mission.add_objective("extract", "Reach the extraction point", extraction_zone)


func _on_breached() -> void:
	if _breached:
		return
	_breached = true
	Mission.complete_objective("breach")
	Radio.say_lines([
		"MBEKI: We're in. Terminal's up on that platform, Sarge.",
		"OVERWATCH: Pathfinder, we need that pylon's logs. Clear the area and pull the data.",
	])
	_update_objectives()
	save_checkpoint()


func _on_enemy_died(enemy_name: String) -> void:
	_dead_enemies.append(enemy_name)
	var remaining := _total_enemies - _dead_enemies.size()
	if remaining <= 0:
		if Mission.has_objective("clear"):
			Mission.complete_objective("clear")
		Radio.say("MBEKI", "That's the last of them. Area clear.")
		_update_objectives()
		save_checkpoint()
	else:
		_update_objectives()
		if remaining == 1:
			Radio.say("MBEKI", "One left. Watch the corners.")


func _on_data_downloaded() -> void:
	_data_downloaded = true
	Mission.complete_objective("data")
	Radio.say_lines([
		"TEO: Got it. Wait... these logs are from inside our network.",
		"OVERWATCH: Not your concern, Sergeant. Bring it home.",
	])
	_update_objectives()
	save_checkpoint()


func _on_extraction_reached() -> void:
	# The zone fires on every entry; it only counts once extraction is the objective.
	if not Mission.has_objective("extract") or _ended:
		return
	_ended = true
	Mission.complete_objective("extract")
	Mission.complete_mission()
	hud.show_banner("MISSION COMPLETE")
	Radio.say_lines([
		"OVERWATCH: Good work, Pathfinder. Bird's inbound.",
		"MBEKI: Sarge... what was on that pylon?",
	])
	await get_tree().create_timer(7.0).timeout
	Game.go_to_menu()


func _on_player_damaged(from_position: Vector3) -> void:
	# Direction of the attacker relative to where the player is facing.
	var local := player.global_transform.basis.inverse() * (from_position - player.global_position)
	hud.show_damage(atan2(local.x, -local.z))


func _on_player_died() -> void:
	hud.show_death_screen()
	await get_tree().create_timer(1.5).timeout
	_can_restart = true
	var lines: PackedStringArray = []
	if not Mission.checkpoint.is_empty():
		lines.append("%s  Retry from checkpoint" % Game.prompt("confirm"))
	lines.append("%s  Restart mission" % Game.prompt("restart"))
	lines.append("%s  Main menu" % Game.prompt("menu"))
	hud.show_restart_hint("      ".join(lines))
