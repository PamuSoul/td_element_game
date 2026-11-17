extends SceneTree
## 烘焙地圖背景 assets/art/map_bg.png（草地雜訊、蜿蜒泥土路、傳送門焦土、城堡石板廣場、暗角）。
## 執行：godot --headless --path . --script tools/gen_bg.gd   （make art 會一併執行）

const MapDef := preload("res://scripts/map_def.gd")
const SCALE := 2  # 以 2 倍解析度烘焙，放大顯示時依然清晰
const W := 1000
const H := 720
const ROAD_HALF := 18.5

var segs: Array = []
var n_big := FastNoiseLite.new()
var n_big2 := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_fine := FastNoiseLite.new()
var n_blade := FastNoiseLite.new()
var n_edge := FastNoiseLite.new()
var n_cell := FastNoiseLite.new()
var n_cob := FastNoiseLite.new()
var n_cobv := FastNoiseLite.new()

const GRASS_DARK := Color("1f4a2b")
const GRASS_MID := Color("336a39")
const GRASS_LIGHT := Color("5b9446")
const GRASS_DRY := Color("8a9a4a")
const DIRT := Color("8f6f4c")
const DIRT_LIGHT := Color("b89567")
const DIRT_DARK := Color("5e452e")
const PEBBLE := Color("cdb690")
const COBBLE := Color("8d8f98")
const COBBLE_DARK := Color("4a4c55")
const BLIGHT := Color("2a1a35")


func _init() -> void:
	for i in MapDef.WAYPOINTS.size() - 1:
		segs.append([MapDef.cell_center(MapDef.WAYPOINTS[i]), MapDef.cell_center(MapDef.WAYPOINTS[i + 1])])
	_noise(n_big, 11, 0.0035, 4)
	_noise(n_big2, 12, 0.006, 3)
	_noise(n_mid, 13, 0.03, 3)
	_noise(n_fine, 14, 0.45, 1)
	_noise(n_blade, 15, 0.35, 2)
	_noise(n_edge, 16, 0.06, 2)
	n_cell.seed = 17
	n_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	n_cell.frequency = 0.11
	n_cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n_cob.seed = 18
	n_cob.noise_type = FastNoiseLite.TYPE_CELLULAR
	n_cob.frequency = 0.075
	n_cob.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n_cobv.seed = 18
	n_cobv.noise_type = FastNoiseLite.TYPE_CELLULAR
	n_cobv.frequency = 0.075
	n_cobv.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE

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


func _path_dist(p: Vector2) -> float:
	var best := INF
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


func _shade(p: Vector2, portal: Vector2, goal: Vector2) -> Color:
	var fine := n_fine.get_noise_2dv(p)
	var mid := n_mid.get_noise_2dv(p)
	var d := _path_dist(p)
	var e := d - ROAD_HALF + n_edge.get_noise_2dv(p) * 2.6 + fine * 0.5

	# ── 草地 ──
	var big := n_big.get_noise_2dv(p)
	var g := GRASS_DARK.lerp(GRASS_MID, _ss(-0.55, 0.45, big))
	g = g.lerp(GRASS_LIGHT, _ss(0.15, 0.65, mid * 0.6 + big * 0.6) * 0.55)
	g = g.lerp(GRASS_DRY, _ss(0.35, 0.8, n_big2.get_noise_2dv(p)) * 0.45)
	# 縱向草葉紋理
	var blade := n_blade.get_noise_2d(p.x * 1.6, p.y * 0.35)
	g = g * (1.0 + 0.22 * blade + 0.09 * fine)
	# 格線提示：極淡的棋盤明暗
	var cx := floori(p.x / MapDef.CELL)
	var cy := floori(p.y / MapDef.CELL)
	g = g * (1.022 if (cx + cy) % 2 == 0 else 0.985)
	# 路邊的陰影（草被踩平、凹陷）
	if e > 0.0 and e < 16.0:
		var k := 1.0 - e / 16.0
		g = g.darkened(0.32 * k * k)

	# ── 泥土路 ──
	var r := DIRT.lerp(DIRT_LIGHT, _ss(-0.5, 0.7, mid))
	r = r * (1.0 + 0.07 * fine)
	# 兩道車轍
	var rut := exp(-pow(d - 8.5, 2.0) / 6.0)
	r = r.darkened(0.13 * rut)
	# 小石子（細胞雜訊）
	var c := n_cell.get_noise_2dv(p)
	var pebble_zone := mid > -0.1
	if pebble_zone and c < -0.8:
		var lit := n_cell.get_noise_2dv(p + Vector2(0.8, 0.8))
		r = PEBBLE.darkened(0.28 if lit < c else 0.0).lightened(0.1 * fine)
	elif pebble_zone and n_cell.get_noise_2dv(p - Vector2(1.3, 1.3)) < -0.8:
		r = r.darkened(0.35)  # 石子投影
	# 路緣變暗
	if e > -6.0:
		r = r.lerp(DIRT_DARK, _ss(-6.0, 0.0, e) * 0.75)

	var col := r.lerp(g, _ss(-0.7, 0.7, e))

	# ── 傳送門焦土 ──
	var dp := p.distance_to(portal) + n_edge.get_noise_2dv(p * 1.7) * 14.0
	if dp < 75.0:
		var k2 := 1.0 - _ss(25.0, 75.0, dp)
		col = col.lerp(BLIGHT, k2 * 0.75)
		col = col.lerp(Color("6a2a9a"), k2 * 0.2 * (0.5 + 0.5 * mid))

	# ── 城堡石板廣場 ──
	var dg := p.distance_to(goal) + n_edge.get_noise_2dv(p * 1.3) * 8.0
	if dg < 64.0:
		var cob := n_cob.get_noise_2dv(p)
		var cv := n_cobv.get_noise_2dv(p)
		var stone := COBBLE.lerp(Color("b4ae9e"), 0.5 + 0.5 * cv) * (1.0 + 0.07 * fine)
		# 石塊邊緣：上緣亮、下緣暗，做出凸起感
		var up := n_cob.get_noise_2dv(p - Vector2(1.0, 1.0))
		if cob < -0.9:
			stone = COBBLE_DARK
		elif up < -0.9:
			stone = stone.lightened(0.18)
		col = col.lerp(stone, 1.0 - _ss(54.0, 64.0, dg))
		if dg > 54.0 and dg < 66.0:
			col = col.darkened(0.25 * (1.0 - absf(dg - 60.0) / 6.0))

	# ── 暗角 ──
	var v := Vector2((p.x / W - 0.5) * 1.6, (p.y / H - 0.5) * 1.6).length()
	col = col.darkened(0.38 * _ss(0.6, 1.2, v))
	# 左上方來的柔光
	col = col.lightened(0.05 * (1.0 - _ss(0.0, 1.0, (p.x + p.y) / (W + H) * 1.6)))
	col.a = 1.0
	return col
