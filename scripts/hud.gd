class_name HUD
extends CanvasLayer
## Heads-up display: crosshair, hit marker, ammo, health, damage feedback,
## objective, messages, and the pause and death screens.

@onready var ammo_label: Label = $AmmoLabel
@onready var reload_label: Label = $ReloadLabel
@onready var hitmarker: Label = $Hitmarker
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var objective_label: Label = $ObjectiveLabel
@onready var message_label: Label = $MessageLabel
@onready var banner_label: Label = $BannerLabel
@onready var damage_overlay: ColorRect = $DamageOverlay
@onready var damage_indicator: Node2D = $DamageIndicator
@onready var pause_screen: Control = $PauseScreen
@onready var death_screen: Control = $DeathScreen
@onready var restart_label: Label = $DeathScreen/Center/RestartLabel

## Red tint that stays on screen at low health.
var _low_health_alpha := 0.0
var _hitmarker_tween: Tween
var _damage_tween: Tween
var _indicator_tween: Tween
var _message_tween: Tween


func _ready() -> void:
	Game.paused_changed.connect(_on_paused_changed)
	Game.message_posted.connect(show_message)
	pause_screen.visible = false
	death_screen.visible = false
	banner_label.visible = false


func _process(_delta: float) -> void:
	damage_indicator.position = get_viewport().get_visible_rect().size * 0.5


func set_ammo(in_magazine: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_magazine, reserve]


func set_reloading(reloading: bool) -> void:
	reload_label.visible = reloading


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d" % ceili(current)
	var ratio := current / maximum
	_low_health_alpha = clampf((0.5 - ratio) / 0.5, 0.0, 1.0) * 0.3
	if not (_damage_tween and _damage_tween.is_running()):
		damage_overlay.color.a = _low_health_alpha


func set_objective(text: String) -> void:
	objective_label.text = text


func show_hitmarker(killed: bool) -> void:
	hitmarker.modulate = Color(1.0, 0.25, 0.25) if killed else Color.WHITE
	if _hitmarker_tween:
		_hitmarker_tween.kill()
	_hitmarker_tween = create_tween()
	_hitmarker_tween.tween_property(hitmarker, "modulate:a", 0.0, 0.25)


## `angle` is the direction the damage came from relative to where the player
## is looking, in radians: 0 = ahead, positive = to the right.
func show_damage(angle: float) -> void:
	if _damage_tween:
		_damage_tween.kill()
	damage_overlay.color.a = maxf(0.3, _low_health_alpha)
	_damage_tween = create_tween()
	_damage_tween.tween_property(damage_overlay, "color:a", _low_health_alpha, 0.4)

	damage_indicator.rotation = angle
	damage_indicator.modulate.a = 1.0
	if _indicator_tween:
		_indicator_tween.kill()
	_indicator_tween = create_tween()
	_indicator_tween.tween_interval(0.4)
	_indicator_tween.tween_property(damage_indicator, "modulate:a", 0.0, 0.6)


func show_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(1.2)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.5)


## Shows a large centred message. A `duration` of 0 keeps it up.
func show_banner(text: String, duration := 0.0) -> void:
	banner_label.text = text
	banner_label.visible = true
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if banner_label.text == text:
			banner_label.visible = false


func show_death_screen() -> void:
	death_screen.visible = true
	restart_label.visible = false


func show_restart_hint() -> void:
	restart_label.visible = true


func _on_paused_changed(paused: bool) -> void:
	pause_screen.visible = paused
