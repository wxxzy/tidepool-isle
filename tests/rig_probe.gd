extends SceneTree
## 绑定验收：同一套骨架摆 4 个姿势（待机 / 走路两帧 / 持竿）横向排列截图
## 用法：godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##        --resolution 1200x620 --script tests/rig_probe.gd -- <glb绝对路径>

var _f := 0
var _out := ""
var _label := ""
var _side := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ""
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.19, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.25
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(28), 0)
	sun.light_energy = 1.6
	root.add_child(sun)

	# 4 个状态：(动画名, 时间秒)
	_side = args.size() > 1 and args[1] == "side"
	var side := _side
	var states := [["idle", 1.0], ["walk", 0.27], ["walk", 0.80], ["hold", 0.5]]
	if side:
		states = [["walk", 0.10], ["walk", 0.30], ["walk", 0.50], ["walk", 0.70], ["walk", 0.90]]
	var gap := 0.62
	for i in states.size():
		var gltf := GLTFDocument.new()
		var st := GLTFState.new()
		if gltf.append_from_file(path, st) != OK:
			print("PARSE FAIL")
			quit(1)
			return
		var sc: Variant = gltf.generate_scene(st)
		if not (sc is Node3D):
			print("SCENE FAIL")
			quit(1)
			return
		var holder := Node3D.new()
		var slot := float(i) - (float(states.size()) - 1.0) * 0.5
		holder.position = Vector3(0, 0, slot * gap) if side else Vector3(slot * gap, 0, 0)
		holder.add_child(sc)
		root.add_child(holder)
		var k := 1.55 / 0.937          # 缩放到 1.55m 身高（与游戏内一致）
		(sc as Node3D).scale = Vector3(k, k, k)
		(sc as Node3D).position.y = 0.468 * k   # GLB 原点在身体中心，抬到脚踩地面

		var ap: AnimationPlayer = null
		for ch in sc.find_children("*", "AnimationPlayer", true, false):
			ap = ch as AnimationPlayer
			break
		if ap == null:
			print("NO ANIMATION PLAYER on #", i)
			continue
		if i == 0:
			print("ANIMS = ", ap.get_animation_list())
		var an: String = str(states[i][0])
		var t: float = float(states[i][1])
		if ap.has_animation(an):
			ap.play(an)
			ap.seek(t, true)
			ap.pause()
		else:
			print("  ! 缺动画 ", an, " 现有 ", ap.get_animation_list())

		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(gap * 0.82, 0.012, 0.55)
		base.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.47, 0.52)
		base.material_override = mat
		base.position = Vector3(0, 0, slot * gap) if side else Vector3(slot * gap, 0, 0)
		root.add_child(base)
		print("placed ", states[i][0], "@", t, " at ", holder.position)

	var cam := Camera3D.new()
	if side:
		cam.position = Vector3(5.2, 1.05, 0)
	else:
		cam.position = Vector3(0, 1.05, 4.6)
	cam.look_at_from_position(cam.position, Vector3(0, 0.80, 0), Vector3.UP)
	cam.fov = 42.0
	cam.current = true
	root.add_child(cam)

	var lbl := Label.new()
	lbl.text = "walk 0.10  0.30  0.50  0.70  0.90  (side view)" if side else "idle      walk 0.27s    walk 0.80s    hold"
	lbl.position = Vector2(28, 8)
	root.add_child(lbl)


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 26:
		var img := root.get_texture().get_image()
		if img != null:
			var p := _out.path_join("rig_check_side.png" if _side else "rig_check.png")
			print("SHOT ", p, " err=", img.save_png(p))
	if _f == 32:
		quit(0)
	return false
