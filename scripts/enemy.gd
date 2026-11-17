extends Node2D
## 敵人：沿路徑前進（offset = 已走距離），身上帶有狀態表 st。

const KINDS := {
	"normal": {"hp": 1.0, "speed": 65.0, "gold": 4, "tenacity": 1.0, "radius": 10.0, "leak": 1, "color": Color("c9505a")},
	"fast": {"hp": 0.6, "speed": 115.0, "gold": 4, "tenacity": 1.0, "radius": 8.0, "leak": 1, "color": Color("e8a03a")},
	"tank": {"hp": 3.0, "speed": 42.0, "gold": 9, "tenacity": 0.7, "radius": 14.0, "leak": 2, "color": Color("7a5a9a")},
	"boss": {"hp": 14.0, "speed": 36.0, "gold": 60, "tenacity": 0.35, "radius": 20.0, "leak": 5, "color": Color("8a1f3a")},
}
const HARD_CC: Array[String] = ["stun", "root"]
const DOTS: Array[String] = ["burn", "poison", "wildfire"]
const STATUS_COLORS := {
	"wet": Color("4aa8ff"), "burn": Color("ff6a3d"), "poison": Color("5fce6a"), "slow": Color("9ad0ff"),
	"stun": Color("f6d743"), "root": Color("2fa37a"), "vuln": Color("b98a5a"), "mark": Color("b6e04a"),
	"wildfire": Color("ff9a2e"), "bomb": Color("ff3a6a"), "bounty": Color("ffd700"),
}

var game
var kind := "normal"
var max_hp := 10.0
var hp := 10.0
var speed := 60.0
var gold := 5
var tenacity := 1.0  # 控場抗性：硬控時間與位移的倍率
var radius := 10.0
var leak := 1
var color := Color.WHITE
var offset := 0.0
var st := {}
var dead := false
var dot_t := 0.0
var tex: Texture2D
var face := 1.0
var anim := 0.0
var knock := Vector2.ZERO  # 擊退 / 牽引的視覺位移，平滑歸零
var hurt := 0.0  # 受擊閃白


func setup(g, k: String, wave: int) -> void:
	game = g
	kind = k
	var d: Dictionary = KINDS[k]
	var base := 28.0 + 12.0 * wave + 2.2 * wave * wave
	max_hp = base * float(d["hp"])
	hp = max_hp
	speed = d["speed"]
	gold = d["gold"]
	tenacity = d["tenacity"]
	radius = d["radius"]
	leak = d["leak"]
	color = d["color"]
	tex = Data.tex("enemy_" + k)
	anim = randf() * TAU
	position = game.curve.sample_baked(0.0)


func add_status(s: String, dur: float, v: float = 0.0, p: float = 1.0, gen: int = 0) -> void:
	if dead:
		return
	if s in HARD_CC:
		dur *= tenacity
	if st.has(s):
		var cur: Dictionary = st[s]
		cur["t"] = maxf(cur["t"], dur)
		cur["v"] = maxf(cur["v"], v)
		cur["p"] = maxf(cur["p"], p)
	else:
		st[s] = {"t": dur, "v": v, "p": p, "g": gen, "max": dur}
		game.fx_status(self, s)


func take_damage(amount: float, dmg_kind: String = "phys") -> void:
	if dead or amount <= 0.0:
		return
	var mult := 1.0
	if st.has("vuln"):
		mult += float(st["vuln"]["v"])
	if dmg_kind == "thunder" and st.has("wet"):
		mult += 0.3
	hp -= amount * mult
	hurt = 0.12
	if hp <= 0.0:
		die()


## 沿路徑位移（正 = 往終點，負 = 擊退）
func push(d: float) -> void:
	if dead:
		return
	var old := position
	offset = clampf(offset + d * tenacity, 0.0, game.path_len - 1.0)
	position = game.curve.sample_baked(offset)
	knock += old - position


func die() -> void:
	if dead:
		return
	dead = true
	game.on_enemy_died(self)
	queue_free()


