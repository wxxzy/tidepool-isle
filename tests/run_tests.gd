extends SceneTree
## headless 确定性测试
## 运行：godot --headless --path . --script tests/run_tests.gd
## 覆盖：JSON 数据 / 昼夜插值 / 抛竿手感参数 / 钓鱼状态机全路径 / 鱼种过滤 / 岛体高度函数

var _fails := 0
var _count := 0


func _init() -> void:
	_run()


func _run() -> void:
	_run_async()


func _run_async() -> void:
	_test_json_load()
	_test_daycycle()
	_test_daycycle_wrap_and_clock()
	_test_cast_monotonic()
	_test_happy_path()
	_test_snap()
	_test_bite_miss()
	_test_early_strike()
	_test_pick_fish_filter()
	_test_island_height()
	_test_fish_def()
	_test_reset_emits_state_changed()
	_test_controller_integration()
	_test_wiring_static()
	_test_persistence_and_dex()
	_test_palette()
	_test_goals_and_components()
	_test_3d_assets()
	# 主场景实例化改由 --quit-after 冒烟命令验证：
	# --script 模式下 autoload 单例名（GameData）不参与脚本编译，ResourceLoader.load 会误报
	print("----")
	print("%d/%d passed" % [_count - _fails, _count])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_count += 1
	if cond:
		print("  ok - %s" % msg)
	else:
		_fails += 1
		printerr("FAIL - %s" % msg)


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text) if text != "" else {}


func _load_pool() -> Array[FishDef]:
	var pool: Array[FishDef] = []
	var data := _load_json("res://data/fish.json")
	for fd in data.get("fish", []):
		pool.append(FishDef.from_dict(fd))
	return pool


func _load_daycycle() -> DayCycle:
	return DayCycle.from_dict(_load_json("res://data/daycycle.json"))


## 走完 等待→轻点→咬钩 流程（最多 sim 秒）
func _wait_for_bite(core: FishingCore, sim := 40.0) -> bool:
	var steps := int(sim / (1.0 / 60.0))
	for i in steps:
		core.tick(1.0 / 60.0, false, false)
		if core.state == FishingCore.State.BITE:
			return true
	return false


## 完整开局：蓄力→抛竿→入水
func _cast_into_water(core: FishingCore, charge_time: float, zone := "dock", bait := "dough") -> void:
	core.request_charge()
	core.tick(charge_time, false, false)
	core.release_cast()
	core.land_bobber(zone, bait)


# ================= 用例 =================

func _test_json_load() -> void:
	print("[json]")
	var fish := _load_json("res://data/fish.json")
	_check(not fish.is_empty(), "fish.json 可解析")
	_check(fish.get("fish", []).size() == 13, "鱼种表 13 条（12 鱼 + 杂物组）")
	var bait := _load_json("res://data/bait.json")
	_check(bait.get("baits", []).size() == 5, "鱼饵表 5 条")
	var dc := _load_json("res://data/daycycle.json")
	_check(dc.get("phases", []).size() == 6, "昼夜 6 时段")
	# 数据引用完整性：每条鱼的 phases/spots/baits 键都合法
	var phase_names := {}
	for p in dc.get("phases", []):
		phase_names[str(p["name"])] = true
	var bait_ids := {}
	for b in bait.get("baits", []):
		bait_ids[str(b["id"])] = true
	var refs_ok := true
	for fd in fish.get("fish", []):
		for ph in fd.get("phases", []):
			if not phase_names.has(str(ph)):
				refs_ok = false
		for k in fd.get("baits", {}).keys():
			if not bait_ids.has(str(k)):
				refs_ok = false
		var sz = fd.get("size_cm", null)
		if sz is Array and sz.size() == 2 and float(sz[0]) > float(sz[1]):
			refs_ok = false
		# icon 字段：阶段4 新增，指向 res://assets/fish/<id>.png
		var icon := str(fd.get("icon", ""))
		if not icon.begins_with("res://assets/fish/") or not icon.ends_with(str(fd["id"]) + ".png"):
			refs_ok = false
	_check(refs_ok, "鱼种表引用完整（时段/鱼饵/尺寸/icon）")


