extends SceneTree
## 烘焙地圖背景 assets/art/map_bg.png ── 奇幻森林風格
## 手繪感草地（色階 + 筆觸 + 野花）、石板古道（沿圓滑彎道）、池塘、大樹陰影、傳送門焦土、城堡廣場。
## 執行：godot --headless --path . --script tools/gen_bg.gd   （make art 會一併執行）

const MapDef := preload("res://scripts/map_def.gd")
const SCALE := 2  # 以 2 倍解析度烘焙，放大顯示時依然清晰
const W := 1000
const H := 720
const ROAD_HALF := 19.0

# 草地色階（由暗到亮）
const GRASS_RAMP: Array[Color] = [Color("1b3d2b"), Color("2b5a32"), Color("467c3a"), Color("6c9e48"), Color("a2c262")]
const MEADOW := Color("b5c860")
const FLOWERS: Array[Color] = [Color("fff6dc"), Color("ffd94a"), Color("f7a6c8"), Color("a9b8ff"), Color("ffffff")]
const STONES: Array[Color] = [Color("9c8f76"), Color("8a8270"), Color("ae9f80"), Color("7f786a"), Color("958f7e")]
const MORTAR := Color("5e4a32")
const MOSS := Color("5d8a3a")
const DIRT := Color("8a6c48")
const BLIGHT := Color("2a1a35")
const WATER_DEEP := Color("1d4e6e")
const WATER_SHALLOW := Color("4fa6b0")
const SHORE := Color("b4a274")

var prims: Array = []
var n_big := FastNoiseLite.new()
var n_warm := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_fine := FastNoiseLite.new()
var n_brush := FastNoiseLite.new()
var n_edge := FastNoiseLite.new()
var n_flower := FastNoiseLite.new()
var n_flower_v := FastNoiseLite.new()
var n_stone := FastNoiseLite.new()
var n_stone_v := FastNoiseLite.new()
var n_clump := FastNoiseLite.new()
var n_clump_v := FastNoiseLite.new()
var tree_shadows: Array = []  # [中心, 半徑]
var pond_c := Vector2.ZERO
var pond_r := Vector2.ZERO


