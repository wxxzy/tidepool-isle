class_name WorldBuilder
extends RefCounted
## 程序化世界搭建 —— 岛体/水面/码头/渔屋/棕榈/小船/礁石（Brief §1.2 五区）
## 全部确定性生成（无随机或固定种子），岛体高度函数与网格共用，供行走与抛竿查询。

const ISLAND_RADIUS := 60.0     # 网格边缘（含水下裙边）
const SHORE_RADIUS := 46.0      # 高度归零的海岸线半径
const ISLAND_HEIGHT := 5.0

const COL_SAND := Color(0.941, 0.863, 0.706)
const COL_WET := Color(0.82, 0.74, 0.58)
const COL_GRASS := Color(0.56, 0.75, 0.44)
const COL_ROCK := Color(0.604, 0.627, 0.647)
const COL_WOOD := Color(0.69, 0.537, 0.329)
const COL_WOOD_DARK := Color(0.588, 0.439, 0.247)
const COL_HUT := Color(0.784, 0.608, 0.416)
const COL_ROOF := Color(0.663, 0.455, 0.31)


## 岛体高度函数（网格生成与游戏查询共用）：中心约 +5m，海岸 0，远海约 -1.7m
static func island_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	if r >= ISLAND_RADIUS:
		return -1.7
	var s := r / SHORE_RADIUS
	var dome := ISLAND_HEIGHT * (1.0 - pow(s, 1.6))
	var ripple := 0.0
	if s < 0.92:
		var f := 1.0 - s / 0.92
		ripple = (0.30 * sin(x * 0.13) * cos(z * 0.17) + 0.22 * sin(x * 0.05 + z * 0.09)) * f
	return dome + ripple


## 地表类型（影响移动速度，Brief §2.1）：sand ×0.85 / grass ×1.0 / rock ×0.7
static func surface_type_at(x: float, z: float) -> String:
	var h := island_height(x, z)
	if Vector2(x, z + 40.0).length() < 9.0:
		return "rock"  # 北侧礁石崖小径
	if h > 2.3:
		return "grass"
	return "sand"


static func zone_for_position(pos: Vector3) -> String:
	if island_height(pos.x, pos.z) > 0.05:
		return "land"
	var r := Vector2(pos.x, pos.z).length()
	if r < 50.0:
		return "dock"
	elif r < 64.0:
		return "shallow"
	return "deep"


## 构建整个世界，返回关键节点引用
static func build(root: Node3D) -> Dictionary:
	var refs := {}
	refs["island"] = _build_island(root)
	refs["seabed"] = _build_seabed(root)
	refs["water"] = _build_water(root)
	refs["dock"] = _build_dock(root)
	refs["hut"] = _build_hut(root)
	var palms := _build_palms(root)
	refs["palms"] = palms
	refs["fireflies"] = _build_fireflies(root, Vector3(17.0, 2.2, 6.0))
	_build_boat(root, Vector3(5.0, 0.0, 52.0))
	_build_rocks(root)
	refs["spawn"] = Vector3(-8.0, island_height(-8.0, 6.0) + 0.6, 6.0)
	return refs


# ================= 岛体 =================

static func _build_island(root: Node3D) -> MeshInstance3D:
	var rings := 30
	var segs := 72
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		var r0 := ISLAND_RADIUS * float(i) / float(rings)
		var r1 := ISLAND_RADIUS * float(i + 1) / float(rings)
		for j in segs:
			var a0 := TAU * float(j) / float(segs)
			var a1 := TAU * float(j + 1) / float(segs)
			var p00 := _island_vert(r0, a0)
			var p01 := _island_vert(r0, a1)
			var p10 := _island_vert(r1, a0)
			var p11 := _island_vert(r1, a1)
			if i == 0:
				# 中心扇面（r0 = 0 时 p00 == p01）
				_add_tri(st, p00, p10, p11)
			else:
				_add_tri(st, p00, p10, p11)
				_add_tri(st, p00, p11, p01)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Island"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	mi.add_child(body)
	root.add_child(mi)
	return mi


