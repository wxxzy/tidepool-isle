extends SceneTree
## 真实渲染探针：加载主场景 → 逐状态截图（日间/蓄力/张力/结算/夜晚/鱼谱）
## 用法（不能加 --headless）：godot --path <proj> --rendering-driver opengl3 \
##   --audio-driver Dummy --resolution 1280x720 --script tests/visual_probe.gd

var _scene: Node = null
var _hud: Node = null
var _dex: Node = null
var _dn: Node = null
var _f := 0
var _out := ""


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _find(n: Node, method: String) -> Node:
	for ch in n.get_children():
		if ch.has_method(method):
			return ch
		var r := _find(ch, method)
		if r != null:
			return r
	return null


func _process(_dt: float) -> bool:
	_f += 1
	if _hud == null:
		_hud = _find(_scene, "set_tension")
		_dex = _find(_scene, "toggle")
		_dn = _scene.get_node_or_null("DayNight")
		if _hud == null:
			return false
	match _f:
		25:
			# 截图用：收起开场 toast，避免挡住角色
			var tp: PanelContainer = _hud.get("_toast_panel")
			if tp != null:
				tp.visible = false
		30:
			_dump()
		38:
			var tp2: PanelContainer = _hud.get("_toast_panel")
			if tp2 != null:
				tp2.visible = false
		40:
			_shot("01_day")
		55:
			_set_phase("morning", "上午 08:01")
			_hud.call("set_mode", FishingCore.State.CHARGING)
			_hud.call("set_charge", 0.72)
		62:
			_shot("02_charge")
		70:
			_hud.call("set_mode", FishingCore.State.REELING)
			_hud.call("set_tension", 88.0)
			_set_phase("golden", "黄金 18:12")
		78:
			_shot("03_tension_golden")
		90:
			_hud.call("set_mode", FishingCore.State.IDLE)
			_hud.call("show_result", "钓到了！蓝鳍鲭", ["42 cm", "★★☆", "★ 新纪录"], {"fish_id": "bluefin"})
		100:
			_shot("04_result")
		112:
			_set_phase("night", "夜晚 21:01")
			if _dn != null:
				_dn.hour = 21.0
				_dn.apply()
		120:
			_shot("05_night")
		130:
			if _dex != null:
				_dex.call("toggle")
		140:
			_shot("06_dex")
		150:
			quit(0)
	return false


func _set_phase(phase: String, clock: String) -> void:
	var tm := root.get_node_or_null("/root/ThemeManager")
	if tm != null:
		tm.call("set_phase", phase)
	_hud.call("set_time", clock, clock.substr(0, 2), phase)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT_FAIL ", name)
		return
	var p := _out.path_join(name + ".png")
	print("SHOT ", p, " err=", img.save_png(p))


func _dump() -> void:
	if _hud == null:
		print("DUMP: HUD NOT FOUND")
		return
	print("=== HUD CONTROLS (viewport ", root.size, ") ===")
	_walk(_hud, 0)


func _walk(n: Node, d: int) -> void:
	var pad := "  ".repeat(d)
	if n is Control:
		var c := n as Control
		var s := "%s%s [%s] pos=(%.0f,%.0f) size=(%.0f,%.0f) vis=%s" % [
			pad, c.name, c.get_class(), c.global_position.x, c.global_position.y,
			c.size.x, c.size.y, str(c.visible)
		]
		if c is Label:
			s += " text=\"%s\"" % (c as Label).text
		print(s)
	for ch in n.get_children():
		_walk(ch, d + 1)
