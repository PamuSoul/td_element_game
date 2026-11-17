extends RefCounted
## 地圖定義（main.gd 與 tools/gen_bg.gd 共用，改路徑後請執行 make art 重新烘焙背景）

const CELL := 40
const COLS := 25
const ROWS := 18
const WAYPOINTS: Array[Vector2i] = [
	Vector2i(-1, 2), Vector2i(5, 2), Vector2i(5, 7), Vector2i(11, 7), Vector2i(11, 2),
	Vector2i(18, 2), Vector2i(18, 10), Vector2i(3, 10), Vector2i(3, 15), Vector2i(22, 15),
]


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)
