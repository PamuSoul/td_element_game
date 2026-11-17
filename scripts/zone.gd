extends Node2D
## 地形 / 物件生成 (Spawn Entity)：水窪、樹牢、熔岩、圖騰、隕石預警……
## 全部由資料 z 描述：tick = 週期觸發的效果，end = 消失時觸發的效果，art = 貼圖。

## 白色貼圖，需依地形顏色染色
const TINTED: Array[String] = ["cloud", "vortex", "warn"]

var game
var z: Dictionary = {}
var power := 1.0
var radius := 60.0
var life := 0.0
var dur := 1.0
var tick_t := 0.0
var interval := 0.25
var color := Color.WHITE
var art := ""
var spin := 0.0
var tick_flash := 0.0  # 圖騰放電時發亮
var arcs: Array = []  # 電窪表面的電弧
var arc_t := 0.0
var seed_i := 0


func setup(g, zdef: Dictionary, p: float) -> void:
	game = g
	z = zdef
	power = p
	radius = z["r"]
	dur = z["dur"]
	# 預警型（隕石 / 噴泉）不延長時間，強化等級只影響威力
	if not z.get("warn", false):
		dur *= p
	interval = z.get("interval", 0.25)
	color = z["color"]
	art = z.get("art", "")
	spin = randf() * TAU
	seed_i = randi() % 1000
	if not z.get("warn", false):
		_add_particles()


## 範圍內緩緩上升的光點
func _add_particles() -> void:
	var ps := CPUParticles2D.new()
	ps.texture = Data.tex("fx_spark" if art in ["puddle", "vortex", "totem"] else "fx_glow")
	ps.amount = 10
	ps.lifetime = 1.1
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = radius * 0.8
	ps.direction = Vector2.UP
	ps.spread = 25.0
	ps.gravity = Vector2.ZERO
	ps.initial_velocity_min = 12.0
	ps.initial_velocity_max = 36.0
	ps.scale_amount_min = 0.08
	ps.scale_amount_max = 0.2
	ps.color = color.lightened(0.2)
	ps.color_ramp = Data.fade_ramp
	ps.material = Data.add_mat
	add_child(ps)


func _process(delta: float) -> void:
	life += delta
	spin += delta
	tick_flash = maxf(tick_flash - delta, 0.0)
	if art == "puddle":
		arc_t -= delta
		if arc_t <= 0.0:
			arc_t = 0.09
			_make_arcs()
	if z.has("tick"):
		tick_t -= delta
		if tick_t <= 0.0:
			tick_t = interval
			var targets: Array = game.enemies_in(position, radius)
			if not targets.is_empty():
				tick_flash = 0.25
				game.run_effects(z["tick"], targets, targets[randi() % targets.size()], position, power)
	if life >= dur:
		if z.has("end"):
			var targets: Array = game.enemies_in(position, radius)
			var primary = targets[0] if not targets.is_empty() else null
			game.run_effects(z["end"], targets, primary, position, power)
		queue_free()
		return
	queue_redraw()


func _disc(tex_name: String, r: float, col: Color, rot: float = 0.0) -> void:
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_texture_rect(Data.tex(tex_name), Rect2(-r, -r, r * 2.0, r * 2.0), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var t := clampf(life / dur, 0.0, 1.0)
	if z.get("warn", false):
		# 預警準星：越接近發動越亮、越快閃
		var blink := 0.55 + 0.45 * sin(life * (10.0 + 30.0 * t))
		_disc("zone_warn", radius, Color(color.r, color.g, color.b, 0.35 + 0.5 * t * blink), spin * 0.6)
		_disc("fx_ring", radius * (1.0 - t) + 6.0, color.lightened(0.4))
		if not z.get("meteor", false):
			# 噴泉蓄壓：地面冒出的水花越來越激烈
			for i in 6:
				var ph := fposmod(life * (2.0 + 4.0 * t) + i / 6.0, 1.0)
				var a := TAU * i / 6.0 + float(seed_i)
				var base := Vector2(cos(a), sin(a) * 0.7) * radius * 0.35
				var hop := sin(ph * PI) * (8.0 + 22.0 * t)
				draw_texture_rect(Data.tex("fx_drop"), Rect2(base.x - 4, base.y - hop - 5, 8, 10), false, Color(0.75, 0.95, 1.0, 0.9))
		if z.get("meteor", false):
			# 隕石由右上墜落
			var fall := (1.0 - t) * (1.0 - t)
			var off := Vector2(340, -420) * fall
			var s := 46.0 + 30.0 * t
			draw_texture_rect(Data.tex("meteor"), Rect2(off.x - s * 0.3, off.y - s * 1.7, s * 2.0, s * 2.0), false)
		return

	# 淡入、淡出，並帶一點呼吸感；登場時彈出
	var fade := minf(minf(1.0, life / 0.25), (dur - life) / 0.4)
	fade = clampf(fade, 0.0, 1.0)
	var breathe := 1.0 + 0.03 * sin(spin * 3.0)
	var grow := _ease_out_back(life / 0.35)
	var r := radius * breathe * grow
	match art:
		"totem":
			_disc("fx_ring", radius, Color(color.r, color.g, color.b, 0.35 * fade))
			draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.05 * fade))
			# 從地底升起
			var rise := _ease_out_back(life / 0.5)
			var hgt := 72.0 * clampf(rise, 0.0, 1.2)
			var lit := tick_flash / 0.25
			draw_texture_rect(Data.tex("fx_glow"), Rect2(-34, -70, 68, 68), false, Color(1.0, 0.95, 0.4, 0.5 * lit * fade))
			draw_texture_rect(Data.tex("totem"), Rect2(-24, 14 - hgt, 48, hgt), false, Color(1, 1, 1, fade).lerp(Color(1.6, 1.6, 1.2, fade), lit))
		"vortex":
			var spd := 3.0 + 9.0 * maxf(0.0, 1.0 - life / 0.6)  # 開場高速旋轉後穩定
			_disc("zone_vortex", r, Color(color.r, color.g, color.b, 0.75 * fade), -spin * spd)
			_disc("zone_vortex", r * 0.6, Color(1, 1, 1, 0.5 * fade), -spin * (spd + 2.0))
		"cloud":
			_disc("zone_cloud", r * 1.1, Color(color.r, color.g, color.b, 0.6 * fade), spin * 0.25)
			_disc("zone_cloud", r * 0.85, Color(color.r, color.g, color.b, 0.45 * fade), -spin * 0.4)
			if color.g > color.b + 0.1:
				_draw_rain(fade)
		"vines":
			# 藤蔓扭轉著長出來
			var twist := (1.0 - clampf(grow, 0.0, 1.0)) * 1.2 + sin(spin * 2.0) * 0.03
			_disc("zone_vines", r * 1.08, Color(1, 1, 1, 0.92 * fade), twist)
		"":
			draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, 0.22 * fade))
		_:
			var col := Color(color.r, color.g, color.b, fade) if art in TINTED else Color(1, 1, 1, 0.92 * fade)
			_disc("zone_" + art, r * 1.08, col)
			match art:
				"lava":
					_disc("fx_glow", r * 1.3, Color(1.0, 0.5, 0.15, 0.25 * fade * (0.7 + 0.3 * sin(spin * 5.0))))
					_draw_bubbles(6, 1.4, Color(1.0, 0.85, 0.4), fade)
				"mud":
					_draw_bubbles(4, 0.7, Color(0.55, 0.45, 0.3), fade)
				"puddle":
					_draw_ripples(fade)
					for pts in arcs:
						draw_polyline(pts, Color(0.75, 0.95, 1.0, 0.5 * fade), 4.0)
						draw_polyline(pts, Color(1, 1, 1, 0.95 * fade), 1.5)
				"thorns":
					# 荊棘偶爾抽動
					var jolt := 1.0 + 0.04 * maxf(0.0, sin(spin * 6.0 + seed_i))
					_disc("zone_thorns", r * 1.08 * jolt, Color(1, 1, 1, 0.35 * fade), 0.1)
	# 剩餘時間
	draw_arc(Vector2.ZERO, radius, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - t), 48, Color(color.r, color.g, color.b, 0.55 * fade), 2.0)


