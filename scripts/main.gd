extends Node3D
## Level root: bakes navigation, wires the player to the HUD, tracks the
## objective, and handles death and restart.

@onready var player: Player = $Player
@onready var hud: HUD = $HUD
@onready var level: NavigationRegion3D = $Level

var _can_restart := false


func _ready() -> void:
	var weapon := player.weapon
	weapon.ammo_changed.connect(hud.set_ammo)
	weapon.reload_state_changed.connect(hud.set_reloading)
	weapon.hit_confirmed.connect(hud.show_hitmarker)
	player.health_changed.connect(hud.set_health)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	# These were emitted before we connected, so sync once here.
	hud.set_ammo(weapon.ammo_in_magazine, weapon.reserve_ammo)
	hud.set_health(player.health, player.max_health)

	for node in get_tree().get_nodes_in_group("enemies"):
		(node as Enemy).died.connect(_on_enemy_died)
	_update_objective()
	hud.show_banner("Clear the compound", 3.0)

	# CSG level geometry is generated at the end of the first frame, so bake
	# the navigation mesh after that.
	await get_tree().process_frame
	level.bake_navigation_mesh()


func _unhandled_input(event: InputEvent) -> void:
	if _can_restart and (event.is_action_pressed("fire") or event.is_action_pressed("jump")):
		Game.restart()


func _update_objective() -> void:
	var remaining := get_tree().get_nodes_in_group("enemies").size()
	if remaining > 0:
		hud.set_objective("Hostiles remaining: %d" % remaining)
	else:
		hud.set_objective("Area secure")


func _on_enemy_died() -> void:
	_update_objective()
	if get_tree().get_nodes_in_group("enemies").is_empty():
		hud.show_banner("AREA CLEARED", 4.0)


func _on_player_damaged(from_position: Vector3) -> void:
	# Direction of the attacker relative to where the player is facing.
	var local := player.global_transform.basis.inverse() * (from_position - player.global_position)
	hud.show_damage(atan2(local.x, -local.z))


func _on_player_died() -> void:
	hud.show_death_screen()
	await get_tree().create_timer(1.5).timeout
	_can_restart = true
	hud.show_restart_hint()
