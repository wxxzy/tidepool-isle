extends SceneTree
## 最小 3D 渲染自检：一个方块 + 一个 GLB，确认 --script 模式下 3D 能出图

var _f := 0


func _initialize() -> void:
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

	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(-0.8, 0, 0)
	root.add_child(box)

	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and FileAccess.file_exists(args[0]):
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_file(args[0], state)
		print("parse err=", err)
		var sc: Variant = gltf.generate_scene(state)
		if sc is Node3D:
			var n3 := sc as Node3D
			n3.scale = Vector3(2, 2, 2)
			n3.position = Vector3(1.0, 0, 0)
			root.add_child(n3)
			for mi in n3.find_children("*", "MeshInstance3D", true, false):
				var mm := mi as MeshInstance3D
				print("MESH ", mm.name, " visible=", mm.visible, " layers=", mm.layers,
					" aabb=", mm.global_transform * mm.mesh.get_aabb() if mm.mesh else "null",
					" mat=", mm.mesh.surface_get_material(0) if mm.mesh and mm.mesh.get_surface_count() > 0 else "none")
				mm.position = Vector3.ZERO

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.4, 3.2)
	cam.look_at_from_position(cam.position, Vector3(0, 0, 0), Vector3.UP)
	cam.fov = 45.0
	cam.current = true
	root.add_child(cam)
	print("CAM ok")


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 30:
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("user://").path_join("probe")
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("self_check.png")
		print("SHOT ", p, " err=", img.save_png(p) if img != null else "no image")
	if _f == 36:
		quit(0)
	return false
