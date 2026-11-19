# 资产流水线

这套脚本负责把「一张参考图」变成「能直接用的游戏资产」。

```
参考图(ComfyUI) → 混元3D 生成 → GLB 后处理 → Blender 绑骨 → assets/models/
   ref3d/*.png      hy3d_*.py      glb_post.py     build_rig.py
```

---

## 0. 准备

```bash
pip install requests pillow
```

Blender 5.x（绑骨用）：

```
C:\Program Files\Blender Foundation\Blender 5.2\blender.exe
```

---

## 1. 配置 API Key

编辑 `hy3d_client.py` 顶部：

```python
KEY = "sk-你的混元APIKey"
```

混元生3D 用的是 OpenAI 兼容端点，**只要 API Key，不需要 SecretId/SecretKey**。

---

## 2. 先探通（不消耗额度）

```bash
python hy3d_client.py probe
```

期望：

```
PROBE query fake job -> 200 {"Response": {"Error": {"Code": "FailedOperation.JobNotFound"}}}
PROBE submit empty   -> 200 {"Response": {"Error": {"Code": "InvalidParameter..."}}}
```

看到 `JobNotFound` 说明：网络通、Key 有效。

---

## 3. 批量生成

```bash
python hy3d_gen.py run spec_all.json        # 主角 + 12 条鱼
python hy3d_gen.py status                   # 看进度
```

参数在 `spec_*.json` 里改，字段含义：

| 字段 | 说明 |
|---|---|
| `model` | `3.0` / `3.1` |
| `face_count` | 目标面数（鱼 6000–8000，主角 15000） |
| `pbr` | 是否生成 PBR 材质 |
| `main` | 主视图参考图（放 `ref3d/`） |
| `views` | 多视角 `{"left": "...", "back": "..."}` |

**注意并发上限是 3 个"未完成任务"，不是 3 个并行线程。**
脚本已经处理了排队、完成即补位、失败分级重试。

积分消耗：鱼 30/条，主角 50/个。余额不足会返回 `ResourceInsufficient`，脚本会中止。

---

## 4. 后处理

```bash
# 主角：贴图 1024、落地、XZ 居中
python glb_post.py hy3d_out/glb/hero.glb hy3d_out/glb/hero_rt.glb --tex 1024 --ground --center

# 鱼：贴图 512、全居中
python glb_post.py hy3d_out/glb/fish_sardine.glb hy3d_out/glb/fish_sardine_rt.glb --tex 512 --center

# 检查结果
python inspect_glb.py hy3d_out/glb/hero_rt.glb
```

**不要加旋转**：混元直出的顶点是 Z-up，但节点已带 −90°X 旋转，在引擎里就是 Y-up。
再烤一次会让角色躺下。

---

## 5. 绑骨

```bash
blender -b --factory-startup --python build_rig.py -- \
  ../../assets/models/hero.glb \
  ./rig_out/hero_rigged.glb
```

产出：18 根骨骼 + `idle` / `walk` / `hold` 三段动画。

绑骨规则是从顶点剖面实测出来的，**换模型要重新量**（脚本里 `HIP_U` / `NECK_U` 等常量）。
详细原理见 `docs/tutorial/08-Blender规则绑骨.md`。

---

## 6. 落库

```bash
cp hy3d_out/glb/hero_rt.glb      ../../assets/models/hero.glb
cp rig_out/hero_rigged.glb       ../../assets/models/hero_rigged.glb
cp hy3d_out/glb/fish_*_rt.glb    ../../assets/models/fish/
```

然后在 Godot 里 `--import` 一次。

---

## 中间产物

`hy3d_out/` 和 `rig_out/` 已在 `.gitignore` 里，不进版本库。
`ref3d/*.png`（参考图）建议留着，重生成时要用。