static func _island_vert(r: float, ang: float) -> Vector3:
	var x := r * cos(ang)
	var z := r * sin(ang)
	return Vector3(x, island_height(x, z), z)


static func _vert_color(x: float, z: float, h: float) -> Color:
	if h < 0.25:
		return COL_WET.lerp(COL_SAND, clampf((h + 1.0) / 1.25, 0.0, 1.0))
	var grass_line := 1.9 + 0.45 * sin(x * 0.3) * cos(z * 0.27)
	if h > grass_line:
		return COL_GRASS
	return COL_SAND.lerp(COL_GRASS, clampf((h - 0.4) / (grass_line - 0.4) * 0.35, 0.0, 0.35))


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.0001:
		n = Vector3.UP
	n = n.normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(_vert_color(v.x, v.z, v.y))
		st.add_vertex(v)


static func _build_seabed(root: Node3D) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	var mi := MeshInstance3D.new()
	mi.name = "Seabed"
	mi.mesh = pm
	mi.position.y = -2.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.79, 0.72, 0.56)
	mat.roughness = 1.0
	mi.material_override = mat
	root.add_child(mi)
	return mi


# ================= 水面 =================

const WATER_SHADER := "
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;
uniform vec4 shallow_color : source_color = vec4(0.55, 0.85, 0.80, 0.62);
uniform vec4 deep_color : source_color = vec4(0.10, 0.38, 0.52, 0.90);
uniform float night_mix = 0.0;
uniform float amp_a = 0.12;
uniform float amp_b = 0.09;

float wave(vec2 p, float t) {
	return amp_a * sin(p.x * 0.5 + t * 1.2) + amp_b * sin(p.y * 0.7 + t * 0.9);
}

void vertex() {
	VERTEX.y += wave(VERTEX.xz, TIME);
	float e = 0.35;
	float hx = wave(VERTEX.xz + vec2(e, 0.0), TIME) - wave(VERTEX.xz - vec2(e, 0.0), TIME);
	float hz = wave(VERTEX.xz + vec2(0.0, e), TIME) - wave(VERTEX.xz - vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-hx, 2.0 * e, -hz));
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec4 col = mix(shallow_color, deep_color, clamp(fres * 0.7 + 0.15, 0.0, 1.0));
	col.rgb = mix(col.rgb, col.rgb * vec3(0.22, 0.28, 0.45), night_mix);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
"


static func _build_water(root: Node3D) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	var shader := Shader.new()
	shader.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = mat
	root.add_child(mi)
	return mi


# ================= 码头 =================

static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, body := true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if body:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


static func _build_dock(root: Node3D) -> Dictionary:
	var dock := Node3D.new()
	dock.name = "Dock"
	root.add_child(dock)
	# 桥面：z 38 → 60
	_box(dock, Vector3(2.4, 0.22, 24.0), Vector3(0, 0.75, 49.0), COL_WOOD)
	# 桩柱
	for kz in 6:
		var z := 40.0 + kz * 3.6
		for sx in [-1.0, 1.0]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.12
			cyl.height = 2.4
			var mi := MeshInstance3D.new()
			mi.mesh = cyl
			var mat := StandardMaterial3D.new()
			mat.albedo_color = COL_WOOD_DARK
			mat.roughness = 1.0
			mi.material_override = mat
			mi.position = Vector3(sx, -0.35, z)
			dock.add_child(mi)
	# 末端灯柱
	_box(dock, Vector3(0.14, 2.6, 0.14), Vector3(0, 2.15, 59.4), Color(0.35, 0.27, 0.2))
	var lamp_bulb := _box(dock, Vector3(0.34, 0.4, 0.34), Vector3(0, 3.5, 59.4), Color(1.0, 0.82, 0.49), false)
	var emit := StandardMaterial3D.new()
	emit.albedo_color = Color(1.0, 0.82, 0.49)
	emit.emission_enabled = true
	emit.emission = Color(1.0, 0.82, 0.49)
	emit.emission_energy_multiplier = 2.0
	lamp_bulb.material_override = emit
	var lamp := OmniLight3D.new()
	lamp.name = "DockLamp"
	lamp.light_color = Color(1.0, 0.82, 0.49)
	lamp.omni_range = 13.0
	lamp.light_energy = 0.0
	lamp.position = Vector3(0, 3.6, 59.4)
	lamp.shadow_enabled = false
	dock.add_child(lamp)
	return {"lamp": lamp}