func _test_daycycle() -> void:
	print("[daycycle]")
	var dc := _load_daycycle()
	_check(dc.phase_at(6.0).get("name") == "dawn", "06:00 = 清晨")
	_check(dc.phase_at(9.0).get("name") == "morning", "09:00 = 上午")
	_check(dc.phase_at(15.0).get("name") == "golden", "15:00 = 黄金时刻")
	_check(dc.phase_at(20.0).get("name") == "night", "20:00 = 夜晚")
	var s := dc.sample(12.0)
	_check(absf(float(s["light_energy"]) - 1.25) < 0.001, "正午光强 = 1.25（无混入）")
	var sb := dc.sample(4.9)
	var e := float(sb["light_energy"])
	_check(e > 0.3 and e < 0.85, "04:54 处于夜晚→清晨 crossfade（%0.2f）" % e)
	# 全天采样连续性（夜间下限 0.05：v0.4 刻意把夜晚压暗，避免"夜空黑、地面亮"的穿帮）
	var ok := true
	var h := 0.0
	while h < 24.0:
		var sm := dc.sample(h)
		if sm.is_empty() or float(sm["light_energy"]) < 0.05 or float(sm["light_energy"]) > 1.3:
			ok = false
			break
		h += 0.05
	_check(ok, "全天 0.05h 步进采样能量均在 [0.05, 1.3]（含夜间压暗）")


func _test_daycycle_wrap_and_clock() -> void:
	print("[daycycle.wrap]")
	var dc := _load_daycycle()
	_check(dc.phase_at(2.0).get("name") == "night", "02:00 仍属夜晚（跨午夜回卷）")
	_check(DayCycle.clock_text(16.7) == "16:42", "时钟文本 16:42（Brief 签名时刻）")
	var h := dc.advance(23.9, 60.0)
	_check(absf(h - 0.9) < 0.01, "24 分钟一日：60s = 1 小时（23.9→0.9）")


func _test_cast_monotonic() -> void:
	print("[cast]")
	var pool := _load_pool()
	var c1 := FishingCore.new()
	c1.setup(pool, 2026)
	c1.request_charge()
	c1.tick(0.2, false, false)
	c1.release_cast()
	var c2 := FishingCore.new()
	c2.setup(pool, 2026)
	c2.request_charge()
	c2.tick(0.9, false, false)
	c2.release_cast()
	_check(c2.cast_distance > c1.cast_distance, "蓄力越满抛越远（%0.1f → %0.1f）" % [c1.cast_distance, c2.cast_distance])
	_check(c1.cast_distance >= FishingCore.CAST_MIN_DIST - 0.01 and c2.cast_distance <= FishingCore.CAST_MAX_DIST + 0.01, "抛距夹在 [5, 35] 米")


func _test_happy_path() -> void:
	print("[happy path]")
	var core := FishingCore.new()
	core.setup(_load_pool(), 42)
	core.hook_window = 0.4
	core.fallback_weight = 0.15
	core.phase_provider = func() -> String: return "noon"
	_cast_into_water(core, 0.5)
	_check(core.state == FishingCore.State.WAITING, "入水后进入等待")
	_check(_wait_for_bite(core), "40s 内出现咬钩窗口")
	var hooked := []
	core.fish_hooked.connect(func(f): hooked.append(f))
	var caught := []
	core.fish_caught.connect(func(f, s, j): caught.append([f, s, j]))
	_check(core.hook_press(), "咬钩窗口内刺鱼成功")
	_check(core.state == FishingCore.State.REELING and not hooked.is_empty(), "进入溜鱼且鱼已确定")
	# 溜鱼：张力 < 70 才收线（简单的读条策略）
	var steps := int(500.0 / (1.0 / 60.0))
	for i in steps:
		var reeling: bool = core.tension < 70.0
		core.tick(1.0 / 60.0, reeling, false)
		if not caught.is_empty():
			break
	_check(caught.size() == 1, "成功把鱼拉上岸")
	if not caught.is_empty():
		var f: FishDef = caught[0][0]
		var s: float = caught[0][1]
		if f.size_cm.size() == 2:
			_check(s >= float(f.size_cm[0]) - 0.01 and s <= float(f.size_cm[1]) + 0.01, "尺寸落在鱼种区间内（%s %.0fcm）" % [f.fish_name, s])
		else:
			_check(true, "杂物无尺寸（%s）" % str(caught[0][2]))
	_check(core.state == FishingCore.State.IDLE, "结算后回到待机")


