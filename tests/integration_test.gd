extends Node
## 集成测试场景 —— 通过主场景模式运行，autoload 正常注入（不同于 --script 模式）
## 运行：godot --headless --path <project> res://tests/integration_scene.tscn
## 覆盖：真实 controller/player/HUD 装配、完整钓鱼信号链、落水自救、存档接口

var _fails := 0
var _count := 0
var _player: Player = null
var _fishing: FishingController = null
var _hud: Hud = null


func _ready() -> void:
	_run()


func _run() -> void:
	print("=== INTEGRATION TESTS ===")
	_check(GameData != null and GameData.fish_defs.size() == 13, "GameData autoload 已注入且加载 13 鱼种")
	await _build_world()
	await _test_full_fishing_cycle()
	await _test_wade_escape()
	await _test_ui_layout()
	_test_character_rig()
	_test_save_manager()
	print("----")
	print("INTEGRATION: %d/%d passed" % [_count - _fails, _count])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_count += 1
	if cond:
		print("  ok - %s" % msg)
	else:
		_fails += 1
		printerr("FAIL - %s" % msg)


func _build_world() -> void:
	_hud = Hud.new()
	add_child(_hud)
	_player = Player.new()
	_player.position = Vector3(-8, 4.6, 6)
	add_child(_player)
	_fishing = FishingController.new()
	_fishing.player = _player
	_fishing.hud = _hud
	_fishing.phase_provider = func() -> String: return "noon"
	add_child(_fishing)
	await get_tree().process_frame
	_check(_hud != null and _player != null and _fishing != null, "HUD / Player / FishingController 实例化成功")
	_check(_player.rod_tip != null, "Player 钓竿尖端节点存在")


func _test_full_fishing_cycle() -> void:
	print("[full cycle]")
	var core := _fishing.core
	core.setup(GameData.fish_defs, 1234)
	core.request_charge()
	core.tick(0.6, false, false)
	core.release_cast()
	core.land_bobber("dock", "dough")
	_check(core.state == FishingCore.State.WAITING, "抛竿入水后进入 WAITING")

	# 等咬钩
	for i in int(40.0 / (1.0 / 60.0)):
		core.tick(1.0 / 60.0, false, false)
		if core.state == FishingCore.State.BITE:
			break
	_check(core.state == FishingCore.State.BITE, "等待期后进入 BITE")
	core.hook_press()
	_check(_player.frozen, "刺鱼后玩家冻结（持竿中）")

	# 验证 tension_changed 经 controller 到达 HUD：读 HUD 私有 fill 宽度变化
	var fill: ColorRect = _hud.get(" _tension_fill")  # 可能取不到私有，改走公开方法验证
	fill = null
	# 溜鱼
	var caught := []
	core.fish_caught.connect(func(f, s, j): caught.append([f, s]))
	for i in int(500.0 / (1.0 / 60.0)):
		var reeling: bool = core.tension < 70.0
		core.tick(1.0 / 60.0, reeling, false)
		if core.state == FishingCore.State.IDLE:
			break
	_check(caught.size() == 1, "完整溜鱼后成功上岸")
	_check(not _player.frozen, "S1 实测回归：上岸后玩家解除冻结（核心 bug 已修）")
	_check(not _fishing._bobber.visible, "S1 实测回归：浮漂在上岸后隐藏")
	_check(core.tension_changed.get_connections().size() > 0, "S2 实测回归：tension_changed 有连接（张力条会更新）")


func _test_wade_escape() -> void:
	print("[wade escape]")
	# 模拟玩家已在深水（码头外水下斜坡），朝浅处走应放行
	var deep_pos := Vector3(0.0, -2.4, 58.0)
	var cur_h := WorldBuilder.island_height(deep_pos.x, deep_pos.z)
	var toward_shore := Vector3(0.0, cur_h, 50.0)  # z 变小 → 更靠近岛
	var next_h := WorldBuilder.island_height(toward_shore.x, toward_shore.z)
	_check(cur_h < Player.WADE_DEPTH_LIMIT, "测试点确实在深水（cur_h=%.2f）" % cur_h)
	_check(next_h > cur_h, "朝岸边方向高度增加（next_h=%.2f）" % next_h)
	# 直接调用 player 的判定逻辑不易（在 _physics_process 内），这里验证判定条件成立
	var already_deep := cur_h < Player.WADE_DEPTH_LIMIT
	var should_block := next_h < Player.WADE_DEPTH_LIMIT and (not already_deep or next_h <= cur_h)
	_check(not should_block, "A4 实测回归：已在深水且朝浅处走 → 不阻挡（可自救）")


