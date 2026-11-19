class_name FishingController
extends Node3D
## 钓鱼运行时封装 —— 驱动 FishingCore 并负责抛物线飞行、浮漂、鱼线与飞溅（Brief §2.2–2.4）

signal bait_changed(bait_id: String, count: int)
signal record_set(fish: FishDef, size_cm: float)

var core := FishingCore.new()
var player: Player = null
var hud: Hud = null
var inventory: Dictionary = {}   # bait_id -> count（-1 = 无限）
var current_bait := "dough"
var records: Dictionary = {}     # fish_id -> best size
var phase_provider: Callable = Callable()  # -> String 时段名
var audio: AudioSystem = null

var _bobber: Node3D = null
var _bobber_mat: StandardMaterial3D = null
var _line_mesh: ImmediateMesh = null
var _line_mi: MeshInstance3D = null
var _splash: CPUParticles3D = null
var _hooked_fish: FishSwimmer = null   # 中鱼后浮漂下的 3D 鱼

var _flying := false
var _flight_t := 0.0
var _flight_dur := 0.0
var _cast_origin := Vector3.ZERO
var _cast_target := Vector3.ZERO
var _max_line_out := 1.0
var _releasing := false
var _land_stuck := false


func _ready() -> void:
	_build_bobber()
	_build_line()
	_build_splash()

	core.fish_pool = GameData.fish_defs
	core.hook_window = GameData.hook_window
	core.bite_miss_escape = GameData.bite_miss_escape
	core.fallback_weight = GameData.fallback_bait_weight
	core.phase_provider = phase_provider
	core.setup(GameData.fish_defs, randi())
	core.state_changed.connect(_on_state_changed)
	core.charge_changed.connect(_on_charge_changed)
	core.cast_started.connect(_on_cast_started)
	core.nibble_happened.connect(_on_nibble)
	core.bite_started.connect(_on_bite)
	core.bite_missed.connect(_on_bite_missed)
	core.fish_hooked.connect(_on_fish_hooked)
	core.fish_caught.connect(_on_fish_caught)
	core.line_snapped.connect(_on_line_snapped)
	core.fish_escaped.connect(_on_fish_escaped)
	core.tension_changed.connect(_on_tension_changed)  # S2：张力条此前从未收到更新
	if hud != null:
		hud.result_action.connect(_on_result_action)

	for b in GameData.baits:
		var bid := str(b["id"])
		inventory[bid] = SaveManager.get_bait_count(bid, int(b.get("count", 0)))
	current_bait = "dough"
	bait_changed.emit(current_bait, inventory[current_bait])


# ================= 视觉搭建 =================

func _build_bobber() -> void:
	_bobber = Node3D.new()
	_bobber.name = "Bobber"
	_bobber.visible = false
	add_child(_bobber)
	var top := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.12
	tm.height = 0.24
	top.mesh = tm
	_bobber_mat = StandardMaterial3D.new()
	_bobber_mat.albedo_color = Color(0.85, 0.2, 0.15)
	_bobber_mat.roughness = 0.4
	top.material_override = _bobber_mat
	top.position.y = 0.06
	_bobber.add_child(top)
	var bottom := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.12
	bm.height = 0.24
	bottom.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.95, 0.93, 0.88)
	bottom.material_override = bmat
	bottom.position.y = -0.06
	_bobber.add_child(bottom)


func _build_line() -> void:
	_line_mesh = ImmediateMesh.new()
	_line_mi = MeshInstance3D.new()
	_line_mi.mesh = _line_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.95)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mi.material_override = mat
	_line_mi.visible = false
	_line_mi.top_level = true
	add_child(_line_mi)


