extends Node2D
## 《首塔 TD》主控：地圖、波次、建造、效果模組執行器、UI。
## 流程：怪物出現 → 守住 X 波 → 三選一抽元素 → 手動放進塔的槽位 → LOOP

const EnemyScript := preload("res://scripts/enemy.gd")
const TowerScript := preload("res://scripts/tower.gd")
const ZoneScript := preload("res://scripts/zone.gd")
const FxScript := preload("res://scripts/fx.gd")

const MapDef := preload("res://scripts/map_def.gd")
const SceneryScript := preload("res://scripts/scenery.gd")

const CELL := MapDef.CELL
const COLS := MapDef.COLS
const ROWS := MapDef.ROWS
const PANEL_X := 1000
const TOTAL_WAVES := 20
const DRAFT_EVERY := 2  # 每守住 X 波抽一次元素
const START_GOLD := 220
const START_LIVES := 20
const SELL_RATE := 0.6
const WAYPOINTS: Array[Vector2i] = MapDef.WAYPOINTS

var curve := Curve2D.new()
var path_len := 0.0
var path_cells := {}
var blocked_cells := {}  # 池塘、大樹等景物
var towers_by_cell := {}
var enemies: Array = []
var towers: Array = []

var gold := START_GOLD
var lives := START_LIVES
var wave := 0
var wave_active := false
var spawn_queue: Array = []
var spawn_t := 0.0
var spawn_interval := 0.8
var inventory: Array = []
var build_mode := ""
var selected = null
var finished := false
var speed_idx := 0
var autotest := false
var bot := false
var bot_i := 0

var world: Node2D
var overlay: Node2D
var ui: Control
var overlays: Array = []
var stats_label: Label
var hint_label: Label
var wave_btn: Button
var speed_btn: Button
var music_btn: Button
var bgm: AudioStreamPlayer
var build_btns := {}
var inv_box: HFlowContainer
var tower_title: Label
var slot_box: HBoxContainer
var info_label: Label
var sell_btn: Button
var toast_label: Label
var toast_t := 0.0
var shake := 0.0


func _ready() -> void:
	bot = OS.get_cmdline_user_args().has("--bot")
	# 網頁版：網址加上 #bot 可看機器人自動示範
	var web_hash := str(JavaScriptBridge.eval("location.hash")) if OS.has_feature("web") else ""
	if web_hash == "#bot":
		bot = true
	# 網址加上 #autotest：9 座塔輪流換上全部融合，可預覽所有技能動畫
	autotest = bot or web_hash == "#autotest" or OS.get_cmdline_user_args().has("--autotest")
	_build_path()
	var scenery = SceneryScript.new()
	scenery.setup(path_cells)
	scenery.z_index = -10  # 所有地形物件（z=-1）、特效都要畫在底圖之上
	add_child(scenery)
	_start_bgm()
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	overlay = Node2D.new()
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	_build_ui()
	_refresh_all()
	if autotest:
		_autotest_begin()
	else:
		_open_title()


# ══════════════════════════ 地圖 ══════════════════════════

func _build_path() -> void:
	# 敵人沿圓滑彎道行走；格子判定（不能蓋塔的路徑格）仍以直角折線計算
	for pt in MapDef.path_points():
		curve.add_point(pt)
	blocked_cells = MapDef.blocked_cells()
	for i in WAYPOINTS.size():
		if i > 0:
			var a := WAYPOINTS[i - 1]
			var b := WAYPOINTS[i]
			var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
			var c := a
			while true:
				path_cells[c] = true
				if c == b:
					break
				c += step
	path_len = curve.get_baked_length()


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


