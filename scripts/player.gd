class_name Player
extends CharacterBody3D
## L0 行走与存在 —— 越肩第三人称（Brief §2.1）
## 没有奔跑，默认就是慢的：沙 ×0.85 / 草 ×1.0 / 礁 ×0.7，Shift 快走 ×1.4。

signal interact_pressed

const WALK_SPEED := 3.2
const SPRINT_MULT := 1.4
const SPEED_MULT := {"sand": 0.85, "grass": 1.0, "rock": 0.7}
const WADE_DEPTH_LIMIT := -1.2   # 可以踩水，但不能游泳（M3 小船接管深水）

var surface_provider: Callable = Callable()  # -> String
var frozen := false                          # 持竿状态下锁移动
var rod_tip: Node3D = null

## 混元3D 生成的主角模型。优先用绑骨版（Blender 自动绑骨 + 烘焙动作），
## 没有再退回静态网格，最后才用程序化角色。
const HERO_RIGGED := "res://assets/models/hero_rigged.glb"
const HERO_MODEL := "res://assets/models/hero.glb"
const HERO_BODY_HEIGHT := 1.55   # 期望的"脚底到帽顶"高度（与程序化角色一致）
var _using_glb := false
var _glb_root: Node3D = null
var _anim: AnimationPlayer = null
var _anim_name := ""
var _skel: Skeleton3D = null
var _hand_idx := -1
var _tip_offset := Vector3.ZERO   # 竿尖在 hand.R 骨骼空间的偏移

var _model: Node3D = null
var _rig: Node3D = null
var _arm: SpringArm3D = null
var _camera: Camera3D = null

# 角色关节（v0.5：程序化低多边形角色）
var _hips: Node3D = null
var _torso: Node3D = null
var _head: Node3D = null
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _leg_l: Node3D = null
var _leg_r: Node3D = null
var _walk_phase := 0.0

# 面部表情（v0.6）—— AI 生成的 2D 五官贴图贴在头部正面
const FACE_DIR := "res://assets/face/"
const FACE_NAMES := ["calm", "smile", "focus", "surprise"]
var _face_mats: Dictionary = {}       # 存 Texture2D
var _face_mesh: Node3D = null         # Sprite3D（用类型弱化避免诊断代码类型冲突）
var _expression := "calm"
var _expression_left := 0.0
var _base_expression := "calm"


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_build_body()
	_build_model()
	_build_face()
	_build_camera_rig()


func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	cs.shape = capsule
	cs.position.y = 0.75
	add_child(cs)


func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	# 模型正面为 +z（与移动朝向公式 atan2(flat.x, flat.z) 一致），初始转 180° 背对镜头
	_model.rotation.y = PI

	if _build_glb_model():
		return
	_build_procedural_model()


## 优先装配混元3D 生成的主角。成功返回 true。
func _build_glb_model() -> bool:
	var path := ""
	if ModelLib.available(HERO_RIGGED):
		path = HERO_RIGGED
	elif ModelLib.available(HERO_MODEL):
		path = HERO_MODEL
	if path == "":
		return false
	var body := ModelLib.spawn(path)
	if body == null:
		return false
	_glb_root = Node3D.new()
	_glb_root.name = "GlbBody"
	_glb_root.add_child(body)
	_model.add_child(_glb_root)
	# 模型总高 0.937（含竿尖），身体（脚→帽顶）需要 1.55 → 整体放到 1.42 倍
	ModelLib.fit_height(body, HERO_BODY_HEIGHT * 1.42, true, true)
	_using_glb = true

	# 钓线起点：有骨骼时每帧从 hand.R 的位姿算，抬竿时竿尖会跟着动
	var local_tip: Vector3 = ModelLib.topmost_local(body)
	rod_tip = Node3D.new()
	rod_tip.name = "RodTip"
	_model.add_child(rod_tip)
	for ch in body.find_children("*", "Skeleton3D", true, false):
		_skel = ch as Skeleton3D
		break
	if _skel != null:
		_hand_idx = _skel.find_bone("hand.R")
		if _hand_idx >= 0:
			# local_tip（body 本地）→ 骨架空间 → 骨骼空间
			var to_skel: Transform3D = _skel.global_transform.affine_inverse() * body.global_transform
			var p_skel: Vector3 = to_skel * local_tip
			var rest: Transform3D = _skel.get_bone_global_rest(_hand_idx)
			_tip_offset = rest.affine_inverse() * p_skel
			_update_rod_tip()
		else:
			_skel = null
	if _skel == null:
		rod_tip.position = local_tip * body.scale + body.position

	# 自带动画（绑骨版才有）：idle / walk / hold
	_anim = ModelLib.find_anim_player(body)
	if _anim != null and _anim.get_animation_list().size() > 0:
		print("Player: 使用骨骼动画 ", _anim.get_animation_list())
		_play("idle")
	return true


