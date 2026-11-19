# 08 · Blender 规则绑骨

> 目标：给一尊"没有骨骼的雕像"补上 18 根骨头 + 3 段动作，导出能直接播的 GLB。
> 预计 50 分钟 · 前置：第 06 篇（有 Blender 5.x）

---

## 先排除两条路

### 路 A：混元官方绑骨（质量最好，但门槛清楚）

腾讯有 `hy-3d-rigging`，同一个 API Key 就能用：

```bash
curl -X POST 'https://tokenhub.tencentmaas.com/v1/api/3d/submit' \
  -H 'Authorization: Bearer sk-你的KEY' \
  -H 'Content-Type: application/json' \
  -d '{"model":"hy-3d-rigging",
       "file_3d":{"url":"https://公网可访问/hero.glb"},
       "motion_type":23}'
```

`motion_type` 23/24/25 是走路，26/27 是待机。

但文档写得很明确：

> 人形角色需采用标准姿态（A Pose 或 T Pose），尽量保持无动作状态。
> 模型中不应包含人体以外的组件（如武器、坐骑、翅膀等），避免松散衣物、配饰及复杂发型。

我们的主角**举着鱼竿、背着鱼篓**——两个都是"人体以外的组件"。而且 `file_3d.url` 必须是**公网地址**，
本地文件传不上去。所以这条路要成立，得先重新生成一个"A-pose、空手、无配饰"的干净模型，再找地方托管。

**结论：留给以后。这次走本机。**

### 路 B：Blender 自动权重（听起来最省事，实测直接失败）

`bpy.ops.object.parent_set(type='ARMATURE_AUTO')` 是标准的"骨骼热量"权重算法。
但混元的网格是这样：

```
连通分量数: 487     ← 前 10 个分量分别只有 376 / 293 / 279 ... 个顶点
```

**487 个互不相连的碎片。** bone heat 需要一个连续曲面来"传热"，碎片网格上无解，
Blender 会直接报 `Bone Heat Weighting: failed to find solution for one or more bones`。

**结论：走规则权重。**

---

## 步骤 1：先把身体量出来

不要凭感觉摆骨骼。用顶点剖面量：

```python
# 只看身体，排除"很靠后的鱼竿"
body = [v for v in VW if v.y > YC - 0.45]
for i in range(21):
    lo, hi = Z0 + H*i/20, Z0 + H*(i+1)/20
    sel = [v for v in body if lo <= v.z < hi]
    axs = sorted(abs(v.x) for v in sel)
    print("u=%.2f n=%4d |x|max=%.3f p90=%.3f" % (i/20, len(sel), axs[-1], axs[int(len(axs)*0.9)]))
```

输出（u = 高度归一化，0 是脚底，1 是帽顶）：

```
 u     n    |x|max  |x|p90
0.00   608   0.114   0.101     脚
0.05   175   0.086   0.078
0.15    71   0.083   0.075     小腿
0.25   299   0.110   0.084     膝
0.35   267   0.214   0.189     ← 变宽，手臂开始
0.40   798   0.214   0.192
0.50  1020   0.184   0.122
0.60  1133   0.135   0.116
0.65   684   0.126   0.101     肩
0.70   278   0.092   0.065     ← 突然变窄，脖子
0.80   866   0.172   0.141     ← 又变宽，帽檐
0.95    88   0.082   0.079     帽顶
```

一张表就把比例讲明白了：

| 部位 | 归一化高度 |
|---|---|
| 脚 | 0.00 |
| 膝 | 0.17 |
| 骨盆 | 0.30 |
| 腰 | 0.40 |
| 胸 | 0.52 |
| 肩 | 0.63 |
| 脖子 | 0.68–0.70 |
| 帽檐 | 0.76–0.90 |

**别用"人类解剖学比例"去套 AI 模型**——这个角色是 Q 版，头占 1/3，腿只占 30%。

---

## 步骤 2：建 18 根骨骼

```python
bone("root",  z_at(0.0),  z_at(HIP_U*0.6))
bone("hips",  z_at(0.30), z_at(0.40), "root")
bone("spine", z_at(0.40), z_at(0.52), "hips", True)
bone("chest", z_at(0.52), z_at(0.68), "spine", True)
bone("neck",  z_at(0.68), z_at(0.76), "chest", True)
bone("head",  z_at(0.76), z_at(0.99), "neck", True)

for side, sx in (("L", -1.0), ("R", 1.0)):
    bone(f"upper_arm.{side}", (sx*AX, Y, z_at(0.63)), (sx*(AX+0.012), Y, z_at(0.50)), "chest")
    bone(f"forearm.{side}",   ..., f"upper_arm.{side}", True)
    bone(f"hand.{side}",      ..., f"forearm.{side}", True)

for side, sx in (("L", -1.0), ("R", 1.0)):
    bone(f"thigh.{side}", (LEG_X*sx, Y, z_at(0.30)), (LEG_X*sx, Y, z_at(0.17)), "hips")
    bone(f"shin.{side}",  ..., f"thigh.{side}", True)
    bone(f"foot.{side}",  ..., f"shin.{side}", True)
```

`AX = 躯干半宽 + 0.015`。躯干半宽不能用 `max(|x|)` 算——那个高度区间里手臂也在，
算出来会是 0.214（整个身体最宽处）。用 62 分位数：

```python
axs = sorted(abs(v.x) for v in torso_band)
TORSO_HALF = axs[int(len(axs) * 0.62)]     # ≈ 0.086
```

> 这个细节很值得记：**分位数能自动忽略"少数离群点"，而离群点往往就是别的肢体。**

---

## 步骤 3：权重用规则算，不用算法猜

核心思路：**按高度定层，按左右定侧，横向用 smoothstep 做软过渡。**

