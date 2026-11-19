class_name FishingCore
extends RefCounted
## 钓鱼状态机核心 —— 纯逻辑、无节点依赖，可 headless 确定性测试（Brief §2.2–2.4）
##
## 状态流：IDLE → CHARGING → CASTING(控制器驱动飞行) → WAITING(静默/轻点)
##        → BITE(0.4s 窗口) → REELING(张力博弈) → IDLE
## 所有数值对应 Brief 默认值，[可调]。

signal state_changed(new_state: int)
signal charge_changed(value: float)
signal cast_started(distance_m: float)
signal nibble_happened
signal bite_started
signal bite_missed
signal fish_hooked(fish: FishDef)
signal fish_caught(fish: FishDef, size_cm: float, junk_name: String)
signal line_snapped
signal fish_escaped(reason: String)  # early / missed / give_up
signal tension_changed(value: float)

enum State { IDLE, CHARGING, CASTING, WAITING, BITE, REELING }

# --- 抛竿 ---
const CAST_MIN_DIST := 5.0
const CAST_MAX_DIST := 35.0
const CAST_SPREAD := 1.5

# --- 等待与咬钩 ---
const SILENT_WAIT_MIN := 3.0
const SILENT_WAIT_MAX := 20.0
const NIBBLE_WINDOW_MIN := 0.4
const NIBBLE_WINDOW_MAX := 0.9

# --- 溜鱼 ---
const REEL_RATE := 14.0          # 收线张力增速 /s
const RELEASE_RATE := 22.0       # 放线张力降速 /s
const TENSION_DECAY := 8.0       # 松弛自然降速 /s
const REEL_SPEED := 3.2          # 收线距离速度 m/s
const SLACK_OUT_SPEED := 1.5     # 放线距离速度 m/s
const TENSION_SNAP := 95.0
const SNAP_HOLD := 1.2
const STRUGGLE_STAMINA_DRAIN := 8.0
const REEL_STAMINA_DRAIN := 2.0
const TIRED_FACTOR := 0.35       # 体力耗尽后挣扎衰减
const VANISH_DROP := 60.0        # 失联型：张力快速归零

var state: int = State.IDLE
var charge: float = 0.0
var cast_distance: float = 0.0
var tension: float = 0.0
var line_out: float = 0.0
var over_tension: float = 0.0
var fish: FishDef = null
var fish_size: float = 0.0
var junk_name: String = ""
var fish_stamina: float = 0.0
var fish_stamina_max: float = 0.0

var fish_pool: Array[FishDef] = []
var phase_provider: Callable = Callable()   # -> String (当前时段名)
var fallback_weight: float = 0.15
var hook_window: float = 0.4
var bite_miss_escape: float = 0.35

var _rng := RandomNumberGenerator.new()
var _wait_left := 0.0
var _nibbles_left := 0
var _nibble_gap := 0.0
var _nibbling := false
var _bite_left := 0.0
var _bite_delay := 0.0   # 最后一次轻点 → 沉漂之间的前摇
var _struggle_timer := 0.0
var _struggling := false
var _struggle_left := 0.0
var _vanish_left := 0.0
var _tired := false
var _zone := ""
var bait_of_zone: String = "dough"  # 当前挂饵（land_bobber 时更新）


func setup(pool: Array[FishDef], rng_seed: int) -> void:
	fish_pool = pool
	_rng.seed = rng_seed


func reset() -> void:
	# 必须先经 _set_state 发信号：直接赋值会让 state_changed 永远不触发，
	# 导致 controller 收不到 IDLE 通知、player.frozen 永久为真（S1 bug）
	_set_state(State.IDLE)
	charge = 0.0
	tension = 0.0
	line_out = 0.0
	over_tension = 0.0
	fish = null
	fish_size = 0.0
	junk_name = ""
	_nibbling = false
	_nibbles_left = 0
	_vanish_left = 0.0
	_struggling = false
	_tired = false


func _set_state(s: int) -> void:
	if state != s:
		state = s
		state_changed.emit(s)


