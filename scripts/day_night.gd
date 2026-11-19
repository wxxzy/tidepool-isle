class_name DayNightDriver
extends Node3D
## 昼夜驱动 —— 太阳/月亮轨迹、天空关键帧插值、夜间灯光与萤火虫（Brief §2.5）
## 时间就是氛围本身：除暂停外任何操作不停止时间。

var cycle: DayCycle = null
var hour: float = 8.0

var sun: DirectionalLight3D = null
var environment: Environment = null
var sky_mat: ProceduralSkyMaterial = null
var water_mat: ShaderMaterial = null
var night_lights: Array = []
var fireflies: CPUParticles3D = null
var on_phase_changed: Callable = Callable()   # (label: String, clock: String)


func _process(dt: float) -> void:
	if cycle == null:
		return
	hour = cycle.advance(hour, dt)
	apply()


func apply() -> void:
	if cycle == null:
		return
	var s := cycle.sample(hour)
	if s.is_empty():
		return
	# 天空
	if sky_mat != null:
		sky_mat.sky_top_color = s["sky_top"]
		sky_mat.sky_horizon_color = s["sky_horizon"]
		sky_mat.ground_bottom_color = s["ground_bottom"]
		sky_mat.ground_horizon_color = s["ground_horizon"]
	# 环境光与雾
	if environment != null:
		environment.ambient_light_energy = float(s["ambient"])
		# 环境光染色：夜间偏冷蓝，避免"夜空很黑但地面仍白天亮度"的穿帮
		var lc: Color = s["light_color"]
		environment.ambient_light_color = Color(
			lerpf(1.0, lc.r, 0.35), lerpf(1.0, lc.g, 0.35), lerpf(1.0, lc.b, 0.30)
		)
		environment.fog_light_color = s["fog"]
	var elev := DayCycle.light_elevation(hour)
	# 太阳/月亮
	if sun != null:
		sun.light_color = s["light_color"]
		var t := clampf((elev + 1.0) * 0.5, 0.0, 1.0)
		sun.rotation = Vector3(lerpf(deg_to_rad(-22.0), deg_to_rad(-80.0), t), deg_to_rad(18.0 + 24.0 * sin(hour / 24.0 * TAU)), 0.0)
		sun.light_energy = maxf(0.06, float(s["light_energy"]))
		var want_shadow := elev > -0.2
		if sun.shadow_enabled != want_shadow:
			sun.shadow_enabled = want_shadow  # 仅跨阈值时切换，避免每帧变更渲染路径
	# 夜间要素
	var nf := night_factor(elev)
	for l in night_lights:
		l.light_energy = nf * (1.6 if l.omni_range > 10.0 else 1.1)
	if fireflies != null:
		fireflies.emitting = nf > 0.5
	if water_mat != null:
		water_mat.set_shader_parameter("night_mix", nf)
	if on_phase_changed.is_valid():
		var clock := DayCycle.clock_text(hour)
		if clock != _last_clock:
			_last_clock = clock
			on_phase_changed.call(str(s["label"]), clock)


var _last_clock := ""


## 夜间系数：elev > 0.15 → 0；elev < -0.2 → 1
func night_factor(elev: float) -> float:
	return clampf(remap(elev, 0.15, -0.2, 0.0, 1.0), 0.0, 1.0)
