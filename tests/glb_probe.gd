extends SceneTree
## GLB 检验探针：加载外部 GLB，dump 结构，自动摆正后截图
## 用法：godot --path <proj> --rendering-driver opengl3 --audio-driver Dummy \
##        --resolution 1024x1024 --script tests/glb_probe.gd -- <glb绝对路径>

var _f := 0
var _model: Node3D = null
var _out := ""


func _initialize() -> void:

	var args := OS.get_cmdline_user_args()
	var path := ""
	if args.size() > 0:
		path = args[0]
	print("LOAD ", path)
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)

	if not FileAccess.file_exists(path):
		print("FILE NOT FOUND")
		quit(1)
		return

	# 运行时用 GLTFDocument 直接解析（不走编辑器 importer）
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(path, state)
	print("GLTF parse err=", err, " nodes=", state.get_nodes().size())
	var scene: Variant = gltf.generate_scene(state)
	if scene is Node3D:
		_model = scene
		root.add_child(_model)
		_dump(_model)

	# 简单光照 + 相机
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.20, 0.23)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var cam := Camera3D.new()
	# 从实际网格包围盒自动取中心，避免模型归一化后相机没对准
	var center := Vector3.ZERO
	var top := 0.0
	if _model != null:
		var minp := Vector3(1e9, 1e9, 1e9)
		var maxp := Vector3(-1e9, -1e9, -1e9)
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var mmi := mi as MeshInstance3D
			if mmi == null or mmi.mesh == null:
				continue
			var aabb: AABB = mmi.global_transform * mmi.mesh.get_aabb()
			print("  INST ", mmi.name, " origin=", mmi.global_transform.origin, " aabb=", aabb)
			minp = minp.min(aabb.position)
			maxp = maxp.max(aabb.end)
		if minp.x < 1e8:
			center = (minp + maxp) * 0.5
			top = maxp.y - minp.y
		print("WORLD aabb min=", minp, " max=", maxp)
	print("MODEL center=", center, " height=", top)
	var dist := maxf(top * 1.9, 2.2)
	cam.position = center + Vector3(0, top * 0.05, dist)
	cam.look_at_from_position(cam.position, center, Vector3.UP)
	cam.fov = 45.0
	cam.current = true
	root.add_child(cam)


func _dump(n: Node) -> void:
	print("=== ROOT ", n.name, " ", n.get_class())
	var count := 0
	var walkers := [n]
	while walkers.size() > 0 and count < 40:
		var cur: Node = walkers.pop_front()
		count += 1
		if cur is MeshInstance3D:
			var mesh := (cur as MeshInstance3D).mesh
			var faces := 0
			if mesh != null and mesh.get_surface_count() > 0:
				for s in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					var verts = arr[Mesh.ARRAY_VERTEX]
					if idx != null:
						faces += (idx as PackedInt32Array).size() / 3
					elif verts != null:
						faces += (verts as PackedVector3Array).size() / 3
			print("  MESH %s faces~%d surfaces=%d" % [cur.name, faces, mesh.get_surface_count()])
		if cur is Skeleton3D:
			print("  SKELETON %s bones=%d" % [cur.name, (cur as Skeleton3D).get_bone_count()])
		for ch in cur.get_children():
			walkers.append(ch)


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 30:
		var img := root.get_texture().get_image()
		if img != null:
			var p := _out.path_join("glb_check.png")
			print("SHOT ", p, " err=", img.save_png(p))
	if _f == 35:
		quit(0)
	return false