func _test_snap() -> void:
	print("[snap]")
	var sardine := FishDef.from_dict(_load_json("res://data/fish.json")["fish"][0])
	var core := FishingCore.new()
	core.setup([sardine], 7)
	core.phase_provider = func() -> String: return "noon"
	_cast_into_water(core, 0.5)
	_wait_for_bite(core)
	core.hook_press()
	var snapped := []
	core.line_snapped.connect(func(): snapped.append(true))
	# 无脑收线 → 必断
	var steps := int(120.0 / (1.0 / 60.0))
	for i in steps:
		core.tick(1.0 / 60.0, true, false)
		if not snapped.is_empty():
			break
	_check(not snapped.is_empty(), "持续满力收线触发断线")
	_check(core.state == FishingCore.State.IDLE, "断线后回到待机")


func _test_bite_miss() -> void:
	print("[bite miss]")
	var sardine := FishDef.from_dict(_load_json("res://data/fish.json")["fish"][0])
	var core := FishingCore.new()
	core.setup([sardine], 9)
	core.phase_provider = func() -> String: return "noon"
	_cast_into_water(core, 0.5)
	_wait_for_bite(core)
	var missed := []
	core.bite_missed.connect(func(): missed.append(true))
	core.tick(0.5, false, false)  # 错过 0.4s 窗口
	_check(not missed.is_empty(), "超时未刺鱼 → bite_missed")
	_check(core.state == FishingCore.State.WAITING or core.state == FishingCore.State.IDLE, "错过后续接等待或直接跑鱼")


func _test_early_strike() -> void:
	print("[early strike]")
	var sardine := FishDef.from_dict(_load_json("res://data/fish.json")["fish"][0])
	var core := FishingCore.new()
	core.setup([sardine], 11)
	core.phase_provider = func() -> String: return "noon"
	_cast_into_water(core, 0.5)
	# 等第一次轻点
	var steps := int(40.0 / (1.0 / 60.0))
	var nibbled := []
	core.nibble_happened.connect(func(): nibbled.append(true))
	for i in steps:
		core.tick(1.0 / 60.0, false, false)
		if not nibbled.is_empty():
			break
	_check(not nibbled.is_empty(), "出现轻点（试探）")
	var escaped := []
	core.fish_escaped.connect(func(r): escaped.append(r))
	core.hook_press()
	_check(not escaped.is_empty() and str(escaped[0]) == "early", "轻点中抢跑 → fish_escaped(early)")


func _test_pick_fish_filter() -> void:
	print("[pick_fish]")
	var pool := _load_pool()
	var squid := FishDef.new()
	for f in pool:
		if f.id == "squid":
			squid = f
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_check(FishingCore.pick_fish(rng, [squid], "noon", "deep", "krill", 0.15) == null, "鱿鱼不在正午出现")
	var butterfly := FishDef.new()
	for f in pool:
		if f.id == "butterfly":
			butterfly = f
	_check(FishingCore.pick_fish(rng, [butterfly], "golden", "shallow", "dough", 0.15) != null, "蝴蝶鱼在黄金时刻浅滩出现")
	_check(FishingCore.pick_fish(rng, [butterfly], "golden", "deep", "dough", 0.15) == null, "蝴蝶鱼不在深水出现")
	# 加权统计：常见鱼应远多于杂物（权重 1.0 vs 0.5*0.3=0.15）
	var duo: Array[FishDef] = []
	for f in pool:
		if f.id == "sardine" or f.id == "trash":
			duo.append(f)
	rng.seed = 2026
	var sardine_n := 0
	var n := 2000
	for i in n:
		var pick := FishingCore.pick_fish(rng, duo, "noon", "dock", "dough", 0.15)
		if pick != null and pick.id == "sardine":
			sardine_n += 1
	var share := float(sardine_n) / float(n)
	_check(share > 0.75 and share < 0.95, "加权随机：沙丁鱼占比 %.2f（期望 ~0.87）" % share)