## 切换动作（同名不重播，避免每帧重启动画）
func _play(name: String) -> void:
	if _anim == null or _anim_name == name:
		return
	if not _anim.has_animation(name):
		return
	_anim_name = name
	_anim.play(name, 0.18)


## 播放速度跟着移动速度走，慢走时不至于"原地快蹬"
func _set_anim_speed(mult: float) -> void:
	if _anim == null or _anim_name != "walk":
		return
	_anim.speed_scale = clampf(mult, 0.55, 1.9)


func _build_procedural_model() -> void:
	# ---------- 髋 / 躯干 ----------
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position.y = 0.70
	_model.add_child(_hips)

	_torso = Node3D.new()
	_torso.name = "Torso"
	_hips.add_child(_torso)
	# 衬衫（收窄一点，避免"一块板"）
	_mesh(_torso, _box(0.36, 0.44, 0.22), C_SHIRT, Vector3(0.0, 0.22, 0.0))
	# 圆肩（把方肩的直角柔化）
	_mesh(_torso, _sphere(0.078, 8, 5), C_SHIRT, Vector3(-0.175, 0.40, 0.0))
	_mesh(_torso, _sphere(0.078, 8, 5), C_SHIRT, Vector3(0.175, 0.40, 0.0))
	# 衣领：绕颈一圈，而不是横在肩上的"板"
	_mesh(_torso, _cyl(0.096, 0.108, 0.05, 10), C_ACCENT, Vector3(0.0, 0.435, 0.0))
	# 短裤
	_mesh(_torso, _box(0.365, 0.16, 0.228), C_PANTS, Vector3(0.0, -0.06, 0.0))
	# 腰带
	_mesh(_torso, _box(0.372, 0.045, 0.233), C_BELT, Vector3(0.0, 0.03, 0.0))

	# ---------- 头 / 草帽 ----------
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.60, 0.0)   # 相对躯干（世界 1.30）
	_torso.add_child(_head)
	_mesh(_head, _cyl(0.058, 0.066, 0.075, 8), C_SKIN, Vector3(0.0, -0.03, 0.0))  # 脖子
	var head_mesh := _mesh(_head, _sphere(0.155, 10, 6), C_SKIN, Vector3(0.0, 0.075, 0.0))
	head_mesh.scale = Vector3(1.0, 1.06, 1.0)
	# 头发：比头略大、向后偏移，正面留出脸 → 前/后一眼能分（不做五官，Brief §5.4）
	var hair := _mesh(_head, _sphere(0.158, 10, 6), C_HAIR, Vector3(0.0, 0.082, -0.052))
	hair.scale = Vector3(1.02, 1.02, 0.92)
	# 草帽：帽檐 + 帽冠 + 布带
	_mesh(_head, _cyl(0.285, 0.31, 0.024, 12), C_STRAW, Vector3(0.0, 0.20, 0.0))
	_mesh(_head, _cyl(0.135, 0.158, 0.125, 10), C_STRAW_D, Vector3(0.0, 0.268, 0.0))
	_mesh(_head, _cyl(0.160, 0.162, 0.03, 10), C_BELT, Vector3(0.0, 0.215, 0.0))

	# ---------- 四肢（枢轴在关节处，便于摆动） ----------
	_leg_l = Node3D.new()
	_leg_l.name = "LegL"
	_leg_l.position = Vector3(-0.10, 0.66, 0.0)
	_model.add_child(_leg_l)
	_mesh(_leg_l, _capsule(0.082, 0.54, 6), C_PANTS, Vector3(0.0, -0.27, 0.0))
	_mesh(_leg_l, _box(0.145, 0.095, 0.23), C_BOOT, Vector3(0.0, -0.555, 0.028))

	_leg_r = Node3D.new()
	_leg_r.name = "LegR"
	_leg_r.position = Vector3(0.10, 0.66, 0.0)
	_model.add_child(_leg_r)
	_mesh(_leg_r, _capsule(0.082, 0.54, 6), C_PANTS, Vector3(0.0, -0.27, 0.0))
	_mesh(_leg_r, _box(0.145, 0.095, 0.23), C_BOOT, Vector3(0.0, -0.555, 0.028))

	_arm_l = Node3D.new()
	_arm_l.name = "ArmL"
	_arm_l.position = Vector3(-0.225, 0.40, 0.0)
	_torso.add_child(_arm_l)
	# 短袖：上臂衬衫、前臂露肤 → 手臂与躯干能区分开
	_mesh(_arm_l, _capsule(0.064, 0.20, 6), C_SHIRT, Vector3(0.0, -0.09, 0.0))
	_mesh(_arm_l, _capsule(0.052, 0.22, 6), C_SKIN, Vector3(0.0, -0.28, 0.0))
	_mesh(_arm_l, _sphere(0.062, 8, 5), C_SKIN, Vector3(0.0, -0.385, 0.0))

	_arm_r = Node3D.new()
	_arm_r.name = "ArmR"
	_arm_r.position = Vector3(0.225, 0.40, 0.0)
	_torso.add_child(_arm_r)
	_mesh(_arm_r, _capsule(0.064, 0.20, 6), C_SHIRT, Vector3(0.0, -0.09, 0.0))
	_mesh(_arm_r, _capsule(0.052, 0.22, 6), C_SKIN, Vector3(0.0, -0.28, 0.0))
	_mesh(_arm_r, _sphere(0.062, 8, 5), C_SKIN, Vector3(0.0, -0.385, 0.0))

	# ---------- 背篓（贴背、不穿模） ----------
	var basket := Node3D.new()
	basket.name = "Basket"
	basket.position = Vector3(0.0, 0.20, -0.205)   # 髋局部：背后
	_hips.add_child(basket)
	_mesh(basket, _cyl(0.125, 0.101, 0.27, 10), C_WICKER, Vector3.ZERO)
	_mesh(basket, _cyl(0.132, 0.132, 0.025, 10), C_STRAW_D, Vector3(0.0, 0.145, 0.0))
	# 双肩背带（左右各一，收在胸前看不到，只在背后露一小段）
	_mesh(basket, _box(0.04, 0.34, 0.022), C_BELT, Vector3(-0.115, 0.30, 0.045))
	_mesh(basket, _box(0.04, 0.34, 0.022), C_BELT, Vector3(0.115, 0.30, 0.045))

	# ---------- 钓竿（右手，指向前上方） ----------
	var rod := Node3D.new()
	rod.name = "Rod"
	rod.position = Vector3(0.01, -0.40, 0.07)
	rod.rotation = Vector3(deg_to_rad(66.0), deg_to_rad(4.0), deg_to_rad(-7.0))
	_arm_r.add_child(rod)
	_mesh(rod, _cyl(0.009, 0.024, 1.38, 6), C_ROD, Vector3(0.0, 0.66, 0.0))
	# 握把与渔轮
	_mesh(rod, _cyl(0.027, 0.027, 0.17, 8), C_BELT, Vector3(0.0, 0.05, 0.0))
	_mesh(rod, _cyl(0.042, 0.042, 0.016, 10), C_ACCENT, Vector3(0.0, 0.15, 0.03))
	rod_tip = Node3D.new()
	rod_tip.name = "RodTip"
	rod_tip.position.y = 1.38
	rod.add_child(rod_tip)


