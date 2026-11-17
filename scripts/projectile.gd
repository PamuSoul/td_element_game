extends Node2D
## 箭矢（追蹤單體）與砲彈（落點範圍）。發射當下就記住傷害與效果，塔被賣掉也不會出錯。

var game
var tower
var target
var kind := "arrow"
var dest := Vector2.ZERO
var speed := 400.0
var damage := 0.0
var effects: Array = []
var power := 1.0
var splash := 0.0
var color := Color.WHITE
var elems: Array = []
var trail: CPUParticles2D
var anim := 0.0

## 拖尾貼圖：依塔上第一個元素決定
const TRAIL_TEX := {"water": "fx_drop", "fire": "fx_flame", "wood": "fx_leaf", "thunder": "fx_spark", "earth": "fx_smoke"}


func setup(g, tw, tg, spd: float) -> void:
	game = g
	tower = tw
	target = tg
	kind = tw.kind
	speed = spd
	dest = tg.position
	damage = tw.def["damage"]
	effects = tw.hit_effects()
	power = tw.power
	splash = tw.def.get("splash", 0.0)
	color = tw.color
	elems = tw.elems.duplicate()
	if not effects.is_empty():
		_add_trail()


func _add_trail() -> void:
	trail = CPUParticles2D.new()
	trail.local_coords = false
	var first: String = elems[0] if not elems.is_empty() else ""
	trail.texture = Data.tex(TRAIL_TEX.get(first, "fx_glow"))
	trail.amount = 18 if kind == "cannon" else 12
	trail.lifetime = 0.35
	trail.gravity = Vector2(0, -40) if first == "fire" else Vector2.ZERO
	trail.spread = 180.0
	trail.initial_velocity_min = 4.0
	trail.initial_velocity_max = 18.0
	trail.angle_max = 360.0
	var big := 0.3 if kind == "cannon" else 0.2
	trail.scale_amount_min = big * 0.5
	trail.scale_amount_max = big
	trail.color = color.lightened(0.25)
	trail.color_ramp = Data.fade_ramp
	if first != "wood" and first != "earth":
		trail.material = Data.add_mat
	add_child(trail)


## 命中後讓拖尾留在原地自然消散
func _release_trail() -> void:
	if trail == null:
		return
	trail.emitting = false
	trail.reparent(game.world)
	var t := trail
	trail.get_tree().create_timer(trail.lifetime + 0.1, false).timeout.connect(t.queue_free)
	trail = null


func _process(delta: float) -> void:
	anim += delta
	if not effects.is_empty():
		queue_redraw()
	if kind == "arrow" and game.alive(target):
		dest = target.position
	var step := speed * delta
	if position.distance_to(dest) > 1.0:
		rotation = (dest - position).angle() + PI / 2.0
	if position.distance_to(dest) > step:
		position = position.move_toward(dest, step)
		return
	position = dest
	var tw = tower if is_instance_valid(tower) else null
	if kind == "arrow":
		if game.alive(target):
			game.tower_hit(tw, damage, effects, power, [target], target, dest)
			game.burst(dest, color.lightened(0.4), 4, 70.0, 0.25, "fx_spark", 0.22)
	else:
		var targets: Array = game.enemies_in(dest, splash)
		game.fx_boom(dest, splash, Color("ffb060").lerp(color, 0.5))
		var primary = null
		var best := INF
		for t in targets:
			var d: float = t.position.distance_to(dest)
			if d < best:
				best = d
				primary = t
		game.tower_hit(tw, damage, effects, power, targets, primary, dest)
	_release_trail()
	queue_free()


func _draw() -> void:
	if not effects.is_empty():
		var g := 13.0 + 2.5 * sin(anim * 30.0)
		draw_texture_rect(Data.tex("fx_glow"), Rect2(-g, -g, g * 2.0, g * 2.0), false, Color(color.r, color.g, color.b, 0.8))
	if kind == "arrow":
		draw_texture_rect(Data.tex("arrow"), Rect2(-8, -10, 16, 16), false)
	else:
		draw_texture_rect(Data.tex("ball"), Rect2(-7, -7, 14, 14), false)