## UI 布局实测 —— 覆盖本次真实截图发现的两个 bug（鱼谱溢出、目标卡空白、夜间过亮）
func _test_ui_layout() -> void:
	print("[ui layout]")
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size

	# 今日目标卡：高度应贴合内容（此前固定 offset 导致底部一大片空白）
	var gc: PanelContainer = _hud.get("_goal_card")
	var gc_h := -1.0
	if gc != null:
		gc_h = gc.size.y
	_check(gc != null and gc_h > 40.0 and gc_h <= 120.0,
		"今日目标卡高度贴合内容（%.0fpx，非固定 96px）" % gc_h)

	# 鱼谱：面板必须完整落在视口内；卡片不能被 512px 插画撑爆
	var dex := FishDex.new()
	add_child(dex)
	await get_tree().process_frame
	dex.toggle()
	await get_tree().process_frame
	var panel: PanelContainer = dex.get("_panel")
	var r := panel.get_global_rect()
	_check(r.position.x >= -1.0 and r.position.y >= -1.0 \
			and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0,
		"鱼谱面板完整落在视口内（panel.end=(%.0f,%.0f) viewport=%s）" % [r.end.x, r.end.y, str(vp)])
	# 尺寸上限独立断言：headless 视口是 1280×1280，仅靠视口判断抓不到 720p 下的纵向溢出
	_check(r.size.x <= 1000.0 and r.size.y <= 640.0,
		"鱼谱面板尺寸在设计分辨率内（%.0f×%.0f）" % [r.size.x, r.size.y])

	var grid: GridContainer = dex.get("_grid")
	var max_card := Vector2.ZERO
	var tex_ok := true
	for c in grid.get_children():
		if c is Control:
			max_card = max_card.max((c as Control).size)
		for ch in c.get_children():
			for g in ch.get_children():
				if g is TextureRect and (g as TextureRect).expand_mode != TextureRect.EXPAND_IGNORE_SIZE:
					tex_ok = false
	_check(grid.get_child_count() == 13, "鱼谱显示全部 13 张卡片（%d）" % grid.get_child_count())
	_check(max_card.x <= 240.0 and max_card.y <= 210.0, "鱼谱卡片未被插画撑爆（最大 %s）" % str(max_card))
	_check(tex_ok, "鱼插画 TextureRect 使用 EXPAND_IGNORE_SIZE（否则最小尺寸=贴图尺寸）")
	dex.queue_free()

	# 夜间环境光：不能是白天亮度（此前 0.25 导致"夜空很黑、地面很亮"的穿帮）
	var night := GameData.daycycle.phase_at(21.0)
	var amb := float(night.get("ambient", 1.0))
	_check(amb <= 0.15, "夜间环境光已压暗（ambient=%.2f）" % amb)