# ================= 输入接口 =================

func request_charge() -> bool:
	if state != State.IDLE:
		return false
	charge = 0.0
	_set_state(State.CHARGING)
	return true


func release_cast() -> bool:
	if state != State.CHARGING:
		return false
	cast_distance = lerpf(CAST_MIN_DIST, CAST_MAX_DIST, clampf(charge, 0.0, 1.0))
	cast_distance += _rng.randf_range(-CAST_SPREAD, CAST_SPREAD)
	cast_distance = clampf(cast_distance, CAST_MIN_DIST, CAST_MAX_DIST)
	_set_state(State.CASTING)
	cast_started.emit(cast_distance)
	return true


## 控制器在抛物线落点后调用；zone == "land" 表示抛到岸上（卡住事件）
func land_bobber(zone: String, bait_id: String) -> bool:
	if state != State.CASTING:
		return false
	if zone == "land":
		reset()
		return false
	_zone = zone
	bait_of_zone = bait_id
	fish = null
	_set_state(State.WAITING)
	_schedule_silence()
	return true


## 左键语义：BITE=刺鱼；轻点中=抢跑；其余=收杆检查
func hook_press() -> bool:
	match state:
		State.BITE:
			_hook()
			return true
		State.WAITING:
			if _nibbling:
				fish_escaped.emit("early")
				reset()
				return true
			give_up()
			return true
		_:
			return false


func give_up() -> void:
	if state in [State.WAITING, State.BITE, State.REELING, State.CASTING, State.CHARGING]:
		if state == State.REELING:
			fish_escaped.emit("give_up")
		reset()


# ================= 主循环 =================

func tick(dt: float, reeling: bool, releasing: bool) -> void:
	match state:
		State.CHARGING:
			charge = clampf(charge + dt, 0.0, 1.0)
			charge_changed.emit(charge)
		State.WAITING:
			_tick_waiting(dt)
		State.BITE:
			_bite_left -= dt
			if _bite_left <= 0.0:
				bite_missed.emit()
				if _rng.randf() < bite_miss_escape:
					fish_escaped.emit("missed")
					reset()
				else:
					_set_state(State.WAITING)
					_schedule_silence()
		State.REELING:
			_tick_reeling(dt, reeling, releasing)
		_:
			pass


func _tick_waiting(dt: float) -> void:
	if _nibbles_left > 0:
		_nibble_gap -= dt
		if _nibble_gap <= 0.0:
			_nibbles_left -= 1
			nibble_happened.emit()
			if _nibbles_left <= 0:
				_bite_delay = _rng.randf_range(0.35, 0.8)
			else:
				_nibble_gap = _rng.randf_range(NIBBLE_WINDOW_MIN, NIBBLE_WINDOW_MAX)
	elif _bite_delay > 0.0:
		_bite_delay -= dt
		if _bite_delay <= 0.0:
			_try_bite()
	else:
		_wait_left -= dt
		if _wait_left <= 0.0:
			_start_nibbles()


func _start_nibbles() -> void:
	# 没有匹配的鱼时保持静默（选不到鱼 = 此地此时无鱼）
	if _select_fish() == null:
		_schedule_silence()
		return
	_nibbles_left = _rng.randi_range(1, 4)
	_nibble_gap = _rng.randf_range(NIBBLE_WINDOW_MIN, NIBBLE_WINDOW_MAX)
	_nibbling = true


func _try_bite() -> void:
	var f := _select_fish()
	if f == null:
		_schedule_silence()
		return
	fish = f
	_bite_left = hook_window
	_set_state(State.BITE)
	bite_started.emit()


func _schedule_silence() -> void:
	_nibbling = false
	_nibbles_left = 0
	_bite_delay = 0.0
	_wait_left = _rng.randf_range(SILENT_WAIT_MIN, SILENT_WAIT_MAX)


func _select_fish() -> FishDef:
	var phase := "noon"
	if phase_provider.is_valid():
		phase = str(phase_provider.call())
	return pick_fish(_rng, fish_pool, phase, _zone, bait_of_zone, fallback_weight)


