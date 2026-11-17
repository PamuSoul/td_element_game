extends Node2D
## 短暫的視覺特效。每種 mode 是一個「動畫原件」，main.gd 的技能動畫會把多個原件組合起來。
##   ring / flash      衝擊波圓環、閃光
##   bolt              閃電（points = 折線）
##   text              飄字
##   ripple            多圈漣漪向外擴散
##   implode           光圈向中心收縮 + 漩渦（牽引、聚能）
##   rune              魔法陣：彈出、旋轉、淡出（施法）
##   column            由地面噴發的光柱 / 水柱 / 火柱
##   spikes            一圈尖刺從地面竄出再縮回（荊棘、岩刺）
##   crack             地面裂痕（一般混色）
##   tether            從 points[0] 長向 points[1] 的波動藤蔓 / 電纜
##   shock             由中心向外亂竄的電弧
##   streaks           沿 dir 方向飛過的風切線（擊退）
##   sprite            單張貼圖的縮放 / 旋轉 / 淡出（tex, s0 → s1, spin）

var mode := "ring"
var life := 0.0
var dur := 0.3
var color := Color.WHITE
var radius := 30.0
var points := PackedVector2Array()
var text := ""
var count := 6
var additive := true
var tex := ""
var s0 := 0.5
var s1 := 1.0
var spin := 0.0
var dir := Vector2.RIGHT
var delay := 0.0
var _seed := 0
var _arcs: Array = []
var _arc_t := 0.0


func _ready() -> void:
	if mode == "text" or mode == "crack":
		additive = false
	if additive:
		material = Data.add_mat
	_seed = randi()
	if mode == "spikes":
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		points = PackedVector2Array()
		for i in count:
			var a := TAU * i / count + rng.randf_range(-0.3, 0.3)
			var d := radius * rng.randf_range(0.25, 0.85)
			points.append(Vector2(cos(a) * d, sin(a) * d * 0.75))
		points.append(Vector2.ZERO)
		var arr := Array(points)
		arr.sort_custom(func(a, b): return a.y < b.y)
		points = PackedVector2Array(arr)
	if delay > 0.0:
		visible = false


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		if delay <= 0.0:
			visible = true
		return
	life += delta
	if life >= dur:
		queue_free()
		return
	if mode == "text":
		position.y -= 30.0 * delta
	if mode == "shock":
		_arc_t -= delta
		if _arc_t <= 0.0:
			_arc_t = 0.05
			_make_arcs()
	queue_redraw()


func _make_arcs() -> void:
	_arcs.clear()
	for i in count:
		var a := randf() * TAU
		var len := radius * randf_range(0.55, 1.0)
		var pts := PackedVector2Array([Vector2.ZERO])
		var segs := 5
		for k in range(1, segs + 1):
			var base := Vector2(cos(a), sin(a)) * len * k / segs
			pts.append(base + Vector2(-sin(a), cos(a)) * randf_range(-len * 0.12, len * 0.12))
		_arcs.append(pts)


static func ease_out_back(x: float) -> float:
	var c := 1.9
	x = clampf(x, 0.0, 1.0)
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