# ================= 面部表情（v0.6） =================

## 贴图存在才装配；缺失时整个面部节点不创建 —— 程序化无脸角色作为 fallback
func _build_face() -> void:
	if _head == null:
		return   # 用混元模型时没有可贴的平面头部，脸上的五官来自模型自身贴图
	for name in FACE_NAMES:
		var path: String = FACE_DIR + str(name) + ".png"
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_face_mats[name] = tex            # 直接存贴图，Sprite3D 自己处理 alpha
	if _face_mats.is_empty():
		return
	# Sprite3D 专为透明 2D 贴图设计；PlaneMesh + ALPHA 材质在 GL Compatibility 下出现"只渲染局部"的问题
	var sprite := Sprite3D.new()
	sprite.name = "Face"
	sprite.centered = true
	sprite.pixel_size = 0.00105   # 256px * 0.00105 ≈ 0.27m 脸宽
	sprite.position = Vector3(0.0, 0.075, 0.17)
	_face_mesh = sprite
	_head.add_child(sprite)
	set_expression("calm")


## 切换表情；可选 duration>0 后自动回到基础表情
func set_expression(name: String, duration := 0.0) -> void:
	if not _face_mats.has(name):
		return
	_expression = name
	_expression_left = duration
	if _face_mesh != null and _face_mesh is Sprite3D:
		(_face_mesh as Sprite3D).texture = _face_mats[name]


