class_name AIJet
extends Aircraft
## Computer-controlled fighter, for enemies and wingmen alike.
##
## States:
##   PATROL  Fly between points around its starting area.
##   ENGAGE  Chase the chosen target (lead pursuit), firing missiles and guns.
##   EVADE   Break hard (and maybe pop flares) when a missile is tracking it.
## Terrain avoidance overrides everything, so AI pilots don't fly into hills.

enum State { PATROL, ENGAGE, EVADE }

const MISSILE_SCENE := preload("res://scenes/flight/missile.tscn")
const ENGINE_SOUND := preload("res://assets/sounds/jet_engine.wav")
const CANNON_SOUND := preload("res://assets/sounds/cannon_shot.wav")

## 0..1: how hard it turns, how well it aims, how often it dodges.
@export_range(0.0, 1.0) var skill := 0.6
## Wingmen can be made very hard to kill so they survive the whole mission.
@export var damage_taken_multiplier := 1.0
@export var engage_range := 7000.0
@export var missile_damage := 34.0
@export var missile_cooldown_min := 7.0
@export var missile_cooldown_max := 12.0
@export var gun_damage := 3.0
@export var patrol_radius := 1500.0
## Keep out of this horizontal distance from the map centre.
@export var map_radius := 5200.0

var state := State.PATROL
var target: Aircraft

var _patrol_center := Vector3.ZERO
var _patrol_point := Vector3.ZERO
var _retarget_timer := 0.0
var _missile_timer := 0.0
var _gun_cooldown := 0.0
var _evade_timer := 0.0
var _evade_side := 1.0
var _flares_left := 2
var _dodged_missiles: Array = []
var _bullets: BulletManager
var _terrain: Terrain

@onready var engine_audio: AudioStreamPlayer3D = $EngineAudio


func _ready() -> void:
	super()
	_patrol_center = global_position
	_pick_patrol_point()
	_missile_timer = randf_range(3.0, missile_cooldown_min)
	throttle = 0.55
	engine_audio.stream = Game.looping(ENGINE_SOUND)
	engine_audio.play(randf() * 2.0)


func take_damage(amount: float, source: Node = null) -> void:
	super(amount * damage_taken_multiplier, source)
	# Getting shot makes whoever did it the priority.
	var attacker := source as Aircraft
	if attacker and attacker.team != team and not is_destroyed:
		target = attacker


func _process(delta: float) -> void:
	if is_destroyed:
		return
	if _bullets == null:
		_bullets = get_tree().get_first_node_in_group("bullets") as BulletManager
		_terrain = get_tree().get_first_node_in_group("terrain") as Terrain

	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _target_valid():
		_retarget_timer = 2.0
		target = _choose_target()
	_update_state(delta)

	var direction := forward()
	var desired_throttle := 0.55
	match state:
		State.PATROL:
			if global_position.distance_to(_patrol_point) < 500.0:
				_pick_patrol_point()
			direction = (_patrol_point - global_position).normalized()
		State.ENGAGE:
			var to_target := target.global_position - global_position
			var distance := to_target.length()
			# Lead pursuit: aim where the target will be.
			var lead := target.velocity * clampf(distance / 900.0, 0.0, 1.5) * lerpf(0.3, 1.0, skill)
			direction = (target.global_position + lead - global_position).normalized()
			desired_throttle = 1.0 if distance > 1500.0 else 0.7
			if distance < 220.0 and angle_to_point(target.global_position) < 0.5:
				# About to ram: overshoot and break off.
				direction = (forward() + global_basis.x * _evade_side).normalized()
		State.EVADE:
			direction = (global_basis.x * _evade_side * 1.2 + Vector3.UP * 0.3 + forward() * 0.2).normalized()
			desired_throttle = 1.0

	direction = _avoid_terrain_and_edges(direction)
	throttle = move_toward(throttle, desired_throttle, 0.5 * delta)
	_steer(direction, delta)
	if state == State.ENGAGE:
		_attack(delta)


func _target_valid() -> bool:
	return is_instance_valid(target) and not target.is_destroyed


func _choose_target() -> Aircraft:
	var best: Aircraft = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("aircraft"):
		var other := node as Aircraft
		if other.team == team or other.is_destroyed:
			continue
		var score := global_position.distance_to(other.global_position)
		if other is PlayerJet:
			score *= 0.7  # The enemy prefers the player over wingmen.
		if score < best_score:
			best_score = score
			best = other
	return best


func _update_state(delta: float) -> void:
	var threat := _incoming_missile()
	if threat and state != State.EVADE and not _dodged_missiles.has(threat):
		_dodged_missiles.append(threat)
		state = State.EVADE
		_evade_timer = randf_range(2.0, 3.5)
		_evade_side = -1.0 if randf() < 0.5 else 1.0
		if _flares_left > 0 and randf() < skill * 0.6:
			_pop_flares()
		return
	if state == State.EVADE:
		_evade_timer -= delta
		if _evade_timer > 0.0:
			return
	if _target_valid() and global_position.distance_to(target.global_position) < engage_range:
		state = State.ENGAGE
	else:
		state = State.PATROL