func _can_build(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS \
		and not path_cells.has(c) and not towers_by_cell.has(c) and not blocked_cells.has(c)


func _draw_overlay() -> void:
	if selected != null and is_instance_valid(selected):
		var rng: float = selected.def["rng"]
		overlay.draw_circle(selected.position, rng, Color(1, 1, 1, 0.05))
		overlay.draw_arc(selected.position, rng, 0.0, TAU, 64, Color(1, 1, 1, 0.5), 1.5)
		overlay.draw_rect(Rect2(selected.position - Vector2(20, 20), Vector2(40, 40)), Color(1, 1, 1, 0.8), false, 2.0)
	if build_mode != "":
		var m := get_global_mouse_position()
		if m.x < PANEL_X:
			var c := _cell_at(m)
			var ok := _can_build(c) and gold >= int(Data.TOWERS[build_mode]["cost"])
			var col := Color(0.4, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.3, 0.35)
			overlay.draw_rect(Rect2(c.x * CELL, c.y * CELL, CELL, CELL), col)
			var rng2: float = Data.TOWERS[build_mode]["rng"]
			overlay.draw_arc(_cell_center(c), rng2, 0.0, TAU, 64, Color(1, 1, 1, 0.4), 1.5)


# ══════════════════════════ 主迴圈 ══════════════════════════

func _process(delta: float) -> void:
	fx_budget = FX_BUDGET_PER_FRAME
	overlay.queue_redraw()
	if shake > 0.0:
		shake = maxf(shake - delta * 25.0 / maxf(Engine.time_scale, 0.01), 0.0)
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	else:
		position = Vector2.ZERO
	if toast_t > 0.0:
		toast_t -= delta / maxf(Engine.time_scale, 0.01)
		toast_label.modulate.a = clampf(toast_t, 0.0, 1.0)
	if get_tree().paused or finished:
		return
	stats_label.text = "波次 %d/%d    生命 %d    金幣 %d" % [wave, TOTAL_WAVES, lives, gold]
	if bot:
		_bot_step()
	if not wave_active:
		return
	if not spawn_queue.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = spawn_interval
			_spawn(spawn_queue.pop_front())
	elif enemies.is_empty():
		_wave_cleared()


func _start_wave() -> void:
	if wave_active or finished or wave >= TOTAL_WAVES:
		return
	wave += 1
	wave_active = true
	spawn_queue = _make_wave(wave)
	spawn_interval = maxf(0.35, 0.9 - wave * 0.02)
	spawn_t = 0.5
	if bot:
		print("[bot] wave %d lives=%d gold=%d towers=%d" % [wave, lives, gold, towers.size()])
	elif autotest:
		_autotest_assign()
	_refresh_all()


func _make_wave(n: int) -> Array:
	var q: Array = []
	var count := 8 + n * 2
	for i in count:
		var k := "normal"
		if n >= 3 and i % 3 == 2:
			k = "fast"
		if n >= 5 and i % 5 == 4:
			k = "tank"
		q.append(k)
	if n % 5 == 0:
		q.insert(count / 2, "boss")
	return q


func _spawn(k: String) -> void:
	var e = EnemyScript.new()
	e.setup(self, k, wave)
	world.add_child(e)
	enemies.append(e)


func _wave_cleared() -> void:
	wave_active = false
	gold += 15 + wave
	if wave >= TOTAL_WAVES:
		_finish(true)
		return
	_refresh_all()
	if wave % DRAFT_EVERY == 0:
		_open_draft()
	elif autotest:
		_start_wave()


func on_enemy_died(en) -> void:
	enemies.erase(en)
	var big: bool = en.kind == "boss"
	burst(en.position, en.color.lightened(0.3), 24 if big else 9, 220.0 if big else 120.0, 0.5, "fx_spark", 0.35)
	burst(en.position, Color(1, 1, 1, 0.5), 5, 40.0, 0.5, "fx_smoke", 0.5 if big else 0.3)
	if big:
		fx_boom(en.position, 120.0, Color("ff3a6a"))
		shake = maxf(shake, 9.0)
	var g: int = en.gold
	if en.st.has("bounty"):
		g *= 2
		fx_text(en.position, "+%d" % g, Color("ffd700"))
	gold += g
	if en.st.has("mark"):
		_splinter_burst(en.position, float(en.st["mark"]["p"]))
	if en.st.has("bomb"):
		_core_blast(en, float(en.st["bomb"]["p"]))


func on_leak(en) -> void:
	enemies.erase(en)
	lives -= int(en.leak)
	fx_boom(en.position, 50.0, Color("ff4040"))
	shake = maxf(shake, 5.0)
	if lives <= 0 and not finished:
		lives = 0
		_finish(false)


func on_status_end(en, s: String, d: Dictionary) -> void:
	match s:
		"mark":
			_splinter_burst(en.position, float(d["p"]))
		"bomb":
			_core_blast(en, float(d["p"]))


## 狂暴超導：木屑爆發
func _splinter_burst(pos: Vector2, p: float) -> void:
	fx_explode("splinter", pos, 80.0, Color("b6e04a"))
	for o in enemies_in(pos, 80.0):
		o.take_damage(35.0 * p, "magic")
		if alive(o):
			o.add_status("slow", 1.5, 0.3, p)


## 超載熔核：以宿主最大生命比例引爆
func _core_blast(en, p: float) -> void:
	var pos: Vector2 = en.position
	var dmg := minf(float(en.max_hp) * 0.25, 250.0) * p
	fx_explode("core", pos, 90.0, Color("ff3a6a"))
	shake = maxf(shake, 6.0)
	for o in enemies_in(pos, 90.0):
		o.take_damage(dmg, "magic")
		if alive(o):
			o.add_status("stun", 0.6, 0.0, p)
	if alive(en):
		en.take_damage(dmg, "magic")


func spread_wildfire(en) -> void:
	var d: Dictionary = en.st["wildfire"]
	if int(d["g"]) >= 2:
		return
	for o in enemies_in(en.position, 45.0):
		if o != en and not o.st.has("wildfire"):
			o.add_status("wildfire", 3.0, float(d["v"]), float(d["p"]), int(d["g"]) + 1)


# ══════════════════════════ 效果模組執行器 ══════════════════════════

func alive(en) -> bool:
	return is_instance_valid(en) and not en.dead


func enemies_in(pos: Vector2, r: float) -> Array:
	var out: Array = []
	for en in enemies:
		if alive(en) and en.position.distance_to(pos) <= r + float(en.radius):
			out.append(en)
	return out


func nearest_enemy(pos: Vector2, r: float, exclude: Array):
	var best = null
	var best_d := r
	for en in enemies:
		if alive(en) and not exclude.has(en):
			var d: float = en.position.distance_to(pos)
			if d <= best_d:
				best_d = d
				best = en
	return best


func tower_hit(tw, dmg: float, effects: Array, p: float, targets: Array, primary, pos: Vector2) -> void:
	for en in targets:
		if alive(en):
			en.take_damage(dmg, "phys")
	if not effects.is_empty():
		run_effects(effects, targets, primary, pos, p, tw)
	if tw != null and is_instance_valid(tw):
		if tw.kind == "aura":
			for en in targets.slice(0, 4):
				if alive(en):
					fx_hit(tw, en.position)
		else:
			fx_hit(tw, pos, tw.kind == "cannon")


func run_effects(effects: Array, targets: Array, primary, pos: Vector2, p: float, tower = null) -> void:
	var ready: bool = tower == null or tower.special_cd <= 0.0
	var used_cd := 0.0
	for e in effects:
		if e.has("cd"):
			if not ready:
				continue
			used_cd = maxf(used_cd, float(e["cd"]))
		match e["t"]:
			"status":
				var s: String = e["s"]
				var dur: float = e["dur"]
				var v: float = e.get("v", 0.0)
				if s in EnemyScript.DOTS:
					v *= p
				else:
					dur *= p
				for en in targets:
					if alive(en):
						en.add_status(s, dur, v, p)
			"dmg":
				for en in targets:
					if alive(en):
						var d: float = float(e.get("dmg", 0.0)) * p
						if e.has("pct"):
							d += minf(float(en.max_hp) * float(e["pct"]), 60.0) * p
						if e.get("speed_scale", false):
							d *= float(en.speed) / 60.0
						en.take_damage(d, e.get("kind", "magic"))
			"knockback":
				for en in targets:
					if alive(en):
						en.push(-float(e["dist"]) * p)
						fx_knock(en)
			"pull":
				var list: Array = targets
				if e.has("r"):
					list = enemies_in(pos, e["r"])
				var center := curve.get_closest_offset(pos)
				var dist: float = float(e["dist"]) * p
				# 磁暴（有半徑）：電纜從落點抓住敵人；塔的領域牽引：藤蔓從塔伸向敵人
				var from := pos
				var tcol := Color("b9a0ff")
				var show_tether: bool = e.has("r")
				if not e.has("r") and tower != null and is_instance_valid(tower):
					from = tower.position
					tcol = tower.color
					show_tether = true
				var shown := 0
				for en in list:
					if alive(en):
						if show_tether and shown < 8:
							shown += 1
							_fx("tether", Vector2.ZERO, tcol, 0.4, {"points": PackedVector2Array([from, en.position])})
						en.push(clampf(center - float(en.offset), -dist, dist))
			"explode":
				var r: float = e["r"]
				fx_explode(e.get("style", ""), pos, r, e.get("color", Color("ff9a4a") if e.get("kind", "") != "thunder" else Color("b9a0ff")))
				if r >= 70.0:
					shake = maxf(shake, 4.0)
				for en in enemies_in(pos, r):
					en.take_damage(float(e["dmg"]) * p, e.get("kind", "magic"))
					if e.has("stun") and alive(en):
						en.add_status("stun", float(e["stun"]) * p, 0.0, p)
			"chain":
				_do_chain(e, primary, pos, p)
			"bolts":
				_do_bolts(e, targets, p, tower)
			"zone":
				spawn_zone(e["z"], pos, p)
	if used_cd > 0.0 and tower != null and is_instance_valid(tower):
		tower.special_cd = used_cd
		fx_cast(tower)


func _strike(en, e: Dictionary, p: float) -> void:
	var at: Vector2 = en.position
	en.take_damage(float(e["dmg"]) * p, "thunder")
	if e.has("stun") and alive(en):
		en.add_status("stun", float(e["stun"]) * p, 0.0, p)
	if e.has("on"):
		run_effects(e["on"], [en], en, at, p)


func _do_chain(e: Dictionary, primary, pos: Vector2, p: float) -> void:
	var cur = primary
	if not alive(cur):
		cur = nearest_enemy(pos, 120.0, [])
	if cur == null:
		return
	var hit: Array = []
	var from := pos
	for i in int(e["n"]):
		hit.append(cur)
		fx_bolt(from, cur.position, Color("f6d743"))
		fx_flash(cur.position, 16.0, Color("fff07a"))
		from = cur.position
		_strike(cur, e, p)
		var nxt = nearest_enemy(from, 110.0, hit)
		if nxt == null:
			break
		cur = nxt
	_redirect_to_marks(e, from, hit, p)


func _do_bolts(e: Dictionary, targets: Array, p: float, tower = null) -> void:
	# 雷暴風雲：落雷從塔上方的雷雲劈下
	var sky := Vector2(-40, -320)
	var from_tower: bool = tower != null and is_instance_valid(tower)
	if from_tower:
		tower.storm_flash = 0.25
	var pool: Array = []
	for en in targets:
		if alive(en):
			pool.append(en)
	pool.shuffle()
	var hit: Array = []
	var last := Vector2.ZERO
	for i in mini(int(e["n"]), pool.size()):
		var en = pool[i]
		if not alive(en):
			continue
		hit.append(en)
		last = en.position
		fx_bolt(tower.position + Vector2(randf_range(-14, 14), -44) if from_tower else last + sky, last, Color("cfe0ff"))
		fx_boom(last, e["r"], Color("cfe0ff"))
		_fx("crack", last, Color(0.05, 0.05, 0.12), 0.9, {"radius": e["r"] * 0.8, "z": -1})
		for o in enemies_in(last, e["r"]):
			o.take_damage(float(e["dmg"]) * p * (1.0 if o == en else 0.5), "thunder")
	if not hit.is_empty():
		_redirect_to_marks(e, last, hit, p)


## 狂暴超導的避雷針：場上所有雷擊都會額外劈向帶有導體的敵人
func _redirect_to_marks(e: Dictionary, from: Vector2, hit: Array, p: float) -> void:
	for en in enemies.duplicate():
		if alive(en) and en.st.has("mark") and not hit.has(en):
			fx_bolt(from, en.position, Color("b6e04a"))
			en.take_damage(float(e["dmg"]) * p * 1.5, "thunder")


func spawn_zone(zdef: Dictionary, pos: Vector2, p: float) -> void:
	var z = ZoneScript.new()
	z.setup(self, zdef, p)
	z.position = pos
	z.z_index = -1
	world.add_child(z)
	if not zdef.get("warn", false):
		fx_zone_intro(zdef, pos)


# ══════════════════════════ 特效 ══════════════════════════
# 動畫原件在 fx.gd；這裡把原件 + 粒子組合成各元素 / 技能的施放動畫。
# fx_budget：每幀可新增的小特效上限，避免大量敵人同時中狀態時掉幀。

const FX_BUDGET_PER_FRAME := 18
var fx_budget := FX_BUDGET_PER_FRAME


func _fx(mode: String, pos: Vector2, col: Color, dur: float, opts: Dictionary = {}):
	var f = FxScript.new()
	f.mode = mode
	f.position = pos
	f.color = col
	f.dur = dur
	f.z_index = opts.get("z", 5)
	for k in opts:
		if k != "z":
			f.set(k, opts[k])
	world.add_child(f)
	return f


func fx_ring(pos: Vector2, r: float, col: Color) -> void:
	_fx("ring", pos, col, 0.3, {"radius": r})


func fx_flash(pos: Vector2, r: float, col: Color) -> void:
	_fx("flash", pos, col, 0.22, {"radius": r})


## 爆炸：衝擊波 + 閃光 + 火花
func fx_boom(pos: Vector2, r: float, col: Color) -> void:
	fx_ring(pos, r, col)
	fx_flash(pos, r * 0.9, col.lightened(0.3))
	burst(pos, col.lightened(0.2), clampi(int(r / 7.0), 6, 16), r * 2.2, 0.45, "fx_spark", 0.3)


## 一次性粒子爆發（簡易版）
func burst(pos: Vector2, col: Color, amount: int = 10, speed: float = 120.0, life: float = 0.45,
		tex_name: String = "fx_spark", size: float = 0.25) -> void:
	emit(pos, col, amount, {"speed": speed, "life": life, "tex": tex_name, "size": size})


## 一次性粒子爆發。opts：tex speed life size grav dir spread radius spin damp add z
func emit(pos: Vector2, col: Color, amount: int, opts: Dictionary = {}) -> void:
	if amount <= 0:
		return
	var ps := CPUParticles2D.new()
	ps.position = pos
	ps.z_index = opts.get("z", 6)
	ps.texture = Data.tex(opts.get("tex", "fx_spark"))
	ps.amount = amount
	ps.lifetime = opts.get("life", 0.45)
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.direction = opts.get("dir", Vector2.UP)
	ps.spread = opts.get("spread", 180.0)
	ps.gravity = opts.get("grav", Vector2(0, 160))
	var sp: float = opts.get("speed", 120.0)
	ps.initial_velocity_min = sp * 0.35
	ps.initial_velocity_max = sp
	var sz: float = opts.get("size", 0.25)
	ps.scale_amount_min = sz * 0.5
	ps.scale_amount_max = sz
	if opts.has("radius"):
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = opts["radius"]
	if opts.has("spin"):
		ps.angle_min = 0.0
		ps.angle_max = 360.0
		ps.angular_velocity_min = -float(opts["spin"])
		ps.angular_velocity_max = float(opts["spin"])
	if opts.has("damp"):
		ps.damping_min = float(opts["damp"]) * 0.6
		ps.damping_max = float(opts["damp"])
	ps.color = col
	ps.color_ramp = Data.fade_ramp
	if opts.get("add", true):
		ps.material = Data.add_mat
	ps.finished.connect(ps.queue_free)
	world.add_child(ps)
	ps.emitting = true


func fx_text(pos: Vector2, text: String, col: Color) -> void:
	_fx("text", pos, col, 0.8, {"text": text})


func fx_bolt(a: Vector2, b: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([a])
	var segs := maxi(2, int(a.distance_to(b) / 18.0))
	var normal := (b - a).orthogonal().normalized()
	for i in range(1, segs):
		pts.append(a.lerp(b, float(i) / segs) + normal * randf_range(-7.0, 7.0))
	pts.append(b)
	_fx("bolt", Vector2.ZERO, col, 0.18, {"points": pts})


## 單一元素的小型粒子（命中、狀態附加時使用）
func fx_elem(e: String, pos: Vector2, k: float = 1.0) -> void:
	match e:
		"water":
			emit(pos, Color("9ad8ff"), int(6 * k), {"tex": "fx_drop", "speed": 170.0, "grav": Vector2(0, 520),
				"spread": 70.0, "size": 0.5, "life": 0.6})
		"fire":
			emit(pos, Color("ff8a3a"), int(6 * k), {"tex": "fx_flame", "speed": 60.0, "grav": Vector2(0, -150),
				"spread": 70.0, "size": 0.7, "life": 0.65, "radius": 8.0})
		"wood":
			emit(pos, Color("8fe07a"), int(5 * k), {"tex": "fx_leaf", "speed": 130.0, "grav": Vector2(0, 80),
				"size": 0.7, "life": 0.9, "spin": 360.0, "damp": 80.0, "add": false})
		"thunder":
			emit(pos, Color("fff07a"), int(6 * k), {"tex": "fx_spark", "speed": 230.0, "grav": Vector2.ZERO,
				"size": 0.4, "life": 0.3})
		"earth":
			emit(pos, Color("c49a6a"), int(5 * k), {"tex": "fx_rock", "speed": 170.0, "grav": Vector2(0, 560),
				"spread": 60.0, "size": 0.55, "life": 0.6, "spin": 420.0, "add": false})


## 元素命中的「衝擊造型」：每次命中都看得到的主體動畫
func fx_impact(e: String, pos: Vector2, k: float = 1.0) -> void:
	var r := 24.0 * k
	match e:
		"water":
			_fx("ripple", pos + Vector2(0, 4), Color("8fd0ff"), 0.6, {"radius": r * 1.3, "count": 2})
			_fx("sprite", pos, Color("9ad8ff"), 0.35, {"tex": "fx_ring", "radius": r, "s0": 0.3, "s1": 1.0})
		"fire":
			_fx("sprite", pos + Vector2(0, -r * 0.4), Color("ff9a40"), 0.45, {"tex": "fx_flame", "radius": r, "s0": 0.3, "s1": 1.3})
			fx_flash(pos, r * 1.1, Color("ff7a30"))
		"wood":
			_fx("spikes", pos + Vector2(0, 6), Color("5fce6a"), 0.55, {"radius": r * 1.1, "count": 4, "z": 1})
		"thunder":
			_fx("shock", pos, Color("f6d743"), 0.25, {"radius": r * 1.3, "count": 4})
			fx_flash(pos, r * 0.9, Color("fff07a"))
		"earth":
			_fx("crack", pos, Color(0.2, 0.12, 0.05), 0.9, {"radius": r * 1.1, "z": -1})
			_fx("sprite", pos, Color("e0c090"), 0.3, {"tex": "fx_ring", "radius": r, "s0": 0.3, "s1": 1.0})


## 命中特效：塔上每種元素各噴一點對應的粒子
func fx_hit(tw, pos: Vector2, big: bool = false) -> void:
	if tw == null or not is_instance_valid(tw) or tw.elems.is_empty() or fx_budget <= 0:
		return
	fx_budget -= 1
	var seen := {}
	for e in tw.elems:
		if not seen.has(e):
			seen[e] = true
			fx_elem(e, pos, 1.5 if big else 1.0)
			fx_impact(e, pos, 1.6 if big else 1.0)


## 敵人新獲得狀態時的動畫（由 enemy.add_status 呼叫）
func fx_status(en, s: String) -> void:
	if fx_budget <= 0:
		return
	fx_budget -= 1
	var p: Vector2 = en.position
	match s:
		"burn":
			fx_elem("fire", p)
		"wildfire":
			fx_elem("fire", p, 1.5)
			fx_ring(p, 30.0, Color("ff9a2e"))
		"poison":
			emit(p, Color("8fe06a"), 4, {"tex": "fx_bubble", "speed": 25.0, "grav": Vector2(0, -50), "size": 0.45,
				"life": 0.8, "radius": 8.0, "add": false})
		"slow":
			_fx("ripple", p + Vector2(0, 6), Color("9ad0ff"), 0.6, {"radius": 24.0, "count": 2})
		"wet":
			fx_elem("water", p)
		"stun":
			fx_flash(p, 18.0, Color("fff07a"))
			_fx("shock", p, Color("f6d743"), 0.2, {"radius": 22.0, "count": 3})
		"root":
			fx_elem("wood", p, 1.5)
		"vuln":
			fx_elem("earth", p)
			_fx("sprite", p, Color("ffd0a0"), 0.45, {"tex": "fx_crack", "radius": 18.0, "s0": 0.4, "s1": 1.0, "additive": false})
		"mark":
			_fx("rune", p, Color("b6e04a"), 0.6, {"radius": 22.0})
			fx_bolt(p + Vector2(8, -70), p, Color("b6e04a"))
		"bomb":
			_fx("implode", p, Color("ff3a6a"), 0.5, {"radius": 40.0})
			fx_text(p + Vector2(0, -22), "！", Color("ff5a7a"))
		"bounty":
			emit(p, Color.WHITE, 2, {"tex": "fx_coin", "speed": 60.0, "grav": Vector2(0, 160), "spread": 30.0,
				"size": 0.5, "life": 0.6, "add": false})


## 各種爆炸的造型（data.gd explode 模組的 style）
func fx_explode(style: String, pos: Vector2, r: float, col: Color) -> void:
	match style:
		"plasma":
			fx_boom(pos, r, col)
			_fx("shock", pos, col, 0.3, {"radius": r * 1.1, "count": 7})
		"fire":
			fx_boom(pos, r, col)
			emit(pos, Color("ffb050"), 6, {"tex": "fx_flame", "speed": r * 1.2, "grav": Vector2(0, -120), "size": 0.5,
				"life": 0.55, "radius": r * 0.3})
			emit(pos, Color(0.25, 0.22, 0.2, 0.6), 3, {"tex": "fx_smoke", "speed": 30.0, "grav": Vector2(0, -30),
				"size": 0.5, "life": 0.9, "add": false})
		"geyser":
			_fx("column", pos, col, 0.9, {"radius": r * 0.55})
			_fx("ripple", pos, Color("bff4ff"), 0.8, {"radius": r * 1.1, "count": 3, "z": -1})
			fx_flash(pos, r * 0.8, col)
			emit(pos + Vector2(0, -r * 0.9), Color("c8f2ff"), 18, {"tex": "fx_drop", "speed": 280.0, "spread": 55.0,
				"grav": Vector2(0, 650), "size": 0.4, "life": 0.95})
		"meteor":
			_fx("crack", pos, Color(0.12, 0.06, 0.03), 2.4, {"radius": r * 1.15, "z": -1})
			fx_boom(pos, r * 1.1, Color("ff7a2a"))
			fx_flash(pos, r * 1.4, Color("ffe0a0"))
			emit(pos, Color("8a6a50"), 12, {"tex": "fx_rock", "speed": 340.0, "spread": 80.0, "grav": Vector2(0, 750),
				"size": 0.5, "life": 0.9, "spin": 600.0, "add": false})
			emit(pos, Color("ff9a3a"), 10, {"tex": "fx_flame", "speed": 120.0, "grav": Vector2(0, -90), "size": 0.65,
				"life": 0.8, "radius": r * 0.4})
			emit(pos, Color(0.2, 0.18, 0.16, 0.7), 6, {"tex": "fx_smoke", "speed": 50.0, "grav": Vector2(0, -25),
				"size": 0.9, "life": 1.4, "radius": r * 0.4, "add": false})
		"magnet":
			_fx("implode", pos, col, 0.45, {"radius": r})
			_fx("shock", pos, col, 0.3, {"radius": r * 0.8, "count": 6})
			fx_flash(pos, r * 0.6, col)
		"core":
			fx_boom(pos, r, col)
			fx_flash(pos, r * 1.2, Color(1, 0.9, 0.9))
			_fx("shock", pos, Color("ff7a9a"), 0.35, {"radius": r, "count": 8})
			_fx("crack", pos, Color(0.1, 0.02, 0.05), 1.6, {"radius": r * 0.8, "z": -1})
			emit(pos, Color(0.25, 0.15, 0.18, 0.7), 5, {"tex": "fx_smoke", "speed": 60.0, "grav": Vector2(0, -25),
				"size": 0.7, "life": 1.0, "radius": r * 0.3, "add": false})
		"splinter":
			fx_ring(pos, r, col)
			fx_flash(pos, r * 0.7, col)
			emit(pos, col, 10, {"tex": "fx_leaf", "speed": r * 2.2, "grav": Vector2(0, 90), "size": 0.5, "life": 0.8,
				"spin": 500.0, "damp": 90.0, "add": false})
			emit(pos, Color("a8763a"), 6, {"tex": "fx_rock", "speed": r * 2.0, "grav": Vector2(0, 400), "size": 0.25,
				"life": 0.6, "spin": 600.0, "add": false})
		_:
			fx_boom(pos, r, col)


## 地形 / 物件生成時的登場動畫
func fx_zone_intro(zdef: Dictionary, pos: Vector2) -> void:
	var r: float = zdef["r"]
	var col: Color = zdef["color"]
	match zdef.get("art", ""):
		"cloud":
			fx_ring(pos, r, col)
			emit(pos, col.lightened(0.3), 10, {"tex": "fx_smoke", "speed": r * 1.4, "grav": Vector2.ZERO, "damp": 120.0,
				"size": 0.9, "life": 0.8, "add": false})
		"vines":
			_fx("spikes", pos, Color("3fae6a"), 0.7, {"radius": r * 0.85, "count": 8, "z": 1})
			_fx("crack", pos, Color(0.1, 0.2, 0.08), 1.2, {"radius": r * 0.9, "z": -2})
			fx_elem("wood", pos, 3.0)
		"puddle":
			_fx("ripple", pos, col, 0.8, {"radius": r, "count": 3, "z": -1})
			_fx("shock", pos, Color("bfeaff"), 0.35, {"radius": r * 0.9, "count": 5})
			emit(pos, Color("bfe6ff"), 12, {"tex": "fx_drop", "speed": 200.0, "spread": 70.0, "grav": Vector2(0, 600),
				"size": 0.32, "life": 0.6})
		"mud":
			_fx("ripple", pos, Color("a08a60"), 0.8, {"radius": r, "count": 2, "z": -1})
			emit(pos, Color("7a6040"), 12, {"tex": "fx_drop", "speed": 220.0, "spread": 75.0, "grav": Vector2(0, 650),
				"size": 0.38, "life": 0.6, "add": false})
		"lava":
			_fx("column", pos, Color("ff7a2a"), 0.55, {"radius": r * 0.45})
			_fx("crack", pos, Color(0.15, 0.04, 0.0), 1.4, {"radius": r, "z": -2})
			emit(pos, Color("ffb050"), 12, {"tex": "fx_flame", "speed": 160.0, "spread": 50.0, "grav": Vector2(0, 260),
				"size": 0.5, "life": 0.7})
		"thorns":
			_fx("spikes", pos, Color("b4c45a"), 0.9, {"radius": r * 0.95, "count": 11, "z": 1})
			_fx("crack", pos, Color(0.12, 0.1, 0.04), 1.3, {"radius": r, "z": -2})
			fx_elem("earth", pos, 2.5)
		"vortex":
			_fx("implode", pos, col, 0.6, {"radius": r})
			_fx("rune", pos, col, 0.8, {"radius": r * 0.8, "z": -1})
			_fx("shock", pos, col.lightened(0.4), 0.3, {"radius": r * 0.7, "count": 5})
		"totem":
			_fx("crack", pos, Color(0.12, 0.1, 0.02), 1.6, {"radius": 46.0, "z": -2})
			_fx("rune", pos, col, 0.9, {"radius": 48.0, "z": -1})
			fx_bolt(pos + Vector2(-20, -360), pos + Vector2(0, -40), Color("fff07a"))
			fx_flash(pos + Vector2(0, -30), 50.0, Color("fff07a"))
			emit(pos, Color("b49a6a"), 10, {"tex": "fx_rock", "speed": 200.0, "spread": 70.0, "grav": Vector2(0, 600),
				"size": 0.3, "life": 0.6, "spin": 500.0, "add": false})
		"":
			fx_ring(pos, r, col)


## 塔的施法動畫：魔法陣 + 上升光點
func fx_cast(tw) -> void:
	if not is_instance_valid(tw):
		return
	tw.cast_t = 0.45
	_fx("rune", tw.position + Vector2(0, 8), tw.color, 0.6, {"radius": 30.0, "z": -1})
	emit(tw.position, tw.color.lightened(0.3), 8, {"speed": 70.0, "grav": Vector2(0, -140), "size": 0.2,
		"life": 0.6, "radius": 14.0})


## 擊退：風切線 + 揚塵（往路徑後方）
func fx_knock(en) -> void:
	if fx_budget <= 0:
		return
	fx_budget -= 1
	var back: Vector2 = curve.sample_baked(maxf(float(en.offset) - 12.0, 0.0)) - en.position
	var d := back.normalized() if back.length() > 0.1 else Vector2.LEFT
	_fx("streaks", en.position, Color(0.85, 0.95, 1.0), 0.35, {"radius": 24.0, "count": 4, "dir": d})
	emit(en.position + Vector2(0, 8), Color(0.75, 0.68, 0.55, 0.6), 3, {"tex": "fx_smoke", "speed": 30.0,
		"grav": Vector2(0, -10), "size": 0.3, "life": 0.5, "add": false})


# ══════════════════════════ 輸入 / 建造 ══════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if not overlays.is_empty() or finished:
		return
	if event is InputEventMouseButton and event.pressed:
		var m := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			build_mode = ""
			_refresh_all()
		elif event.button_index == MOUSE_BUTTON_LEFT and m.x < PANEL_X:
			var c := _cell_at(m)
			if build_mode != "":
				_try_build(build_mode, c)
			else:
				selected = towers_by_cell.get(c)
				_refresh_all()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_start_wave()
			KEY_1:
				_set_build("arrow")
			KEY_2:
				_set_build("cannon")
			KEY_3:
				_set_build("aura")
			KEY_ESCAPE:
				build_mode = ""
				selected = null
				_refresh_all()
			KEY_C:
				_open_codex()
			KEY_M:
				_toggle_music()


func _set_build(k: String) -> void:
	build_mode = "" if build_mode == k else k
	_refresh_all()


func _try_build(k: String, c: Vector2i) -> bool:
	var cost: int = Data.TOWERS[k]["cost"]
	if not _can_build(c):
		return false
	if gold < cost:
		_toast("金幣不足")
		return false
	gold -= cost
	var t = TowerScript.new()
	t.setup(self, k, c)
	t.position = _cell_center(c)
	world.add_child(t)
	t.refresh_fusion()
	towers.append(t)
	towers_by_cell[c] = t
	selected = t
	if not Input.is_key_pressed(KEY_SHIFT):
		build_mode = ""
	_refresh_all()
	return true


func _sell_selected() -> void:
	if selected == null:
		return
	gold += int(int(selected.def["cost"]) * SELL_RATE)
	inventory.append_array(selected.elems)
	towers.erase(selected)
	towers_by_cell.erase(selected.cell)
	selected.queue_free()
	selected = null
	_refresh_all()


func _insert_element(idx: int) -> void:
	if selected == null:
		_toast("先點選一座塔，再點元素放入槽位")
		return
	if selected.elems.size() >= Data.MAX_SLOTS:
		_toast("這座塔的 3 個槽位已滿")
		return
	selected.elems.append(inventory[idx])
	inventory.remove_at(idx)
	_tower_changed(selected)


func _remove_element(slot: int) -> void:
	if selected == null or slot >= selected.elems.size():
		return
	inventory.append(selected.elems[slot])
	selected.elems.remove_at(slot)
	_tower_changed(selected)


func _tower_changed(t) -> void:
	t.refresh_fusion()
	var key := Data.key_of(t.elems)
	if Data.unlock(key):
		_toast("圖鑑解鎖：【%s】（%s）" % [Data.FUSIONS[key]["name"], Data.elem_names(key)])
	_refresh_all()


# ══════════════════════════ UI ══════════════════════════

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = Data.font
	th.default_font_size = 15
	ui.theme = th
	layer.add_child(ui)

	var side := PanelContainer.new()
	var side_sb := StyleBoxFlat.new()
	side_sb.bg_color = Color("161a22")
	side_sb.border_color = Color("3a4252")
	side_sb.border_width_left = 2
	side.add_theme_stylebox_override("panel", side_sb)
	side.position = Vector2(PANEL_X, 0)
	side.size = Vector2(1280 - PANEL_X, 720)
	ui.add_child(side)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 10)
	side.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := _label("首塔 TD", 22)
	box.add_child(title)
	stats_label = _label("", 15)
	box.add_child(stats_label)

	var build_row := HBoxContainer.new()
	box.add_child(build_row)
	for i in Data.TOWER_ORDER.size():
		var k: String = Data.TOWER_ORDER[i]
		var b := Button.new()
		b.text = "%s\n$%d [%d]" % [Data.TOWERS[k]["name"], Data.TOWERS[k]["cost"], i + 1]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(_set_build.bind(k))
		build_row.add_child(b)
		build_btns[k] = b
	hint_label = _wrap_label("", 13)
	hint_label.custom_minimum_size = Vector2(0, 40)
	hint_label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint_label)

	wave_btn = Button.new()
	wave_btn.custom_minimum_size = Vector2(0, 40)
	wave_btn.pressed.connect(_start_wave)
	box.add_child(wave_btn)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	speed_btn = Button.new()
	speed_btn.text = "速度 1x"
	speed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_btn.pressed.connect(_cycle_speed)
	row2.add_child(speed_btn)
	music_btn = Button.new()
	music_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_btn.pressed.connect(_toggle_music)
	row2.add_child(music_btn)
	_update_music_btn()
	var codex_btn := Button.new()
	codex_btn.text = "手冊 [C]"
	codex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_btn.pressed.connect(_open_codex)
	row2.add_child(codex_btn)

	box.add_child(HSeparator.new())
	box.add_child(_label("元素背包", 15))
	inv_box = HFlowContainer.new()
	inv_box.custom_minimum_size = Vector2(0, 84)
	box.add_child(inv_box)

	box.add_child(HSeparator.new())
	tower_title = _wrap_label("", 16)
	box.add_child(tower_title)
	slot_box = HBoxContainer.new()
	slot_box.custom_minimum_size = Vector2(0, 44)
	box.add_child(slot_box)
	info_label = _wrap_label("", 13)
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(info_label)
	sell_btn = Button.new()
	sell_btn.pressed.connect(_sell_selected)
	box.add_child(sell_btn)

	toast_label = _label("", 20)
	toast_label.position = Vector2(0, 14)
	toast_label.size = Vector2(PANEL_X, 30)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 6)
	toast_label.modulate.a = 0.0
	ui.add_child(toast_label)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _wrap_label(text: String, size: int) -> Label:
	var l := _label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(120, 0)
	return l


