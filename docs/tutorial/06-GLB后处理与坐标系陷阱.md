# 06 · GLB 后处理与坐标系陷阱

> 目标：把混元直出的 25.9MB / 4096² 贴图模型，压到 2.5MB 并摆正、落地、居中。
> 预计 30 分钟 · 前置：第 05 篇

---

## 拿到手的模型长什么样

```
hero.glb   25.92 MB   15000 面   3 张 4096×4096 PBR 贴图（normal / baseColor / metallic-roughness）
fish_sardine.glb  9.78 MB  6000 面  1 张 4096×4096
```

三个问题：

1. **太大**。Web 首包会被撑爆，手机端加载要转圈。
2. **坐标系不明**。直接扔进 Godot 可能是躺着的。
3. **原点不在脚底**。原点在身体中心，摆到地上会陷进去一半。

---

## 坑 1：贴图降到 1024，体积掉 90%

这是收益最大的一步，也最简单：把 `bufferView` 里的 PNG 解出来、缩放、重编码、重建 BIN 块。

```python
def reorder_bin(js, bin_, replacements):
    """按 bufferViews 顺序重建整个 BIN 块（图片替换后的偏移要全量重算）"""
    new = bytearray()
    for i, bv in enumerate(js["bufferViews"]):
        start = bv.get("byteOffset", 0)
        data = replacements.get(i) or bin_[start:start + bv["byteLength"]]
        while len(new) % 4:
            new.append(0)              # 4 字节对齐，float 访问器要求
        bv["byteOffset"] = len(new)
        bv["byteLength"] = len(data)
        new += data
    js["buffers"][0]["byteLength"] = len(new)
    return bytes(new)
```

结果：

| 文件 | 原大小 | 1024 | 512 |
|---|---|---|---|
| `hero.glb` | 25.9 MB | **2.5 MB** | — |
| `fish_sardine.glb` | 9.8 MB | — | **0.44 MB** |

主角在屏幕上要占半个屏，用 1024；鱼在 30 米外只有十几像素，512 就够了。

**不要无脑统一 512**：主角特写会糊成一团。

---

## 坑 2：accessor 的 min/max 是错的

我想算包围盒做落地，直接读了 glTF accessor 里的 `min` / `max`，结果得到：

```
min [-0.203, -0.191, -0.937]  max [0.224, 0.474, 0.0]
```

看起来很正常，但用它算"高度"会得到 0.665，而实际渲染出来的角色高 0.937。

**混元导出的 accessor `min/max` 不可信。** 必须从顶点数据自己算：

```python
def vertex_bounds(js, bin_):
    mn, mx = [inf]*3, [-inf]*3
    for ai in _pos_accessors(js):          # 只取每个 primitive 的 POSITION
        acc, base, stride = _acc_region(js, ai)
        for i in range(acc["count"]):
            x, y, z = struct.unpack_from("<fff", bin_, base + i * stride)
            mn = [min(mn[0], x), ...]
            mx = [max(mx[0], x), ...]
    return mn, mx
```

> 顺带一提：`byteStride` 一定要读。交错存储的顶点缓冲里，第 i 个顶点不是从 `base + i*12` 开始的。

---

## 坑 3：模型到底是 Z-up 还是 Y-up

这是我整条流水线里翻得最久的一次。

我的第一反应是"混元直出肯定是 Z-up"，于是写了一手"绕 X 轴 −90° 烤进顶点"。
结果角色**躺下了**。

为了不再瞎猜，写了个对照探针：**同一个 GLB 复制三份，分别施加 0 / −90°X / +90°X，横排渲染一张图**。

```gdscript
var rots := [Vector3.ZERO, Vector3(-PI/2, 0, 0), Vector3(PI/2, 0, 0)]
for i in rots.size():
    var holder := Node3D.new()
    holder.rotation = rots[i]
    holder.position = Vector3((i - 1) * 1.6, 0, 0)
    holder.add_child(scene_copy)
```

看图立刻明白：**AS_IS 就是对的**。

真相是：**顶点数据是 Z-up，但节点上已经带了 −90°X 的旋转**，
两者叠加之后在 Godot 里就是 Y-up。我再烤一次就成了 −180°，当然躺下。

**结论：不要烘焙旋转，直接信节点变换。**

这个方法值得记住：**遇到朝向问题，别推理，做对照图。**

---

## 坑 4：原点在身体中心

混元的模型原点在包围盒中心，不是脚底。直接摆到地上会陷一半。

我的做法是把平移**烤进顶点**（而不是改节点变换）——
因为后面要在 Godot 里对模型做整体缩放，节点变换会被覆盖，顶点里的偏移不会。

```python
def bake_transform(js, bin_, rot_x_deg=0.0, offset=(0, 0, 0)):
    buf = bytearray(bin_)
    for m in js["meshes"]:
        for p in m["primitives"]:
            for key in ("POSITION", "NORMAL"):
                ai = p["attributes"].get(key)
                acc, base, stride = _acc_region(js, ai)
                for i in range(acc["count"]):
                    o = base + i * stride
                    x, y, z = struct.unpack_from("<fff", buf, o)
                    if key == "POSITION":
                        x, y, z = x + dx, y + dy, z + dz
                    struct.pack_into("<fff", buf, o, x, y, z)
                if key == "POSITION":
                    acc["min"], acc["max"] = new_bounds    # 顺手修正错误的 min/max
    return bytes(buf)
```

用法：

```bash
# 主角：不旋转，落地（min Y → 0），XZ 居中
python glb_post.py in.glb out.glb --tex 1024 --ground --center

# 鱼：不旋转，XZ + Y 全居中（悬在水里）
python glb_post.py in.glb out.glb --tex 512 --center
```

---

## 坑 5：鱼竿"很深"

主角的包围盒是 `0.428 × 0.937 × 0.665`（宽 × 高 × 深）。

高度 0.937 正常，但**深度 0.665 是什么？**

看顶点分布的 Z 分带就明白了：

```
band9 z[0.375-0.468]  x[-0.197,0.089]  y[-0.665,-0.123]   ← 顶端那撮顶点在很靠后的位置
```

那撮顶点是**鱼竿尖**——竿向后上方伸出去，所以深度很大。这解释了为什么模型"看起来不高但包围盒很深"。

这个发现后面有直接用处：第 08 篇绑骨时，我用"y 比背篓更靠后"这个条件，**精确地把鱼竿顶点挑出来单独绑到右手**。

---

## 完整流水线

```bash
cd tools/asset_pipeline

# 1. 生成（第 05 篇）
python hy3d_gen.py run spec_all.json

# 2. 后处理
python glb_post.py hy3d_out/glb/hero.glb        hy3d_out/glb/hero_rt.glb --tex 1024 --ground --center
python glb_post.py hy3d_out/glb/fish_sardine.glb hy3d_out/glb/fish_sardine_rt.glb --tex 512 --center

# 3. 拷进工程
cp hy3d_out/glb/hero_rt.glb ../../assets/models/hero.glb
```

---

## 验收

```python
# 看结构：面数、骨骼、贴图尺寸、包围盒
python inspect_glb.py assets/models/hero.glb
```

期望：

```
total triangles=15000  vertices=11748
skins=0                        ← 还没有骨骼，第 08 篇补
img0 texture_pbr_normal   1024x1024 PNG
true bounds min=[-0.2138, 0.0, -0.4684] max=[0.2138, 0.6651, 0.4684]
```

`min.y == 0` 说明落地成功。

---

## 下一步

文件摆正了，但**放进 Godot 你会发现：编辑器里好好的，导出的 exe 里角色变回方块**。
第 07 篇讲这个必踩的坑。