## 纯函数：按时段/钓点/鱼饵加权随机选鱼（可独立测试）
static func pick_fish(rng: RandomNumberGenerator, pool: Array[FishDef], phase: String, zone: String, bait_id: String, fallback: float) -> FishDef:
	var total := 0.0
	var weights: Array[float] = []
	for f in pool:
		if not f.matches(phase, zone):
			weights.append(0.0)
			continue
		var w := f.bait_weight(bait_id, fallback)
		var rarity_factor := 0.3 if f.rarity <= 0 else pow(0.5, float(f.rarity - 1))
		w *= rarity_factor
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


# ================= 溜鱼 =================

func _hook() -> void:
	fish_size = fish.roll_size(_rng)
	junk_name = fish.roll_junk_name(_rng)
	var st: Dictionary = fish.struggle
	fish_stamina_max = float(st.get("stamina", 40.0))
	fish_stamina = fish_stamina_max
	_struggle_timer = _rng.randf_range(float(st.get("interval", [1.0, 2.0])[0]), float(st.get("interval", [1.0, 2.0])[1])) * 0.5
	_struggling = false
	_tired = false
	tension = 30.0
	line_out = cast_distance * 0.8
	over_tension = 0.0
	_set_state(State.REELING)
	fish_hooked.emit(fish)


func _tick_reeling(dt: float, reeling: bool, releasing: bool) -> void:
	var st: Dictionary = fish.struggle if fish != null else {}
	var stype := str(st.get("type", "none"))
	var surge := float(st.get("surge", 0.0))
	if _tired:
		surge *= TIRED_FACTOR

	# 挣扎调度
	if _vanish_left > 0.0:
		_vanish_left -= dt
		tension = maxf(0.0, tension - VANISH_DROP * dt)
		if _vanish_left <= 0.0:
			_struggling = false
			_struggle_timer = _rng.randf_range(float(st.get("interval", [1.0, 2.0])[0]), float(st.get("interval", [1.0, 2.0])[1]))
	else:
		if _struggling:
			_struggle_left -= dt
			if _struggle_left <= 0.0:
				_struggling = false
				_struggle_timer = _rng.randf_range(float(st.get("interval", [1.0, 2.0])[0]), float(st.get("interval", [1.0, 2.0])[1]))
		else:
			_struggle_timer -= dt
			if _struggle_timer <= 0.0 and surge > 0.0:
				_struggling = true
				_struggle_left = float(st.get("surge_time", 0.8))
				if stype == "vanish":
					_vanish_left = _rng.randf_range(float(st.get("vanish_time", [2.0, 4.0])[0]), float(st.get("vanish_time", [2.0, 4.0])[1]))

	# 失联期：张力归零、收放线均无效
	if _vanish_left > 0.0:
		tension_changed.emit(tension)
		return

	# 张力三态
	var base := -TENSION_DECAY
	if reeling:
		base = REEL_RATE
	elif releasing:
		base = -RELEASE_RATE
	if _struggling:
		base += surge
	tension = clampf(tension + base * dt, 0.0, 100.0)

	# 体力
	if _struggling:
		fish_stamina -= STRUGGLE_STAMINA_DRAIN * dt
	elif reeling:
		fish_stamina -= REEL_STAMINA_DRAIN * dt
	if fish_stamina <= 0.0 and not _tired:
		_tired = true

	# 距离
	if reeling:
		line_out -= REEL_SPEED * dt
	elif releasing:
		line_out += SLACK_OUT_SPEED * dt

	# 断线判定
	if tension > TENSION_SNAP:
		over_tension += dt
		if over_tension >= SNAP_HOLD:
			line_snapped.emit()
			reset()
			return
	else:
		over_tension = maxf(0.0, over_tension - 2.0 * dt)

	tension_changed.emit(tension)

	# 上岸
	if line_out <= 0.0:
		line_out = 0.0
		fish_caught.emit(fish, fish_size, junk_name)
		reset()