func _elem_button(e: String, size: float = 40.0) -> Button:
	var b := Button.new()
	b.icon = Data.tex("elem_" + e)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = "%s：%s" % [Data.ELEM[e]["name"], Data.FUSIONS[e]["name"]]
	var col: Color = Data.ELEM[e]["color"]
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r, col.g, col.b, 0.35 if state == "hover" else 0.0)
		sb.set_corner_radius_all(int(size / 2.0))
		sb.set_content_margin_all(1)
		b.add_theme_stylebox_override(state, sb)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	return b


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _toast(text: String) -> void:
	toast_label.text = text
	toast_t = 3.0


func _start_bgm() -> void:
	bgm = AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = load("res://assets/audio/bgm.ogg")
	stream.loop = true
	bgm.stream = stream
	bgm.volume_db = -8.0
	bgm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bgm)
	if Data.music_on and not autotest:
		bgm.play()


func _toggle_music() -> void:
	Data.set_music(not Data.music_on)
	if Data.music_on:
		bgm.play()
	else:
		bgm.stop()
	_update_music_btn()


func _update_music_btn() -> void:
	music_btn.text = "音樂 開 [M]" if Data.music_on else "音樂 關 [M]"


func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % 3
	Engine.time_scale = [1.0, 2.0, 3.0][speed_idx]
	speed_btn.text = "速度 %dx" % (speed_idx + 1)


