extends Node
## Autoload：加载 data/*.json，全局只读游戏数据（Brief：数据驱动，改表不发版）

var fish_defs: Array[FishDef] = []
var baits: Array[Dictionary] = []
var fallback_bait_weight: float = 0.15
var hook_window: float = 0.4
var bite_miss_escape: float = 0.35
var daycycle: DayCycle = null
var goals: Array[Dictionary] = []
var feedback: Dictionary = {}
var phase_hints: Dictionary = {}

var _load_errors: PackedStringArray = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_load_errors.clear()
	_load_bait()
	_load_fish()
	_load_daycycle()
	_load_goals()


func has_errors() -> bool:
	return not _load_errors.is_empty()


func errors() -> PackedStringArray:
	return _load_errors


func bait_by_id(bait_id: String) -> Dictionary:
	for b in baits:
		if str(b.get("id")) == bait_id:
			return b
	return {}


func bait_name(bait_id: String) -> String:
	var b := bait_by_id(bait_id)
	return str(b.get("name", bait_id))


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_load_errors.append("无法读取或空文件: %s (err=%d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	_load_errors.append("JSON 解析失败: %s" % path)
	return {}


func _load_fish() -> void:
	fish_defs.clear()
	var data := _read_json("res://data/fish.json")
	hook_window = float(data.get("hook_window", 0.4))
	bite_miss_escape = float(data.get("bite_miss_escape_chance", 0.35))
	for fd in data.get("fish", []):
		if fd is Dictionary:
			fish_defs.append(FishDef.from_dict(fd))


func _load_bait() -> void:
	baits.clear()
	var data := _read_json("res://data/bait.json")
	fallback_bait_weight = float(data.get("fallback_weight", 0.15))
	for b in data.get("baits", []):
		if b is Dictionary:
			baits.append(b)


func _load_daycycle() -> void:
	var data := _read_json("res://data/daycycle.json")
	daycycle = DayCycle.from_dict(data)


func _load_goals() -> void:
	var data := _read_json("res://data/goals.json")
	goals.clear()
	for g in data.get("goals", []):
		if g is Dictionary:
			goals.append(g)
	feedback = data.get("feedback", {})
	phase_hints = data.get("phase_hints", {})


func hint_for_phase(phase: String) -> String:
	return str(phase_hints.get(phase, ""))


func feedback_text(key: String, fallback: String) -> String:
	return str(feedback.get(key, fallback))
