extends Node
## 全域資料表（Autoload: Data）
## - 五元素、三種基礎塔
## - 元素融合表 FUSIONS：每個組合 = 一組「效果模組」的資料，不需要為每個組合寫專屬程式
## - 合成圖鑑的解鎖存檔
##
## 效果模組 (t)：
##   status    對目標套用狀態 s（dur 秒, v 數值）
##   dmg       額外傷害（dmg 固定值 / pct 最大生命比例 / speed_scale 依移速加成）
##   knockback 沿路徑擊退 dist
##   pull      沿路徑往落點牽引 dist（有 r 則抓落點半徑內敵人）
##   explode   落點半徑 r 爆炸
##   chain     閃電鏈，彈跳 n 個目標；on = 每次彈跳額外觸發的效果
##   bolts     隨機落雷 n 道
##   zone      在落點生成地形物件 z（tick = 週期效果, end = 消失時效果）
## 任何模組加上 cd 表示該塔的特殊能力冷卻（秒）。
## 動畫：explode 的 style 決定爆炸造型（見 main.fx_explode）；zone 依 art 播放登場動畫（main.fx_zone_intro）；
## domain_art 決定領域塔外觀（storm 雷雲 / forest 樹海 / tree 世界樹）。
## hit = 攻擊命中時觸發；domain = 塔本體每秒對射程內全體觸發。

const ELEMENTS: Array[String] = ["water", "fire", "wood", "thunder", "earth"]
const MAX_SLOTS := 3
const SAVE_PATH := "user://codex.json"
const SETTINGS_PATH := "user://settings.cfg"

var ELEM := {
	"water": {"name": "水", "color": Color("4aa8ff")},
	"fire": {"name": "火", "color": Color("ff6a3d")},
	"wood": {"name": "木", "color": Color("5fce6a")},
	"thunder": {"name": "雷", "color": Color("f6d743")},
	"earth": {"name": "土", "color": Color("b98a5a")},
}

## eff = 每次命中的效果倍率（攻速慢的塔單次效果較強）
var TOWERS := {
	"arrow": {
		"name": "箭塔", "cost": 50, "damage": 12.0, "interval": 0.5, "rng": 150.0, "eff": 1.0,
		"desc": "單體高速射擊。元素效果頻繁套用在單一目標上。",
	},
	"cannon": {
		"name": "大砲", "cost": 80, "damage": 30.0, "interval": 1.6, "rng": 175.0, "eff": 1.8, "splash": 55.0,
		"desc": "範圍濺射、攻速慢。元素效果一次套用在爆炸範圍內全體。",
	},
	"aura": {
		"name": "光環塔", "cost": 70, "damage": 6.0, "interval": 1.0, "rng": 110.0, "eff": 0.8,
		"desc": "每秒脈衝，命中射程內所有敵人。元素效果覆蓋整個光環。",
	},
}
const TOWER_ORDER: Array[String] = ["arrow", "cannon", "aura"]