func _test_island_height() -> void:
	print("[island]")
	_check(WorldBuilder.island_height(0.0, 0.0) > 4.0, "岛心高度 > 4m")
	_check(WorldBuilder.island_height(0.0, 59.0) < 0.0, "r=59 已入水")
	_check(WorldBuilder.island_height(0.0, 70.0) == -1.7, "远海恒定 -1.7m")
	var ok := true
	var x := -70.0
	var prev := WorldBuilder.island_height(x, 3.0)
	while x < 70.0:
		x += 0.5
		var h := WorldBuilder.island_height(x, 3.0)
		if is_nan(h) or absf(h - prev) > 1.0:
			ok = false
			break
		prev = h
	_check(ok, "高度函数连续无跳变")
	_check(WorldBuilder.surface_type_at(0.0, 0.0) == "grass" and WorldBuilder.surface_type_at(0.0, 44.0) == "sand", "地表类型分区正确")


func _test_fish_def() -> void:
	print("[fish_def]")
	var pool := _load_pool()
	var sardine := FishDef.new()
	var trash := FishDef.new()
	for f in pool:
		if f.id == "sardine":
			sardine = f
		elif f.id == "trash":
			trash = f
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 50:
		var s := sardine.roll_size(rng)
		if s < 15.0 or s > 25.0:
			_check(false, "沙丁鱼尺寸越界 %.1f" % s)
			return
	_check(true, "50 次尺寸采样均在 [15, 25]")
	var jn := trash.roll_junk_name(rng)
	_check(trash.junk_names.has(jn), "杂物名称取自配置表（%s）" % jn)
	_check(sardine.matches("noon", "dock") and not sardine.matches("noon", "deep"), "matches() 时段与钓点判定")
	_check(sardine.icon == "res://assets/fish/sardine.png", "FishDef.icon 从 JSON 正确加载")


## 回归 S1：reset() 必须经 _set_state 发 state_changed，否则 controller 收不到 IDLE
func _test_reset_emits_state_changed() -> void:
	print("[reset signal]")
	var core := FishingCore.new()
	core.setup(_load_pool(), 3)
	core.phase_provider = func() -> String: return "noon"
	_cast_into_water(core, 0.5)
	_wait_for_bite(core)
	core.hook_press()
	_check(core.state == FishingCore.State.REELING, "已入溜鱼态")
	var states: Array = []
	core.state_changed.connect(func(s): states.append(s))
	# 无脑收线直到断线（也会走 reset）
	var steps := int(120.0 / (1.0 / 60.0))
	for i in steps:
		core.tick(1.0 / 60.0, true, false)
		if core.state == FishingCore.State.IDLE:
			break
	_check(core.state == FishingCore.State.IDLE, "断线后回到 IDLE")
	_check(not states.is_empty() and states[states.size() - 1] == FishingCore.State.IDLE, "reset 路径确实发射了 state_changed(IDLE)")