func _build_splash() -> void:
	_splash = CPUParticles3D.new()
	_splash.emitting = false
	_splash.one_shot = true
	_splash.amount = 14
	_splash.lifetime = 0.55
	_splash.explosiveness = 1.0
	_splash.direction = Vector3.UP
	_splash.spread = 55.0
	_splash.initial_velocity_min = 1.6
	_splash.initial_velocity_max = 3.0
	_splash.gravity = Vector3(0, -9.8, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	_splash.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.97, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash.material_override = mat
	add_child(_splash)


# ================= 输入 =================

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if core.state == FishingCore.State.IDLE:
				core.request_charge()
			else:
				core.hook_press()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_releasing = true
	elif event is InputEventMouseButton and not event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			core.release_cast()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_releasing = false
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_Q:
			_cycle_bait()
		elif k == KEY_SPACE:
			core.give_up()


func _cycle_bait() -> void:
	var ids: Array[String] = []
	for b in GameData.baits:
		ids.append(str(b["id"]))
	var idx := ids.find(current_bait)
	for step in ids.size():
		var cand := ids[(idx + 1 + step) % ids.size()]
		if int(inventory.get(cand, 0)) != 0:
			current_bait = cand
			bait_changed.emit(current_bait, inventory[current_bait])
			if hud != null:
				hud.toast("挂上 %s" % GameData.bait_name(current_bait), 1.4)
			return


# ================= 主循环 =================

func _process(dt: float) -> void:
	var reeling := core.state == FishingCore.State.REELING and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	core.tick(dt, reeling, _releasing and core.state == FishingCore.State.REELING)
	_update_bobber(dt)
	_update_line()


func _update_bobber(dt: float) -> void:
	if not _bobber.visible:
		return
	var t := Time.get_ticks_msec() * 0.001
	if _flying:
		_flight_t += dt / maxf(_flight_dur, 0.05)
		var k := clampf(_flight_t, 0.0, 1.0)
		var pos := _cast_origin.lerp(_cast_target, k)
		var peak := _cast_origin.distance_to(_cast_target) * 0.18 + 1.0
		pos.y += peak * 4.0 * k * (1.0 - k)
		_bobber.global_position = pos
		if k >= 1.0:
			_flying = false
			_on_flight_done()
		return
	if _land_stuck:
		return
	match core.state:
		FishingCore.State.WAITING:
			_bobber.global_position.y = WaterMath.wave_height(_bobber.global_position.x, _bobber.global_position.z, t) + 0.05
		FishingCore.State.BITE:
			_bobber.global_position.y = WaterMath.wave_height(_bobber.global_position.x, _bobber.global_position.z, t) - 0.22 * absf(sin(t * 9.0))
		FishingCore.State.REELING:
			var p := player.global_position + player.camera_forward_flat() * 1.2
			var progress := 1.0 - clampf(core.line_out / maxf(_max_line_out, 0.1), 0.0, 1.0)
			# A3 修复：_cast_target 是抛竿落点锚点，必须保持不变，
			# 否则放线时 progress 变小也无法退回真实远处（视觉与 line_out 脱节）
			var pos := _cast_target.lerp(p, progress)
			pos.y = WaterMath.wave_height(pos.x, pos.z, t) + 0.05
			_bobber.global_position = pos
		_:
			pass


func _update_line() -> void:
	if _bobber == null or player == null or player.rod_tip == null:
		return
	var show := _bobber.visible and core.state != FishingCore.State.IDLE
	_line_mi.visible = show
	if not show:
		return
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line_mesh.surface_add_vertex(player.rod_tip.global_position)
	_line_mesh.surface_add_vertex(_bobber.global_position)
	_line_mesh.surface_end()


# ================= 核心信号 =================

func _on_state_changed(s: int) -> void:
	if player != null:
		player.frozen = s != FishingCore.State.IDLE
	if hud != null:
		hud.set_mode(s)
	if s == FishingCore.State.IDLE:
		_bobber.visible = false
		_land_stuck = false
		_flying = false


func _on_charge_changed(v: float) -> void:
	if hud != null:
		hud.set_charge(v)


func _on_cast_started(dist: float) -> void:
	var casts := int(SaveManager.get_setting("cast_count", 0)) + 1
	SaveManager.set_setting("cast_count", casts)
	if hud != null:
		hud.set_situational_hint(FishingCore.State.CASTING)
	if audio != null:
		audio.play_sfx("cast")
	_cast_origin = player.rod_tip.global_position
	var dir := player.camera_forward_flat()
	_cast_target = player.global_position + dir * dist
	_cast_target.y = 0.0
	var zone := WorldBuilder.zone_for_position(_cast_target)
	if zone == "land":
		_cast_target.y = WorldBuilder.island_height(_cast_target.x, _cast_target.z) + 0.15
	_max_line_out = maxf(dist * 0.8, 1.0)
	_flight_t = 0.0
	_flight_dur = 0.45 + dist * 0.02
	_flying = true
	_bobber.visible = true
	_bobber.global_position = _cast_origin


func _on_flight_done() -> void:
	var zone := WorldBuilder.zone_for_position(_cast_target)
	if zone == "land":
		_land_stuck = true
		_splash.global_position = _cast_target
		core.land_bobber("land", current_bait)
		if hud != null:
			hud.toast("挂住了……扯杆重抛吧", 2.0)
			hud.set_charge(0.0)
		return
	_splash.global_position = _cast_target + Vector3(0, 0.1, 0)
	_splash.restart()
	if audio != null:
		audio.play_sfx("splash")
	core.land_bobber(zone, current_bait)


func _on_nibble() -> void:
	_face("focus", 1.2)
	if audio != null:
		audio.play_sfx("nibble")
	if hud != null:
		hud.pulse_bobber_hint("……轻点（试探中，别急）")


## 表情驱动：贴图缺失时 player.set_expression 会安全跳过
func _face(expr: String, duration := 0.0) -> void:
	if player != null:
		player.set_expression(expr, duration)


func _on_bite() -> void:
	_face("surprise", 0.9)
	if audio != null:
		audio.play_sfx("bite")
		audio.duck(-6.0)  # 咬钩瞬间压低环境声，让"就是现在"被听见
	if hud != null:
		hud.show_bite(true)


func _on_bite_missed() -> void:
	_face("calm", 0.0)
	if hud != null:
		hud.show_bite(false)
		hud.toast("慢了半拍……")


func _on_fish_hooked(f: FishDef) -> void:
	# 消耗鱼饵
	var c := int(inventory.get(current_bait, 0))
	if c > 0:
		inventory[current_bait] = c - 1
		SaveManager.set_bait_count(current_bait, c - 1)
		SaveManager.flush()
		if c - 1 == 0:
			current_bait = "dough"
			bait_changed.emit(current_bait, inventory[current_bait])
			if hud != null:
				hud.toast("%s 用完了，换回面团" % GameData.bait_name(current_bait), 1.8)
		else:
			bait_changed.emit(current_bait, inventory[current_bait])
	if audio != null:
		audio.play_sfx("hook")
	if hud != null:
		hud.show_bite(false)
		hud.toast("中鱼！", 1.0)
	_spawn_hooked_fish(f)


## 中鱼后水下能看到那条鱼在浮漂附近挣扎（只对有 3D 模型的鱼种生效）
func _spawn_hooked_fish(f: FishDef) -> void:
	_despawn_fish()
	if f == null or FishSwimmer.model_path(f.id) == "":
		return
	var pos := _bobber.global_position if _bobber != null else player.global_position
	_hooked_fish = FishSwimmer.new()
	_hooked_fish.name = "HookedFish"
	add_child(_hooked_fish)
	_hooked_fish.setup_hooked(f.id, pos)


func _despawn_fish() -> void:
	if _hooked_fish != null and is_instance_valid(_hooked_fish):
		_hooked_fish.queue_free()
	_hooked_fish = null


## 上鱼瞬间：鱼从浮漂处跃出水面一小段，然后消失（给"真的钓到了"一个物理交代）
func _spawn_leap_fish(f: FishDef) -> void:
	if f == null or f.junk or f.auto_release or f.force_release:
		return
	if FishSwimmer.model_path(f.id) == "":
		return
	if _bobber == null:
		return
	var from := _bobber.global_position + Vector3(0, -0.12, 0)
	# 朝玩家方向跃起，落在两者之间偏上方
	var to := from.lerp(player.global_position + Vector3(0, 1.0, 0), 0.35) + Vector3(0, 1.25, 0)
	var fl := FishSwimmer.new()
	fl.name = "LeapFish"
	add_child(fl)
	fl.setup_leap(f.id, from, to)


func _on_fish_caught(f: FishDef, size: float, junk_name: String) -> void:
	_face("smile", 2.4)
	_despawn_fish()
	_spawn_leap_fish(f)
	if audio != null:
		audio.play_sfx("catch")
	if hud == null:
		return
	if f.junk:
		hud.show_result("钓到了%s" % junk_name, ["在潮汐小岛，你什么都能钓到。"])
		return
	if f.auto_release:
		hud.show_result("水母：请勿垂钓", ["轻轻一抖，它滑回了海里。（已放生）"])
		return
	if f.force_release:
		hud.show_result("与鲨同游", ["%s · 约 %.0f cm" % [f.fish_name, size], "巨力三连冲——你割断了线。", "★ 成就：与鲨同游"])
		return
	var prev := SaveManager.get_record(f.id)
	var is_record := size > prev and prev > 0.0
	records[f.id] = maxf(prev, size)
	SaveManager.set_record(f.id, size)
	SaveManager.mark_caught(f.id)
	SaveManager.flush()
	_update_goals(f, size)
	if is_record:
		record_set.emit(f, size)
	var stars := ""
	for i in f.rarity:
		stars += "★"
	hud.show_result("钓到了！%s" % f.fish_name, [
		"%.0f cm" % size,
		stars,
		"★ 新纪录" if is_record else "",
	], {"id": f.id, "name": f.fish_name, "size": size, "rare": f.rarity})


## 今日目标进度：从 goals.json 数据驱动，避免硬编码
func _update_goals(f: FishDef, size: float) -> void:
	var phase := "noon"
	if phase_provider.is_valid():
		phase = str(phase_provider.call())
	for g in GameData.goals:
		if SaveManager.is_goal_done(str(g["id"])):
			continue
		var gid := str(g["id"])
		var kind := str(g.get("type", ""))
		var target := int(g.get("target", 1))
		var progress := 0
		match kind:
			"species_count":
				progress = SaveManager.caught_list().size()
			"phase_catch":
				if str(g.get("phase", "")) == phase:
					progress = 1
			"size":
				if size >= float(target):
					progress = int(target)
		if progress > 0:
			SaveManager.set_goal_progress(gid, progress)
		if progress >= target:
			SaveManager.mark_goal_done(gid)
			if hud != null:
				hud.show_achievement("★ " + str(g.get("reward", "今日小目标达成")))
	if hud != null:
		hud.update_goal_display()
		hud.update_dex_display()


func _on_line_snapped() -> void:
	_face("surprise", 1.6)
	_despawn_fish()
	if audio != null:
		audio.play_sfx("snap")
	if hud != null:
		hud.toast("啪——线断了。它还在下面。", 2.6)
		hud.set_charge(0.0)


func _on_tension_changed(v: float) -> void:
	if hud != null:
		hud.set_tension(v)


func _on_result_action(_action: String, _fish_info: Dictionary) -> void:
	# 保留/放生的正反馈文案已在 HUD 内处理；此处留给未来扩展（如鱼篓库存）
	pass


func _on_fish_escaped(reason: String) -> void:
	_despawn_fish()
	if hud == null:
		return
	hud.set_charge(0.0)
	match reason:
		"early":
			hud.toast("太急了，它被吓跑了。", 2.2)
		"missed":
			pass  # 咬钩未中已由 bite_missed 提示
		"give_up":
			hud.toast("收杆。", 1.2)