func _process(delta: float) -> void:
	if dead:
		return
	var ended: Array = []
	for k in st.keys():
		st[k]["t"] -= delta
		if st[k]["t"] <= 0.0:
			ended.append(k)
	for k in ended:
		var d: Dictionary = st[k]
		st.erase(k)
		game.on_status_end(self, k, d)
		if dead:
			return

	dot_t += delta
	if dot_t >= 0.5:
		dot_t -= 0.5
		var dps := 0.0
		for k in DOTS:
			if st.has(k):
				dps += float(st[k]["v"])
		if st.has("wildfire"):
			game.spread_wildfire(self)
		if dps > 0.0:
			take_damage(dps * 0.5, "dot")
			if dead:
				return

	if not (st.has("stun") or st.has("root")):
		var s := speed
		if st.has("slow"):
			s *= 1.0 - float(st["slow"]["v"])
		offset += s * delta
		if offset >= game.path_len:
			dead = true
			game.on_leak(self)
			queue_free()
			return
	knock = knock.lerp(Vector2.ZERO, 1.0 - exp(-delta * 12.0))
	hurt = maxf(hurt - delta, 0.0)
	var np: Vector2 = game.curve.sample_baked(offset)
	if absf(np.x - position.x) > 0.01:
		face = signf(np.x - position.x)
	position = np
	if not (st.has("stun") or st.has("root")):
		anim += delta * (4.0 + speed * 0.08)
	queue_redraw()