var FUSIONS := {
	# ───────────── 單系 ─────────────
	"water": {
		"name": "水流衝擊", "color": Color("4aa8ff"),
		"desc": "攻擊附帶小幅擊退與潮濕（潮濕的敵人受到雷擊傷害 +30%）。",
		"hit": [
			{"t": "knockback", "dist": 10.0},
			{"t": "status", "s": "wet", "dur": 3.0},
		],
	},
	"fire": {
		"name": "烈焰灼燒", "color": Color("ff6a3d"),
		"desc": "點燃目標，持續燃燒造成傷害。",
		"hit": [
			{"t": "dmg", "dmg": 4.0},
			{"t": "status", "s": "burn", "dur": 3.0, "v": 10.0},
		],
	},
	"wood": {
		"name": "寄生藤蔓", "color": Color("5fce6a"),
		"desc": "孢子附著於敵人，每秒吸取體力並減緩移動速度。",
		"hit": [
			{"t": "status", "s": "poison", "dur": 4.0, "v": 8.0},
			{"t": "status", "s": "slow", "dur": 2.0, "v": 0.25},
		],
	},
	"thunder": {
		"name": "連鎖電擊", "color": Color("f6d743"),
		"desc": "發出閃電鏈，在最多 3 個目標間彈跳並造成短暫麻痺。",
		"hit": [
			{"t": "chain", "n": 3, "dmg": 8.0, "stun": 0.2},
		],
	},
	"earth": {
		"name": "岩石重擊", "color": Color("b98a5a"),
		"desc": "沉重的岩塊造成額外傷害並碎甲（受到的所有傷害 +25%）。",
		"hit": [
			{"t": "dmg", "dmg": 8.0},
			{"t": "status", "s": "vuln", "dur": 3.0, "v": 0.25},
		],
	},
	# ───────────── 雙系融合 ─────────────
	"water+fire": {
		"name": "蒸氣爆發", "color": Color("d8e6f0"),
		"desc": "落點噴發高溫蒸氣雲，雲中敵人持續燙傷且防禦瓦解（受傷 +35%）。",
		"hit": [{"t": "zone", "cd": 6.0, "z": {
			"label": "蒸氣", "art": "cloud", "r": 80.0, "dur": 3.5, "color": Color("d8e6f0"),
			"tick": [
				{"t": "dmg", "dmg": 5.0},
				{"t": "status", "s": "vuln", "dur": 1.0, "v": 0.35},
			],
		}}],
	},
	"water+wood": {
		"name": "樹木禁錮", "color": Color("2fa37a"),
		"desc": "攻擊落點誕生巨型樹木藤蔓，將範圍內敵群完全定身並阻擋路徑。",
		"hit": [{"t": "zone", "cd": 7.0, "z": {
			"label": "樹牢", "art": "vines", "r": 65.0, "dur": 2.5, "color": Color("2fa37a"),
			"tick": [{"t": "status", "s": "root", "dur": 0.35}],
		}}],
	},
	"water+thunder": {
		"name": "感電水窪", "color": Color("7fd6ff"),
		"desc": "地面留下帶電水域，踏入的敵群持續受到百分比傷害、麻痺與連鎖觸電。",
		"hit": [{"t": "zone", "cd": 6.0, "z": {
			"label": "電窪", "art": "puddle", "r": 75.0, "dur": 5.0, "interval": 0.5, "color": Color("7fd6ff"),
			"tick": [
				{"t": "dmg", "pct": 0.012, "kind": "thunder"},
				{"t": "status", "s": "stun", "dur": 0.12},
				{"t": "status", "s": "wet", "dur": 1.5},
				{"t": "chain", "n": 2, "dmg": 4.0},
			],
		}}],
	},
	"water+earth": {
		"name": "泥沼", "color": Color("7a6a4f"),
		"desc": "地面化為深泥沼，範圍內敵人移動速度大幅降低 60%。",
		"hit": [{"t": "zone", "cd": 6.0, "z": {
			"label": "泥沼", "art": "mud", "r": 85.0, "dur": 6.0, "color": Color("7a6a4f"),
			"tick": [{"t": "status", "s": "slow", "dur": 0.5, "v": 0.6}],
		}}],
	},
	"fire+wood": {
		"name": "野火燎原", "color": Color("ff9a2e"),
		"desc": "點燃會傳染的野火：燃燒中的敵人會把火勢蔓延給身邊的敵人。",
		"hit": [{"t": "status", "s": "wildfire", "dur": 4.0, "v": 12.0}],
	},
	"fire+thunder": {
		"name": "電漿爆裂", "color": Color("ff7ad9"),
		"desc": "命中時引爆電漿球，範圍爆炸並向外放出電弧。",
		"hit": [
			{"t": "explode", "r": 65.0, "dmg": 12.0, "stun": 0.15, "kind": "thunder", "style": "plasma"},
			{"t": "chain", "n": 2, "dmg": 8.0},
		],
	},
	"fire+earth": {
		"name": "熔岩池", "color": Color("ff4a1c"),
		"desc": "落點熔化為岩漿池，站在上面的敵人受到高額持續傷害並被點燃。",
		"hit": [{"t": "zone", "cd": 6.0, "z": {
			"label": "熔岩", "art": "lava", "r": 60.0, "dur": 5.0, "color": Color("ff4a1c"),
			"tick": [
				{"t": "dmg", "dmg": 7.0},
				{"t": "status", "s": "burn", "dur": 2.0, "v": 8.0},
			],
		}}],
	},
	"wood+thunder": {
		"name": "狂暴超導", "color": Color("b6e04a"),
		"desc": "在敵人身上植入「雷木導體」：場上所有雷擊都會額外劈向該目標，導體結束或宿主死亡時觸發木屑爆發。",
		"hit": [
			{"t": "status", "s": "mark", "dur": 5.0},
			{"t": "chain", "n": 2, "dmg": 8.0},
		],
	},
	"wood+earth": {
		"name": "荊棘地刺", "color": Color("8a9a3a"),
		"desc": "地面長出荊棘叢，緩速並持續刺傷；跑得越快的敵人受傷越重。",
		"hit": [{"t": "zone", "cd": 6.0, "z": {
			"label": "荊棘", "art": "thorns", "r": 75.0, "dur": 6.0, "color": Color("8a9a3a"),
			"tick": [
				{"t": "dmg", "dmg": 3.0, "speed_scale": true},
				{"t": "status", "s": "slow", "dur": 0.5, "v": 0.3},
				{"t": "status", "s": "poison", "dur": 2.0, "v": 6.0},
			],
		}}],
	},
	"thunder+earth": {
		"name": "磁暴震盪", "color": Color("b9a0ff"),
		"desc": "落點產生強磁場，把周圍敵人沿路吸向中心並震暈。",
		"hit": [
			{"t": "pull", "cd": 4.0, "r": 110.0, "dist": 70.0},
			{"t": "explode", "cd": 4.0, "r": 110.0, "dmg": 10.0, "stun": 0.5, "kind": "thunder", "style": "magnet"},
		],
	},
	# ───────────── 三系融合（終極） ─────────────
	"water+fire+wood": {
		"name": "瘴氣雨林", "color": Color("9acb6a"),
		"desc": "召喚悶熱的毒瘴雨林：大範圍內敵人同時中毒、燃燒並被濕熱拖慢。",
		"hit": [{"t": "zone", "cd": 7.0, "z": {
			"label": "瘴林", "art": "cloud", "r": 100.0, "dur": 5.0, "color": Color("9acb6a"),
			"tick": [
				{"t": "status", "s": "poison", "dur": 2.0, "v": 10.0},
				{"t": "status", "s": "burn", "dur": 2.0, "v": 8.0},
				{"t": "status", "s": "slow", "dur": 0.5, "v": 0.4},
			],
		}}],
	},
	"water+fire+thunder": {
		"name": "雷暴風雲", "color": Color("9fb4ff"), "domain_art": "storm",
		"desc": "塔上空凝結雷雨雲：每秒對射程內隨機 3 名敵人降下落雷，並讓全體潮濕。",
		"hit": [{"t": "status", "s": "wet", "dur": 3.0}],
		"domain": [
			{"t": "status", "s": "wet", "dur": 2.0},
			{"t": "bolts", "n": 3, "dmg": 30.0, "r": 35.0},
		],
	},
	"water+fire+earth": {
		"name": "間歇噴泉", "color": Color("8fe0e8"),
		"desc": "地底蓄壓後噴發：短暫延遲後造成巨大傷害，並把敵群沿路沖回去。",
		"hit": [{"t": "zone", "cd": 6.0, "z": {
			"label": "噴泉", "art": "warn", "r": 70.0, "dur": 0.9, "color": Color("8fe0e8"), "warn": true,
			"end": [
				{"t": "explode", "r": 70.0, "dmg": 60.0, "style": "geyser", "color": Color("8fe0e8")},
				{"t": "knockback", "dist": 90.0},
			],
		}}],
	},
	"water+wood+thunder": {
		"name": "超導樹海結界", "color": Color("3fe0b0"), "domain_art": "forest",
		"desc": "塔本體化為「超導樹海」：每秒發射感電藤蔓，把射程內敵群牽引向樹海中心強行禁錮並電擊。",
		"hit": [{"t": "status", "s": "wet", "dur": 2.0}],
		"domain": [
			{"t": "pull", "dist": 45.0},
			{"t": "status", "s": "root", "dur": 0.4},
			{"t": "dmg", "dmg": 10.0, "kind": "thunder"},
			{"t": "chain", "n": 3, "dmg": 6.0},
		],
	},
	"water+wood+earth": {
		"name": "世界樹", "color": Color("6fd08a"), "domain_art": "tree",
		"desc": "塔化為世界樹：射程內敵人被緩速並吸取生命，在樹蔭下被擊殺的敵人掉落雙倍金幣。",
		"hit": [],
		"domain": [
			{"t": "status", "s": "slow", "dur": 1.2, "v": 0.4},
			{"t": "status", "s": "poison", "dur": 1.5, "v": 8.0},
			{"t": "status", "s": "bounty", "dur": 1.5},
		],
	},
	"water+thunder+earth": {
		"name": "磁暴漩渦", "color": Color("6a8cff"),
		"desc": "生成帶電漩渦，持續把敵群捲向中心並電擊。",
		"hit": [{"t": "zone", "cd": 8.0, "z": {
			"label": "漩渦", "art": "vortex", "r": 95.0, "dur": 4.0, "color": Color("6a8cff"),
			"tick": [
				{"t": "pull", "dist": 18.0},
				{"t": "dmg", "dmg": 4.0, "kind": "thunder"},
				{"t": "status", "s": "wet", "dur": 1.0},
			],
		}}],
	},
	"fire+wood+thunder": {
		"name": "連環爆燃", "color": Color("ffb03a"),
		"desc": "閃電鏈在 4 個目標間彈跳，每次彈跳都引發爆炸並點燃野火。",
		"hit": [{"t": "chain", "n": 4, "dmg": 6.0, "on": [
			{"t": "explode", "r": 40.0, "dmg": 5.0, "style": "fire"},
			{"t": "status", "s": "wildfire", "dur": 3.0, "v": 8.0},
		]}],
	},
	"fire+wood+earth": {
		"name": "天火隕石", "color": Color("ff5a2a"),
		"desc": "召喚隕石：短暫延遲後砸下造成毀滅性範圍傷害，並留下一片燃燒林地。",
		"hit": [{"t": "zone", "cd": 7.0, "z": {
			"label": "隕石", "art": "warn", "meteor": true, "r": 90.0, "dur": 1.0, "color": Color("ff5a2a"), "warn": true,
			"end": [
				{"t": "explode", "r": 90.0, "dmg": 90.0, "style": "meteor"},
				{"t": "zone", "z": {
					"label": "焦土", "art": "lava", "r": 70.0, "dur": 4.0, "color": Color("ff8a3a"),
					"tick": [
						{"t": "dmg", "dmg": 5.0},
						{"t": "status", "s": "burn", "dur": 2.0, "v": 8.0},
					],
				}},
			],
		}}],
	},
	"fire+thunder+earth": {
		"name": "超載熔核", "color": Color("ff3a6a"),
		"desc": "把目標變成不穩定的熔核炸彈：2 秒後（或死亡時）以其最大生命的 25% 引爆周圍並震暈。",
		"hit": [{"t": "status", "cd": 3.0, "s": "bomb", "dur": 2.0}],
	},
	"wood+thunder+earth": {
		"name": "雷木圖騰", "color": Color("c8d84a"),
		"desc": "在落點豎立雷木圖騰，圖騰會持續對周圍敵人放出閃電鏈。",
		"hit": [{"t": "zone", "cd": 8.0, "z": {
			"label": "圖騰", "art": "totem", "r": 120.0, "dur": 6.0, "interval": 0.6, "color": Color("c8d84a"), "totem": true,
			"tick": [{"t": "chain", "n": 3, "dmg": 9.0, "stun": 0.1}],
		}}],
	},
}