func _refresh_all() -> void:
	stats_label.text = "波次 %d/%d    生命 %d    金幣 %d" % [wave, TOTAL_WAVES, lives, gold]
	for k in build_btns.keys():
		build_btns[k].set_pressed_no_signal(build_mode == k)
	if build_mode != "":
		hint_label.text = "%s：%s\n左鍵放置（Shift 連續）、右鍵取消" % [Data.TOWERS[build_mode]["name"], Data.TOWERS[build_mode]["desc"]]
	else:
		hint_label.text = "選擇塔種後點地圖建造；點已建的塔可配置元素。"
	wave_btn.disabled = wave_active
	if wave_active:
		wave_btn.text = "第 %d 波進行中…" % wave
	else:
		var left := DRAFT_EVERY - (wave % DRAFT_EVERY)
		wave_btn.text = "開始第 %d 波 [Space]\n（再守 %d 波抽元素）" % [wave + 1, left]

	_clear(inv_box)
	if inventory.is_empty():
		var empty := _wrap_label("（空）每守住 %d 波可三選一抽取元素" % DRAFT_EVERY, 13)
		empty.custom_minimum_size = Vector2(250, 0)
		empty.modulate = Color(1, 1, 1, 0.5)
		inv_box.add_child(empty)
	for i in inventory.size():
		var b := _elem_button(inventory[i])
		b.pressed.connect(_insert_element.bind(i))
		b.mouse_entered.connect(_preview_insert.bind(inventory[i]))
		b.mouse_exited.connect(_refresh_tower_panel)
		inv_box.add_child(b)
	_refresh_tower_panel()


