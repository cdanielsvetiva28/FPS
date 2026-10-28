class_name FlightHUD
extends CanvasLayer
## Flight HUD: speed, altitude, throttle, weapons, health, target markers with
## lock-on ring, off-screen target arrow, radar and warnings. Radio chatter and
## objectives come from the shared Radio and Mission autoloads.

const ALERT_SOUND := preload("res://assets/sounds/missile_alert.wav")
const HIT_SOUND := preload("res://assets/sounds/hitmarker.wav")
const KILL_SOUND := preload("res://assets/sounds/kill_confirm.wav")

const HUD_GREEN := Color(0.55, 1.0, 0.6, 0.95)
const ENEMY_COLOR := Color(1.0, 0.45, 0.3, 0.95)
const LOCK_COLOR := Color(1.0, 0.2, 0.15, 1.0)
const WARN_COLOR := Color(1.0, 0.25, 0.2, 1.0)
const RADAR_RANGE := 6000.0
const RADAR_RADIUS := 90.0
const KEYBOARD_CONTROLS := """PAUSED
Click or Esc to resume      M - main menu

Mouse - pitch and roll      Q / E - roll      A / D - rudder (yaw)
W / S - throttle (full throttle = afterburner)
Left click - cannon      Right click - missile (lock on first)
Space / Tab - switch target      F - flares
V - cockpit / chase camera      F11 - fullscreen"""
const CONTROLLER_CONTROLS := """PAUSED
%s to resume      %s - main menu

Left stick - pitch and roll (push up to dive)      L1 / R1 - rudder (yaw)
R2 - accelerate      L2 - brake      Right stick - look around
Square / X - cannon      Circle / B - missile (lock on first)
Triangle / Y - switch target      Cross / A - flares      R3 - camera"""

@onready var overlay: Control = $Overlay
@onready var speed_label: Label = $SpeedLabel
@onready var altitude_label: Label = $AltitudeLabel
@onready var throttle_bar: ProgressBar = $ThrottleBar
@onready var weapons_label: Label = $WeaponsLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var target_label: Label = $TargetLabel
@onready var warning_label: Label = $WarningLabel
@onready var banner_label: Label = $BannerLabel
@onready var prompt_label: Label = $PromptLabel
@onready var pause_screen: Control = $PauseScreen
@onready var pause_text: Label = $PauseScreen/Text

var player: PlayerJet
var _alert_timer := 0.0
var _blink := 0.0


func _ready() -> void:
	Game.paused_changed.connect(_on_paused_changed)
	pause_screen.visible = false
	banner_label.visible = false
	prompt_label.visible = false
	overlay.draw.connect(_draw_overlay)


func bind_player(jet: PlayerJet) -> void:
	player = jet
	player.hit_confirmed.connect(_on_hit_confirmed)


func show_banner(text: String, color := HUD_GREEN) -> void:
	banner_label.text = text
	banner_label.modulate = color
	banner_label.visible = true


func show_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = true


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta, 1.0)
	overlay.queue_redraw()
	if player == null:
		return

	speed_label.text = "SPEED\n%d" % roundi(player.speed * 3.6)
	altitude_label.text = "ALT\n%d" % roundi(player.global_position.y)
	throttle_bar.value = player.throttle * 100.0
	weapons_label.text = "GUN  %d\nMSL  %d\nFLR  %d" % [player.gun_ammo_left, player.missiles_left, player.flares_left]
	health_bar.value = player.health / player.max_health * 100.0

	if is_instance_valid(player.target) and not player.target.is_destroyed:
		var distance := player.global_position.distance_to(player.target.global_position)
		target_label.text = "%s   %d m" % [player.target.display_name, roundi(distance)]
	else:
		target_label.text = ""

	_update_warnings(delta)


func _update_warnings(delta: float) -> void:
	var warnings: PackedStringArray = []
	if player.is_destroyed:
		warning_label.text = ""
		return

	# Incoming missiles: beep faster the closer the nearest one is.
	var closest := INF
	for node in get_tree().get_nodes_in_group("missiles"):
		var missile := node as Missile
		if missile.is_tracking(player):
			closest = minf(closest, missile.global_position.distance_to(player.global_position))
	if closest < INF:
		warnings.append("MISSILE")
		_alert_timer -= delta
		if _alert_timer <= 0.0:
			_alert_timer = clampf(closest / 3000.0, 0.07, 0.45)
			Game.play_sound(ALERT_SOUND, -8.0, 0.0)

	# Pull up: low and descending toward the ground.
	var sink := -player.velocity.y
	if player.clearance() < 400.0 and sink > 10.0 and player.clearance() / sink < 5.0:
		warnings.append("PULL UP")
	if player.speed < player.stall_speed:
		warnings.append("STALL")
	if Vector2(player.global_position.x, player.global_position.z).length() > 5500.0:
		warnings.append("RETURN TO COMBAT AREA")

	warning_label.text = "\n".join(warnings) if _blink < 0.6 else ""


func _on_paused_changed(paused: bool) -> void:
	pause_screen.visible = paused
	if not paused:
		return
	if Game.input_style() == "keyboard":
		pause_text.text = KEYBOARD_CONTROLS
	else:
		pause_text.text = CONTROLLER_CONTROLS % [Game.prompt("confirm"), Game.prompt("menu")]


func _on_hit_confirmed(killed: bool) -> void:
	Game.play_sound(KILL_SOUND if killed else HIT_SOUND, -8.0 if killed else -14.0, 0.05)


# --- Drawing -------------------------------------------------------------------

