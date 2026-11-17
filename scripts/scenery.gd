extends Node2D
## 地圖場景：烘焙好的底圖 + 森林景物（大樹、池塘）+ 隨機裝飾（花草、石頭、蘑菇……）+ 環境動畫
## （樹冠與草叢隨風擺動、雲影、陽光光束、水面波光、花粉光點、傳送門漩渦、城堡窗光）。
## 景物佔用的格子由 MapDef.FEATURES 定義，main.gd 會禁止在上面蓋塔。

const MapDef := preload("res://scripts/map_def.gd")
const STATIC_DECOR: Array[String] = ["deco_flower_a", "deco_flower_b", "deco_flower_c", "deco_rock", "deco_pebbles",
	"deco_mush", "deco_bush", "deco_stump"]

var path_cells := {}
var decor: Array = []  # [tex_name, pos, size, flip]
var tufts: Array = []  # [pos, size, phase]
var trees: Array = []  # [根部位置, 寬度, 變體, 相位]
var lilies: Array = []  # [pos, 旋轉, 大小]
var reeds: Array = []  # [pos, 大小, 相位]
var pond_c := Vector2.ZERO
var pond_r := Vector2.ZERO
var blocked := {}
var t := 0.0
var portal_pos := Vector2.ZERO
var goal_pos := Vector2.ZERO
var dyn: Node2D  # 每幀重畫：草叢、雲影
var glow: Node2D  # 加色發光：傳送門、窗光