# ================= 渔屋 =================

static func _build_hut(root: Node3D) -> Dictionary:
	var hut := Node3D.new()
	hut.name = "Hut"
	var base_y := island_height(-13.0, -5.0)
	hut.position = Vector3(-13.0, base_y, -5.0)
	root.add_child(hut)
	# 平台
	_box(hut, Vector3(7.2, 0.3, 6.2), Vector3(0, 0.15, 0), COL_WOOD_DARK)
	# 墙体
	_box(hut, Vector3(5.6, 3.0, 4.6), Vector3(0, 1.8, 0), COL_HUT)
	# 屋顶（三棱柱）
	var roof := PrismMesh.new()
	roof.size = Vector3(6.9, 2.0, 5.9)
	var roof_mi := MeshInstance3D.new()
	roof_mi.mesh = roof
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = COL_ROOF
	roof_mat.roughness = 1.0
	roof_mi.material_override = roof_mat
	roof_mi.position = Vector3(0, 4.3, 0)
	hut.add_child(roof_mi)
	var roof_body := StaticBody3D.new()
	var roof_col := CollisionShape3D.new()
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(6.9, 2.0, 5.9)
	roof_col.shape = roof_shape
	roof_body.add_child(roof_col)
	roof_mi.add_child(roof_body)
	# 门（朝南 +z）
	_box(hut, Vector3(1.2, 2.2, 0.12), Vector3(0, 1.4, 2.32), Color(0.478, 0.322, 0.212), false)
	# 亮灯的窗
	var win := _box(hut, Vector3(1.0, 0.9, 0.1), Vector3(1.8, 2.0, 2.32), Color(1.0, 0.914, 0.722), false)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(1.0, 0.914, 0.722)
	wmat.emission_enabled = true
	wmat.emission = Color(1.0, 0.85, 0.55)
	wmat.emission_energy_multiplier = 1.6
	win.material_override = wmat
	var win_light := OmniLight3D.new()
	win_light.name = "HutWindow"
	win_light.light_color = Color(1.0, 0.85, 0.55)
	win_light.omni_range = 9.0
	win_light.light_energy = 0.0
	win_light.position = Vector3(1.8, 2.0, 2.8)
	win_light.shadow_enabled = false
	hut.add_child(win_light)
	return {"window_light": win_light}


# ================= 棕榈树 =================

static func _build_palms(root: Node3D) -> Array:
	var spots := [
		Vector2(17.0, 4.0), Vector2(20.5, 7.5), Vector2(14.5, 9.0),
		Vector2(19.0, 0.5), Vector2(-19.0, 6.0), Vector2(-21.0, 2.0),
	]
	var palms: Array = []
	for i in spots.size():
		var p := _build_palm(root, spots[i], 1000 + i * 77)
		palms.append(p)
	return palms