var font: Font
var add_mat: CanvasItemMaterial  # 加色混合（發光特效用）
var fade_ramp: Gradient  # 粒子淡出
var _tex := {}
var unlocked := {}
var save_enabled := true
var music_on := true


func _ready() -> void:
	# 內嵌字型：網頁版沒有系統字型可用
	font = load("res://assets/fonts/NotoSansTC.ttf")
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fade_ramp = Gradient.new()
	fade_ramp.set_color(0, Color(1, 1, 1, 1))
	fade_ramp.set_color(1, Color(1, 1, 1, 0))
	_load()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_on = cfg.get_value("audio", "music", true)


func set_music(on: bool) -> void:
	music_on = on
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", on)
	cfg.save(SETTINGS_PATH)


## 美術素材（assets/art/*.svg，由 tools/gen_art.py 產生）
func tex(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = load("res://assets/art/%s.svg" % n)
	return _tex[n]


## 點陣圖素材（assets/art/*.png，例如 tools/gen_bg.gd 烘焙的地圖底圖）
func tex_png(n: String) -> Texture2D:
	var k := n + ".png"
	if not _tex.has(k):
		_tex[k] = load("res://assets/art/%s.png" % n)
	return _tex[k]


## 元素陣列 → 融合表的 key（去重後依 ELEMENTS 順序排列）
func key_of(elems: Array) -> String:
	var parts: Array[String] = []
	for e in ELEMENTS:
		if elems.has(e):
			parts.append(e)
	return "+".join(parts)


func get_fusion(elems: Array) -> Dictionary:
	return FUSIONS.get(key_of(elems), {})


## 同元素重複放入 = 強化等級
func rank_of(elems: Array) -> int:
	if elems.is_empty():
		return 0
	return elems.size() - key_of(elems).split("+").size() + 1


func rank_mult(elems: Array) -> float:
	return 1.0 + 0.4 * float(maxi(rank_of(elems) - 1, 0))


func elem_names(key: String) -> String:
	var names: Array[String] = []
	for e in key.split("+"):
		names.append(ELEM[e]["name"])
	return "＋".join(names)


func fusion_title(elems: Array) -> String:
	var f := get_fusion(elems)
	if f.is_empty():
		return "無元素"
	var r := rank_of(elems)
	return str(f["name"]) + (" Lv%d" % r if r > 1 else "")


## 回傳 true 表示這是第一次發現
func unlock(key: String) -> bool:
	if key == "" or unlocked.has(key):
		return false
	unlocked[key] = true
	_save()
	return true


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for k in parsed:
			if FUSIONS.has(k):
				unlocked[k] = true


func _save() -> void:
	if not save_enabled:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(unlocked.keys()))
