class_name ModelLib
extends RefCounted
## 混元3D 生成模型的运行时加载与归一化
##
## 混元直出的 GLB 没有骨骼（单个合并网格），因此这里只做：
##   1. GLTFDocument 运行时解析（不依赖编辑器 importer，导出包内也能跑）
##   2. 按目标高度/长度等比缩放
##   3. 落地/居中，让调用方可以直接把节点放到世界坐标
##   4. 找出"最高顶点"——对主角来说那正好是鱼竿尖

## 缓存 PackedScene 而不是 Node3D：
## 静态变量持有 Node 会在引擎关闭阶段（静态变量晚于 SceneServer 释放）导致段错误。
static var _scenes: Dictionary = {}


static func available(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## 取（并缓存）PackedScene
static func packed(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var ps := _load_packed(path)
	if ps == null:
		return null
	_scenes[path] = ps
	return ps


static func _load_packed(path: String) -> PackedScene:
	# 路径 1：导出包里 .glb 已 import 成 PackedScene（remap），必须走资源管线
	if ResourceLoader.exists(path):
		var res: Variant = ResourceLoader.load(path)
		if res is PackedScene:
			return res as PackedScene
	# 路径 2：未经 import 的裸文件
	var n := _from_document(path)
	if n == null:
		return null
	var ps := PackedScene.new()
	var err := ps.pack(n)
	n.free()
	if err != OK:
		push_warning("ModelLib: 打包场景失败 %s err=%d" % [path, err])
		return null
	return ps


## 生成一个可独立摆放的实例
static func spawn(path: String) -> Node3D:
	var ps := packed(path)
	if ps == null:
		return null
	var inst: Variant = ps.instantiate()
	return inst as Node3D


## 兼容旧调用：返回一个新实例（调用方负责释放）
static func template(path: String) -> Node3D:
	return spawn(path)


static func _from_document(path: String) -> Node3D:
	var real := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(real):
		real = path
	if not FileAccess.file_exists(real):
		push_warning("ModelLib: 找不到 %s" % path)
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(real, st)
	if err != OK:
		push_warning("ModelLib: 解析失败 %s err=%d" % [path, err])
		return null
	var scene: Variant = doc.generate_scene(st)
	if not (scene is Node3D):
		push_warning("ModelLib: 场景生成失败 %s" % path)
		return null
	return scene as Node3D


## 顶点级包围盒（在 node 的父空间里；会取 mesh 与自身相对变换）
static func local_bounds(root: Node3D) -> AABB:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for ch in root.find_children("*", "MeshInstance3D", true, false):
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = mi.transform * v
				mn = mn.min(p)
				mx = mx.max(p)
	if mn.x == INF:
		return AABB()
	return AABB(mn, mx - mn)


## 等比缩放到目标高度（Y 方向总高），并让最低点落在 y=0、XZ 居中
static func fit_height(n: Node3D, target_h: float, ground := true, center_xz := true) -> AABB:
	var a := local_bounds(n)
	if a.size.y <= 0.0001:
		return a
	var k := target_h / a.size.y
	n.scale = Vector3(k, k, k)
	var off := Vector3.ZERO
	if ground:
		off.y = -a.position.y * k
	if center_xz:
		off.x = -(a.position.x + a.size.x * 0.5) * k
		off.z = -(a.position.z + a.size.z * 0.5) * k
	n.position = off
	return AABB(a.position * k + off, a.size * k)


## 等比缩放到目标长度（X 方向），XZ 居中、Y 也居中（鱼悬在水中）
static func fit_length(n: Node3D, target_len: float) -> AABB:
	var a := local_bounds(n)
	if a.size.x <= 0.0001:
		return a
	var k := target_len / a.size.x
	n.scale = Vector3(k, k, k)
	var off := Vector3(
		-(a.position.x + a.size.x * 0.5) * k,
		-(a.position.y + a.size.y * 0.5) * k,
		-(a.position.z + a.size.z * 0.5) * k)
	n.position = off
	return AABB(a.position * k + off, a.size * k)


## 最高顶点（主角的鱼竿尖）。返回相对 n 的**本地**坐标（未含 n 自身的缩放/位移）
static func topmost_local(n: Node3D) -> Vector3:
	var best := Vector3.ZERO
	var best_y := -INF
	for ch in n.find_children("*", "MeshInstance3D", true, false):
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = mi.transform * v
				if p.y > best_y:
					best_y = p.y
					best = p
	return best


## 最高顶点，已换算到 n 的父空间
static func topmost_point(n: Node3D) -> Vector3:
	return topmost_local(n) * n.scale + n.position


## 把某个节点挂到骨骼上（用于"钓线起点跟着手走"这类需求）
## point 是 root 的**本地**空间坐标，函数内部换算到骨骼的绑定空间
static func attach_to_bone(root: Node3D, bone_name: String, point: Vector3) -> Node3D:
	var skel: Skeleton3D = null
	for ch in root.find_children("*", "Skeleton3D", true, false):
		skel = ch as Skeleton3D
		break
	if skel == null:
		return null
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		push_warning("ModelLib: 找不到骨骼 %s" % bone_name)
		return null
	# point 在 root 空间 → 骨架空间
	var to_skel := skel.global_transform.affine_inverse() * root.global_transform
	var p_skel: Vector3 = to_skel * point
	var rest := skel.get_bone_global_rest(idx)
	var attach := BoneAttachment3D.new()
	attach.name = "BoneAttach_" + bone_name
	attach.bone_name = bone_name
	skel.add_child(attach)
	attach.position = rest.affine_inverse() * p_skel
	return attach


## 找模型自带的动画播放器（glTF 导入的 GLB 会把 animation 变成 AnimationPlayer）
static func find_anim_player(root: Node3D) -> AnimationPlayer:
	for ch in root.find_children("*", "AnimationPlayer", true, false):
		return ch as AnimationPlayer
	return null


static func has_skin(root: Node3D) -> bool:
	for ch in root.find_children("*", "Skeleton3D", true, false):
		return true
	return false


## 把整棵子树的材质改成无光照偏色（用于水下物体压暗，避免 GLB 抢戏）
static func tint(n: Node, color_scale: float) -> void:
	for ch in n.find_children("*", "MeshInstance3D", true, false):
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				m.albedo_color = m.albedo_color * color_scale
				mi.set_surface_override_material(s, m)