```python
def torso_chain(u, side):
    if u < 0.05:  return {f"foot.{side}": 1.0}
    if u < 0.14:
        k = smooth((u - 0.05) / 0.09)
        return {f"shin.{side}": k, f"foot.{side}": 1.0 - k}
    ...
```

`smooth` 是标准 smoothstep：

```python
def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)
```

为什么关节处要过渡，而不是硬切换？因为顶点是离散的，硬切换会在关节处出现**折角撕裂**。
±0.09 的过渡带刚好让小腿在膝盖附近平滑弯过去。

手臂单独处理——它和躯干在同一个高度区间，只能靠**横向距离**区分：

```python
def weights_for(v):
    u = U(v)

    # 鱼竿：比背篓更靠后的顶点，整根刚性绑到右手
    if v.y < ROD_Y and u > 0.25:
        return {"hand.R": 1.0}

    side = "L" if v.x < 0 else "R"
    base = torso_chain(u, side)

    if HAND_U - 0.06 <= u <= SHOULDER_U + 0.06:
        a = smooth((abs(v.x) - ARM_MIN_X) / ARM_FADE)     # 越靠外越算手臂
        if a > 0.001:
            base = mix(base, arm_chain(u, side), a)
    return base
```

`mix()` 就是按权重线性混合两个字典。`ARM_FADE = 0.045` 让肩部有个柔和的过渡，
否则手臂一抬，肩膀会被"撕"开一条缝。

### 关于鱼竿

这是这套规则里最讨巧的一笔：

```python
ROD_Y = YC - 0.22     # YC 是身体前后中心；背篓最远到 -0.405，鱼竿到 -0.665
```

**用"比背篓更靠后"这一个条件，就把鱼竿顶点全挑出来了**，整根绑到 `hand.R`。
效果是：手臂一动，鱼竿跟着走，而且是刚性跟随，不会弯。

---

## 步骤 4：烘焙动作

三段，都用同一个 `swing()` 生成循环关键帧：

```python
def swing(amp, phase=0.0, axis=0, frames=30, step=5):
    out = []
    for i in range(0, frames + 1, step):
        rot = [0.0, 0.0, 0.0]
        rot[axis] = amp * math.sin(2 * math.pi * (i / float(frames)) + phase)
        out.append((1 + i, tuple(rot)))
    return out
```

- `idle`：只有 `chest` ±1.4°、`head` ±1.0°，呼吸级别
- `walk`：`thigh` ±20° 反相、`shin` ±14°、`upper_arm` ±14°/±6°、`spine` 侧摆 ±3°
- `hold`：**几乎不动**

### 坑：hold 不能抬手臂

第一版我让 `upper_arm.R` 抬 34°，想着"做个举竿姿势"。

结果：**鱼竿以手为轴转了 34°，直接甩到脸上。**

后来才反应过来——**模型的静止姿态本来就是举竿钓鱼的**。它不需要你摆姿势，你只要别乱动。

```python
make_action("hold", {
    "upper_arm.R": [(1, (0.0, 0, 0)), (30, (-2.0, 0, 0)), (60, (0.0, 0, 0))],
    "spine": [(1, (3.0, 0, 0)), (30, (3.8, 0, 0)), (60, (3.0, 0, 0))],
    ...
})
```

**教训：先看模型自带的姿态，再决定要补什么动作。**

---

## 步骤 5：导出

```python
bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format="GLB",
    use_selection=True,
    export_apply=False,          # 关键：别把 Armature 修改器 apply 掉
    export_skins=True,
    export_animations=True,
    export_animation_mode="ACTIONS",   # 每个 action 导成一段动画
    export_yup=True,
)
```

`export_apply=False` 必须。设成 True 会把修改器烘焙掉，蒙皮直接没了。

---

## 验：一定要看侧视

正面图看不出步态。所以探针要能切侧视：

```bash
godot --path . --rendering-driver opengl3 --audio-driver Dummy \
      --resolution 1200x560 --script tests/rig_probe.gd -- \
      "res://assets/models/hero_rigged.glb" side
```

输出 5 帧走路侧视。判断标准：

- 腿有没有**前后分开**（不是只有一点点抖）
- 膝盖有没有弯
- 脚有没有**严重**穿地（轻微可以接受，没有 IK 都会有）
- 有没有撕裂、拉长

---

## 一个附带发现：骨骼轴向

想"抬手臂"到底绕哪个轴？直接测：

```gdscript
# tests/bone_axis_test.gd：同一根骨头分别绕本地 X/Y/Z 转 ±40°，六个并排
skel.set_bone_pose_rotation(idx, Quaternion.from_euler(Vector3(deg_to_rad(-40), 0, 0)))
```

打印骨骼的 rest 全局变换就很清楚了：

```
upper_arm.R rest global:
  X: (0.990, 0.098, 0.098)     ← 本地 X ≈ 世界 X
  Y: (0.098, -0.995, 0.0)      ← 本地 Y 指向下（骨骼朝向）
  Z: (0.098, 0.010, -0.995)    ← 本地 Z ≈ 世界 -Z
```

所以绕本地 X 转 = 前后摆臂。**这种问题 30 秒测一次，别推理半小时。**

---

## 验收

```bash
python inspect_glb.py assets/models/hero_rigged.glb
```

期望：

```
counts nodes=20 meshes=1 skins=1 ... animations=3
skin0 joints=18
  joints: root, hips, spine, chest, neck, head,
          upper_arm.L, forearm.L, hand.L, upper_arm.R, forearm.R, hand.R,
          thigh.L, shin.L, foot.L, thigh.R, shin.R, foot.R
```

---

## 下一步

骨头有了，但游戏还不知道**什么时候该播哪段**。第 09 篇接状态机。
