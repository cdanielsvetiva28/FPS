extends Node3D
## Test level root. Wires the player's weapon to the HUD and handles
## window-level shortcuts.

@onready var player: Player = $Player
@onready var hud: HUD = $HUD


func _ready() -> void:
	var weapon := player.weapon
	weapon.ammo_changed.connect(hud.set_ammo)
	weapon.reload_state_changed.connect(hud.set_reloading)
	weapon.hit_confirmed.connect(hud.show_hitmarker)
	# The weapon emitted its initial ammo before we connected, so sync once here.
	hud.set_ammo(weapon.ammo_in_magazine, weapon.reserve_ammo)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