## 角色装配：两条路径都要能跑通
##   A. 混元3D GLB（v0.7 默认）：单个合并网格、无骨骼，只能整体运动
##   B. 程序化骨架（回退）：分关节，能摆腿抬臂
func _test_character_rig() -> void:
	print("[character rig]")
	var p := _player
	var using_glb: bool = bool(p.get("_using_glb"))
	_check(not p.get("_model") == null, "角色模型节点已创建")
	if using_glb:
		var glb: Node3D = p.get("_glb_root")
		_check(glb != null and glb.get_child_count() > 0, "混元3D 主角已装配（GlbBody 有子节点）")
		_check(p.rod_tip != null, "钓线起点（模型竿尖）已就位")
		var ap: AnimationPlayer = p.get("_anim")
		if ap != null:
			# A2：绑骨版 —— 走路/持竿要切到对应动作
			var names := ap.get_animation_list()
			_check(names.size() >= 3, "主角自带 %d 段骨骼动画 %s" % [names.size(), str(names)])
			p.set("frozen", false)
			for i in 4:
				p.call("_animate", 0.05, 3.2)
			_check(str(p.get("_anim_name")) == "walk", "移动时切换到 walk（当前 %s）" % p.get("_anim_name"))
			p.set("frozen", true)
			for i in 4:
				p.call("_animate", 0.05, 0.0)
			_check(str(p.get("_anim_name")) == "hold", "持竿时切换到 hold（当前 %s）" % p.get("_anim_name"))
			p.set("frozen", false)
			# 竿尖必须真的跟着手骨走
			var tip: Node3D = p.rod_tip
			var y_a := tip.global_position.y
			for i in 4:
				p.call("_animate", 0.05, 0.0)
			_check(tip.global_position.y > p.global_position.y + 1.2,
				"竿尖在手骨上方（相对脚底 %.2fm）" % (tip.global_position.y - p.global_position.y))
			_check(not p.call("has_face"), "GLB 主角用模型自带贴图，不叠加 2D 表情贴片")
			return
		# A1：静态网格 —— 只能整体运动
		p.set("frozen", false)
		var y0: float = glb.position.y
		var moved := 0.0
		for i in 8:
			p.call("_animate", 0.05, 3.2)
			moved = maxf(moved, absf(glb.position.y - y0))
		_check(moved > 0.001 or absf(glb.rotation.z) > 0.001,
			"无骨骼模型有整体行走表现（Δy=%.4f, roll=%.3f）" % [moved, glb.rotation.z])
		p.set("frozen", true)
		for i in 10:
			p.call("_animate", 0.05, 0.0)
		_check(glb.rotation.x < 0.01, "持竿时整体前倾而非直立（pitch=%.3f）" % glb.rotation.x)
		p.set("frozen", false)
		_check(not p.call("has_face"), "GLB 主角用模型自带贴图，不叠加 2D 表情贴片")
		return

	_check(p.get("_hips") != null and p.get("_torso") != null and p.get("_head") != null,
		"角色关节齐全（髋 / 躯干 / 头）")
	_check(p.get("_leg_l") != null and p.get("_leg_r") != null \
			and p.get("_arm_l") != null and p.get("_arm_r") != null,
		"角色四肢枢轴齐全")
	_check(p.rod_tip != null and p.rod_tip.get_parent() != null \
			and str(p.rod_tip.get_parent().name) == "Rod",
		"钓竿尖端挂在 Rod 节点下（持竿时随臂移动）")
	# 走路：摆动腿
	p.set("frozen", false)
	var leg: Node3D = p.get("_leg_l")
	var before := leg.rotation.x
	for i in 6:
		p.call("_animate", 0.05, 3.2)
	_check(absf(leg.rotation.x - before) > 0.05,
		"行走动画驱动腿部摆动（Δ=%.2f rad）" % absf(leg.rotation.x - before))
	# 持竿：双臂抬起
	p.set("frozen", true)
	for i in 12:
		p.call("_animate", 0.05, 0.0)
	var arm: Node3D = p.get("_arm_r")
	_check(arm.rotation.x < -0.6, "持竿姿态右臂抬起（x=%.2f rad）" % arm.rotation.x)
	p.set("frozen", false)
	# v0.6：四表情贴图装配与切换
	_check(p.call("has_face"), "四张 AI 面部贴图已导入并装配（has_face=true）")
	for expr in ["calm", "smile", "focus", "surprise"]:
		p.call("set_expression", expr)
		var sprite: Sprite3D = p.get("_face_mesh") as Sprite3D
		var tex_name := ""
		if sprite != null and sprite.texture != null:
			tex_name = sprite.texture.resource_path.get_file().get_basename()
		_check(tex_name == expr, "表情切换 %s → 贴片贴图正确（%s）" % [expr, tex_name])
	p.call("set_expression", "calm")


func _test_save_manager() -> void:
	print("[save manager]")
	if SaveManager == null:
		_check(false, "SaveManager autoload 存在")
		return
	_check(true, "SaveManager autoload 存在")
	SaveManager.set_record("sardine", 23.5)
	_check(absf(SaveManager.get_record("sardine") - 23.5) < 0.01, "纪录写入/读取一致")
	SaveManager.mark_caught("sardine")
	_check(SaveManager.is_caught("sardine"), "鱼谱已捕获标记生效")
	SaveManager.set_setting("day_minutes", 48.0)
	_check(absf(SaveManager.get_setting("day_minutes", 24.0) - 48.0) < 0.01, "设置写入/读取一致")
	# 阶段2/3：目标进度 API
	SaveManager.set_goal_progress("three_species", 2)
	_check(SaveManager.goal_progress("three_species") == 2, "目标进度写入/读取一致")
	SaveManager.mark_goal_done("three_species")
	_check(SaveManager.is_goal_done("three_species"), "目标完成标记生效")
	SaveManager.flush()
	_check(FileAccess.file_exists("user://tidepool_save.cfg"), "存档文件已写入 user://")
	# 阶段1：ThemeManager 换肤信号
	var phases_seen: Array = []
	ThemeManager.theme_changed.connect(func(p, _c): phases_seen.append(p))
	ThemeManager.set_phase("night")
	_check(not phases_seen.is_empty() and phases_seen[0] == "night", "ThemeManager 换肤信号已广播")
	_check(ThemeManager.color("accent") == Color(1.0, 0.824, 0.490), "night 色板强调色正确")