## 回归 S1/S2：实例化真实 Player + FishingController + Hud，验证整条 UI 通知链
func _test_controller_integration() -> void:
	print("[controller integration]")
	# 说明：--script 模式下 autoload（GameData）不注入，FishingController._ready 会解析失败，
	# 因此这里用「静态源码断言 + 独立状态机回归」覆盖 S1/S2，真实运行时链路由
	# --quit-after 主场景冒烟 + 下文 _test_wiring_static 双重保证。

	# S1 完整回归：core 从 BITE → REELING → reset，state_changed 必须发 IDLE
	var core := FishingCore.new()
	core.setup(_load_pool(), 42)
	core.phase_provider = func() -> String: return "noon"
	_cast_into_water(core, 0.5)
	_wait_for_bite(core)
	core.hook_press()
	var idle_seen: Array = []
	core.state_changed.connect(func(s):
		if s == FishingCore.State.IDLE:
			idle_seen.append(s))
	for i in int(500.0 / (1.0 / 60.0)):
		var reeling: bool = core.tension < 70.0
		core.tick(1.0 / 60.0, reeling, false)
		if core.state == FishingCore.State.IDLE:
			break
	_check(core.state == FishingCore.State.IDLE and not idle_seen.is_empty(),
		"S1 回归：上岸经 reset 发出 state_changed(IDLE)，controller 可据此解冻")

	# S2 静态断言：源码中必须存在 tension_changed.connect，防止再次漏连
	var src := FileAccess.get_file_as_string("res://scripts/fishing_controller.gd")
	_check(src.contains("core.tension_changed.connect(_on_tension_changed)"),
		"S2 回归：controller 源码已连接 tension_changed（此前漏连导致张力条空白）")
	_check(src.contains("hud.set_tension(v)"), "S2 回归：张力回调确实写入 HUD")


## 静态检查：关键信号链与配置键存在（--script 环境下无法实例化 autoload 时的兜底）
func _test_wiring_static() -> void:
	print("[wiring static]")
	var core_src := FileAccess.get_file_as_string("res://scripts/fishing_core.gd")
	_check(core_src.contains("_set_state(State.IDLE)") and not core_src.contains("state = State.IDLE\n\tcharge"),
		"S1 源码：reset 不再直接赋值 state（防止信号被吞）")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_check(proj.contains("renderer/rendering_method=\"gl_compatibility\""), "Web 导出：GL Compatibility 渲染器已设")
	var water_src := FileAccess.get_file_as_string("res://scripts/world_builder.gd")
	_check(water_src.contains("render_mode blend_mix"), "B1 回归：水面着色器已启用 blend_mix")


## P1 持久化 + P2 鱼谱的静态覆盖（运行时读写由 integration_scene 验证）
func _test_persistence_and_dex() -> void:
	print("[persistence / dex]")
	var save_src := FileAccess.get_file_as_string("res://scripts/save_manager.gd")
	_check(save_src.contains("user://tidepool_save.cfg"), "存档路径为 user://tidepool_save.cfg")
	for api in ["set_record", "get_record", "mark_caught", "is_caught", "get_bait_count", "set_setting"]:
		_check(save_src.contains("func " + api), "SaveManager.%s 存在" % api)
	var dex_src := FileAccess.get_file_as_string("res://scripts/fish_dex.gd")
	_check(dex_src.contains("caught") and dex_src.contains("seen"), "鱼谱含已捕获/见过两态")
	_check(dex_src.contains("GameData.fish_defs"), "鱼谱数据源为 fish.json 驱动")
	var audio_src := FileAccess.get_file_as_string("res://scripts/audio_system.gd")
	_check(audio_src.contains("play_sfx") and audio_src.contains("duck"), "音频系统含音效与 ducking")


