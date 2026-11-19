extends SceneTree
## 游戏内角色验证：同一局里截 3 张 —— 待机 / 走路 / 持竿，确认动画状态机真的在切
## 用法：godot --path . --rendering-driver opengl3 --audio-driver Dummy \
##        --resolution 1000x760 --script tests/walk_probe.gd

var _scene: Node = null
var _player: Node = null
var _f := 0
var _out := ""
var _step := 0


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("user://").path_join("probe")
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 6:
		_player = root.find_child("Player", true, false)
		print("player=", _player)
		if _player != null:
			# 不动位置：直接用出生点，只把机位挪到侧面
			print("anim=", _player.get("_anim"), " name=", _player.get("_anim_name"))
			var cam := Camera3D.new()
			cam.name = "ProbeCam"
			cam.fov = 38.0
			var p0: Vector3 = _player.global_position
			cam.position = p0 + Vector3(3.6, 1.1, 1.2)
			cam.look_at_from_position(cam.position, p0 + Vector3(0, 0.85, 0), Vector3.UP)
			cam.current = true
			root.add_child(cam)
			print("cam at ", cam.position, " player at ", p0)
	if _f == 30:
		_shot("walk_01_idle.png")
	if _f == 32:
		if _player != null:
			_player.call("_play", "walk")
			print("切到 walk, anim_name=", _player.get("_anim_name"))
	# 持续喂"在走路"的速度，否则玩家逻辑每帧会把状态重置回 idle
	if _f > 32 and _f < 60 and _player != null:
		_player.call("_animate", 0.033, 3.2)
	if _f == 42:
		_shot("walk_02_walk_a.png")
	if _f == 54:
		_shot("walk_03_walk_b.png")
	if _f == 66:
		_shot("walk_05_walk_c.png")
	if _f == 68:
		if _player != null:
			_player.set("frozen", true)
	if _f > 68 and _f < 100 and _player != null:
		_player.call("_animate", 0.033, 0.0)
	if _f == 96:
		_shot("walk_04_hold.png")
		print("最终 anim_name=", _player.get("_anim_name"))
	if _f == 104:
		quit(0)
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	if img != null:
		print("SHOT ", _out.path_join(name), " err=", img.save_png(_out.path_join(name)))