func _tex_rect(t: Texture2D, r: float, col: Color, rot: float = 0.0, sc := Vector2.ONE) -> void:
	draw_set_transform(Vector2.ZERO, rot, sc)
	draw_texture_rect(t, Rect2(-r, -r, r * 2.0, r * 2.0), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var t := life / dur
	var a := 1.0 - t
	var c := Color(color.r, color.g, color.b, 1.0)
	match mode:
		"ring":
			var r := radius * (0.35 + 0.65 * sqrt(t))
			_tex_rect(Data.tex("fx_ring"), r, Color(c, a))
		"flash":
			var r := radius * (0.5 + 0.7 * t)
			_tex_rect(Data.tex("fx_glow"), r, Color(c, a * a))
		"bolt":
			if points.size() >= 2:
				draw_polyline(points, Color(c, a * 0.35), 9.0)
				draw_polyline(points, Color(c, a), 3.5)
				draw_polyline(points, Color(1, 1, 1, a), 1.5)
				var g := 22.0 * a
				var e := points[points.size() - 1]
				draw_texture_rect(Data.tex("fx_spark"), Rect2(e.x - g, e.y - g, g * 2.0, g * 2.0), false, Color(c, a))
		"text":
			draw_string_outline(Data.font, Vector2(-60, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, 4, Color(0, 0, 0, a))
			draw_string(Data.font, Vector2(-60, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(c, a))
		"ripple":
			for k in count:
				var tk := clampf((t - k * 0.18) / 0.62, 0.0, 1.0)
				if tk <= 0.0 or tk >= 1.0:
					continue
				var r := radius * (0.15 + 0.85 * sqrt(tk))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.72))
				draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(c, (1.0 - tk) * 0.9), 3.0 * (1.0 - tk) + 1.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"implode":
			for k in 3:
				var tk := fposmod(t * 1.6 + k / 3.0, 1.0)
				var r := radius * (1.0 - tk)
				_tex_rect(Data.tex("fx_ring"), maxf(r, 2.0), Color(c, a * tk))
			_tex_rect(Data.tex("zone_vortex"), radius * 0.7 * (1.0 - 0.5 * t), Color(c, a * 0.8), -life * 9.0)
			_tex_rect(Data.tex("fx_glow"), radius * 0.35 * (0.4 + t), Color(c, a))
		"rune":
			var g := ease_out_back(t / 0.25)
			var fade := clampf((1.0 - t) / 0.45, 0.0, 1.0)
			_tex_rect(Data.tex("fx_glow"), radius * 1.15 * g, Color(c, 0.35 * fade))
			_tex_rect(Data.tex("fx_rune"), radius * g, Color(c, fade), life * 1.6, Vector2(1.0, 0.62))
			_tex_rect(Data.tex("fx_rune"), radius * 0.55 * g, Color(1, 1, 1, fade * 0.8), -life * 2.6, Vector2(1.0, 0.62))
		"column":
			# 0~25% 噴發、25~65% 維持、之後縮回
			var h: float
			if t < 0.25:
				h = ease_out_back(t / 0.25)
			elif t < 0.65:
				h = 1.0 + 0.05 * sin(life * 40.0)
			else:
				h = 1.0 - (t - 0.65) / 0.35
			var hh := radius * 2.6 * h
			var w := radius * (0.7 + 0.08 * sin(life * 33.0)) * (0.6 + 0.4 * h)
			var fade := clampf((1.0 - t) / 0.3, 0.0, 1.0)
			draw_texture_rect(Data.tex("fx_column"), Rect2(-w / 2.0, -hh, w, hh), false, Color(c, 0.9 * fade))
			draw_texture_rect(Data.tex("fx_column"), Rect2(-w / 4.0, -hh * 0.95, w / 2.0, hh * 0.95), false, Color(1, 1, 1, 0.7 * fade))
			var top := radius * 0.55 * (0.8 + 0.3 * sin(life * 25.0))
			draw_texture_rect(Data.tex("fx_glow"), Rect2(-top, -hh - top * 0.6, top * 2.0, top * 2.0), false, Color(c, fade))
			_tex_rect(Data.tex("fx_glow"), radius * 0.9, Color(c, 0.5 * fade), 0.0, Vector2(1.0, 0.5))
		"spikes":
			var sp := Data.tex("fx_spike")
			for i in points.size():
				var p := points[i]
				var lag := p.length() / maxf(radius, 1.0) * 0.18
				var tk := clampf((t - lag) / 0.22, 0.0, 1.0)
				var rise := ease_out_back(tk)
				if t > 0.7:
					rise *= clampf(1.0 - (t - 0.7) / 0.3, 0.0, 1.0)
				if rise <= 0.0:
					continue
				var hgt := (22.0 if p != Vector2.ZERO else 30.0) * radius / 60.0 * rise
				var wid := hgt * 0.42
				draw_texture_rect(sp, Rect2(p.x - wid / 2.0, p.y - hgt, wid, hgt), false, Color(c, 1.0))
		"crack":
			var fade := clampf((1.0 - t) / 0.4, 0.0, 1.0)
			var g := minf(1.0, t / 0.08)
			_tex_rect(Data.tex("fx_crack"), radius * g, Color(c, 0.9 * fade), float(_seed % 628) / 100.0, Vector2(1.0, 0.75))
		"tether":
			if points.size() >= 2:
				var grow := minf(1.0, t / 0.35)
				var from := points[0]
				var to := points[1]
				var pts := PackedVector2Array()
				var n := 14
				var nrm := (to - from).orthogonal().normalized()
				for k in n + 1:
					var u := float(k) / n * grow
					var wave := sin(u * 9.0 + life * 18.0 + float(_seed % 7)) * 7.0 * sin(u * PI)
					pts.append(from.lerp(to, u) + nrm * wave)
				draw_polyline(pts, Color(c, a * 0.4), 8.0)
				draw_polyline(pts, Color(c, a), 3.0)
				draw_polyline(pts, Color(1, 1, 1, a * 0.8), 1.2)
				var tip := pts[pts.size() - 1]
				var g := 12.0 * a
				draw_texture_rect(Data.tex("fx_spark"), Rect2(tip.x - g, tip.y - g, g * 2.0, g * 2.0), false, Color(c, a))
		"shock":
			for pts in _arcs:
				draw_polyline(pts, Color(c, a * 0.4), 6.0)
				draw_polyline(pts, Color(c, a), 2.2)
				draw_polyline(pts, Color(1, 1, 1, a), 1.0)
			_tex_rect(Data.tex("fx_glow"), radius * 0.45, Color(c, a * 0.8))
		"streaks":
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed
			var ang := dir.angle()
			for k in count:
				var off := Vector2(rng.randf_range(-10, 10), rng.randf_range(-radius * 0.5, radius * 0.5)).rotated(ang)
				var travel := dir * (radius * 1.6 * t + rng.randf_range(0, 10))
				var len := rng.randf_range(18.0, 34.0) * (1.0 - t * 0.5)
				draw_set_transform(off + travel, ang, Vector2.ONE)
				draw_texture_rect(Data.tex("fx_streak"), Rect2(-len, -3, len, 6), false, Color(c, a * 0.85))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"sprite":
			var s := lerpf(s0, s1, ease_out_back(minf(1.0, t / 0.4)) if s1 > s0 else t)
			var fade := clampf((1.0 - t) / 0.5, 0.0, 1.0)
			_tex_rect(Data.tex(tex), radius * s, Color(c, fade), spin * life)
