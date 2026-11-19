extends SceneTree
## 模型四向检视：同一 GLB 绕 Y 轴转 0/90/180/270 度横向排列，一张图看清所有面

var _f := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 0:
		print("need glb path")
		quit(1)
		return
	var path: String = args[0]
	var h := float(args[1]) if args.size() > 1 else 1.4 
	var gap := h * 0.42

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.3
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	sun.light_energy = 1.6
	root.add_child(sun)

	var labels := ["0", "90", "180", "270"]
	for i in 4:
		var gltf := GLTFDocument.new()
		var st := GLTFState.new()
		if gltf.append_from_file(path, st) != OK:
			print("parse fail")
			quit(1)
			return
		var sc: Variant = gltf.generate_scene(st)
		if not (sc is Node3D):
			print("scene fail")
			continue
		var holder := Node3D.new()
		holder.rotation.y = deg_to_rad(i * 90)
		holder.position = Vector3((i - 1.5) * gap, 0, 0)
		holder.add_child(sc)
		root.add_child(holder)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(gap * 0.8, 0.01, gap * 0.8)
		base.mesh = bm
		base.position = Vector3((i - 1.5) * gap, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.5, 0.55)
		base.material_override = mat
		root.add_child(base)
		print(labels[i], " at ", holder.position)

	var cam := Camera3D.new()
	cam.position = Vector3(0, h * 0.55, h * 2.0)
	cam.look_at_from_position(cam.position, Vector3(0, h * 0.42, 0), Vector3.UP)
	cam.fov = 42.0
	cam.current = true
	root.add_child(cam)

	var lbl := Label.new()
	lbl.text = "Y 0        90        180       270"
	lbl.position = Vector2(30, 8)
	root.add_child(lbl)


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 30:
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("user://").path_join("probe")
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("model_views.png")
		print("SHOT ", p, " err=", img.save_png(p) if img != null else "no image")
	if _f == 36:
		quit(0)
	return false