## 阶段1 全局换肤：色板映射与语义色完整性
func _test_palette() -> void:
	print("[palette]")
	_check(Palette.group_for_phase("noon") == "day", "正午 → day 色板")
	_check(Palette.group_for_phase("golden") == "golden", "黄金时刻 → golden 色板")
	_check(Palette.group_for_phase("dusk") == "golden", "黄昏 → golden 色板")
	_check(Palette.group_for_phase("night") == "night", "夜晚 → night 色板")
	for ph in Palette.PHASES:
		var sem := ["panel", "panel_alt", "accent", "text", "text_muted", "border", "highlight", "safe", "warn", "danger"]
		var ok := true
		for s in sem:
			var c := Palette.get_color(ph, s)
			if c == Color.MAGENTA:
				ok = false
		_check(ok, "%s 色板 10 个语义色齐全" % ph)
	# 三套面板底色确实不同（证明换肤有视觉差异）
	var d: Color = Palette.get_color("noon", "panel")
	var g: Color = Palette.get_color("golden", "panel")
	var n: Color = Palette.get_color("night", "panel")
	_check(not d.is_equal_approx(g) and not g.is_equal_approx(n) and not d.is_equal_approx(n),
		"day / golden / night 面板底色互不相同（换肤有可见差异）")
	var tm_src := FileAccess.get_file_as_string("res://scripts/theme_manager.gd")
	_check(tm_src.contains("signal theme_changed"), "ThemeManager 有 theme_changed 广播信号")
	var hud_src := FileAccess.get_file_as_string("res://scripts/hud.gd")
	_check(hud_src.contains("ThemeManager.theme_changed.connect"), "HUD 已订阅换肤信号")
	var dex_src2 := FileAccess.get_file_as_string("res://scripts/fish_dex.gd")
	_check(dex_src2.contains("ThemeManager.theme_changed.connect"), "鱼谱已订阅换肤信号")
	# v0.4 视觉层回归：图标必须自绘（默认字体没有 ☀/☾ 字形，会渲染成小圆点）
	_check(hud_src.contains("IconGlyph"), "HUD 图标为自绘，不依赖字体字形")
	_check(hud_src.contains("card_style"), "HUD 面板走统一卡片样式")
	var comp_v := FileAccess.get_file_as_string("res://scripts/ui_components.gd")
	_check(comp_v.contains("shadow_color"), "卡片样式含柔和投影（不再是一块扁平色块）")
	_check(dex_src2.contains("EXPAND_IGNORE_SIZE"), "鱼谱插画限制最小尺寸（防止 512px 贴图撑爆卡片）")


## 阶段2/3：目标数据 + 反馈文案库 + 组件工厂
func _test_goals_and_components() -> void:
	print("[goals / components]")
	var gd := _load_json("res://data/goals.json")
	_check(gd.get("goals", []).size() == 3, "goals.json 3 个今日目标")
	_check(gd.get("feedback", {}).size() >= 8, "反馈文案库 >= 8 条")
	_check(gd.get("phase_hints", {}).size() == 6, "6 个时段各有情境提示")
	var kinds := {}
	for g in gd.get("goals", []):
		kinds[str(g.get("type", ""))] = true
	for k in ["species_count", "phase_catch", "size"]:
		_check(kinds.has(k), "目标类型 %s 存在" % k)
	var comp_src := FileAccess.get_file_as_string("res://scripts/ui_components.gd")
	_check(comp_src.contains("func goal_card"), "UiComponents.goal_card 存在")
	_check(comp_src.contains("func key_badge"), "UiComponents.key_badge 存在")
	var hud_src2 := FileAccess.get_file_as_string("res://scripts/hud.gd")
	for api in ["update_goal_display", "update_dex_display", "show_achievement", "set_situational_hint", "result_action"]:
		_check(hud_src2.contains(api), "HUD.%s 存在" % api)
	var save_src2 := FileAccess.get_file_as_string("res://scripts/save_manager.gd")
	_check(save_src2.contains("goal_progress") and save_src2.contains("mark_goal_done"), "SaveManager 目标进度 API 存在")
	# 阶段4：鱼谱插画渐进增强（有图用 TextureRect，无图回退 emoji）
	var dex_src3 := FileAccess.get_file_as_string("res://scripts/fish_dex.gd")
	_check(dex_src3.contains("ResourceLoader.exists(f.icon)"), "鱼谱检查插画是否存在")
	_check(dex_src3.contains("TextureRect") and dex_src3.contains("🐟"), "鱼谱有插画/emoji 双路径")
	# 阶段4：已导入的插画路径确实可被 Godot 识别
	var pool2 := _load_pool()
	var present := 0
	for f in pool2:
		if f.icon != "" and ResourceLoader.exists(f.icon):
			present += 1
	_check(present >= 1, "至少 1 张鱼插画已导入 Godot assets（当前 %d/13）" % present)