func _init() -> void:
	prims = MapDef.path_prims()
	_noise(n_big, 11, 0.004, 4)
	_noise(n_warm, 12, 0.007, 3)
	_noise(n_mid, 13, 0.03, 3)
	_noise(n_fine, 14, 0.45, 1)
	_noise(n_brush, 15, 0.09, 2)
	_noise(n_edge, 16, 0.08, 2)
	_cell(n_flower, 17, 0.06, FastNoiseLite.RETURN_DISTANCE)
	_cell(n_flower_v, 17, 0.06, FastNoiseLite.RETURN_CELL_VALUE)
	_cell(n_stone, 18, 0.058, FastNoiseLite.RETURN_DISTANCE2_SUB)
	_cell(n_stone_v, 18, 0.058, FastNoiseLite.RETURN_CELL_VALUE)
	_cell(n_clump, 19, 0.11, FastNoiseLite.RETURN_DISTANCE)
	_cell(n_clump_v, 19, 0.11, FastNoiseLite.RETURN_CELL_VALUE)
	n_clump.cellular_jitter = 0.9
	for f in MapDef.FEATURES:
		if f["type"] == "pond":
			var r: Rect2i = f["rect"]
			pond_c = Vector2(r.get_center()) * MapDef.CELL
			pond_r = Vector2(r.size) * MapDef.CELL * 0.5 + Vector2(4, 0)
		else:
			var s := float(f["size"]) * MapDef.CELL
			var c := Vector2(f["cell"]) * MapDef.CELL + Vector2(s, s) * 0.5
			tree_shadows.append([c + Vector2(10, 12), s * 0.62])

	var t0 := Time.get_ticks_msec()
	var img := Image.create(W * SCALE, H * SCALE, false, Image.FORMAT_RGB8)
	var portal := MapDef.cell_center(Vector2i(0, MapDef.WAYPOINTS[0].y))
	var goal := MapDef.cell_center(MapDef.WAYPOINTS[MapDef.WAYPOINTS.size() - 1])
	for py in H * SCALE:
		for px in W * SCALE:
			var p := Vector2((px + 0.5) / SCALE, (py + 0.5) / SCALE)
			img.set_pixel(px, py, _shade(p, portal, goal))
	img.save_png("res://assets/art/map_bg.png")
	print("map_bg.png baked in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func _noise(n: FastNoiseLite, s: int, f: float, oct: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = f
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if oct > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = oct


func _cell(n: FastNoiseLite, s: int, f: float, ret: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = f
	n.cellular_return_type = ret


func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


func _ramp(v: float) -> Color:
	var x := clampf(v, 0.0, 0.999) * (GRASS_RAMP.size() - 1)
	var i := floori(x)
	return GRASS_RAMP[i].lerp(GRASS_RAMP[i + 1], x - i)


func _grass(p: Vector2, fine: float, mid: float) -> Color:
	# 色階 + 半色調分層，帶手繪感
	var v := 0.5 + 0.42 * n_big.get_noise_2dv(p) + 0.18 * mid
	var stepped := floorf(v * 7.0) / 7.0
	v = lerpf(v, stepped, 0.35)
	# 一叢一叢的草：細胞中心亮、下緣暗（手繪塔防常見的草叢質感）
	var cd := n_clump.get_noise_2dv(p)
	var cd_up := n_clump.get_noise_2dv(p + Vector2(0, -2.0))
	var cv := n_clump_v.get_noise_2dv(p)
	v += 0.05 * cv
	var g := _ramp(v)
	var dome := 1.0 - _ss(-1.0, -0.55, cd)
	g = g.lightened(0.1 * dome)
	if cd > -0.62 and cd_up < cd - 0.03:
		g = g.darkened(0.16)  # 草叢下緣的陰影
	g = g * (1.0 + 0.03 * fine)
	# 暖色向陽草地
	var warm := _ss(0.25, 0.7, n_warm.get_noise_2dv(p))
	g = g.lerp(MEADOW, warm * 0.28)
	# 野花：細胞雜訊的點，只長在向陽處
	var fd := n_flower.get_noise_2dv(p)
	var fv := n_flower_v.get_noise_2dv(p)
	if warm > 0.05 and fd < -0.75 and fv > -0.1:
		var fc: Color = FLOWERS[int((fv * 0.5 + 0.5) * 4.99)]
		if fd < -0.78:
			g = Color("ffcf3a") if fd < -0.86 else fc
		else:
			g = g.darkened(0.3)  # 花朵外緣
	return g


func _road(p: Vector2, d: float, fine: float, mid: float) -> Color:
	# 石板：細胞雜訊，邊緣是長苔的泥縫
	var sd := n_stone.get_noise_2dv(p)
	var sv := n_stone_v.get_noise_2dv(p)
	var mortar := MORTAR.lerp(MOSS, _ss(-0.2, 0.5, mid) * 0.7) * (1.0 + 0.1 * fine)
	if sv > 0.72:
		return DIRT.lerp(mortar, 0.3) * (1.0 + 0.08 * fine)  # 缺了一塊石板
	var stone: Color = STONES[int((sv * 0.5 + 0.5) * 4.99)]
	stone = stone * (1.0 + 0.04 * fine + 0.05 * n_mid.get_noise_2dv(p * 3.0))
	# 中央被踩得較亮
	stone = stone.lightened(0.12 * (1.0 - _ss(0.0, ROAD_HALF, d)))
	# 上緣亮、下緣暗的倒角
	var up := n_stone.get_noise_2dv(p - Vector2(1.1, 1.1))
	var dn := n_stone.get_noise_2dv(p + Vector2(1.1, 1.1))
	if up < -0.86:
		stone = stone.lightened(0.2)
	elif dn < -0.86:
		stone = stone.darkened(0.28)
	return stone.lerp(mortar.darkened(0.25), _ss(-0.86, -0.93, sd))


func _shade(p: Vector2, portal: Vector2, goal: Vector2) -> Color:
	var fine := n_fine.get_noise_2dv(p)
	var mid := n_mid.get_noise_2dv(p)
	var d := MapDef.path_dist(p, prims)
	var e := d - ROAD_HALF + n_edge.get_noise_2dv(p) * 2.2
	# 草葉伸進路面
	var blades := n_fine.get_noise_2d(p.x * 0.6, p.y * 0.6)
	e += maxf(blades, 0.0) * 3.0

	var col: Color
	if e > 3.0:
		col = _grass(p, fine, mid)
	else:
		var g := _grass(p, fine, mid)
		var r := _road(p, d, fine, mid)
		# 路緣：一圈深色的土
		r = r.lerp(MORTAR.darkened(0.2), _ss(-5.0, 0.0, e) * 0.85)
		col = r.lerp(g, _ss(-0.6, 0.6, e))
	# 路邊草地的陰影
	if e > 0.0 and e < 14.0:
		var k := 1.0 - e / 14.0
		col = col.darkened(0.3 * k * k)

	# ── 池塘 ──
	if pond_r != Vector2.ZERO:
		var q := (p - pond_c) / pond_r
		var pr := q.length() + n_warm.get_noise_2dv(p * 3.0) * 0.14
		if pr < 1.18:
			var depth := 1.0 - _ss(0.15, 1.0, pr)
			var water := WATER_SHALLOW.lerp(WATER_DEEP, depth) * (1.0 + 0.05 * n_mid.get_noise_2dv(p * 2.0))
			# 水面倒映的天光
			water = water.lightened(0.18 * _ss(0.25, 0.0, absf(q.y + 0.35 - q.x * 0.3)) * (1.0 - _ss(0.6, 0.9, pr)))
			if pr < 0.94:
				col = water
			elif pr < 1.02:
				col = water.lerp(SHORE.darkened(0.35), _ss(0.94, 1.02, pr))
			else:
				col = SHORE.lerp(col, _ss(1.02, 1.18, pr)) * (1.0 + 0.08 * fine)

	# ── 大樹陰影 ──
	for ts in tree_shadows:
		var dt: float = p.distance_to(ts[0]) / float(ts[1])
		if dt < 1.0:
			col = col.darkened(0.42 * (1.0 - _ss(0.35, 1.0, dt)))

	# ── 傳送門焦土 ──
	var dp := p.distance_to(portal) + n_edge.get_noise_2dv(p * 1.7) * 14.0
	if dp < 78.0:
		var k2 := 1.0 - _ss(25.0, 78.0, dp)
		col = col.lerp(BLIGHT, k2 * 0.75)
		col = col.lerp(Color("6a2a9a"), k2 * 0.2 * (0.5 + 0.5 * mid))

	# ── 城堡石板廣場 ──
	var dg := p.distance_to(goal) + n_edge.get_noise_2dv(p * 1.3) * 6.0
	if dg < 64.0:
		var plaza := _road(p, 0.0, fine, mid).lightened(0.05)
		col = col.lerp(plaza, 1.0 - _ss(55.0, 64.0, dg))
		if dg > 54.0 and dg < 66.0:
			col = col.darkened(0.3 * (1.0 - absf(dg - 60.0) / 6.0))

	# ── 光線：左上的暖色陽光、四周暗角 ──
	var sun := 1.0 - _ss(0.0, 1.0, (p.x * 0.8 + p.y) / (W * 0.8 + H) * 1.4)
	col = col.lerp(Color(1.0, 0.95, 0.75), 0.07 * sun)
	var v := Vector2((p.x / W - 0.5) * 1.6, (p.y / H - 0.5) * 1.6).length()
	col = col.darkened(0.3 * _ss(0.65, 1.25, v))
	col.a = 1.0
	return col
