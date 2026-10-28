extends Control
## Dynamic crosshair. The gap between the lines shows the current weapon's
## spread: where your shots can land. Fades out while aiming down sights.

@export var line_length := 9.0
@export var line_width := 2.0
@export var color := Color(1, 1, 1, 0.9)
@export var outline_color := Color(0, 0, 0, 0.6)

var player: Player
var _gap := 8.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or player.is_dead:
		return
	var holder := player.weapons
	var alpha := 1.0 - smoothstep(0.0, 0.6, holder.aim_amount)
	if alpha <= 0.01:
		return

	# Convert the spread angle into pixels at the current field of view.
	var spread := deg_to_rad(holder.current_spread_degrees())
	var half_fov := deg_to_rad(holder.camera.fov * 0.5)
	var target_gap := tan(spread) / tan(half_fov) * size.y * 0.5 + 3.0
	_gap = lerpf(_gap, target_gap, 0.35)

	var center := size * 0.5
	var c := Color(color, color.a * alpha)
	var o := Color(outline_color, outline_color.a * alpha)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var from := center + dir * _gap
		var to := from + dir * line_length
		draw_line(from - dir, to + dir, o, line_width + 2.0)
		draw_line(from, to, c, line_width)
	draw_rect(Rect2(center - Vector2(1.5, 1.5), Vector2(3, 3)), o)
	draw_rect(Rect2(center - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), c)