func _refresh_tower_panel() -> void:
	_clear(slot_box)
	if selected == null or not is_instance_valid(selected):
		selected = null
		tower_title.text = "未選擇塔"
		info_label.text = "每座塔有 3 個元素槽位。放入不同元素不是效果並存，而是融合成全新的能力；同元素重複則強化等級。"
		sell_btn.visible = false
		return
	tower_title.text = "%s — %s" % [selected.def["name"], Data.fusion_title(selected.elems)]
	tower_title.add_theme_color_override("font_color", selected.color.lightened(0.3))
	for i in Data.MAX_SLOTS:
		if i < selected.elems.size():
			var b := _elem_button(selected.elems[i], 44.0)
			b.tooltip_text = "點擊取回背包"
			b.pressed.connect(_remove_element.bind(i))
			slot_box.add_child(b)
		else:
			var e := Button.new()
			e.text = "空"
			e.disabled = true
			e.custom_minimum_size = Vector2(44, 44)
			slot_box.add_child(e)
	if selected.fusion.is_empty():
		info_label.text = "%s\n\n尚未放入元素：點背包中的元素放入槽位。" % selected.def["desc"]
	else:
		info_label.text = "【%s】%s\n\n%s\n點槽位可取回元素。" % [
			Data.elem_names(Data.key_of(selected.elems)), selected.fusion["desc"], selected.def["desc"]]
	sell_btn.visible = true
	sell_btn.text = "拆除（退 $%d，元素歸還）" % int(int(selected.def["cost"]) * SELL_RATE)


