extends SceneTree
## 水下鱼群探针：把相机压低到水面附近，正对近岸，看 3D 鱼是否能透过水面看到
## 用法：godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##        --resolution 1280x720 --script tests/fish_probe.gd

var _scene: Node = null
var _f := 0
var _out := ""


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 8:
		_aim_camera()
	if _f == 26:
		_shot("fish_01_surface.png")
	if _f == 30:
		_place_test_fish()
	if _f == 48:
		_shot("fish_02_closeup.png")
	if _f == 52:
		_aim_wide()
	if _f == 70:
		_shot("fish_03_school.png")
	if _f == 74:
		_player_shore_view()
	if _f == 96:
		_shot("fish_04_playerside.png")
	if _f == 102:
		quit(0)
	return false


func _aim_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "ProbeCam"
	cam.fov = 55.0
	# 站在岸线外侧、水面上方 1.6m，朝岸看（这段没有码头遮挡）
	cam.position = Vector3(56.0, 1.6, 0.0)
	cam.look_at_from_position(cam.position, Vector3(44.0, -1.0, 0.0), Vector3.UP)
	cam.current = true
	root.add_child(cam)
	print("CAM at ", cam.position)


## 在相机正前方浅水放一排鱼，确认模型/朝向/尺寸
func _place_test_fish() -> void:
	var kinds := FishSwimmer.available_species()
	print("可用鱼种: ", kinds)
	var i := 0
	for id in kinds:
		var f := FishSwimmer.new()
		f.name = "Test_" + str(id)
		root.add_child(f)
		var z := (i - 2) * 1.05
		# radius=0、speed=0 → 原地悬停，只保留水面起伏，便于逐个对比体型
		f.setup_orbit(id, Vector3(51.0, 0, z), 0.0, 0.42, 0.0, 0.0)
		print("  ", id, " len=", FishSwimmer.body_length(str(id)))
		i += 1


## 高空俯视：看环境鱼群在近岸浅水带里的整体分布
func _aim_wide() -> void:
	var cam := root.find_child("ProbeCam", true, false) as Camera3D
	if cam == null:
		return
	cam.position = Vector3(58.0, 9.0, 10.0)
	cam.look_at_from_position(cam.position, Vector3(40.0, -1.0, -2.0), Vector3.UP)
	var school := root.find_child("FishSchool", true, false)
	print("FishSchool 子节点数 = ", school.get_child_count() if school != null else -1)


## 玩家视角：站到岸线朝外，看玩家能不能在自己脚边看到鱼
func _player_shore_view() -> void:
	var cam := root.find_child("ProbeCam", true, false) as Camera3D
	if cam != null:
		cam.current = false
	var player := root.find_child("Player", true, false)
	if player == null:
		return
	player.set("global_position", Vector3(43.0, 1.2, 0.0))
	var rig := player.get("_rig") as Node3D
	if rig != null:
		rig.rotation.y = -PI / 2.0   # 朝 +X（外海）看
	var pcam := player.get("_camera") as Camera3D
	if pcam != null:
		pcam.current = true
	print("玩家已移到岸边，相机切换为玩家视角")


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	if img != null:
		print("SHOT ", _out.path_join(name), " err=", img.save_png(_out.path_join(name)))
