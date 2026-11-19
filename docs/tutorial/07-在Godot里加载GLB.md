# 07 · 在 Godot 里加载 GLB

> 目标：同一份代码，编辑器里跑、导出的 exe 里跑，角色都得是 3D 模型。
> 预计 25 分钟 · 前置：第 06 篇

---

## 这个坑长什么样

模型放好、代码写完、编辑器里 F5 —— 完美，混元的主角站在岛上。

导出 exe，双击运行 —— **角色变回了第一版的方块小人**。

没有报错，没有警告，代码甚至走了"模型加载失败"的 fallback 分支。**这就是最坑的一类 bug：
它不崩，它只是悄悄降级。**

---

## 原因：导出包里根本没有那个 `.glb`

Godot 的导入流程是这样的：

```
assets/models/hero.glb          ← 源文件
assets/models/hero.glb.import   ← 导入配置
.godot/imported/hero-xxx.scn    ← 实际被加载的资源
```

`.import` 文件里记着 `path="res://.godot/imported/hero-xxx.scn"`。
**运行时 `load("res://assets/models/hero.glb")` 会通过 remap 找到那个 `.scn`。**

而导出时，打包进去的是**导入后的 `.scn` + remap 表**，原始 `.glb` 一般**不会**进 pck
（除非你在导入设置里勾了"保持原始文件"）。

所以：

| 做法 | 编辑器 | 导出 exe |
|---|---|---|
| `GLTFDocument.append_from_file("res://...glb")` | ✅ 文件在磁盘上 | ❌ 文件不在包里 |
| `ResourceLoader.load("res://...glb")` | ✅ 走 remap | ✅ 走 remap |

---

## 步骤 1：先试资源管线，再退到运行时解析

`scripts/model_lib.gd`：

```gdscript
static func _load_packed(path: String) -> PackedScene:
    # 路径 1：走 Godot 资源管线（导出包必须走这条）
    if ResourceLoader.exists(path):
        var res: Variant = ResourceLoader.load(path)
        if res is PackedScene:
            return res as PackedScene

    # 路径 2：未导入的裸文件（编辑器首次运行 / 外部拖进来的模型）
    var n := _from_document(path)
    if n == null:
        return null
    var ps := PackedScene.new()
    var err := ps.pack(n)
    n.free()
    return ps if err == OK else null
```

顺序**不能反**。反过来写，导出包里第一步就失败——虽然第二步也会失败，但你会以为是模型有问题。

---

## 步骤 2：缓存 PackedScene，不要缓存 Node3D

第一版我这么写的：

```gdscript
static var _templates: Dictionary = {}      # path -> Node3D
```

跑起来没问题，**但退出游戏时段错误**（`Segmentation fault`，exit code 139）。

原因：静态变量在引擎关闭阶段才被清理，那时 `SceneServer` / `RenderingServer` 已经销毁了，
你再 `free()` 一个 `MeshInstance3D`，就是访问已释放的服务器。

改成缓存 `PackedScene`（纯 Resource，不持有渲染资源句柄）：

```gdscript
static var _scenes: Dictionary = {}         # path -> PackedScene

static func spawn(path: String) -> Node3D:
    var ps := packed(path)
    if ps == null:
        return null
    var inst: Variant = ps.instantiate()
    return inst as Node3D
```

**规则：静态缓存只存 Resource，不存 Node。**

---

## 步骤 3：模型要会"缩放 + 落地 + 居中"

混元模型高 0.937（含竿尖），游戏里角色要 1.55m。所以不要改模型的建模单位，加载后统一缩放：

```gdscript
static func local_bounds(root: Node3D) -> AABB:
    var mn := Vector3(INF, INF, INF)
    var mx := Vector3(-INF, -INF, -INF)
    for ch in root.find_children("*", "MeshInstance3D", true, false):
        var mi := ch as MeshInstance3D
        for s in mi.mesh.get_surface_count():
            var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
            for v in verts:
                var p: Vector3 = mi.transform * v
                mn = mn.min(p); mx = mx.max(p)
    return AABB(mn, mx - mn)

static func fit_height(n: Node3D, target_h: float, ground := true, center_xz := true) -> AABB:
    var a := local_bounds(n)
    var k := target_h / a.size.y
    n.scale = Vector3(k, k, k)
    var off := Vector3.ZERO
    if ground:
        off.y = -a.position.y * k
    if center_xz:
        off.x = -(a.position.x + a.size.x * 0.5) * k
        off.z = -(a.position.z + a.size.z * 0.5) * k
    n.position = off
    return AABB(a.position * k + off, a.size * k)
```

用**顶点**算包围盒而不是 `mesh.get_aabb()`，理由和第 06 篇一样：
有些导出的 accessor 元数据不可信，顶点是唯一真相。

---

## 步骤 4：三层 fallback，任何一层挂了游戏都能玩

`player.gd`：

```gdscript
func _build_glb_model() -> bool:
    var path := ""
    if ModelLib.available(HERO_RIGGED):
        path = HERO_RIGGED          # 1. 绑骨版（第 08 篇）
    elif ModelLib.available(HERO_MODEL):
        path = HERO_MODEL           # 2. 静态网格
    if path == "":
        return false                # 3. 程序化角色

    var body := ModelLib.spawn(path)
    if body == null:
        return false

    ModelLib.fit_height(body, HERO_BODY_HEIGHT * 1.42, true, true)
    _using_glb = true
    ...
    return true
```

`_build_model()` 里：

```gdscript
if _build_glb_model():
    return
_build_procedural_model()
```

**这个设计是有意的**：资产没准备好、下载失败、包体裁剪，任何一种情况下玩家看到的都是一个能跑的角色，
而不是一个空场景。第一次跑通的人不会卡在"为什么什么都看不见"。

---

## 步骤 5：必须用 exe 验证

编辑器里 100% 正常，不代表导出后正常。所以加了自检截图（第 04 篇）：

```bash
TidepoolIsle.exe --rendering-driver opengl3 --audio-driver Dummy \
  -- --shot="C:\tmp\shot.png" --shot-frames=120
```

判断标准：**图里是带草帽鱼篓的模型，还是方块小人。**

我第一次跑出来是方块小人 → 说明走的是 fallback → 一看代码，`GLTFDocument` 在导出包里返回失败。
照第 1 步改掉顺序，重导，再截，正常。

---

## 一个容易忽略的细节：`.import` 要进版本库

```
assets/models/hero.glb.import
assets/models/hero_texture_pbr_20250901.png.import
```

`.import` 文件必须提交，否则同事拉下来 Godot 会重新导入、生成新的 UID 引用，容易出"资源丢失"。
但 `.godot/` 目录必须 gitignore（第 10 篇有 `.gitignore`）。

---

## 验收

```bash
# 1. 编辑器
godot --headless --path . --script tests/player_size.gd
#   → using_glb=true，height≈2.20（含竿尖），feet_y 贴着地面高度

# 2. 导出包
godot --headless --path . --export-release "Windows Desktop" "../outputs/TidepoolIsle.exe"
cd ../outputs && ./TidepoolIsle.exe -- --shot="./shot.png" --shot-frames=120
```

两张证据齐了才算过。

---

## 下一步

模型能显示了，但它是一尊**雕像**——没有骨骼，走路只能整块滑。
第 08 篇用 Blender 给它补 18 根骨头。