func set_base_expression(name: String) -> void:
	if _face_mats.has(name):
		_base_expression = name
		set_expression(name)


func has_face() -> bool:
	return not _face_mats.is_empty()


# ================= 角色构件与配色 =================

const C_SKIN := Color(0.898, 0.741, 0.588)
const C_HAIR := Color(0.235, 0.176, 0.137)
const C_SHIRT := Color(0.937, 0.898, 0.816)
const C_ACCENT := Color(0.290, 0.588, 0.639)
const C_PANTS := Color(0.247, 0.325, 0.365)
const C_BOOT := Color(0.235, 0.204, 0.184)
const C_STRAW := Color(0.882, 0.780, 0.529)
const C_STRAW_D := Color(0.792, 0.663, 0.412)
const C_BELT := Color(0.451, 0.310, 0.216)
const C_WICKER := Color(0.541, 0.416, 0.263)
const C_ROD := Color(0.451, 0.322, 0.220)

var _mat_cache: Dictionary = {}


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	_mat_cache[key] = m
	return m


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


## 低多边形基础体（分段数压低，保持 poly 风格）
func _capsule(r: float, h: float, seg: int) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = 2
	return m


func _sphere(r: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _cyl(top_r: float, bot_r: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _build_camera_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "CameraRig"
	add_child(_rig)
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.0
	_arm.collision_mask = 1
	_arm.margin = 0.25
	_rig.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_arm.add_child(_camera)
	_arm.rotation.x = -0.35
	_camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_rig.rotation.y -= m.relative.x * 0.0032
		_arm.rotation.x = clampf(_arm.rotation.x - m.relative.y * 0.0028, -1.15, 0.25)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_E:
			interact_pressed.emit()


func _physics_process(dt: float) -> void:
	# 表情自动回退（咬钩专注 1.2s、断线惊讶 1.6s 等）
	if _expression_left > 0.0:
		_expression_left -= dt
		if _expression_left <= 0.0:
			set_expression(_base_expression)

	# 镜头呼吸感（Brief §5.4：±0.3° 手持感）
	_rig.position.y = 1.55 + 0.012 * sin(Time.get_ticks_msec() * 0.0011)

	if frozen:
		velocity = Vector3.ZERO
		_animate(dt, 0.0)
		return

	var input_vec := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_vec.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_vec.y -= 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_vec.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_vec.x += 1.0
	input_vec = input_vec.normalized() if input_vec.length() > 0.1 else Vector2.ZERO

	var mult: float = SPEED_MULT.get(_surface_type(), 1.0)
	if Input.is_physical_key_pressed(KEY_SHIFT):
		mult *= SPRINT_MULT
	var speed := WALK_SPEED * mult

	var fwd := -_rig.global_transform.basis.z
	var right := _rig.global_transform.basis.x
	fwd.y = 0.0
	right.y = 0.0
	fwd = fwd.normalized()
	right = right.normalized()
	var wish := (right * input_vec.x + fwd * input_vec.y) * speed

	# 踩水限制：只禁止「向更深走」，允许已在深水者往浅处爬（A4 落水自救）
	var on_deck := is_on_floor() and global_position.y > 0.5
	var next_xz := global_position + Vector3(wish.x, 0.0, wish.z) * dt
	if not on_deck:
		var cur_h := WorldBuilder.island_height(global_position.x, global_position.z)
		var next_h := WorldBuilder.island_height(next_xz.x, next_xz.z)
		var already_deep := cur_h < WADE_DEPTH_LIMIT
		# 只有「目标更深」才阻挡；已在深水且朝更浅处走则放行
		if next_h < WADE_DEPTH_LIMIT and (not already_deep or next_h <= cur_h):
			wish.x = 0.0
			wish.z = 0.0

	velocity.x = wish.x
	velocity.z = wish.z
	if not is_on_floor():
		velocity.y -= 9.8 * dt
	else:
		velocity.y = -0.5
	move_and_slide()

	# 模型朝向移动方向
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.4:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(flat.x, flat.z), 10.0 * dt)
	_animate(dt, flat.length())


## 行走动画：腿/臂反相摆动 + 髋部起伏 + 轻微前倾；静止时呼吸起伏
func _animate(dt: float, speed: float) -> void:
	if _using_glb:
		_animate_glb(dt, speed)
		return
	if _leg_l == null or _arm_l == null:
		return
	var moving := speed > 0.15
	var norm := clampf(speed / WALK_SPEED, 0.0, 1.4)
	if moving:
		_walk_phase += dt * (5.0 + speed * 1.1)
	else:
		_walk_phase = lerpf(_walk_phase, round(_walk_phase / PI) * PI, 8.0 * dt)

	var swing := sin(_walk_phase) * 0.62 * norm if moving else 0.0
	var k := clampf(dt * 12.0, 0.0, 1.0)
	var hold := frozen
	# 腿：持竿时站定，走路时反相摆动
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0 if hold else swing, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0 if hold else -swing, k)
	# 臂：持竿时双臂抬起（右臂抬得更高），走路时反相摆、右臂摆幅压到 30%
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.72 if hold else -swing * 0.85, k)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.02 if hold else swing * 0.30, k)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.06, k)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.05, k)

	# 髋部起伏：走路是双频小跳，站立是慢呼吸
	var t := Time.get_ticks_msec() * 0.001
	var bob := 0.0
	if moving:
		bob = absf(sin(_walk_phase)) * 0.028 * norm
	else:
		bob = sin(t * 1.5) * 0.008
	_hips.position.y = 0.70 + bob
	_torso.rotation.x = lerpf(_torso.rotation.x, -0.07 * norm if moving else 0.0, k)
	_torso.rotation.z = lerpf(_torso.rotation.z, sin(_walk_phase) * 0.05 * norm if moving else 0.0, k)
	# 头部轻微反向摆动，抵消躯干晃动
	_head.rotation.z = lerpf(_head.rotation.z, -sin(_walk_phase) * 0.04 * norm if moving else 0.0, k)