## 動態合成預覽：滑鼠停在背包元素上時，顯示放入所選塔後會變成什麼
func _preview_insert(e: String) -> void:
	if selected == null or not is_instance_valid(selected):
		info_label.text = "先點選一座塔，就能預覽放入【%s】後的合成結果。" % Data.ELEM[e]["name"]
		return
	if selected.elems.size() >= Data.MAX_SLOTS:
		info_label.text = "這座塔的槽位已滿。"
		return
	var next: Array = selected.elems.duplicate()
	next.append(e)
	var f := Data.get_fusion(next)
	var key := Data.key_of(next)
	var is_new := "（新發現！）" if not Data.unlocked.has(key) else ""
	info_label.text = "裝備後將合成：\n【%s】%s\n\n%s" % [Data.fusion_title(next), is_new, f["desc"]]


# ── 覆蓋層（標題 / 抽卡 / 圖鑑 / 結算）──

func _open_overlay(alpha: float) -> ColorRect:
	var ov := ColorRect.new()
	ov.color = Color(0.03, 0.04, 0.06, alpha)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(ov)
	overlays.append(ov)
	get_tree().paused = true
	return ov


func _close_overlay(ov: Control) -> void:
	overlays.erase(ov)
	ov.queue_free()
	get_tree().paused = not overlays.is_empty()


