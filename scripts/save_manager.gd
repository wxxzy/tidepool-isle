extends Node
## SaveManager —— 持久化存档（P1）
## 路径 user://tidepool_save.cfg；Web 上映射到 IndexedDB，天然可用。
## 四节：records / dex / inventory / settings

const SAVE_PATH := "user://tidepool_save.cfg"

var _cfg := ConfigFile.new()
var _dirty := false


func _ready() -> void:
	load_game()


func load_game() -> void:
	_cfg = ConfigFile.new()
	var err := _cfg.load(SAVE_PATH)
	if err != OK:
		# 首次运行：写入默认骨架
		_init_sections()
		flush()
	else:
		_init_sections()


func _init_sections() -> void:
	# ConfigFile 没有 set_section()；用 set_value 写入一个占位键即可创建节，
	# 再立即擦除该键，得到空节
	for section in ["records", "dex", "inventory", "settings", "goals"]:
		if not _cfg.has_section(section):
			_cfg.set_value(section, "__init__", true)
			_cfg.erase_section_key(section, "__init__")
	# 默认设置
	if not _cfg.has_section_key("settings", "day_minutes"):
		_cfg.set_value("settings", "day_minutes", 24.0)
	if not _cfg.has_section_key("settings", "auto_release_line"):
		_cfg.set_value("settings", "auto_release_line", true)
	if not _cfg.has_section_key("settings", "master_volume"):
		_cfg.set_value("settings", "master_volume", 1.0)


func flush() -> void:
	_cfg.save(SAVE_PATH)
	_dirty = false


func is_dirty() -> bool:
	return _dirty


# ================= 纪录 =================

func set_record(fish_id: String, size: float) -> void:
	var key := "best_" + fish_id
	var prev := float(_cfg.get_value("records", key, 0.0))
	if size > prev:
		_cfg.set_value("records", key, size)
		_dirty = true


func get_record(fish_id: String) -> float:
	return float(_cfg.get_value("records", "best_" + fish_id, 0.0))


# ================= 鱼谱 =================

func mark_caught(fish_id: String) -> void:
	_append_unique("dex", "caught", fish_id)


func mark_seen(fish_id: String) -> void:
	_append_unique("dex", "seen", fish_id)


func is_caught(fish_id: String) -> bool:
	return Array(_cfg.get_value("dex", "caught", [])).has(fish_id)


func is_seen(fish_id: String) -> bool:
	return Array(_cfg.get_value("dex", "seen", [])).has(fish_id)


func caught_list() -> Array:
	return Array(_cfg.get_value("dex", "caught", []))


# ================= 库存 =================

func get_bait_count(bait_id: String, default: int) -> int:
	return int(_cfg.get_value("inventory", "bait_" + bait_id, default))


func set_bait_count(bait_id: String, count: int) -> void:
	_cfg.set_value("inventory", "bait_" + bait_id, count)
	_dirty = true


# ================= 设置 =================

func get_setting(key: String, default):
	return _cfg.get_value("settings", key, default)


func set_setting(key: String, value) -> void:
	_cfg.set_value("settings", key, value)
	_dirty = true


func _append_unique(section: String, key: String, value: String) -> void:
	var arr := Array(_cfg.get_value(section, key, []))
	if not arr.has(value):
		arr.append(value)
		_cfg.set_value(section, key, arr)
		_dirty = true


# ================= 今日目标 =================

func goal_progress(goal_id: String) -> int:
	return int(_cfg.get_value("goals", "progress_" + goal_id, 0))


func set_goal_progress(goal_id: String, value: int) -> void:
	var prev := goal_progress(goal_id)
	if value > prev:
		_cfg.set_value("goals", "progress_" + goal_id, value)
		_dirty = true


func is_goal_done(goal_id: String) -> bool:
	return bool(_cfg.get_value("goals", "done_" + goal_id, false))


func mark_goal_done(goal_id: String) -> void:
	if not is_goal_done(goal_id):
		_cfg.set_value("goals", "done_" + goal_id, true)
		_dirty = true


func reset_daily_goals() -> void:
	# 每个游戏日开始时调用（由 main 在跨日时触发，外部可手动调用测试）
	for k in _cfg.get_section_keys("goals"):
		_cfg.erase_section_key("goals", k)
	_dirty = true