## 混元3D 模型是单个合并网格（无骨骼），只能在整体层面做运动感：
## 起步下沉 → 迈步弹起 → 左右摆胯 → 前倾，配合移动速度插值，避免"滑行感"。
## 竿尖世界坐标 = 骨架世界变换 × (hand.R 当前全局位姿 × 骨骼内偏移)
func _update_rod_tip() -> void:
	if _skel == null or _hand_idx < 0 or rod_tip == null:
		return
	var pose: Transform3D = _skel.get_bone_global_pose(_hand_idx)
	rod_tip.global_position = _skel.global_transform * (pose * _tip_offset)


func _animate_glb(dt: float, speed: float) -> void:
	if _glb_root == null:
		return
	_update_rod_tip()
	if _anim != null:
		# 有骨骼动画：只负责状态切换 + 速度匹配
		if frozen:
			_play("hold")
		elif speed > 0.15:
			_play("walk")
			_set_anim_speed(speed / WALK_SPEED)
		else:
			_play("idle")
		return
	var t := Time.get_ticks_msec() * 0.001
	var moving := speed > 0.15
	var norm := clampf(speed / WALK_SPEED, 0.0, 1.4)
	if moving:
		_walk_phase += dt * (5.2 + speed * 1.15)
	else:
		_walk_phase = lerpf(_walk_phase, round(_walk_phase / PI) * PI, 6.0 * dt)

	var k := clampf(dt * 10.0, 0.0, 1.0)
	var bob := 0.0
	var roll := 0.0
	var yaw := 0.0
	var pitch := 0.0
	if moving:
		bob = (absf(sin(_walk_phase)) - 0.5) * 0.075 * norm
		roll = sin(_walk_phase) * 0.055 * norm
		yaw = sin(_walk_phase) * 0.05 * norm
		pitch = -0.09 * norm
	else:
		bob = sin(t * 1.6) * 0.012
		pitch = -0.06 if frozen else 0.0
		roll = sin(t * 0.8) * 0.008

	_glb_root.position.y = lerpf(_glb_root.position.y, bob, k)
	_glb_root.rotation.z = lerpf(_glb_root.rotation.z, roll, k)
	_glb_root.rotation.y = lerpf(_glb_root.rotation.y, yaw, k)
	_glb_root.rotation.x = lerpf(_glb_root.rotation.x, pitch, k)
	# 迈步瞬间的轻微纵向挤压，补足"没有腿在动"的观感
	var squash := 1.0 + (sin(_walk_phase * 2.0) * 0.012 * norm if moving else 0.0)
	_glb_root.scale = Vector3(1.0, squash, 1.0)


func _surface_type() -> String:
	if surface_provider.is_valid():
		return str(surface_provider.call())
	return "grass"


func camera_yaw() -> float:
	return _rig.global_rotation.y


func camera_forward_flat() -> Vector3:
	var fwd := -_rig.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()