## 混元3D 资产：模型文件、体长表、玩家换装与鱼群接线
func _test_3d_assets() -> void:
	print("[3d assets]")
	var hero := "res://assets/models/hero.glb"
	_check(FileAccess.file_exists(hero), "主角 GLB 存在")
	var hero_bytes := FileAccess.get_file_as_bytes(hero)
	_check(hero_bytes.size() > 100000, "主角 GLB 非空（%.1f MB）" % (hero_bytes.size() / 1048576.0))
	_check(hero_bytes.size() < 12 * 1024 * 1024, "主角 GLB 已压缩到 12MB 以内（防止 Web 首包过大）")

	# 每个登记在 SPECIES 里的鱼都必须真的有文件，避免运行时空模型
	var kinds := FishSwimmer.available_species()
	_check(kinds.size() >= 5, "已接入 %d 种 3D 鱼模型" % kinds.size())
	for k in kinds:
		var p := FishSwimmer.model_path(str(k))
		_check(FileAccess.file_exists(p), "鱼模型存在: %s" % p)
		_check(FishSwimmer.body_length(str(k)) > 0.05, "体长有效: %s" % k)

	# 模型库：能真正解析出网格（GLTFDocument 路径可用）
	var t := ModelLib.template(hero)
	_check(t != null, "ModelLib 能解析主角 GLB")
	if t != null:
		var a := ModelLib.local_bounds(t)
		_check(a.size.y > 0.1, "主角模型有有效高度（%.3f）" % a.size.y)
		var tip := ModelLib.topmost_point(t)
		_check(tip.y > a.position.y * 0.5, "能找到鱼竿尖顶点（y=%.2f）" % tip.y)

	# 绑骨版：必须有骨骼 + 至少 3 段动画（idle/walk/hold）
	var rigged := "res://assets/models/hero_rigged.glb"
	_check(FileAccess.file_exists(rigged), "绑骨版主角 GLB 存在")
	if FileAccess.file_exists(rigged):
		var rt := ModelLib.template(rigged)
		_check(rt != null, "绑骨版主角可加载")
		if rt != null:
			_check(ModelLib.has_skin(rt), "绑骨版主角含骨骼（Skeleton3D 存在）")
			var rap := ModelLib.find_anim_player(rt)
			_check(rap != null, "绑骨版主角带动画播放器")
			if rap != null:
				var an := rap.get_animation_list()
				_check(an.size() >= 3, "绑骨版主角动画数 %d（%s）" % [an.size(), str(an)])
				for want in ["idle", "walk", "hold"]:
					_check(an.has(want), "含动画 %s" % want)

	# 玩家脚本已切到 GLB，并保留程序化回退
	var psrc := FileAccess.get_file_as_string("res://scripts/player.gd")
	_check(psrc.contains("HERO_MODEL") and psrc.contains("_build_glb_model"), "玩家优先装配 GLB 主角")
	_check(psrc.contains("_build_procedural_model"), "保留程序化角色作为回退")
	_check(psrc.contains("rod_tip") and (psrc.contains("topmost_local") or psrc.contains("topmost_point")), "钓线起点取自模型竿尖")

	# 鱼群与中鱼表现已接线
	var msrc := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(msrc.contains("FishSchool"), "主场景生成鱼群节点")
	var fsrc := FileAccess.get_file_as_string("res://scripts/fishing_controller.gd")
	_check(fsrc.contains("_spawn_hooked_fish"), "中鱼时生成水下鱼模型")
	_check(fsrc.contains("_spawn_leap_fish"), "上鱼时播放跃出水面")
	_check(fsrc.contains("_despawn_fish"), "断线/脱钩清理鱼模型")


## 集成冒烟：主场景能否实例化（此前零覆盖）
func _test_main_scene_instantiates() -> void:
	print("[main scene]")
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_check(packed != null, "main.tscn 可加载")
	if packed != null:
		var inst := packed.instantiate()
		_check(inst != null, "main.tscn 可实例化（装配链无致命错误）")
		if inst != null:
			inst.free()
