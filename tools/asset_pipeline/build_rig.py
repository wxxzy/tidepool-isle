# -*- coding: utf-8 -*-
"""给混元3D 直出的静态角色绑骨 + 蒙皮 + 烘焙动作，导出可动画 GLB

为什么不用 Blender 的"自动权重"：混元网格是几百个互不相连的碎片，
bone heat 求解需要连续曲面，会直接报 failed to find solution。
这里改成几何规则权重：按高度分层 + 左右分侧 + 横向软过渡，结果确定可调。

骨骼比例是从顶点剖面实测出来的（H=全身高，u=高度归一化，0=脚底 1=帽顶）：
    腿 0.00–0.30 / 骨盆 0.30 / 躯干 0.30–0.68 / 脖子 0.70 / 头帽 0.76–1.00
    手臂 0.35（手）–0.65（肩），贴在身体两侧

用法:
  blender -b --factory-startup --python build_rig.py -- <in.glb> <out.glb>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0] if len(ARGS) > 0 else r"C:/Users/wangxingxiang/WorkBuddy/daily/tidepool-isle/assets/models/hero.glb"
DST = ARGS[1] if len(ARGS) > 1 else r"C:/Users/wangxingxiang/WorkBuddy/daily/outputs/tidepool-ui/rig_out/hero_rigged.glb"

# ---------------------------------------------------------------- 导入

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
assert meshes, "no mesh"
ob = meshes[0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

VW = [ob.matrix_world @ v.co for v in ob.data.vertices]
Z0 = min(v.z for v in VW)
H = max(v.z for v in VW) - Z0
_ys = sorted(v.y for v in VW)
YC = _ys[len(_ys) // 2]          # 身体前后中心；竿尖很靠后，用中位数避开
print(f"[info] H={H:.4f} z0={Z0:.4f} y_center={YC:.4f} verts={len(VW)}")


def U(v):
    return (v.z - Z0) / H


def z_at(u):
    return Z0 + u * H


# ---------------------------------------------------------------- 解剖参数

HIP_U = 0.30        # 骨盆
WAIST_U = 0.40
CHEST_U = 0.52
NECK_U = 0.68
HEAD_U = 0.76
SHOULDER_U = 0.63
HAND_U = 0.35
ARM_MIN_X = 0.095   # 躯干半径；超过这个横向距离开始向手臂过渡
ARM_FADE = 0.045    # 软过渡宽度，避免腰侧出现硬接缝
ROD_Y = YC - 0.22   # 比背篓更靠后的顶点＝鱼竿

_t = [abs(v.x) for v in VW if 0.40 <= U(v) <= 0.60]
TORSO_HALF = sorted(_t)[int(len(_t) * 0.62)] if _t else 0.09
LEG_X = 0.06
_low = [v for v in VW if U(v) < 0.10 and v.x > 0]
if _low:
    LEG_X = sum(v.x for v in _low) / len(_low)
print(f"[info] 躯干半宽={TORSO_HALF:.3f} 腿中心x={LEG_X:.3f}")


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


# ---------------------------------------------------------------- 骨架

arm_data = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
Y = YC
AX = TORSO_HALF + 0.015     # 手臂中心 x


def bone(name, head, tail, parent=None, connect=False):
    b = eb.new(name)
    b.head = head
    b.tail = tail
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


bone("root", Vector((0, Y, z_at(0.0))), Vector((0, Y, z_at(HIP_U * 0.6))))
bone("hips", Vector((0, Y, z_at(HIP_U))), Vector((0, Y, z_at(WAIST_U))), "root")
bone("spine", Vector((0, Y, z_at(WAIST_U))), Vector((0, Y, z_at(CHEST_U))), "hips", True)
bone("chest", Vector((0, Y, z_at(CHEST_U))), Vector((0, Y, z_at(NECK_U))), "spine", True)
bone("neck", Vector((0, Y, z_at(NECK_U))), Vector((0, Y, z_at(HEAD_U))), "chest", True)
bone("head", Vector((0, Y, z_at(HEAD_U))), Vector((0, Y, z_at(0.99))), "neck", True)

for side, sx in (("L", -1.0), ("R", 1.0)):
    sh = Vector((sx * AX, Y, z_at(SHOULDER_U)))
    el = Vector((sx * (AX + 0.012), Y, z_at(0.50)))
    wr = Vector((sx * (AX + 0.020), Y, z_at(0.40)))
    hd = Vector((sx * (AX + 0.024), Y, z_at(HAND_U)))
    bone(f"upper_arm.{side}", sh, el, "chest")
    bone(f"forearm.{side}", el, wr, f"upper_arm.{side}", True)
    bone(f"hand.{side}", wr, hd, f"forearm.{side}", True)

for side, sx in (("L", -1.0), ("R", 1.0)):
    x = LEG_X * sx
    bone(f"thigh.{side}", Vector((x, Y, z_at(HIP_U))), Vector((x, Y, z_at(0.17))), "hips")
    bone(f"shin.{side}", Vector((x, Y, z_at(0.17))), Vector((x, Y, z_at(0.05))), f"thigh.{side}", True)
    bone(f"foot.{side}", Vector((x, Y, z_at(0.05))), Vector((x, Y + 0.085, z_at(0.012))), f"shin.{side}", True)

bpy.ops.object.mode_set(mode="OBJECT")
print(f"[info] 骨骼数 = {len(arm_data.bones)}")


# ---------------------------------------------------------------- 权重规则

def torso_chain(u, side):
    """按高度返回躯干/腿/头的基础权重"""
    if u < 0.05:
        return {f"foot.{side}": 1.0}
    if u < 0.14:
        k = smooth((u - 0.05) / 0.09)
        return {f"shin.{side}": k, f"foot.{side}": 1.0 - k}
    if u < 0.22:
        k = smooth((u - 0.14) / 0.08)
        return {f"thigh.{side}": k, f"shin.{side}": 1.0 - k}
    if u < HIP_U:
        k = smooth((u - 0.22) / (HIP_U - 0.22))
        return {"hips": k, f"thigh.{side}": 1.0 - k}
    if u < 0.37:
        k = smooth((u - HIP_U) / 0.07)
        return {"spine": k, "hips": 1.0 - k}
    if u < 0.47:
        k = smooth((u - 0.37) / 0.10)
        return {"chest": k, "spine": 1.0 - k}
    if u < NECK_U:
        k = smooth((u - 0.47) / (NECK_U - 0.47))
        return {"neck": k, "chest": 1.0 - k}
    if u < HEAD_U:
        k = smooth((u - NECK_U) / (HEAD_U - NECK_U))
        return {"head": k, "neck": 1.0 - k}
    return {"head": 1.0}


def arm_chain(u, side):
    """u=0.35 手 → u=0.63 肩"""
    t = max(0.0, min(1.0, (u - HAND_U) / (SHOULDER_U - HAND_U)))
    if t > 0.68:
        return {f"upper_arm.{side}": 1.0}
    if t > 0.34:
        k = smooth((t - 0.34) / 0.34)
        return {f"upper_arm.{side}": k, f"forearm.{side}": 1.0 - k}
    if t > 0.10:
        k = smooth((t - 0.10) / 0.24)
        return {f"forearm.{side}": k, f"hand.{side}": 1.0 - k}
    return {f"hand.{side}": 1.0}


def mix(a, b, w):
    out = {}
    for k, v in a.items():
        out[k] = out.get(k, 0.0) + v * (1.0 - w)
    for k, v in b.items():
        out[k] = out.get(k, 0.0) + v * w
    return out


def weights_for(v):
    u = U(v)
    # 鱼竿：整根刚性绑到右手，随手走
    if v.y < ROD_Y and u > 0.25:
        return {"hand.R": 1.0}
    side = "L" if v.x < 0 else "R"
    base = torso_chain(u, side)
    # 手臂区：横向距离越远越算手臂
    if HAND_U - 0.06 <= u <= SHOULDER_U + 0.06:
        a = smooth((abs(v.x) - ARM_MIN_X) / ARM_FADE)
        if a > 0.001:
            base = mix(base, arm_chain(u, side), a)
    return base


groups = {b.name: ob.vertex_groups.new(name=b.name) for b in arm_data.bones}
for i, v in enumerate(ob.data.vertices):
    w = weights_for(VW[i])
    tot = sum(w.values()) or 1.0
    for name, val in w.items():
        if val > 0.0005:
            groups[name].add([i], val / tot, "REPLACE")

mod = ob.modifiers.new("Armature", "ARMATURE")
mod.object = rig
ob.parent = rig

# ---------------------------------------------------------------- 动作

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = "XYZ"


def swing(amp, phase=0.0, axis=0, frames=30, step=5):
    out = []
    for i in range(0, frames + 1, step):
        rot = [0.0, 0.0, 0.0]
        rot[axis] = amp * math.sin(2 * math.pi * (i / float(frames)) + phase)
        out.append((1 + i, tuple(rot)))
    return out


def make_action(name, keys):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for b in pb:
        b.rotation_euler = (0, 0, 0)
        b.location = (0, 0, 0)
    last = 1
    for bone_name, frames in keys.items():
        b = pb.get(bone_name)
        if b is None:
            print("  ! 缺骨骼", bone_name)
            continue
        last = max(last, frames[-1][0])
        for f, rot in frames:
            b.rotation_euler = tuple(math.radians(a) for a in rot)
            b.keyframe_insert("rotation_euler", frame=f)
    act.use_fake_user = True
    print(f"[anim] {name}: {len(keys)} bones, {last} frames")
    return act


make_action("idle", {
    "chest": swing(1.4, 0.0, 0, 60, 10),
    "head": swing(1.0, 1.2, 0, 60, 10),
})
make_action("walk", {
    "thigh.L": swing(20.0, 0.0),
    "thigh.R": swing(20.0, math.pi),
    "shin.L": swing(14.0, math.pi * 0.55),
    "shin.R": swing(14.0, math.pi * 1.55),
    "upper_arm.L": swing(14.0, math.pi),
    "upper_arm.R": swing(6.0, 0.0),
    "spine": swing(3.0, 0.0, 2),
    "head": swing(1.5, math.pi, 0),
})
make_action("hold", {
    # 模型静止姿态已经是"举竿"，所以这里只做呼吸级别的微调，
    # 一旦抬手臂，长竿会以手为轴甩到脸上（实测过）。
    "upper_arm.R": [(1, (0.0, 0, 0)), (30, (-2.0, 0, 0)), (60, (0.0, 0, 0))],
    "upper_arm.L": [(1, (-2.0, 0, 0)), (60, (-3.0, 0, 0))],
    "spine": [(1, (3.0, 0, 0)), (30, (3.8, 0, 0)), (60, (3.0, 0, 0))],
    "head": [(1, (-2.0, 0, 0)), (60, (-2.5, 0, 0))],
})

bpy.ops.object.mode_set(mode="OBJECT")
rig.animation_data.action = None

# ---------------------------------------------------------------- 导出

os.makedirs(os.path.dirname(DST), exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format="GLB",
    use_selection=True,
    export_apply=False,
    export_skins=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_yup=True,
    export_image_format="AUTO",
)
print("[done]", DST, round(os.path.getsize(DST) / 1048576.0, 2), "MB")
