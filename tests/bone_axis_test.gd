extends SceneTree
## 骨骼轴向测试：对同一根骨头分别绕本地 X/Y/Z 旋转 ±40°，看哪个方向是"抬臂向前"
## 用法：godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##        --resolution 1200x700 --script tests/bone_axis_test.gd -- <glb> <bone名> [轴] 

var _f := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var bone_name: String = args[1] if args.size() > 1 else "upper_arm.R"
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.19, 0.22)
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

	# 6 个变体：X-/X+ Y-/Y+ Z-/Z+
	var cases := [
		["X-40", Vector3(-40, 0, 0)], ["X+40", Vector3(40, 0, 0)],
		["Y-40", Vector3(0, -40, 0)], ["Y+40", Vector3(0, 40, 0)],
		["Z-40", Vector3(0, 0, -40)], ["Z+40", Vector3(0, 0, 40)],
	]
	var gap := 0.58
	for i in cases.size():
		var gltf := GLTFDocument.new()
		var st := GLTFState.new()
		gltf.append_from_file(path, st)
		var sc: Variant = gltf.generate_scene(st)
		var root3 := sc as Node3D
		var holder := Node3D.new()
		var slot := float(i) - (float(cases.size()) - 1.0) * 0.5
		holder.position = Vector3(slot * gap, 0, 0)
		holder.add_child(root3)
		root.add_child(holder)
		var k := 1.55 / 0.937
		root3.scale = Vector3(k, k, k)
		root3.position.y = 0.468 * k

		var skel: Skeleton3D = null
		for ch in root3.find_children("*", "Skeleton3D", true, false):
			skel = ch as Skeleton3D
			break
		if skel == null:
			print("NO SKELETON")
			continue
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			print("NO BONE ", bone_name, " 现有:", _bones(skel))
			continue
		var deg: Vector3 = cases[i][1]
		var q := Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
		skel.set_bone_pose_rotation(idx, q)
		if i == 0:
			print("BONE ", bone_name, " idx=", idx, " 共 ", skel.get_bone_count(), " 根")
			print("BONES ", _bones(skel))
			print("rest global of bone = ", skel.get_bone_global_rest(idx))

		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(gap * 0.8, 0.012, 0.5)
		base.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.47, 0.52)
		base.material_override = mat
		base.position = Vector3(slot * gap, 0, 0)
		root.add_child(base)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 4.8)
	cam.look_at_from_position(cam.position, Vector3(0, 0.78, 0), Vector3.UP)
	cam.fov = 42.0
	cam.current = true
	root.add_child(cam)

	var lbl := Label.new()
	lbl.text = "  ".join(cases.map(func(c): return c[0]))
	lbl.position = Vector2(24, 8)
	root.add_child(lbl)


func _bones(skel: Skeleton3D) -> Array:
	var out: Array = []
	for i in skel.get_bone_count():
		out.append(skel.get_bone_name(i))
	return out


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 24:
		var img := root.get_texture().get_image()
		if img != null:
			var p := _out.path_join("bone_axis.png")
			print("SHOT ", p, " err=", img.save_png(p))
	if _f == 30:
		quit(0)
	return false
