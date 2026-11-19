class_name DayCycle
extends RefCounted
## 昼夜循环 —— 由 data/daycycle.json 数据驱动（Brief §1.4 / L4）
## 六时段关键帧 + 边界平滑过渡（默认 0.5h crossfade）

var day_length_minutes: float = 24.0
var start_hour: float = 8.0
var boundary_fade: float = 0.5
var phases: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> DayCycle:
	var dc := DayCycle.new()
	dc.day_length_minutes = float(d.get("day_length_minutes", 24.0))
	dc.start_hour = float(d.get("start_hour", 8.0))
	dc.boundary_fade = float(d.get("boundary_fade_hours", 0.5))
	for p in d.get("phases", []):
		if p is Dictionary:
			dc.phases.append({
				"name": str(p.get("name", "")),
				"label": str(p.get("label", "")),
				"start": float(p.get("start", 0.0)),
				"sky_top": _col(p.get("sky_top")),
				"sky_horizon": _col(p.get("sky_horizon")),
				"ground_bottom": _col(p.get("ground_bottom")),
				"ground_horizon": _col(p.get("ground_horizon")),
				"light_color": _col(p.get("light_color")),
				"light_energy": float(p.get("light_energy", 1.0)),
				"ambient": float(p.get("ambient", 0.6)),
				"fog": _col(p.get("fog")),
			})
	dc.phases.sort_custom(func(a, b): return float(a["start"]) < float(b["start"]))
	return dc


static func _col(arr) -> Color:
	if arr is Array and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color.WHITE


## 返回 hour 所在时段索引（夜间跨午夜回卷）
func phase_index_at(hour: float) -> int:
	if phases.is_empty():
		return -1
	var h := fposmod(hour, 24.0)
	for i in phases.size():
		var s := float(phases[i]["start"])
		var e := _phase_end(i)
		if s <= h and h < e:
			return i
		if h < s:  # 已越过午夜回卷点，属于上一时段
			return phases.size() - 1
	return phases.size() - 1


func _phase_end(i: int) -> float:
	var next_i := (i + 1) % phases.size()
	var e := float(phases[next_i]["start"])
	if e <= float(phases[i]["start"]):
		e += 24.0
	return e


func phase_at(hour: float) -> Dictionary:
	var i := phase_index_at(hour)
	return phases[i] if i >= 0 else {}


## 采样任意时刻的完整视觉参数（含边界 crossfade）
func sample(hour: float) -> Dictionary:
	var i := phase_index_at(hour)
	if i < 0:
		return {}
	var cur: Dictionary = phases[i]
	var h := fposmod(hour, 24.0)
	var s := float(cur["start"])
	var local := h - s
	if local < 0.0:
		local += 24.0
	var win := _phase_end(i) - s
	var out := cur.duplicate()
	if boundary_fade > 0.0 and win > boundary_fade * 2.0 and local > win - boundary_fade:
		var t := (local - (win - boundary_fade)) / boundary_fade
		var nxt: Dictionary = phases[(i + 1) % phases.size()]
		for k in ["sky_top", "sky_horizon", "ground_bottom", "ground_horizon", "light_color", "fog"]:
			out[k] = (cur[k] as Color).lerp(nxt[k] as Color, t)
		out["light_energy"] = lerpf(float(cur["light_energy"]), float(nxt["light_energy"]), t)
		out["ambient"] = lerpf(float(cur["ambient"]), float(nxt["ambient"]), t)
	out["phase_index"] = i
	return out


## 太阳/月亮仰角系数：正午 +1，午夜 -1（连续、可插值）
static func light_elevation(hour: float) -> float:
	return sin(PI * (fposmod(hour, 24.0) - 6.0) / 12.0)


static func clock_text(hour: float) -> String:
	var total_min := int(round(fposmod(hour, 24.0) * 60.0))
	return "%02d:%02d" % [(total_min / 60) % 24, total_min % 60]


## 推进游戏时间：返回新的 hour
func advance(hour: float, delta_seconds: float) -> float:
	var hours_per_sec := 24.0 / (day_length_minutes * 60.0)
	return fposmod(hour + delta_seconds * hours_per_sec, 24.0)