func _draw() -> void:
	var size := radius * 3.4
	# 走路時的彈跳擠壓
	var sq := 1.0 + 0.07 * sin(anim)
	var hop := absf(sin(anim * 0.5)) * radius * 0.18
	var tint := Color.WHITE
	if st.has("burn") or st.has("wildfire"):
		tint = tint.lerp(Color("ff8a3a"), 0.4)
	if st.has("poison"):
		tint = tint.lerp(Color("6fdc6f"), 0.4)
	if st.has("wet"):
		tint = tint.lerp(Color("7cc4ff"), 0.35)
	if st.has("stun"):
		tint = tint.darkened(0.25)
	if st.has("slow"):
		tint = tint.lerp(Color("bfe4ff"), 0.3)
	if hurt > 0.0:
		tint = tint.lerp(Color(2.0, 2.0, 2.0), hurt / 0.12 * 0.5)
	draw_set_transform(knock, 0.0, Vector2.ONE)
	var now := Time.get_ticks_msec() / 1000.0
	# 緩速：腳下的冰藍漣漪
	if st.has("slow"):
		var sr := radius * (1.3 + 0.25 * fposmod(now * 1.5, 1.0))
		_ellipse_arc(Vector2(0, radius * 0.55), sr, Color(0.7, 0.88, 1.0, 0.45 * (1.0 - fposmod(now * 1.5, 1.0))))
	if st.has("bounty"):
		draw_texture_rect(Data.tex("fx_glow"), Rect2(-size * 0.7, -size * 0.7, size * 1.4, size * 1.4), false, Color(1.0, 0.84, 0.0, 0.45))
	# 被擊退時身體往後仰
	var lean := clampf(knock.x * 0.02, -0.35, 0.35)
	draw_set_transform(knock + Vector2(0, -radius * 0.25 - hop), lean, Vector2(face * sq, 2.0 - sq))
	draw_texture_rect(tex, Rect2(-size / 2.0, -size / 2.0, size, size), false, tint)
	draw_set_transform(knock, 0.0, Vector2.ONE)

	# 碎甲：身上的裂痕
	if st.has("vuln"):
		var cr := radius * 1.1
		draw_texture_rect(Data.tex("fx_crack"), Rect2(-cr, -cr - radius * 0.2, cr * 2.0, cr * 2.0), false, Color(0.25, 0.12, 0.05, 0.8))
	if st.has("root"):
		# 藤蔓由下往上纏繞長出
		var rd: Dictionary = st["root"]
		var grow := clampf((float(rd["max"]) - float(rd["t"])) / 0.18, 0.0, 1.0) if rd.has("max") else 1.0
		var h := radius * 2.0 * grow
		draw_texture_rect(Data.tex("zone_vines"), Rect2(-radius * 1.3, radius * 1.4 - h, radius * 2.6, h), false, Color(1, 1, 1, 0.9))
	if st.has("burn") or st.has("wildfire"):
		var f := radius * (0.9 + 0.25 * sin(anim * 3.0))
		draw_texture_rect(Data.tex("fx_glow"), Rect2(-f, -radius - f, f * 2.0, f * 2.0), false, Color(1.0, 0.5, 0.1, 0.55))
		# 竄動的火舌
		var fc := Color("ffb040") if st.has("wildfire") else Color("ff7a30")
		for i in 3:
			var ph := now * 4.0 + i * 2.1
			var fh := radius * (1.1 + 0.35 * sin(ph * 2.3))
			var fx := (i - 1) * radius * 0.55 + sin(ph) * 2.0
			draw_texture_rect(Data.tex("fx_flame"), Rect2(fx - fh * 0.4, -radius * 0.6 - fh, fh * 0.8, fh), false, Color(fc, 0.85))
	# 中毒：冒出綠色泡泡
	if st.has("poison"):
		for i in 2:
			var ph := fposmod(now * 0.9 + i * 0.5, 1.0)
			var bx := (i - 0.5) * radius * 0.9
			var by := -radius * 0.4 - ph * radius * 1.6
			var bs := 4.0 + 3.0 * ph
			draw_texture_rect(Data.tex("fx_bubble"), Rect2(bx - bs, by - bs, bs * 2.0, bs * 2.0), false, Color(0.55, 0.95, 0.4, 1.0 - ph))
	# 潮濕：往下滴的水珠
	if st.has("wet"):
		for i in 2:
			var ph := fposmod(now * 1.3 + i * 0.47, 1.0)
			var dx := (i - 0.5) * radius * 1.2
			var dy := -radius * 0.2 + ph * radius * 1.2
			draw_texture_rect(Data.tex("fx_drop"), Rect2(dx - 3, dy - 4, 6, 8), false, Color(0.6, 0.85, 1.0, 1.0 - ph))
	if st.has("mark"):
		var mr := radius + 7.0
		draw_set_transform(knock, anim * 0.5, Vector2.ONE)
		draw_texture_rect(Data.tex("zone_warn"), Rect2(-mr, -mr, mr * 2.0, mr * 2.0), false, STATUS_COLORS["mark"])
		draw_set_transform(knock, 0.0, Vector2.ONE)
	if st.has("bomb"):
		var pulse := 0.5 + 0.5 * absf(sin(Time.get_ticks_msec() / 70.0))
		var br := radius * (1.6 + pulse)
		draw_texture_rect(Data.tex("fx_glow"), Rect2(-br, -br, br * 2.0, br * 2.0), false, Color(1.0, 0.2, 0.35, 0.4 + 0.4 * pulse))
	if st.has("stun"):
		for i in 3:
			var a := Time.get_ticks_msec() / 200.0 + i * TAU / 3.0
			var sp := Vector2(cos(a) * radius * 0.9, -radius * 1.5 + sin(a) * 3.0)
			draw_texture_rect(Data.tex("fx_spark"), Rect2(sp.x - 6, sp.y - 6, 12, 12), false, STATUS_COLORS["stun"])

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 血條
	var w := maxf(radius * 2.4, 22.0)
	var top := -radius * 1.9 - 8.0
	draw_rect(Rect2(-w / 2.0 - 1.0, top - 1.0, w + 2.0, 6.0), Color(0, 0, 0, 0.75))
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-w / 2.0, top, w * ratio, 4.0), Color("e0483a").lerp(Color("6ee06e"), ratio))
	# 狀態小點
	var i := 0
	for k in st.keys():
		if STATUS_COLORS.has(k):
			draw_circle(Vector2(-w / 2.0 + 3.0 + i * 6.0, top - 6.0), 2.5, STATUS_COLORS[k])
			i += 1


func _ellipse_arc(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.45))
	draw_polyline(pts, col, 2.0)