func _draw_overlay() -> void:
	if player == null or player.is_destroyed:
		return
	var camera := player.camera
	var font := ThemeDB.fallback_font

	# Gun reticle: where the nose points, 600 m out.
	var aim := player.global_position + player.forward() * 600.0
	if not camera.is_position_behind(aim):
		var p := camera.unproject_position(aim)
		overlay.draw_arc(p, 18.0, 0.0, TAU, 32, HUD_GREEN, 2.0)
		overlay.draw_circle(p, 2.0, HUD_GREEN)

	# Aircraft markers.
	for node in get_tree().get_nodes_in_group("aircraft"):
		var aircraft := node as Aircraft
		if aircraft == player or aircraft.is_destroyed:
			continue
		if camera.is_position_behind(aircraft.global_position):
			continue
		var p := camera.unproject_position(aircraft.global_position)
		var friendly := aircraft.team == player.team
		var color := HUD_GREEN if friendly else ENEMY_COLOR
		if aircraft == player.target:
			_draw_target_marker(p, aircraft, font)
		else:
			_draw_brackets(p, 12.0, color)
		overlay.draw_string(font, p + Vector2(16, -10), aircraft.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

	# Incoming missiles.
	for node in get_tree().get_nodes_in_group("missiles"):
		var missile := node as Missile
		if missile.is_tracking(player) and not camera.is_position_behind(missile.global_position):
			var p := camera.unproject_position(missile.global_position)
			overlay.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(7, 6), p + Vector2(-7, 6)]), WARN_COLOR)

	_draw_target_arrow(camera)
	_draw_radar()


func _draw_brackets(p: Vector2, half: float, color: Color) -> void:
	var l := half * 0.5
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := p + Vector2(sx * half, sy * half)
			overlay.draw_line(corner, corner - Vector2(sx * l, 0), color, 2.0)
			overlay.draw_line(corner, corner - Vector2(0, sy * l), color, 2.0)


func _draw_target_marker(p: Vector2, aircraft: Aircraft, font: Font) -> void:
	var locked := player.is_locked()
	var color := LOCK_COLOR if locked else ENEMY_COLOR
	# Diamond around the target.
	var d := 16.0
	overlay.draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d),
		p + Vector2(-d, 0), p + Vector2(0, -d)]), color, 2.0)
	# Lock ring closes in as the lock builds.
	if player.lock_progress > 0.0:
		var radius := lerpf(70.0, 24.0, player.lock_progress)
		overlay.draw_arc(p, radius, 0.0, TAU, 40, color if locked else Color(1, 0.9, 0.3, 0.9), 2.0)
	if locked:
		overlay.draw_string(font, p + Vector2(-16, 40), "LOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LOCK_COLOR)
	var distance := player.global_position.distance_to(aircraft.global_position)
	overlay.draw_string(font, p + Vector2(16, 18), "%.1f km" % (distance / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


## Arrow at the screen edge pointing toward an off-screen target.
func _draw_target_arrow(camera: Camera3D) -> void:
	var target := player.target
	if not is_instance_valid(target) or target.is_destroyed:
		return
	var size := overlay.size
	var center := size * 0.5
	var behind := camera.is_position_behind(target.global_position)
	var p := camera.unproject_position(target.global_position)
	var on_screen := not behind and Rect2(Vector2.ZERO, size).grow(-20.0).has_point(p)
	if on_screen:
		return
	# Direction in camera space works whether the target is in front or behind.
	var local := camera.global_basis.inverse() * (target.global_position - camera.global_position)
	var direction := Vector2(local.x, -local.y).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	var tip := center + direction * minf(size.x, size.y) * 0.38
	var side := direction.orthogonal() * 10.0
	overlay.draw_colored_polygon(PackedVector2Array([tip + direction * 14.0, tip + side, tip - side]), ENEMY_COLOR)


func _draw_radar() -> void:
	var center := Vector2(overlay.size.x * 0.5, overlay.size.y - RADAR_RADIUS - 24.0)
	overlay.draw_circle(center, RADAR_RADIUS, Color(0.0, 0.08, 0.02, 0.45))
	overlay.draw_arc(center, RADAR_RADIUS, 0.0, TAU, 48, Color(HUD_GREEN, 0.6), 1.5)
	overlay.draw_arc(center, RADAR_RADIUS * 0.5, 0.0, TAU, 32, Color(HUD_GREEN, 0.25), 1.0)
	# Player at the centre, nose up.
	overlay.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -7), center + Vector2(5, 5),
		center + Vector2(-5, 5)]), HUD_GREEN)

	var yaw_basis := Basis(Vector3.UP, player.global_rotation.y)
	for node in get_tree().get_nodes_in_group("aircraft"):
		var aircraft := node as Aircraft
		if aircraft == player or aircraft.is_destroyed:
			continue
		var color := HUD_GREEN if aircraft.team == player.team else ENEMY_COLOR
		_draw_radar_blip(center, yaw_basis, aircraft.global_position, color, 4.0 if aircraft == player.target else 3.0)
	for node in get_tree().get_nodes_in_group("missiles"):
		var missile := node as Missile
		if missile.is_tracking(player):
			_draw_radar_blip(center, yaw_basis, missile.global_position, Color.WHITE, 2.0)


func _draw_radar_blip(center: Vector2, yaw_basis: Basis, world: Vector3, color: Color, radius: float) -> void:
	var local := yaw_basis.inverse() * (world - player.global_position)
	var flat := Vector2(local.x, local.z) / RADAR_RANGE * RADAR_RADIUS
	if flat.length() > RADAR_RADIUS:
		flat = flat.normalized() * RADAR_RADIUS
	overlay.draw_circle(center + flat, radius, color)
