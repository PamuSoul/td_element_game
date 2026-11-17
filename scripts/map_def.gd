extends RefCounted
## 地圖定義（main.gd、scenery.gd 與 tools/gen_bg.gd 共用；改動後請執行 make art 重新烘焙背景）

const CELL := 40
const COLS := 25
const ROWS := 18
const WAYPOINTS: Array[Vector2i] = [
	Vector2i(-1, 2), Vector2i(5, 2), Vector2i(5, 7), Vector2i(11, 7), Vector2i(11, 2),
	Vector2i(18, 2), Vector2i(18, 10), Vector2i(3, 10), Vector2i(3, 15), Vector2i(22, 15),
]
## 路徑轉角的圓弧半徑（敵人沿圓弧行走，格子判定不變）
const CORNER_R := 40.0

## 地圖景物：佔用的格子不能蓋塔
## pond = 池塘（rect 為格子範圍），tree = 大樹（cell 為左上格，size 為佔幾格見方）
const FEATURES: Array = [
	{"type": "pond", "rect": Rect2i(20, 4, 3, 3)},
	{"type": "tree", "cell": Vector2i(23, 0), "size": 2, "variant": 0},
	{"type": "tree", "cell": Vector2i(0, 16), "size": 2, "variant": 1},
	{"type": "tree", "cell": Vector2i(18, 12), "size": 2, "variant": 0},
	{"type": "tree", "cell": Vector2i(0, 6), "size": 1, "variant": 1},
	{"type": "tree", "cell": Vector2i(1, 8), "size": 1, "variant": 0},
	{"type": "tree", "cell": Vector2i(24, 8), "size": 1, "variant": 1},
	{"type": "tree", "cell": Vector2i(24, 10), "size": 1, "variant": 0},
	{"type": "tree", "cell": Vector2i(8, 0), "size": 1, "variant": 1},
	{"type": "tree", "cell": Vector2i(14, 17), "size": 1, "variant": 0},
]


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)


## 被景物佔用的格子
static func blocked_cells() -> Dictionary:
	var out := {}
	for f in FEATURES:
		if f["type"] == "pond":
			var r: Rect2i = f["rect"]
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					out[Vector2i(x, y)] = true
		else:
			var c: Vector2i = f["cell"]
			for dy in int(f["size"]):
				for dx in int(f["size"]):
					out[c + Vector2i(dx, dy)] = true
	return out


## 路徑幾何：直線段與圓弧。["seg", a, b] / ["arc", 圓心, 半徑, 起始角, 掃過角]
static func path_prims() -> Array:
	var pts: Array[Vector2] = []
	for w in WAYPOINTS:
		pts.append(cell_center(w))
	var prims: Array = []
	var cur: Vector2 = pts[0]
	for i in range(1, pts.size()):
		var p: Vector2 = pts[i]
		if i == pts.size() - 1:
			prims.append(["seg", cur, p])
			break
		var a := (p - pts[i - 1]).normalized()
		var b := (pts[i + 1] - p).normalized()
		var s := p - a * CORNER_R
		var e := p + b * CORNER_R
		prims.append(["seg", cur, s])
		var c := p - a * CORNER_R + b * CORNER_R
		var a0 := (s - c).angle()
		prims.append(["arc", c, CORNER_R, a0, angle_difference(a0, (e - c).angle())])
		cur = e
	return prims


## 敵人行走用的密集折線（圓弧每 10 度一點）
static func path_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for pr in path_prims():
		if pr[0] == "seg":
			out.append(pr[1])
		else:
			var c: Vector2 = pr[1]
			var r: float = pr[2]
			var steps := 9
			for k in steps:
				var ang: float = pr[3] + pr[4] * float(k) / steps
				out.append(c + Vector2(cos(ang), sin(ang)) * r)
	var last: Array = path_prims()[-1]
	out.append(last[2])
	return out


## 點到路徑中心線的距離（烘焙背景用）
static func path_dist(p: Vector2, prims: Array) -> float:
	var best := INF
	for pr in prims:
		if pr[0] == "seg":
			var a: Vector2 = pr[1]
			var ab: Vector2 = pr[2] - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
		else:
			var c: Vector2 = pr[1]
			var r: float = pr[2]
			var sweep: float = pr[4]
			var t := angle_difference(pr[3], (p - c).angle()) / sweep
			if t >= 0.0 and t <= 1.0:
				best = minf(best, absf(p.distance_to(c) - r))
			else:
				var a0: float = pr[3]
				var a1: float = pr[3] + sweep
				best = minf(best, minf(p.distance_to(c + Vector2(cos(a0), sin(a0)) * r),
					p.distance_to(c + Vector2(cos(a1), sin(a1)) * r)))
	return best
