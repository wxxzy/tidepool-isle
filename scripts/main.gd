extends Node3D
## 主场景装配 —— 世界 / 玩家 / 昼夜 / 钓鱼 / HUD 的组装与输入捕获（Brief M0-M2 切片）

var day_night: DayNightDriver = null
var player: Player = null
var fishing: FishingController = null
var hud: Hud = null
var fish_dex: FishDex = null
var audio: AudioSystem = null

## 自检截图：导出包也能用。启动参数 --shot=<绝对路径> [--shot-frames=N] [--shot-move]
## 用途：验证"导出的 exe 到底长什么样"，而不是只看编辑器/脚本模式
var _shot_path := ""
var _shot_frames := 0
var _shot_move := false


func _ready() -> void:
	for e in GameData.errors():
		push_error(e)

	var refs := WorldBuilder.build(self)

	# ---- 环境与光照 ----
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.85, 0.92, 0.95)
	env.fog_sky_affect = 0.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	# ---- 玩家 ----
	player = Player.new()
	player.name = "Player"
	player.position = refs["spawn"]
	add_child(player)
	player.surface_provider = func() -> String:
		return WorldBuilder.surface_type_at(player.global_position.x, player.global_position.z)

	# ---- HUD ----
	hud = Hud.new()
	add_child(hud)

	# ---- 昼夜 ----
	day_night = DayNightDriver.new()
	day_night.name = "DayNight"
	day_night.cycle = GameData.daycycle
	day_night.hour = GameData.daycycle.start_hour
	day_night.sun = sun
	day_night.environment = env
	day_night.sky_mat = sky_mat
	day_night.water_mat = refs["water"].material_override as ShaderMaterial
	day_night.night_lights = [refs["dock"]["lamp"], refs["hut"]["window_light"]]
	day_night.fireflies = refs["fireflies"]
	day_night.on_phase_changed = func(label: String, clock: String) -> void:
		var phase_name := str(GameData.daycycle.phase_at(day_night.hour).get("name", "noon"))
		ThemeManager.set_phase(phase_name)  # 全局换肤：先更新色板，UI 通过 theme_changed 自行刷新
		hud.set_time(label, clock, phase_name)
		if audio != null:
			audio.set_phase(phase_name, day_night.night_factor(DayCycle.light_elevation(day_night.hour)) > 0.5)
	add_child(day_night)
	day_night.apply()

	# ---- 钓鱼 ----
	fishing = FishingController.new()
	fishing.name = "Fishing"
	fishing.player = player
	fishing.hud = hud
	fishing.phase_provider = func() -> String:
		return str(GameData.daycycle.phase_at(day_night.hour).get("name", "noon"))
	# B4 修复：先连接信号再 add_child —— add_child 会立刻触发 _ready，
	# 而 controller 在 _ready 里 emit bait_changed，晚连接会丢事件
	fishing.bait_changed.connect(_on_bait_changed)
	fishing.record_set.connect(func(_f: FishDef, _s: float) -> void:
		hud.toast("新纪录！已记入鱼谱。", 1.8)
		player.set_expression("smile", 2.4))
	add_child(fishing)
	hud.set_bait(_bait_text())

	# ---- 鱼谱图鉴（Tab）----
	fish_dex = FishDex.new()
	fish_dex.name = "FishDex"
	add_child(fish_dex)

	# ---- 音频（P3）----
	audio = AudioSystem.new()
	audio.name = "Audio"
	add_child(audio)
	fishing.audio = audio

	# ---- 鱼群（混元3D 模型）----
	_spawn_fish_school(refs)

	hud.toast("欢迎来到潮汐小岛。今天想钓点什么？", 3.5)
	# Web 上浏览器拒绝自动指针锁定与音频播放，改为等待首次点击（手势）解锁
	if OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.toast("点击画面开始 · 潮汐小岛", 6.0)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_parse_shot_args()


func _parse_shot_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-frames="):
			_shot_frames = int(a.substr(14))
		elif a == "--shot-move":
			_shot_move = true
	if _shot_path != "" and _shot_frames <= 0:
		_shot_frames = 90
	if _shot_path != "":
		print("自检截图已启用 -> ", _shot_path, " 等待 ", _shot_frames, " 帧")


func _process(_dt: float) -> void:
	if _shot_path == "":
		return
	if _shot_move and player != null:
		# 让角色朝海边走，顺便验证行走动画与镜头跟随
		var dir := Vector3(1, 0, 0)
		player.global_position += dir * 0.03
		player.get("_model").rotation.y = atan2(dir.x, dir.z) if player.get("_model") != null else 0.0
	_shot_frames -= 1
	if _shot_frames > 0:
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path) if img != null else FAILED
	print("SHOT_SAVED ", _shot_path, " err=", err)
	_shot_path = ""
	get_tree().quit()


## 近岸鱼群：围着岛外围巡游，深浅分层，让水面之下"有东西"
## 用固定随机种子，保证每次进入游戏的观感一致
func _spawn_fish_school(_refs: Dictionary) -> void:
	var kinds := FishSwimmer.available_species()
	if kinds.is_empty():
		push_warning("没有可用的鱼模型，跳过鱼群")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var school := Node3D.new()
	school.name = "FishSchool"
	add_child(school)

	# 浅水（能看见）与深水（只露影子）两带
	var bands := [
		{"r": [47.0, 56.0], "depth": [0.25, 0.50], "count": 16},
		{"r": [57.0, 74.0], "depth": [0.60, 1.20], "count": 10},
	]
	for band in bands:
		for i in int(band["count"]):
			var id: String = kinds[rng.randi() % kinds.size()]
			var rr := rng.randf_range(band["r"][0], band["r"][1])
			var d := rng.randf_range(band["depth"][0], band["depth"][1])
			# 每群 2 条同种同向，读起来像"群"
			var base_phase := rng.randf() * TAU
			var dir := 1.0 if rng.randf() > 0.5 else -1.0
			for j in 2:
				var f := FishSwimmer.new()
				f.name = "Fish_%s_%d_%d" % [id, i, j]
				school.add_child(f)
				f.setup_orbit(id,
					Vector3(0, 0, 0),
					rr + j * 0.85,
					d + j * 0.12,
					dir * (0.16 + 8.0 / maxf(rr, 1.0)) * rng.randf_range(0.85, 1.15),
					base_phase + j * 0.35)


func _bait_text() -> String:
	var c := int(fishing.inventory.get(fishing.current_bait, 0))
	var n := GameData.bait_name(fishing.current_bait)
	return "%s ×%s" % [n, "∞" if c < 0 else str(c)]


func _on_bait_changed(bait_id: String, count: int) -> void:
	hud.set_bait("%s ×%s" % [GameData.bait_name(bait_id), "∞" if count < 0 else str(count)])


func _unhandled_input(event: InputEvent) -> void:
	# Tab：切换鱼谱；鱼谱打开时优先消费筛选数字键
	if fish_dex != null:
		if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).physical_keycode == KEY_TAB:
			fish_dex.toggle()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if fish_dex.is_open() else Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		if fish_dex.is_open() and fish_dex.handle_input(event):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if audio != null:
			audio.unlock_audio()  # Web AudioContext 必须在用户手势中解锁
		get_viewport().set_input_as_handled()
