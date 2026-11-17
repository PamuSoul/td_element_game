extends Node2D
## 塔 = 觸發載體 (Trigger)。箭塔 / 大砲 / 光環塔決定「怎麼命中」，
## 3 個元素槽位決定命中後觸發哪個融合能力（見 data.gd 的 FUSIONS）。

const ProjectileScript := preload("res://scripts/projectile.gd")

var game
var kind := "arrow"
var def: Dictionary = {}
var cell := Vector2i.ZERO
var elems: Array = []
var fusion: Dictionary = {}
var power := 1.0
var color := Color("9aa3ad")
var cd := 0.0
var special_cd := 0.0
var domain_t := 0.0
var flash := 0.0
var aim := 0.0
var aim_to := 0.0
var anim := 0.0
var cast_t := 0.0  # 施法動畫剩餘時間（main.fx_cast 設定）
var storm_flash := 0.0  # 雷雲閃光
var domain_art := ""
var domain_fx: CPUParticles2D  # 領域塔的持續粒子（雨、落葉）


func setup(g, k: String, c: Vector2i) -> void:
	game = g
	kind = k
	def = Data.TOWERS[k]
	cell = c


func refresh_fusion() -> void:
	fusion = Data.get_fusion(elems)
	power = Data.rank_mult(elems) * float(def["eff"])
	color = fusion["color"] if not fusion.is_empty() else Color("9aa3ad")
	var art: String = fusion.get("domain_art", "")
	if art != domain_art:
		domain_art = art
		_setup_domain_fx()
	queue_redraw()


func _setup_domain_fx() -> void:
	if domain_fx != null:
		domain_fx.queue_free()
		domain_fx = null
	if domain_art == "":
		return
	var ps := CPUParticles2D.new()
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.color_ramp = Data.fade_ramp
	match domain_art:
		"storm":
			# 雷雲下的小雨
			ps.texture = Data.tex("fx_drop")
			ps.position = Vector2(0, -40)
			ps.emission_rect_extents = Vector2(26, 4)
			ps.amount = 16
			ps.lifetime = 0.35
			ps.direction = Vector2(0.1, 1)
			ps.spread = 4.0
			ps.gravity = Vector2(0, 500)
			ps.initial_velocity_min = 80.0
			ps.initial_velocity_max = 110.0
			ps.scale_amount_min = 0.12
			ps.scale_amount_max = 0.18
			ps.color = Color(0.7, 0.85, 1.0, 0.7)
		"tree":
			# 世界樹的落葉
			ps.texture = Data.tex("fx_leaf")
			ps.position = Vector2(0, -30)
			ps.emission_rect_extents = Vector2(34, 10)
			ps.amount = 6
			ps.lifetime = 2.2
			ps.direction = Vector2(0.3, 1)
			ps.spread = 30.0
			ps.gravity = Vector2(8, 24)
			ps.initial_velocity_min = 6.0
			ps.initial_velocity_max = 14.0
			ps.angle_min = 0.0
			ps.angle_max = 360.0
			ps.angular_velocity_min = -90.0
			ps.angular_velocity_max = 90.0
			ps.scale_amount_min = 0.25
			ps.scale_amount_max = 0.4
			ps.color = Color("8fe07a")
		"forest":
			# 樹海結界：竄動的電光
			ps.texture = Data.tex("fx_spark")
			ps.material = Data.add_mat
			ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
			ps.emission_ring_radius = 30.0
			ps.emission_ring_inner_radius = 22.0
			ps.amount = 10
			ps.lifetime = 0.5
			ps.gravity = Vector2(0, -30)
			ps.initial_velocity_min = 5.0
			ps.initial_velocity_max = 20.0
			ps.scale_amount_min = 0.1
			ps.scale_amount_max = 0.2
			ps.color = Color("8fffe0")
	domain_fx = ps
	add_child(ps)


func hit_effects() -> Array:
	return fusion.get("hit", [])


func _process(delta: float) -> void:
	cd -= delta
	special_cd -= delta
	flash = maxf(flash - delta, 0.0)
	cast_t = maxf(cast_t - delta, 0.0)
	storm_flash = maxf(storm_flash - delta, 0.0)
	anim += delta
	aim = lerp_angle(aim, aim_to, 1.0 - exp(-delta * 18.0))
	queue_redraw()
	var rng: float = def["rng"]

	# 三系「領域」型能力：塔本體每秒對射程內全體觸發
	if fusion.has("domain"):
		domain_t -= delta
		if domain_t <= 0.0:
			var in_domain: Array = game.enemies_in(position, rng)
			if not in_domain.is_empty():
				domain_t = 1.0
				game.fx_ring(position, rng, color)
				cast_t = 0.3
				match domain_art:
					"tree":
						game._fx("ripple", position, color, 0.9, {"radius": rng, "count": 2, "z": -1})
						game.emit(position + Vector2(0, -26), Color("8fe07a"), 6, {"tex": "fx_leaf", "speed": 110.0,
							"grav": Vector2(0, 60), "size": 0.4, "life": 1.0, "spin": 300.0, "damp": 60.0, "add": false})
					"forest":
						game._fx("rune", position + Vector2(0, 8), color, 0.6, {"radius": 40.0, "z": -1})
				game.run_effects(fusion["domain"], in_domain, in_domain[0], position, Data.rank_mult(elems), self)

	if cd > 0.0:
		return
	var targets: Array = game.enemies_in(position, rng)
	if targets.is_empty():
		return
	cd = def["interval"]
	flash = 0.15
	match kind:
		"arrow":
			_shoot(_front(targets), 520.0)
		"cannon":
			_shoot(_front(targets), 300.0)
		"aura":
			game.fx_ring(position, rng, color)
			game.burst(position, color.lightened(0.3), 6, 90.0, 0.4, "fx_spark", 0.3)
			var primary = targets[randi() % targets.size()]
			game.tower_hit(self, def["damage"], hit_effects(), power, targets, primary, primary.position)


