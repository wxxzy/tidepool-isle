class_name FishDef
extends RefCounted
## 鱼种定义 —— 由 data/fish.json 数据驱动（Brief §3.1）

var id: String = ""
var fish_name: String = ""
var icon: String = ""
var phases: PackedStringArray = []          # 出没时段（daycycle phase name）
var spots: PackedStringArray = []           # 钓点：dock / shallow / deep
var bait_weights: Dictionary = {}           # bait_id -> 权重
var rarity: int = 1                         # 1 常见 ~ 5 传说；0 事件/杂物
var size_cm: Array = []                     # [min, max]；空 = 无尺寸（杂物）
var junk: bool = false
var junk_names: PackedStringArray = []
var force_release: bool = false             # 鲨鱼：强制放生
var auto_release: bool = false              # 水母：无法上岸
var struggle: Dictionary = {}               # 挣扎模式参数


static func from_dict(d: Dictionary) -> FishDef:
	var f := FishDef.new()
	f.id = str(d.get("id", ""))
	f.fish_name = str(d.get("name", ""))
	f.icon = str(d.get("icon", ""))
	for p in d.get("phases", []):
		f.phases.append(str(p))
	for s in d.get("spots", []):
		f.spots.append(str(s))
	var bw: Dictionary = d.get("baits", {})
	for k in bw.keys():
		f.bait_weights[str(k)] = float(bw[k])
	f.rarity = int(d.get("rarity", 1))
	var sz = d.get("size_cm", null)
	if sz is Array and sz.size() == 2:
		f.size_cm = [float(sz[0]), float(sz[1])]
	f.junk = bool(d.get("junk", false))
	for jn in d.get("junk_names", []):
		f.junk_names.append(str(jn))
	f.force_release = bool(d.get("force_release", false))
	f.auto_release = bool(d.get("auto_release", false))
	f.struggle = d.get("struggle", {})
	return f


func matches(phase: String, zone: String) -> bool:
	return phases.has(phase) and spots.has(zone)


func bait_weight(bait_id: String, fallback: float) -> float:
	return float(bait_weights.get(bait_id, fallback))


func roll_size(rng: RandomNumberGenerator) -> float:
	if size_cm.size() != 2:
		return 0.0
	var t := pow(rng.randf(), 1.3)  # 偏小分布，大鱼更稀有
	return lerpf(float(size_cm[0]), float(size_cm[1]), t)


func roll_junk_name(rng: RandomNumberGenerator) -> String:
	if junk_names.is_empty():
		return fish_name
	return junk_names[rng.randi_range(0, junk_names.size() - 1)]
