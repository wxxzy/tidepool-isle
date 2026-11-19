class_name FishSwimmer
extends Node3D
## 混元3D 生成的鱼模型（无骨骼）在水中的运动
##
## 三种用途：
##   ORBIT  环境鱼群：绕着岛/礁石缓慢巡游，深浅不同
##   HOOKED 咬钩后绕着浮漂打转、被拉扯
##   LEAP   上鱼瞬间从水里抬升、翻转，再淡出

enum Mode { ORBIT, HOOKED, LEAP }

## 各鱼种的模型与体长（米）
const SPECIES := {
	"sardine":   {"path": "res://assets/models/fish/sardine.glb",   "len": 0.30},
	"butterfly": {"path": "res://assets/models/fish/butterfly.glb", "len": 0.34},
	"seabream":  {"path": "res://assets/models/fish/seabream.glb",  "len": 0.46},
	"puffer":    {"path": "res://assets/models/fish/puffer.glb",    "len": 0.34},
	"grouper":   {"path": "res://assets/models/fish/grouper.glb",   "len": 0.62},
}

var mode: int = Mode.ORBIT
var species := ""
var radius := 6.0
var speed := 0.5           # rad/s
var depth := 1.4
var phase := 0.0
var center := Vector3.ZERO

var _body: Node3D = null
var _t := 0.0
var _life := 0.0
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO


static func model_path(id: String) -> String:
	return str(SPECIES.get(id, {}).get("path", ""))


static func body_length(id: String) -> float:
	return float(SPECIES.get(id, {}).get("len", 0.35))


## 有可用模型的鱼种列表（用于随机分配）
static func available_species() -> Array:
	var out: Array = []
	for k in SPECIES:
		if ModelLib.available(str(SPECIES[k]["path"])):
			out.append(k)
	return out


func setup_orbit(id: String, c: Vector3, r: float, d: float, spd: float, ph: float) -> void:
	species = id
	mode = Mode.ORBIT
	center = c
	radius = r
	depth = d
	speed = spd
	phase = ph
	_build()


func setup_hooked(id: String, at: Vector3) -> void:
	species = id
	mode = Mode.HOOKED
	center = at
	radius = 0.45
	depth = 0.22
	speed = 2.6
	_build()


func setup_leap(id: String, from: Vector3, to: Vector3) -> void:
	species = id
	mode = Mode.LEAP
	_leap_from = from
	_leap_to = to
	depth = 0.0
	_build()


func _build() -> void:
	if _body != null:
		return
	var path := model_path(species)
	if path == "":
		return
	var n := ModelLib.spawn(path)
	if n == null:
		return
	_body = n
	add_child(_body)
	ModelLib.fit_length(n, body_length(species))
	_apply_pos(0.0)


func _apply_pos(_dt: float) -> void:
	if _body == null:
		return
	if mode == Mode.LEAP:
		var k := clampf(_life / 0.85, 0.0, 1.0)
		# 抛物线跃出水面
		var arc := sin(k * PI) * 0.9
		global_position = _leap_from.lerp(_leap_to, k) + Vector3(0, arc, 0)
		rotation.y = atan2(_leap_to.z - _leap_from.z, -(_leap_to.x - _leap_from.x))
		_body.rotation.z = k * TAU * 1.2
		return
	var a: float = phase + _t * speed
	var px := center.x + cos(a) * radius
	var pz := center.z + sin(a) * radius
	var wy := WaterMath.wave_height(px, pz, _t) - depth
	global_position = Vector3(px, wy, pz)
	# 切线方向（逆时针绕行）
	var dx := -sin(a)
	var dz := cos(a)
	rotation.y = atan2(dz, -dx)
	# 摆尾：整体轻微摆动 + 左右滚转，弥补没有骨骼的呆板
	var rate := 9.0 if mode == Mode.HOOKED else 3.2
	var amp := 0.18 if mode == Mode.HOOKED else 0.10
	var wag := sin(_t * rate + phase * 3.0)
	_body.rotation.y = wag * amp
	_body.rotation.z = wag * 0.06


func _process(dt: float) -> void:
	_t += dt
	_life += dt
	if _body == null:
		return
	_apply_pos(dt)
	if mode == Mode.LEAP and _life > 1.05:
		queue_free()
