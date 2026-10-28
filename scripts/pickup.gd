class_name Pickup
extends Area3D
## Health or ammo pickup. Spins and bobs; collected when the player touches
## it, unless they're already full.

enum Kind { HEALTH, AMMO }

const PICKUP_SOUND := preload("res://assets/sounds/pickup.wav")

@export var kind := Kind.HEALTH
## Health restored, or (for ammo) magazines given to every weapon.
@export var amount := 30

@onready var visual: Node3D = $Visual

var _time := randf() * TAU


func _process(delta: float) -> void:
	_time += delta
	visual.rotation.y += delta * 1.5
	visual.position.y = 0.5 + sin(_time * 2.0) * 0.08


func _physics_process(_delta: float) -> void:
	# Polling (rather than body_entered) means a player standing on the pickup
	# at full health still gets it once they take damage.
	for body in get_overlapping_bodies():
		var player := body as Player
		if player and _give_to(player):
			queue_free()
			return


func _give_to(player: Player) -> bool:
	match kind:
		Kind.HEALTH:
			if player.heal(amount):
				Game.post_message("+%d health" % amount)
				Game.play_sound(PICKUP_SOUND, -4.0)
				return true
		Kind.AMMO:
			if player.weapons.add_ammo_magazines(amount):
				Game.post_message("+ammo")
				Game.play_sound(PICKUP_SOUND, -4.0)
				return true
	return false
