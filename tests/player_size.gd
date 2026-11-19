extends SceneTree
## 玩家尺寸核对：实测世界包围盒，确认身高与地面接触


func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)


func _process(_dt: float) -> bool:
	if Engine.get_process_frames() < 10:
		return false
	var p := root.find_child("Player", true, false)
	if p == null:
		print("no player")
		quit(1)
		return true
	var model := p.get("_model") as Node3D
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		mn = mn.min(a.position)
		mx = mx.max(a.end)
	print("PLAYER world aabb min=", mn, " max=", mx)
	print("  height=", mx.y - mn.y, "  width=", mx.x - mn.x, "  depth=", mx.z - mn.z)
	print("  feet_y=", mn.y, " (应≈0)")
	print("  using_glb=", p.get("_using_glb"))
	var tip := p.get("rod_tip") as Node3D
	if tip != null:
		print("  rod_tip world=", tip.global_position)
	quit(0)
	return true