static func _ease_out_back(x: float) -> float:
	var c := 1.7
	x = clampf(x, 0.0, 1.0)
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


## 以固定亂數決定位置的氣泡：膨脹後破掉，再從別處冒出
func _draw_bubbles(n: int, rate: float, col: Color, fade: float) -> void:
	for i in n:
		var ph := spin * rate + i * 0.37
		var cycle := floori(ph)
		var k := ph - cycle
		var h := hash(Vector3i(seed_i, i, cycle))
		var a := float(h % 628) / 100.0
		var d := radius * 0.65 * sqrt(float((h >> 10) % 100) / 100.0)
		var p := Vector2(cos(a) * d, sin(a) * d * 0.8)
		if k < 0.8:
			var br := 2.0 + 6.0 * (k / 0.8)
			draw_circle(p, br, Color(col, 0.55 * fade))
			draw_arc(p, br, 0.0, TAU, 12, Color(col.lightened(0.4), 0.9 * fade), 1.5)
		else:
			var pk := (k - 0.8) / 0.2
			draw_arc(p, 8.0 + 6.0 * pk, 0.0, TAU, 12, Color(col.lightened(0.4), (1.0 - pk) * fade), 1.5)


## 水面的漣漪
func _draw_ripples(fade: float) -> void:
	for i in 3:
		var ph := spin * 0.8 + i * 0.33
		var cycle := floori(ph)
		var k := ph - cycle
		var h := hash(Vector3i(seed_i, i + 10, cycle))
		var a := float(h % 628) / 100.0
		var d := radius * 0.55 * float((h >> 10) % 100) / 100.0
		var p := Vector2(cos(a) * d, sin(a) * d * 0.8)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.7))
		draw_arc(Vector2.ZERO, 4.0 + 20.0 * k, 0.0, TAU, 20, Color(1, 1, 1, 0.55 * (1.0 - k) * fade), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 瘴氣雨林：細雨
func _draw_rain(fade: float) -> void:
	for i in 14:
		var h := hash(Vector2i(seed_i, i))
		var x := (float(h % 200) / 100.0 - 1.0) * radius * 0.85
		var ph := fposmod(spin * 1.6 + float((h >> 8) % 100) / 100.0, 1.0)
		var y := -radius * 0.7 + ph * radius * 1.3
		draw_line(Vector2(x, y), Vector2(x - 2.0, y + 9.0), Color(0.8, 1.0, 0.75, 0.6 * fade * (1.0 - ph)), 1.5)


func _make_arcs() -> void:
	arcs.clear()
	if randf() < 0.35:
		return
	for i in randi_range(1, 2):
		var a := randf() * TAU
		var p := Vector2(cos(a), sin(a) * 0.8) * radius * randf_range(0.0, 0.6)
		var ang := randf() * TAU
		var pts := PackedVector2Array([p])
		for k in 4:
			p += Vector2(cos(ang), sin(ang)) * randf_range(8.0, 15.0)
			ang += randf_range(-0.9, 0.9)
			pts.append(p)
		arcs.append(pts)
