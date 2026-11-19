extends SceneTree
## 角色外观探针：冻结玩家物理，环绕三个角度 + 走路中间帧截图
## 用法：godot --path <proj> --rendering-driver opengl3 --audio-driver Dummy \
##        --resolution 1280x720 --script tests/character_probe.gd

var _scene: Node = null
var _player: Node = null
var _rig: Node3D = null
var _arm: SpringArm3D = null
var _f := 0
var _out := ""


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	_f += 1
	if _player == null:
		_player = _find(_scene, "camera_yaw")
		if _player == null:
			return false
		var hud := _find(_scene, "set_tension")
		if hud != null:
			(hud as CanvasLayer).visible = false
		_player.set_physics_process(false)
		_rig = _player.get("_rig") as Node3D
		_arm = _player.get("_arm") as SpringArm3D
		if _arm != null:
			_arm.spring_length = 2.7
			_arm.rotation.x = -0.16
		return false

	match _f:
		20:
			_rig.rotation.y = 0.0       # 镜头在身后 → 看背面
		40:
			_shot("char_01_back")
		45:
			_rig.rotation.y = PI        # 镜头转到正面
		65:
			_shot("char_02_front")
		70:
			_rig.rotation.y = PI * 0.5  # 侧面
		90:
			_shot("char_03_side")
		95:
			# 走路中间帧：手动推进动画相位（不依赖 Input）
			for i in 9:
				_player.call("_animate", 0.05, 3.2)
		100:
			_shot("char_04_walk")
		105:
			# 持竿姿态（fishing）
			_player.set("frozen", true)
			for i in 12:
				_player.call("_animate", 0.05, 0.0)
		115:
			_shot("char_06_hold")
		120:
			# 特写：拉近看头部/草帽细节
			_player.set("frozen", false)
			_arm.spring_length = 1.5
			_arm.rotation.x = -0.02
			_rig.rotation.y = PI * 0.82
		125:
			_shot("char_05_closeup")
		130:
			# 四表情特写：正面、拉近
			_player.set("frozen", false)
			_arm.spring_length = 1.25
			_arm.rotation.x = -0.02
			_rig.rotation.y = PI
		135:
			_player.call("set_expression", "calm")
		140:
			_shot("face_01_calm")
		145:
			_player.call("set_expression", "smile")
		150:
			_shot("face_02_smile")
		155:
			_player.call("set_expression", "focus")
		160:
			_shot("face_03_focus")
		165:
			_player.call("set_expression", "surprise")
		170:
			_shot("face_04_surprise")
		175:
			quit(0)
	return false


func _find(n: Node, method: String) -> Node:
	for ch in n.get_children():
		if ch.has_method(method):
			return ch
		var r := _find(ch, method)
		if r != null:
			return r
	return null


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT_FAIL ", name)
		return
	print("SHOT ", _out.path_join(name + ".png"), " err=", img.save_png(_out.path_join(name + ".png")))