func _disc(tex_name: String, r: float, col: Color, rot: float) -> void:
	draw_set_transform(Vector2.ZERO, rot, Vector2(1.0, 0.8))
	draw_texture_rect(Data.tex(tex_name), Rect2(-r, -r, r * 2.0, r * 2.0), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _front(targets: Array):
	var best = targets[0]
	for t in targets:
		if t.offset > best.offset:
			best = t
	return best


func _shoot(target, speed: float) -> void:
	aim_to = (target.position - position).angle() + PI / 2.0
	var muzzle := position + Vector2.UP.rotated(aim_to) * 20.0
	if kind == "cannon":
		game.burst(muzzle, Color("ffd9a0"), 6, 80.0, 0.3, "fx_smoke", 0.3)
		game.fx_flash(muzzle, 16.0, Color("ffb060"))
	var p = ProjectileScript.new()
	p.setup(game, self, target, speed)
	p.position = position
	game.world.add_child(p)


func _draw() -> void:
	var has_fusion := not fusion.is_empty()
	if fusion.has("domain"):
		var rng: float = def["rng"]
		draw_circle(Vector2.ZERO, rng, Color(color.r, color.g, color.b, 0.07 + 0.02 * sin(anim * 2.0)))
		# 領域邊界：緩慢旋轉的虛線
		var dashes := 24
		for i in dashes:
			var a0 := anim * 0.3 + TAU * i / dashes
			draw_arc(Vector2.ZERO, rng, a0, a0 + TAU / dashes * 0.6, 6, Color(color.r, color.g, color.b, 0.45), 2.0)
	match domain_art:
		"forest":
			_disc("zone_vines", 34.0 + 2.0 * sin(anim * 2.0), Color(1, 1, 1, 0.9), anim * 0.25)
		"tree":
			# 樹冠在塔的後方，從上面露出來
			var sw := sin(anim * 1.3) * 0.04
			draw_set_transform(Vector2(0, -16), sw, Vector2.ONE)
			draw_texture_rect(Data.tex("deco_bush"), Rect2(-34, -40, 68, 68), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 施法：塔身下的光圈
	if cast_t > 0.0:
		var k := cast_t / 0.45
		var cr := 26.0 + 14.0 * (1.0 - k)
		draw_texture_rect(Data.tex("fx_glow"), Rect2(-cr, -cr, cr * 2.0, cr * 2.0), false, Color(color.r, color.g, color.b, 0.7 * k))
	draw_texture_rect(Data.tex("tower_base"), Rect2(-22, -22, 44, 44), false)
	if has_fusion:
		var g := 30.0 + 3.0 * sin(anim * 3.0)
		draw_texture_rect(Data.tex("fx_glow"), Rect2(-g, -g, g * 2.0, g * 2.0), false, Color(color.r, color.g, color.b, 0.35))

	var kick := flash / 0.15  # 開火後座力 1 → 0
	match kind:
		"arrow":
			draw_set_transform(Vector2.DOWN.rotated(aim) * kick * 3.0, aim, Vector2.ONE)
			draw_texture_rect(Data.tex("tower_arrow"), Rect2(-19, -21, 38, 38), false)
			draw_texture_rect(Data.tex("gem"), Rect2(-5, 6, 10, 10), false, color)
		"cannon":
			draw_set_transform(Vector2.DOWN.rotated(aim) * kick * 5.0, aim, Vector2.ONE)
			draw_texture_rect(Data.tex("tower_cannon"), Rect2(-19, -24, 38, 38), false)
			draw_texture_rect(Data.tex("gem"), Rect2(-6, -3, 12, 12), false, color)
		"aura":
			var s := 1.0 + 0.06 * sin(anim * 2.5) + 0.2 * kick
			draw_set_transform(Vector2(0, -2), 0.0, Vector2(s, s))
			draw_texture_rect(Data.tex("tower_aura"), Rect2(-18, -18, 36, 36), false, color.lightened(0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 施法時寶石發亮
	if cast_t > 0.0:
		var gk := cast_t / 0.45
		var gr := 10.0 + 10.0 * gk
		draw_texture_rect(Data.tex("fx_spark"), Rect2(-gr, -gr - 2.0, gr * 2.0, gr * 2.0), false, Color(1, 1, 1, gk))
	# 雷暴風雲：塔上方的雷雲
	if domain_art == "storm":
		var bob := sin(anim * 1.7) * 2.0
		var lit := storm_flash / 0.25
		var cc := Color(0.32, 0.35, 0.48).lerp(Color(0.85, 0.9, 1.0), lit)
		draw_texture_rect(Data.tex("zone_cloud"), Rect2(-36, -66 + bob, 72, 46), false, Color(cc, 0.95))
		draw_texture_rect(Data.tex("zone_cloud"), Rect2(-26, -72 + bob, 52, 32), false, Color(cc.lightened(0.15), 0.9))

	# 元素槽位
	for i in Data.MAX_SLOTS:
		var pos := Vector2(-12.0 + i * 12.0, 17.0)
		if i < elems.size():
			draw_texture_rect(Data.tex("elem_" + elems[i]), Rect2(pos.x - 6, pos.y - 6, 12, 12), false)
		else:
			draw_circle(pos, 4.0, Color(0, 0, 0, 0.55))
			draw_arc(pos, 4.0, 0.0, TAU, 12, Color(1, 1, 1, 0.35), 1.0)