func setup(cells: Dictionary) -> void:
	path_cells = cells
	portal_pos = MapDef.cell_center(Vector2i(0, MapDef.WAYPOINTS[0].y))
	goal_pos = MapDef.cell_center(MapDef.WAYPOINTS[MapDef.WAYPOINTS.size() - 1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	blocked = MapDef.blocked_cells()
	_setup_features(rng)
	for y in MapDef.ROWS:
		for x in MapDef.COLS:
			var c := Vector2i(x, y)
			if path_cells.has(c) or blocked.has(c):
				continue
			var center := MapDef.cell_center(c)
			if center.distance_to(portal_pos) < 70.0 or center.distance_to(goal_pos) < 75.0:
				continue
			var near_road := false
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if path_cells.has(c + d):
					near_road = true
			# 路邊多長草叢
			var tuft_n := rng.randi_range(1, 2) if near_road else (1 if rng.randf() < 0.35 else 0)
			for i in tuft_n:
				var off := Vector2(rng.randf_range(-16, 16), rng.randf_range(-14, 16))
				if near_road:
					# 草叢貼著路緣長
					for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
						if path_cells.has(c + d) and rng.randf() < 0.7:
							off = Vector2(d) * 15.0 + Vector2(d).orthogonal() * rng.randf_range(-14, 14)
							break
				tufts.append([center + off, rng.randf_range(20.0, 28.0), rng.randf() * TAU])
			if rng.randf() < 0.2:
				var name: String = STATIC_DECOR[rng.randi() % STATIC_DECOR.size()]
				var size := rng.randf_range(26.0, 32.0)
				if name in ["deco_bush", "deco_stump", "deco_rock"]:
					size += 6.0
				var pos := center + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
				decor.append([name, pos, size, rng.randf() < 0.5])
	# 由上往下畫，下方的物件蓋住上方
	decor.sort_custom(func(a, b): return a[1].y < b[1].y)
	tufts.sort_custom(func(a, b): return a[0].y < b[0].y)

	dyn = Node2D.new()
	dyn.draw.connect(_draw_dynamic)
	add_child(dyn)
	glow = Node2D.new()
	glow.material = Data.add_mat
	glow.draw.connect(_draw_glow)
	add_child(glow)
	_add_ambient_particles()


func _setup_features(rng: RandomNumberGenerator) -> void:
	for f in MapDef.FEATURES:
		if f["type"] == "pond":
			var r: Rect2i = f["rect"]
			pond_c = Vector2(r.get_center()) * MapDef.CELL
			pond_r = Vector2(r.size) * MapDef.CELL * 0.5
			for i in 5:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.35, 0.75)
				lilies.append([pond_c + Vector2(cos(a) * pond_r.x, sin(a) * pond_r.y) * d, rng.randf() * TAU, rng.randf_range(14.0, 20.0)])
			for a in [2.4, 2.9, 0.4, 5.6, 3.6]:
				var pos := pond_c + Vector2(cos(a) * pond_r.x, sin(a) * pond_r.y) * 1.02
				reeds.append([pos, rng.randf_range(24.0, 32.0), rng.randf() * TAU])
		else:
			var size := float(f["size"]) * MapDef.CELL
			var base := Vector2(f["cell"]) * MapDef.CELL + Vector2(size * 0.5, size * 0.92)
			trees.append([base, size * 1.45 + 12.0, int(f["variant"]), rng.randf() * TAU])
	trees.sort_custom(func(a, b): return a[0].y < b[0].y)


func _add_ambient_particles() -> void:
	# 飄浮的花粉 / 螢光
	var ps := CPUParticles2D.new()
	ps.texture = Data.tex("fx_glow")
	ps.material = Data.add_mat
	ps.amount = 28
	ps.lifetime = 7.0
	ps.preprocess = 7.0
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.emission_rect_extents = Vector2(500, 360)
	ps.position = Vector2(500, 360)
	ps.direction = Vector2(1, -0.4)
	ps.spread = 50.0
	ps.gravity = Vector2.ZERO
	ps.initial_velocity_min = 6.0
	ps.initial_velocity_max = 16.0
	ps.scale_amount_min = 0.03
	ps.scale_amount_max = 0.07
	ps.color = Color(1.0, 0.95, 0.6, 0.55)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 1))
	ramp.add_point(0.75, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	ps.color_ramp = ramp
	add_child(ps)

	# 傳送門：被吸入的紫色光點
	var pp := CPUParticles2D.new()
	pp.texture = Data.tex("fx_spark")
	pp.material = Data.add_mat
	pp.position = portal_pos
	pp.amount = 14
	pp.lifetime = 1.1
	pp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	pp.emission_ring_radius = 46.0
	pp.emission_ring_inner_radius = 38.0
	pp.gravity = Vector2.ZERO
	pp.radial_accel_min = -70.0
	pp.radial_accel_max = -50.0
	pp.tangential_accel_min = 40.0
	pp.tangential_accel_max = 60.0
	pp.scale_amount_min = 0.08
	pp.scale_amount_max = 0.16
	pp.color = Color("d08aff")
	pp.color_ramp = Data.fade_ramp
	add_child(pp)



func _process(delta: float) -> void:
	t += delta / maxf(Engine.time_scale, 0.01)  # 環境動畫不受遊戲加速影響
	dyn.queue_redraw()
	glow.queue_redraw()


func _draw() -> void:
	draw_texture_rect(Data.tex_png("map_bg"), Rect2(0, 0, MapDef.COLS * MapDef.CELL, MapDef.ROWS * MapDef.CELL), false)
	for d in decor:
		var s: float = d[2]
		var p: Vector2 = d[1]
		var rect := Rect2(p.x - s / 2.0, p.y - s * 0.8, s, s)
		if d[3]:
			rect = Rect2(p.x + s / 2.0, p.y - s * 0.8, -s, s)
		draw_texture_rect(Data.tex(d[0]), rect, false)


func _draw_dynamic() -> void:
	# 草叢隨風擺動（以底部為支點）
	var tuft := Data.tex("deco_tuft")
	for tf in tufts:
		var p: Vector2 = tf[0]
		var s: float = tf[1]
		var sway := sin(t * 1.6 + p.x * 0.02 + tf[2] * 0.3) * 0.12 + sin(t * 3.1 + tf[2]) * 0.03
		dyn.draw_set_transform(p, sway, Vector2.ONE)
		dyn.draw_texture_rect(tuft, Rect2(-s / 2.0, -s * 0.78, s, s), false)
	dyn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 池塘：漣漪、睡蓮、蘆葦
	if pond_r != Vector2.ZERO:
		for i in 3:
			var k := fposmod(t * 0.35 + i / 3.0, 1.0)
			var rp := pond_c + Vector2(sin(i * 2.1) * pond_r.x * 0.35, cos(i * 1.7) * pond_r.y * 0.3)
			dyn.draw_set_transform(rp, 0.0, Vector2(1.0, 0.6))
			dyn.draw_arc(Vector2.ZERO, 4.0 + 22.0 * k, 0.0, TAU, 24, Color(1, 1, 1, 0.35 * (1.0 - k)), 1.5)
		dyn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for l in lilies:
			var bob := sin(t * 1.2 + l[1]) * 1.2
			var ls: float = l[2]
			dyn.draw_set_transform(l[0] + Vector2(0, bob), l[1] + sin(t * 0.5 + l[1]) * 0.08, Vector2.ONE)
			dyn.draw_texture_rect(Data.tex("deco_lily"), Rect2(-ls / 2.0, -ls / 2.0, ls, ls), false)
		for rd in reeds:
			var rs: float = rd[1]
			dyn.draw_set_transform(rd[0], sin(t * 1.4 + rd[2]) * 0.08, Vector2.ONE)
			dyn.draw_texture_rect(Data.tex("deco_reeds"), Rect2(-rs / 2.0, -rs * 0.95, rs, rs), false)
		dyn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 大樹：樹冠以根部為支點輕輕搖擺
	for tr in trees:
		var w: float = tr[1]
		var sway := sin(t * 0.9 + tr[3]) * 0.025 + sin(t * 2.3 + tr[3] * 2.0) * 0.008
		dyn.draw_set_transform(tr[0], sway, Vector2(1.0 + sin(t * 1.1 + tr[3]) * 0.01, 1.0))
		dyn.draw_texture_rect(Data.tex("tree_%d" % tr[2]), Rect2(-w / 2.0, -w * 0.97, w, w), false)
	dyn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 傳送門與城堡
	var pulse := 1.0 + 0.04 * sin(t * 3.0)
	dyn.draw_set_transform(portal_pos, 0.0, Vector2(pulse, pulse))
	dyn.draw_texture_rect(Data.tex("portal"), Rect2(-30, -32, 60, 64), false)
	dyn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	dyn.draw_texture_rect(Data.tex("castle"), Rect2(goal_pos.x - 44, goal_pos.y - 54, 88, 88), false)

	# 緩慢飄過的雲影
	var cloud := Data.tex("zone_cloud")
	for i in 3:
		var speed := 9.0 + i * 3.0
		var span := 1000.0 + 700.0
		var x := fposmod(t * speed + i * 600.0, span) - 350.0
		if x - 190.0 > 1000.0:
			continue
		var y := 120.0 + i * 230.0 + sin(t * 0.1 + i) * 30.0
		var w := 380.0 + i * 60.0
		dyn.draw_texture_rect(cloud, Rect2(x - w / 2.0, y - w * 0.35, w, w * 0.7), false, Color(0, 0.02, 0.05, 0.1))


func _draw_glow() -> void:
	# 斜射穿過樹林的陽光光束
	var beam := Data.tex("fx_column")
	for i in 4:
		var bx := 120.0 + i * 260.0 + sin(t * 0.07 + i) * 30.0
		var a := 0.035 + 0.025 * sin(t * 0.4 + i * 1.7)
		glow.draw_set_transform(Vector2(bx, -40), -0.55, Vector2.ONE)
		glow.draw_texture_rect(beam, Rect2(-40 - i * 8, 0, 80 + i * 16, 900), false, Color(1.0, 0.95, 0.7, a))
	glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 池塘的波光
	if pond_r != Vector2.ZERO:
		for i in 6:
			var ph := fposmod(t * 0.6 + i * 0.37, 1.0)
			var sp := pond_c + Vector2(sin(i * 2.7 + floorf(t * 0.6 + i * 0.37)) * pond_r.x * 0.6,
				cos(i * 1.9 + floorf(t * 0.6 + i * 0.37) * 1.3) * pond_r.y * 0.5)
			var sz := 7.0 * sin(ph * PI)
			glow.draw_texture_rect(Data.tex("fx_spark"), Rect2(sp.x - sz, sp.y - sz, sz * 2.0, sz * 2.0), false, Color(1, 1, 1, 0.7 * sin(ph * PI)))
	# 傳送門的旋轉光暈
	var g := 44.0 + 4.0 * sin(t * 2.3)
	glow.draw_texture_rect(Data.tex("fx_glow"), Rect2(portal_pos.x - g, portal_pos.y - g, g * 2.0, g * 2.0), false, Color(0.7, 0.3, 1.0, 0.45))
	glow.draw_set_transform(portal_pos, -t * 1.5, Vector2(0.82, 1.0))
	glow.draw_texture_rect(Data.tex("zone_vortex"), Rect2(-30, -30, 60, 60), false, Color(0.85, 0.5, 1.0, 0.55))
	glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 城堡窗戶的燭光閃爍
	for wpos in [Vector2(-11, -4), Vector2(12, -4)]:
		var f := 0.6 + 0.25 * sin(t * 7.0 + wpos.x) + 0.15 * sin(t * 13.0 + wpos.x * 2.0)
		var r := 12.0
		var c: Vector2 = goal_pos + wpos
		glow.draw_texture_rect(Data.tex("fx_glow"), Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, Color(1.0, 0.75, 0.3, 0.5 * f))