func _incoming_missile() -> Missile:
	for node in get_tree().get_nodes_in_group("missiles"):
		var missile := node as Missile
		if missile.is_tracking(self) and missile.global_position.distance_to(global_position) < 2200.0:
			return missile
	return null


## Bank-and-pull steering toward a world direction.
func _steer(direction: Vector3, delta: float) -> void:
	var local := global_basis.inverse() * direction
	var off_nose := acos(clampf(-local.z, -1.0, 1.0))
	# Roll so the target sits "above" the canopy, then pull.
	var bank_roll := clampf(atan2(local.x, local.y) * 1.5, -1.0, 1.0)
	# Near the nose, level the wings instead and make fine corrections.
	var level_roll := clampf(global_basis.x.y * 2.0, -1.0, 1.0)
	var blend := clampf(off_nose / 0.3, 0.0, 1.0)
	var roll := lerpf(level_roll, bank_roll, blend)
	var pitch := clampf(local.y * 4.0, -0.5, 1.0)
	if local.z > 0.0:
		pitch = 1.0 if absf(atan2(local.x, local.y)) < 1.2 else 0.3  # Target behind: pull hard.
	var yaw := clampf(local.x * 4.0, -1.0, 1.0) * (1.0 - blend)
	var effort := lerpf(0.65, 1.0, skill)
	fly(pitch * effort, roll, yaw, delta)


func _avoid_terrain_and_edges(direction: Vector3) -> Vector3:
	var flat_forward := Vector3(forward().x, 0.0, forward().z).normalized()
	if _terrain:
		var ahead := global_position + forward() * speed * 3.0
		var ground_here := maxf(_terrain.height_at(global_position.x, global_position.z), 0.0)
		var ground_ahead := maxf(_terrain.height_at(ahead.x, ahead.z), 0.0)
		if global_position.y - ground_here < 350.0 or ahead.y - ground_ahead < 250.0:
			return (flat_forward + Vector3.UP * 1.3).normalized()
	var horizontal := Vector2(global_position.x, global_position.z)
	if horizontal.length() > map_radius:
		var home := Vector3(-global_position.x, 0.0, -global_position.z).normalized()
		return (home + Vector3.UP * 0.1).normalized()
	return direction


func _attack(delta: float) -> void:
	_missile_timer -= delta
	_gun_cooldown -= delta
	var distance := global_position.distance_to(target.global_position)
	var angle := angle_to_point(target.global_position)

	if _missile_timer <= 0.0 and distance > 400.0 and distance < 2800.0 and angle < deg_to_rad(25.0):
		_missile_timer = randf_range(missile_cooldown_min, missile_cooldown_max)
		var missile: Missile = MISSILE_SCENE.instantiate()
		missile.setup(self, target, Vector3(3.4 if randf() < 0.5 else -3.4, -0.6, 2.8))
		missile.damage = missile_damage
		missile.turn_rate = lerpf(1.4, 2.1, skill)
		missile.max_speed = 600.0
		get_tree().current_scene.add_child(missile)

	if distance < 900.0 and angle < deg_to_rad(5.0) and _gun_cooldown <= 0.0:
		_gun_cooldown = 1.0 / 12.0
		var spread := deg_to_rad(lerpf(2.0, 0.6, skill))
		var direction := (forward() + global_basis.x * randf_range(-spread, spread)
			+ global_basis.y * randf_range(-spread, spread)).normalized()
		_bullets.fire(self, global_position + forward() * 9.0, direction * 1000.0 + velocity, gun_damage, 1.2)
		Game.play_sound_at(CANNON_SOUND, global_position, -6.0, 0.1, 1200.0)


func _pop_flares() -> void:
	_flares_left -= 1
	var flares: Array[Flare] = []
	for i in 4:
		var side := 1.0 if i % 2 == 0 else -1.0
		var launch := velocity * 0.6 + global_basis.x * side * 20.0 - global_basis.y * 15.0
		flares.append(Flare.spawn(get_tree().current_scene, global_position, launch))
	for node in get_tree().get_nodes_in_group("missiles"):
		var missile := node as Missile
		if missile.is_tracking(self) and randf() < 0.6:
			missile.target = flares.pick_random()


func _pick_patrol_point() -> void:
	var angle := randf() * TAU
	_patrol_point = _patrol_center + Vector3(cos(angle), 0.0, sin(angle)) * patrol_radius
	_patrol_point.y = maxf(_patrol_center.y, 900.0)
