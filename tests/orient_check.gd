extends SceneTree
## 朝向对照：同一 GLB 复制三份，分别施加 0 / -90°X / +90°X，横向排列截图

var _f := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 0:
		print("need glb path")
		quit(1)
		return
	var path: String = args[0]

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	sun.light_energy = 1.5
	root.add_child(sun)

	var rots := [Vector3.ZERO, Vector3(-PI / 2, 0, 0), Vector3(PI / 2, 0, 0)]
	var labels := ["AS_IS", "X-90", "X+90"]
	for i in rots.size():
		var gltf := GLTFDocument.new()
		var st := GLTFState.new()
		gltf.append_from_file(path, st)
		var sc: Variant = gltf.generate_scene(st)
		if not (sc is Node3D):
			print("scene fail")
			continue
		var holder := Node3D.new()
		holder.name = "H%d" % i
		holder.rotation = rots[i]
		holder.position = Vector3((i - 1) * 1.6, 0, 0)
		holder.add_child(sc)
		root.add_child(holder)
		# 每个实例下方放个地面参考方块
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.02, 0.5)
		base.mesh = bm
		base.position = Vector3((i - 1) * 1.6, -0.6, 0)
		root.add_child(base)
		print(labels[i], " placed at ", holder.position)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.9, 3.6)
	cam.look_at_from_position(cam.position, Vector3(0, -0.2, 0), Vector3.UP)
	cam.fov = 50.0
	cam.current = true
	root.add_child(cam)

	var lbl := Label.new()
	lbl.text = "AS_IS      X-90      X+90"
	lbl.position = Vector2(40, 10)
	root.add_child(lbl)


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 30:
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("user://").path_join("probe")
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("orient_check.png")
		print("SHOT ", p, " err=", img.save_png(p) if img != null else "no image")
	if _f == 36:
		quit(0)
	return false