func _center_box(ov: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 48)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _open_title() -> void:
	var ov := _open_overlay(0.96)
	var box := _center_box(ov)
	var t := _label("首塔 TD", 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := _label("元素融合塔防 ── 水・火・木・雷・土", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)
	box.add_child(sub)
	var start := _big_button("開始遊戲")
	start.pressed.connect(func():
		_close_overlay(ov)
		_open_draft())
	box.add_child(start)
	var codex := _big_button("元素合成手冊（%d/%d）" % [Data.unlocked.size(), Data.FUSIONS.size()])
	codex.pressed.connect(_open_codex)
	box.add_child(codex)


func _open_draft() -> void:
	var choices: Array = Array(Data.ELEMENTS).duplicate()
	choices.shuffle()
	choices.resize(3)
	if autotest:
		inventory.append(choices[0])
		_start_wave.call_deferred()
		return
	var ov := _open_overlay(0.8)
	var box := _center_box(ov)
	var t := _label("抽取元素 ── 三選一", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	for e in choices:
		row.add_child(_draft_card(e, ov))


func _draft_card(e: String, ov: Control) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c212b")
	sb.border_color = Data.ELEM[e]["color"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	card.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var icon := _elem_button(e, 72.0)
	icon.disabled = true
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var single: Dictionary = Data.FUSIONS[e]
	var name_l := _label("單系：%s" % single["name"], 18)
	name_l.add_theme_color_override("font_color", Data.ELEM[e]["color"])
	box.add_child(name_l)
	box.add_child(_wrap_label(single["desc"], 13))
	box.add_child(HSeparator.new())

	# 動態合成預覽：掃描目前所有塔的槽位，列出選這張卡能合成什麼
	var lines: Array[String] = []
	var seen := {}
	for t in towers:
		if t.elems.is_empty() or t.elems.size() >= Data.MAX_SLOTS:
			continue
		var next: Array = t.elems.duplicate()
		next.append(e)
		var title := Data.fusion_title(next)
		var sig := "%s|%s" % [Data.key_of(t.elems), title]
		if seen.has(sig):
			continue
		seen[sig] = true
		var star := " ★新" if not Data.unlocked.has(Data.key_of(next)) else ""
		lines.append("%s[%s] → 【%s】%s" % [t.def["name"], Data.elem_names(Data.key_of(t.elems)), title, star])
	var pv_text := "放入現有的塔後將合成：\n" + "\n".join(lines.slice(0, 6))
	if lines.is_empty():
		pv_text = "放入空的塔即獲得單系能力；\n與其他元素放在同一座塔會融合出新能力。"
	var pv := _wrap_label(pv_text, 13)
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_theme_color_override("font_color", Color("ffe28a"))
	box.add_child(pv)

	var pick := _big_button("選擇【%s】" % Data.ELEM[e]["name"])
	pick.custom_minimum_size = Vector2(0, 44)
	pick.pressed.connect(func():
		inventory.append(e)
		_close_overlay(ov)
		_refresh_all())
	box.add_child(pick)
	return card


func _open_codex() -> void:
	for o in overlays:
		if o.has_meta("codex"):
			return
	var ov := _open_overlay(0.92)
	ov.set_meta("codex", true)
	var box := _center_box(ov)
	var t := _label("元素合成手冊  %d / %d" % [Data.unlocked.size(), Data.FUSIONS.size()], 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 520)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for key in Data.FUSIONS.keys():
		var f: Dictionary = Data.FUSIONS[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		var parts: PackedStringArray = key.split("+")
		for i in 3:
			if i < parts.size():
				var chip := _elem_button(parts[i], 30.0)
				chip.disabled = true
				row.add_child(chip)
			else:
				var pad := Control.new()
				pad.custom_minimum_size = Vector2(30, 30)
				row.add_child(pad)
		var known: bool = Data.unlocked.has(key)
		var name_l := _label(f["name"] if known else "？？？", 17)
		name_l.custom_minimum_size = Vector2(150, 0)
		name_l.add_theme_color_override("font_color", f["color"] if known else Color(1, 1, 1, 0.35))
		row.add_child(name_l)
		var desc := _wrap_label(f["desc"] if known else "尚未發現。把這些元素放進同一座塔試試看。", 13)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.modulate = Color(1, 1, 1, 0.85 if known else 0.4)
		row.add_child(desc)
	var close := _big_button("關閉")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_overlay.bind(ov))
	box.add_child(close)


func _finish(win: bool) -> void:
	finished = true
	if autotest:
		print("[bot] END win=%s wave=%d lives=%d" % [win, wave, lives])
		get_tree().quit()
		return
	var ov := _open_overlay(0.85)
	var box := _center_box(ov)
	var t := _label("守城成功！" if win else "城堡陷落…", 56)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := _label("抵達第 %d 波　圖鑑 %d/%d" % [wave, Data.unlocked.size(), Data.FUSIONS.size()], 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var again := _big_button("再來一局")
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene())
	box.add_child(again)


# ══════════════════════════ 自動測試（godot --headless -- --autotest）══════════════════════════
# 蓋 9 座塔（三種各 3 座），每波換一批元素組合，把 25 種融合 × 3 種塔全部跑過一遍。

func _autotest_begin() -> void:
	Data.save_enabled = false
	if bot:
		if OS.has_feature("web"):
			_cycle_speed()
			_cycle_speed()
		_open_draft()
		return
	gold = 99999
	lives = 999999
	var cells: Array[Vector2i] = [
		Vector2i(12, 3), Vector2i(13, 3), Vector2i(14, 3), Vector2i(15, 3), Vector2i(16, 3),
		Vector2i(17, 3), Vector2i(13, 1), Vector2i(15, 1), Vector2i(17, 1),
	]
	for i in cells.size():
		var built := _try_build(Data.TOWER_ORDER[i % 3], cells[i])  # assert 在 release 匯出會被移除，不可把呼叫放在裡面
		assert(built)
	_open_draft()


func _autotest_assign() -> void:
	var keys: Array = Data.FUSIONS.keys()
	for i in towers.size():
		var key: String = keys[((wave - 1) * 3 + i / 3) % keys.size()]
		var elems: Array = Array(key.split("+"))
		if wave > 9:
			elems.append(elems[0])  # 測試強化等級
			elems.resize(mini(elems.size(), Data.MAX_SLOTS))
		towers[i].elems = elems
		_tower_changed(towers[i])
	print("[autotest] wave %d  towers[0..2]=%s  kills so far gold=%d" % [wave, Data.fusion_title(towers[0].elems), gold])
	if wave > 10 and not OS.has_feature("web"):
		print("[autotest] DONE unlocked=%d/%d" % [Data.unlocked.size(), Data.FUSIONS.size()])
		get_tree().quit()


# 平衡用的簡單機器人（godot --headless -- --bot）：有錢就蓋塔、抽到元素就塞進第一個有空位的塔。
const BOT_CELLS: Array[Vector2i] = [
	Vector2i(4, 3), Vector2i(6, 6), Vector2i(10, 6), Vector2i(12, 3), Vector2i(17, 3), Vector2i(17, 9),
	Vector2i(10, 9), Vector2i(10, 11), Vector2i(4, 11), Vector2i(4, 14), Vector2i(6, 3), Vector2i(12, 6),
	Vector2i(16, 9), Vector2i(8, 14), Vector2i(12, 14), Vector2i(4, 6), Vector2i(10, 3), Vector2i(14, 11),
	Vector2i(7, 9), Vector2i(16, 3),
]


func _bot_step() -> void:
	if bot_i < BOT_CELLS.size():
		var k: String = Data.TOWER_ORDER[bot_i % 3]
		if gold >= int(Data.TOWERS[k]["cost"]) and _try_build(k, BOT_CELLS[bot_i]):
			bot_i += 1
	while not inventory.is_empty():
		var placed := false
		for t in towers:
			if t.elems.size() < Data.MAX_SLOTS:
				t.elems.append(inventory.pop_back())
				_tower_changed(t)
				placed = true
				break
		if not placed:
			break
