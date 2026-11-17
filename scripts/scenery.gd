extends Node2D
## 地圖場景：烘焙好的底圖 + 隨機裝飾（花草、石頭、蘑菇……）+ 環境動畫
## （草叢隨風擺動、雲影飄過、花粉光點、傳送門漩渦、城堡窗光）。純視覺，不影響遊戲邏輯。

const MapDef := preload("res://scripts/map_def.gd")
const STATIC_DECOR: Array[String] = ["deco_flower_a", "deco_flower_b", "deco_flower_c", "deco_rock", "deco_pebbles",
	"deco_mush", "deco_bush", "deco_stump"]

var path_cells := {}
var decor: Array = []  # [tex_name, pos, size, flip]
var tufts: Array = []  # [pos, size, phase]
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
	for y in MapDef.ROWS:
		for x in MapDef.COLS:
			var c := Vector2i(x, y)
			if path_cells.has(c):
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
		dyn.draw_texture_rect(cloud, Rect2(x - w / 2.0, y - w * 0.35, w, w * 0.7), false, Color(0, 0.02, 0.05, 0.13))


func _draw_glow() -> void:
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
