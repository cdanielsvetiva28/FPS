extends Node3D
## Flight test mission, a preview of Mission 2, "First Light" (see docs/STORY.md).
## Wren and Lantern Lead intercept a Sevrin fighter sweep over the strait;
## a second wave arrives with a Stormcrow ace.

const ENEMY_SCENE := preload("res://scenes/flight/enemy_jet.tscn")
const MISSION_ID := "first_light"

const KILL_LINES: Array[String] = [
	"Splash one! Good kill, Wren.",
	"Bandit down. Nice shooting.",
	"That's a kill. Keep your eyes open.",
	"Splash! He's going in.",
]

@onready var player: PlayerJet = $PlayerJet
@onready var wingman: AIJet = $Wingman
@onready var hud: FlightHUD = $FlightHUD
@onready var enemies_root: Node3D = $Enemies

var _wave := 0
var _ended := false
var _can_restart := false
var _warned_smoke := false
var _warned_missile := false


func _ready() -> void:
	hud.bind_player(player)
	player.destroyed.connect(_on_player_destroyed)
	player.damaged.connect(_on_player_damaged)

	if Mission.begin(MISSION_ID, "First Light") and Mission.checkpoint.get("wave", 1) == 2:
		# Retrying from the checkpoint: straight to the second wave.
		Radio.say("LANTERN 1", "Shake it off, Wren. They're coming around again.")
		_spawn_wave_two()
		return
	Radio.say("SKYWARD", "Lantern, Skyward. Radar contact: four bandits, bearing zero-zero-zero, angels twelve. Weapons free.")
	Radio.say("LANTERN 1", "Lantern 2, form up on me... ah, forget it. You've got the lead, Wren. Go get them.")
	if Game.using_controller:
		Radio.say("SKYWARD", "Reminder: lock on before you fire missiles. Left stick to fly, R2 and L2 for throttle.")
	else:
		Radio.say("SKYWARD", "Reminder: lock on before you fire missiles. Mouse to fly, W and S for throttle.")
	_spawn_wave_one()


func _process(_delta: float) -> void:
	if _ended:
		return
	if not _warned_missile:
		for node in get_tree().get_nodes_in_group("missiles"):
			if (node as Missile).is_tracking(player):
				_warned_missile = true
				Radio.say("LANTERN 1", "Missile on you, Wren! Break hard, pop flares!")
				break


func _unhandled_input(event: InputEvent) -> void:
	if not _can_restart:
		return
	if event.is_action_pressed("fire") or event.is_action_pressed("gun") or event.is_action_pressed("jump"):
		Mission.retry(true)
	elif event.is_action_pressed("retry_mission"):
		Mission.retry(false)
	elif event.is_action_pressed("menu"):
		Game.go_to_menu()


func _spawn_wave_one() -> void:
	_wave = 1
	for i in 4:
		var x := (i - 1.5) * 700.0
		_spawn_enemy("BANDIT", Vector3(x, randf_range(1100.0, 1400.0), randf_range(-1400.0, -600.0)), Vector3.BACK, 0.45 + i * 0.05)
	Mission.add_objective("wave_1", "")
	_update_objective()


func _spawn_wave_two() -> void:
	_wave = 2
	if Mission.has_objective("wave_1"):
		Mission.complete_objective("wave_1")
	Mission.add_objective("wave_2", "")
	Mission.save_checkpoint({"wave": 2})
	Radio.say("SKYWARD", "New contacts, bearing zero-niner-zero. Three... no, four. One of them is fast.")
	for i in 3:
		_spawn_enemy("BANDIT", Vector3(5000.0, 1300.0 + i * 80.0, 1500.0 - i * 500.0), Vector3.LEFT, 0.6)
	var ace := _spawn_enemy("STORMCROW 2", Vector3(5200.0, 1600.0, 600.0), Vector3.LEFT, 0.95)
	ace.max_health = 220.0
	ace.health = 220.0
	ace.max_speed = 370.0
	ace.missile_cooldown_min = 5.0
	ace.missile_cooldown_max = 8.0
	Radio.say("LANTERN 1", "Orange tail fin... that's a Stormcrow. Wren, don't let him get behind you.")
	Radio.say("STORMCROW 2", "Halvard pilots. You fly like you have something to prove.")
	_update_objective()


func _spawn_enemy(callsign: String, at: Vector3, heading: Vector3, skill: float) -> AIJet:
	var jet: AIJet = ENEMY_SCENE.instantiate()
	jet.display_name = callsign
	jet.skill = skill
	jet.transform = Transform3D(Basis.looking_at(heading.normalized()), at)
	enemies_root.add_child(jet)
	jet.destroyed.connect(_on_enemy_destroyed)
	return jet


func _remaining_enemies() -> int:
	var count := 0
	for node in enemies_root.get_children():
		var jet := node as Aircraft
		if jet and not jet.is_destroyed:
			count += 1
	return count


func _update_objective() -> void:
	var id := "wave_%d" % _wave
	var text := "Destroy the bandits" if _wave == 1 else "Destroy the reinforcements"
	Mission.set_objective_text(id, "%s (%d left)" % [text, _remaining_enemies()])


func _on_enemy_destroyed(aircraft: Aircraft) -> void:
	if _ended:
		return
	_update_objective()
	var remaining := _remaining_enemies()
	if aircraft.display_name.begins_with("STORMCROW"):
		Radio.say("LANTERN 1", "You got the Stormcrow! Wren, that's... that's going to make you famous.")
	elif randf() < 0.75:
		Radio.say("LANTERN 1", KILL_LINES.pick_random())

	if _wave == 1 and remaining <= 1:
		_spawn_wave_two()
	elif _wave == 2 and remaining == 0:
		_end_mission(true)


func _on_player_damaged(_amount: float) -> void:
	if not _warned_smoke and player.health < player.max_health * 0.4 and not player.is_destroyed:
		_warned_smoke = true
		Radio.say("LANTERN 1", "Wren, you're trailing smoke! Keep it together.")


func _on_player_destroyed(_aircraft: Aircraft) -> void:
	_end_mission(false)


func _end_mission(won: bool) -> void:
	if _ended:
		return
	_ended = true
	if won:
		Mission.complete_objective("wave_2")
		Mission.complete_mission()
		hud.show_banner("MISSION ACCOMPLISHED")
		Radio.say("SKYWARD", "All bandits down. Lantern, good work. RTB.")
		Radio.say("LANTERN 1", "Not bad for your first day, Wren. Not bad at all.")
	else:
		hud.show_banner("CRASHED" if player.crashed else "SHOT DOWN", FlightHUD.WARN_COLOR)
		Radio.say("LANTERN 1", "Wren! WREN! ...Skyward, Lantern 2 is down.")
	await get_tree().create_timer(2.0).timeout
	_can_restart = true
	var lines: PackedStringArray = []
	if not won and not Mission.checkpoint.is_empty():
		lines.append("%s  Retry from checkpoint" % Game.prompt("confirm"))
		lines.append("%s  Restart mission" % Game.prompt("restart"))
	else:
		lines.append("%s  Fly again" % Game.prompt("confirm"))
	lines.append("%s  Main menu" % Game.prompt("menu"))
	hud.show_prompt("      ".join(lines))