static func _build_palm(root: Node3D, pos: Vector2, seed_val: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var palm := Node3D.new()
	var y := island_height(pos.x, pos.y)
	palm.position = Vector3(pos.x, y - 0.05, pos.y)
	palm.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(palm)
	var trunk_col := Color(0.541, 0.416, 0.271)
	var lean := rng.randf_range(0.08, 0.2)
	var seg_h := 1.25
	var cur := Vector3.ZERO
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	for s in 3:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.13 - s * 0.02
		cyl.bottom_radius = 0.16 - s * 0.02
		cyl.height = seg_h
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = trunk_col
		mat.roughness = 1.0
		mi.material_override = mat
		var mid := cur + (dir * lean * seg_h + Vector3(0, seg_h * 0.5, 0))
		mi.position = mid
		mi.rotation.z = -lean * 0.5 if absf(dir.x) > 0.01 else 0.0
		mi.rotation.x = lean * 0.5 if absf(dir.z) > 0.01 else 0.0
		palm.add_child(mi)
		cur = cur + dir * lean * seg_h + Vector3(0, seg_h, 0)
	# 树冠
	var crown := Node3D.new()
	crown.position = cur + Vector3(0, 0.15, 0)
	palm.add_child(crown)
	for leaf in 6:
		var leaf_mesh := BoxMesh.new()
		leaf_mesh.size = Vector3(2.1, 0.07, 0.5)
		var lm := MeshInstance3D.new()
		lm.mesh = leaf_mesh
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.435, 0.639, 0.353) if leaf % 2 == 0 else Color(0.373, 0.588, 0.314)
		lmat.roughness = 1.0
		lm.material_override = lmat
		lm.position = Vector3(cos(TAU * leaf / 6.0) * 0.9, 0, sin(TAU * leaf / 6.0) * 0.9)
		lm.rotation.y = -TAU * leaf / 6.0
		lm.rotation.z = -0.42
		crown.add_child(lm)
	for nut in 2:
		var nut_mesh := SphereMesh.new()
		nut_mesh.radius = 0.13
		nut_mesh.height = 0.26
		var nm := MeshInstance3D.new()
		nm.mesh = nut_mesh
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = trunk_col
		nm.material_override = nmat
		nm.position = Vector3(rng.randf_range(-0.2, 0.2), -0.18, rng.randf_range(-0.2, 0.2))
		crown.add_child(nm)
	return palm


# ================= 萤火虫 / 小船 / 礁石 =================

static func _build_fireflies(root: Node3D, center: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = 26
	p.lifetime = 4.5
	p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.gravity = Vector3(0, 0.15, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	# 性能：默认 SphereMesh 约 4000 三角形 × 26 粒子 ≈ 10 万；降到 8×4 段约 64 三角形
	var fmesh := SphereMesh.new()
	fmesh.radius = 0.05
	fmesh.height = 0.1
	fmesh.radial_segments = 8
	fmesh.rings = 4
	p.mesh = fmesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.97, 0.66)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.97, 0.66)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	p.position = center
	p.emitting = false
	root.add_child(p)
	return p


static func _build_boat(root: Node3D, pos: Vector3) -> void:
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.position = pos
	boat.rotation.y = 0.5
	root.add_child(boat)
	_box(boat, Vector3(3.0, 0.9, 1.5), Vector3(0, 0.15, 0), Color(0.663, 0.455, 0.31))
	_box(boat, Vector3(2.6, 0.25, 1.1), Vector3(0, 0.62, 0), Color(0.784, 0.608, 0.416))
	var mast := CylinderMesh.new()
	mast.top_radius = 0.05
	mast.bottom_radius = 0.06
	mast.height = 2.4
	var mm := MeshInstance3D.new()
	mm.mesh = mast
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.478, 0.322, 0.212)
	mm.material_override = mmat
	mm.position = Vector3(0.9, 1.6, 0)
	boat.add_child(mm)


static func _build_rocks(root: Node3D) -> void:
	var spots := [Vector2(-9, -46), Vector2(3, -49), Vector2(13, -44), Vector2(-2, -42)]
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var sm := SphereMesh.new()
		sm.radius = 1.4 + 0.5 * (i % 3)
		sm.height = sm.radius * 1.2
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COL_ROCK
		mat.roughness = 1.0
		mi.material_override = mat
		mi.position = Vector3(sp.x, -0.4, sp.y)
		mi.scale = Vector3(1.2, 0.7, 1.0)
		root.add_child(mi)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = sm.radius * 0.9
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
