# 《潮汐小岛》Tidepool Isle

小型治愈系钓鱼游戏 · Godot 4 落地切片（方案 A）。
设计文档见 `../outputs/fishing-brief/钓鱼游戏设计大Brief.html`（**v0.6 已修订 §5.4 角色条款并新增 §5.7 AI 资产管线**）。
ComfyUI 能力实测与 3D/2D 路线决策见 `../outputs/tidepool-ui/ComfyUI能力评估与路线决策_2026-11-18.html`。

> 一座半小时能走完的小岛，一根有四拍手感的钓竿，一个会呼吸的昼夜。没有失败，只有「再一杆」。

## 教程

**想学怎么做出来的，看 [`docs/tutorial/`](docs/tutorial/README.md)** —— 10 篇，从"一个空场景"写到"导出 exe 自检"，
每篇都能独立验收。含混元 3D 生成、GLB 后处理、Blender 绑骨、真实渲染截图验证的完整踩坑记录。

## 运行

- **编辑器打开**：Godot 4.7+ → Import → 选择本目录（含 `project.godot`）→ F5 运行
- **命令行直跑**：`godot --path <本目录>`
- **跑单元测试**：`godot --headless --path <本目录> --script tests/run_tests.gd`（当前 129/129 通过）
- **跑集成测试**：`godot --headless --path <本目录> res://tests/integration_scene.tscn`（当前 37/37 通过，autoload 正常注入）
- **截图验证（真实渲染，非 headless）**：
  `godot --path <本目录> --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --script tests/visual_probe.gd`
  → 在 `user://probe/` 生成 6 张状态截图（日间/蓄力/张力/结算/夜晚/鱼谱）
  `... --script tests/character_probe.gd` → 角色背/正/侧/走路/持竿/特写 6 张
  `... --script tests/fish_probe.gd` → 水面/鱼特写/俯视鱼群/玩家岸边 4 张
  `... --script tests/model_views.gd -- <glb路径> <高度>` → 任意 GLB 的 0/90/180/270 四向检视
  UI 或角色改动必须看这几组图确认
- **导出包自检截图**（验证 exe 实际长什么样，而不是只看编辑器）：
  `TidepoolIsle.exe -- --shot=<绝对路径.png> --shot-frames=120`

## v0.7.0 混元3D 资产落地（2026-11-18）

**接入方式**：腾讯混元生3D（专业版）的 OpenAI 兼容端点 `https://api.ai3d.cloud.tencent.com/v1/ai3d/submit|query`，
用 API Key（`Authorization: sk-...`）直接调用，**不需要** SecretId/SecretKey 签名。工具链见
`../outputs/tidepool-ui/hy3d_client.py`（单次提交/查询）、`hy3d_gen.py`（3 并发队列调度：在飞任务上限 3，完成即补位、即下载）。

**已生成资产**（`assets/models/`，全部经 `glb_post.py` 后处理）：

| 资产 | 原始 | 处理后 | 说明 |
|---|---|---|---|
| `hero.glb` 主角 | 25.9 MB / 15 000 面 / 3×4096 PBR | 2.5 MB / 1024 贴图 | 多视角（正+左+背）+ PBR |
| `fish/sardine.glb` | 9.8 MB / 6 000 面 | 0.44 MB / 512 贴图 | |
| `fish/butterfly.glb` | 9.3 MB / 6 000 面 | 0.38 MB | |
| `fish/seabream.glb` | 8.1 MB / 6 000 面 | 0.28 MB | |
| `fish/puffer.glb` | 9.4 MB / 6 000 面 | 0.33 MB | |
| `fish/grouper.glb` | 7.3 MB / 7 000 面 | 0.37 MB | |

**关键结论（踩过的坑，别再走一遍）**：

1. **混元直出的模型已经是 Y-up**（顶点数据 Z-up + 节点带 -90°X 旋转），**不要再烘焙旋转**，否则人物会躺下。
2. 混元导出的 accessor `min/max` 不可信，包围盒必须从顶点数据实算（`glb_post.py --ground/--center` 就是这么做的）。
3. **运行时加载必须走 `ResourceLoader`**：导出包里 `.glb` 已被 import 成 PackedScene 并 remap，裸文件不存在；
   先试 `GLTFDocument` 会直接失败，导致"编辑器里好好的、exe 里退回方块角色"。
4. 静态变量缓存 **Node 会在引擎关闭阶段段错误**，要缓存 `PackedScene`（`ModelLib` 已按此实现）。
5. 并发上限是**未完成任务数 3**（不是 3 个并行线程），第 4 个提交直接返回 `RequestLimitExceeded.JobNumExceed`。
6. 积分消耗：鱼 30/条（FaceCount 10 + Normal 20），主角 50（多视角 +10、PBR +10）。本轮 6 个模型共 **200 积分**。

**游戏侧改动**：

- `scripts/model_lib.gd`（新）：GLB 加载/缓存、等比缩放、落地居中、找"最高顶点"当鱼竿尖。
- `scripts/player.gd`：优先装配混元主角（`_build_glb_model`），失败回退程序化角色（`_build_procedural_model`）；
  无骨骼模型用整体运动表现（迈步弹起/摆胯/前倾 + 纵向挤压），钓线起点自动取模型竿尖。
- `scripts/fish_swimmer.gd`（新）：三种运动模式 —— `ORBIT` 环境鱼群、`HOOKED` 中鱼后在浮漂旁挣扎、`LEAP` 上鱼跃出水面。
- `scripts/main.gd`：近岸两带鱼群（浅 47–56m / 深 57–74m，共 26 群 52 条），固定随机种子保证观感一致；
  新增 `--shot=` 自检截图开关（导出包也能用）。
- `scripts/fishing_controller.gd`：中鱼生成水下鱼模型、上鱼播放跃出、断线/脱钩清理。
- `scripts/world_builder.gd`：水面浅水 alpha 0.70 → 0.62，让水下鱼能透出来。

**验证**：单元 121/121、集成 35/35；新增 `fish_probe.gd` 四张实拍图；导出 exe 用 `--shot` 实测确认角色是 3D 模型。

**未完成**：剩余 7 条鱼（squid / moray / bluefin / moonfish / sailfish / shark / jellyfish）因账户积分不足（`ResourceInsufficient`）未生成，
每条 30 积分，补齐需 **210 积分**。补齐后只需在 `FishSwimmer.SPECIES` 加一行、跑一遍 `glb_post.py` 再放进 `assets/models/fish/`。

## v0.8.0 主角绑骨（2026-11-19）

**目标**：让只有静态网格的混元主角能真的迈腿，而不是整块"滑行"。

**结论先说**：混元生3D 专业版只出静态网格（`skins=0`）。补骨骼有两条路：

| 路线 | 怎么做 | 代价 / 限制 | 本仓库状态 |
|---|---|---|---|
| **A. 本机 Blender 自动绑骨** | `outputs/tidepool-ui/build_rig.py` | 免费、离线、可控；质量取决于规则 | ✅ 已落地 |
| B. 混元官方 `hy-3d-rigging` | `POST https://tokenhub.tencentmaas.com/v1/api/3d/submit`，`Authorization: Bearer <API Key>`，`{"model":"hy-3d-rigging","file_3d":{"url":"<公网URL>"},"motion_type":23}` | 模型必须 **A/T Pose、不含鱼竿等道具、无松散配饰**；`file_3d.url` 要**公网可访问**（本地文件传不上去）；并发 1 | ⏸ 未用（当前模型举着竿、背着篓，且本地文件无公网地址） |

**为什么不用 Blender 的"自动权重"**：混元网格是 **487 个互不相连的碎片**，bone heat 求解依赖连续曲面，会直接
`failed to find solution`。所以改成几何规则权重（`build_rig.py`）：

1. 从顶点剖面实测身体比例：腿 0–0.30 / 骨盆 0.30 / 躯干 0.30–0.68 / 脖子 0.70 / 帽檐 0.76–1.00，手臂 0.35（手）–0.65（肩）。
2. 建 18 根骨骼：`root/hips/spine/chest/neck/head` + 双臂 `upper_arm/forearm/hand` + 双腿 `thigh/shin/foot`。
3. 逐顶点算权重：按高度分层 + 左右分侧，横向用 `smoothstep` 做软过渡（防止腰侧硬接缝）；
   **鱼竿顶点（y 比背篓更靠后）整根刚性绑到 `hand.R`**，手臂一动竿就跟着走。
4. 烘焙 3 段动作：`idle`（呼吸）/ `walk`（迈腿摆臂，1 秒循环）/ `hold`（持竿微调）。导出 GLB 带 skin + animation。

**坑（都实测过）**：
- 骨架建好后**不要**再给 `hold` 抬手臂：长竿以手为轴一抬就甩到脸上。`hold` 只做呼吸级微调，因为模型静止姿态本身就是举竿。
- 钓线起点不能写死：要用 `hand.R` 当前位姿实时算（`rod_tip = skel.global_transform * (bone_pose * offset)`），
  否则抬竿时钓线会从旧位置飘出去。Godot 的 `BoneAttachment3D` 在这种嵌套骨架下算出的偏移不对，已弃用。

**游戏侧**：`player.gd` 优先 `hero_rigged.glb` → 退回 `hero.glb`（静态）→ 退回程序化角色；
有 `AnimationPlayer` 时按状态切 `idle/walk/hold`，并把 `speed_scale` 跟移动速度挂钩（慢走不"原地快蹬"）。

**验证**：单元 129/129、集成 37/37（新增"移动切 walk / 持竿切 hold / 竿尖在手骨上方 2.20m"断言）；
`tests/rig_probe.gd` 出正面四姿势图与侧面五帧步态图，步幅真实、无撕裂；导出 exe `--shot` 实测通过。

## 发布包（v0.8.0，已导出）

- **Windows**：`../outputs/tidepool_isle_win/TidepoolIsle.exe`（109 MB）+ `.pck`
- **Web**：`../outputs/tidepool_isle_web/index.html`（38 MB wasm，需 HTTP 服务器打开，不能 file:// 直开）
- 导出预设：`export_presets.cfg`（Web 预设的 `custom_template` 指向本机已装的 `web_release.zip`，因 Godot 4.7 默认寻找的 `web_nothreads_*` 模板未安装；若换新机可直接装全模板后清空这两个字段）

## 操作（M1 切片）

| 输入 | 动作 |
| --- | --- |
| WASD / 鼠标 | 行走 / 视角（Web 首次点击解锁鼠标与音频；Esc 释放） |
| Shift | 快走 ×1.4 |
| 左键（按住） | 蓄力 → 松开抛竿；咬钩时刺鱼；溜鱼时收线 |
| 右键 | 溜鱼时放线（张力管理） |
| Q | 换鱼饵 |
| 空格 | 收杆 |
| E | 交互（预留） |

地形速度差：沙 ×0.85 / 草 ×1.0 / 礁石 ×0.7；可以踩水但不能游泳（深度 -1.2m 为界）。

## v0.6.0 角色面部表情（2026-11-18，无需 Rodin 授权）

按《ComfyUI 能力评估与路线决策》结论：Rodin 3D 需额外登录授权（实测 Unauthorized），因此**不进关键路径**，改用已验证可用的 Qwen-Image 2D 能力实现 Brief §5.4 修订后的面部要求：

- **四表情贴图**：ComfyUI Qwen-Image 2.1 bf16 生成白底简笔五官（calm / smile / focus / surprise，1024×1024，固定 seed 2026111801–04），`fix_face_alpha.py` 四角连通泛洪抠透明，取四张 bbox 并集统一画布（切换表情不跳位），落位 `assets/face/*.png`（256×256）。
- **Sprite3D 贴片**：`player.gd` 用 `Sprite3D`（而非 PlaneMesh + 透明材质）挂在头部正面 `z=0.17`、`pixel_size=0.00105`。**踩坑记录**：PlaneMesh 方案在 GL Compatibility 下只渲染局部（先只露眉毛、放大后整片消失），换 Sprite3D 后五官完整显示。
- **表情 API**：`player.set_expression(name, duration)` + `set_base_expression()` + `has_face()`；`_physics_process` 里计时自动回退基础表情。
- **事件联动**：咬钩→surprise 0.9s、鱼讯试探→focus 1.2s、断线→surprise 1.6s、上岸/新纪录→smile 2.4s、错过咬钩→calm。
- **渐进增强**：贴图缺失时不创建面部节点，回退 v0.5 无脸程序化角色，不会崩。
- 验证：角色探针扩到 10 张截图（含 `face_01..04` 四表情特写），集成测试加四表情贴图断言；单元 97/97、集成 39/39、冒烟零错误。

## v0.5.0 角色替换（2026-11-18）

灰胶囊 + 圆锥帽的占位角色换成**程序化低多边形渔夫**（仍零外部美术资源，全部代码生成）：

- **骨架式装配**：`Hips → Torso → Head`，四肢各自有枢轴节点（`LegL/LegR/ArmL/ArmR`），因此能真正摆臂摆腿，而不是整体平移。
- **造型**：草帽（帽檐 + 帽冠 + 布带）、奶油色短袖衬衫（袖口以下露肤，手臂与躯干能区分）、牛仔短裤 + 腰带、深色靴子、背后藤编鱼篓（双肩带）、右手钓竿（握把 + 渔轮 + 竿尖）。圆肩球体柔化方肩，衣领改成绕颈圆环（原来横在肩上的"板"很难看）。
- **前/后辨识**：设计上不做五官（Brief §5.4），改用"头发球比头略大、向后偏移"的方式，正面是脸、背面是头发，一眼能分出朝向。
- **动画**：`_animate(dt, speed)` —— 走路时腿/臂反相摆动（右臂持竿摆幅压到 30%）、髋部双频起伏、躯干轻微前倾与左右摇；站立时慢呼吸起伏；`frozen`（持竿钓鱼）时双臂抬起握竿、双腿站定。
- **钓竿挂在右手**：`rod_tip` 成为手臂子节点，甩竿/抬臂时竿尖跟着动，鱼线起点更自然。
- **顺带修的 UI 问题**：toast 原来在屏幕正中，正好压住第三人称角色。移到顶部时段 chip 下方，成就卡顺次下移。
- 新增 `tests/character_probe.gd`（背/正/侧/走路/持竿/特写六张截图）+ 集成测试 `_test_character_rig()`（关节齐全、竿尖归属、走路腿摆角、持竿抬臂角）。

## v0.4.0 视觉层重做（2026-11-18，截图实测驱动）

**背景**：v0.3.0 声称"五阶段落地"，但用真实渲染截图复查后发现界面上几乎看不出变化——原因不是没写代码，而是三处实现缺陷：

1. **图标全是字体字形**（`☀ ◇ ☾`）。Godot 默认字体不含这些字形，实际渲染成小圆点。→ 改为 `IconGlyph` 自绘（`_draw` 画太阳/月牙/鱼/绕线轮/星），不依赖字体。
2. **面板全是同一块扁平色块**。→ `UiComponents.card_style()` 统一卡片：半透明底 + 1px 亮边 + `shadow_color` 柔和投影；圆角进度条改用 `UiMeter`（`StyleBoxFlat` 画，`ColorRect` 无法圆角）。
3. **鱼谱面板溢出屏幕**。插画接进来后 `TextureRect` 的最小尺寸等于贴图尺寸（512px），把卡片撑到 250×400，面板从屏幕中心向右下溢出。→ 加 `expand_mode = EXPAND_IGNORE_SIZE` + 面板显式居中矩形 + 4 列网格 + 内部滚动。
4. **夜间穿帮**：夜空很黑但地面还是白天亮度（`sun.light_energy` 的下限被写死 0.25）。→ 夜间 ambient 0.10 / light 0.12，环境光按光照色染色。
5. 次要：目标卡高度贴合内容、toast 宽度按字体实测贴合、结算卡出现时收起 toast、按键徽章文字纳入换肤。

**这一轮的可验证性改进**：新增 `tests/visual_probe.gd`（真实 OpenGL 渲染 + 逐状态截图 + 节点矩形 dump），并把这些 bug 写成断言进集成测试（面板必须落在视口内且 ≤1000×640、卡片 ≤240×210、目标卡高度 ≤120px、夜间 ambient ≤0.15）。

## v0.3.0 UI 视觉落地（2026-11-18）

按《Godot落地差距清单》五阶段顺序推进，前四阶段已完成：

1. **全局换肤** ✅：`Palette`（三套色板 + 尺寸/字号 token）→ `ThemeManager` Autoload 广播 `theme_changed` → HUD / 鱼谱统一换色。白天/黄金时刻/夜晚三个时段整个 UI 变色，不再只有 chip。
2. **8 个 UI 组件** ✅：今日目标卡（进度条+达成标记）、鱼谱常驻 chip、情境化键位提示（按 FishingCore.State 切换，新手期后启用）、按键徽章工厂、结算卡保留/放生按钮、咬钩屏幕压暗层、成就卡淡入、新纪录星芒描边。
3. **数据层** ✅：`data/goals.json`（3 目标 + 10 条正向反馈文案 + 6 时段情境提示）、fish.json 加 `icon` 字段、SaveManager 加 `[goals]` 节与目标进度 API。
4. **美术资产** ✅：13 张低多边形鱼种插画由 ComfyUI Qwen-Image 生成（768×768 白底 → 四角泛洪抠图 → 256×256 透明 PNG），落位 `assets/fish/<id>.png`。抠图采用**四角连通背景填充**而非全图亮度阈值——后者会把浅色半透明主体（水母、鱿鱼）一起吃掉。
5. **回归与打包** ✅：单元 93/93、集成 22/22、主场景 240 帧冒烟零错误；Windows 与 Web 重新导出（pck 88KB → 455KB，13 张插画已包含）。

**资产说明**：`assets/fish/` 下 13 张 PNG（sardine / seabream / sailfish / butterfly / puffer / grouper / squid / moray / bluefin / moonfish / shark / jellyfish / trash），命名与 `fish.json` 的 `id` 一一对应；鱼谱读取 `f.icon`，文件缺失时自动回退 emoji 占位（渐进增强，删图也不会崩）。

## 已实现（对应 Brief 里程碑）

- **M0 可玩切片** ✅：程序化低多边形岛（五区布局）+ 第三人称行走 + 码头 + 蓄力抛竿 + 浮漂入水
- **M1 钓鱼闭环** ✅：静默→轻点试探→沉漂咬钩（0.4s 窗口）→刺鱼→张力收放线→断线/上岸→结算卡；13 条鱼种数据 + 5 种鱼饵
- **M2 完整** ✅：24 分钟昼夜循环（六时段插值 + crossfade）、夜间灯与萤火虫、**持久化存档**（`user://tidepool_save.cfg`：纪录/鱼谱/库存/设置）、**鱼谱图鉴界面**（Tab 打开，三态显示 + 尺寸纪录墙 + 时段/钓点筛选）、**音频系统**（程序生成潮声环境床 + 10 种音效 + 咬钩 ducking + 时段氛围）、HUD 重做（时段 chip 高亮、toast 背景板、鱼饵 chip 修复）
- **M3 扩展（未做）**：小船驾驶与深水门槛、天气系统、烹饪收集
- **拟饵主动玩法**：当前 lure 仍是高权重普通饵，ACTIVE_REEL 主动收线玩法待后续迭代

## 数据驱动（改表不发版）

- `data/fish.json`：鱼种 / 时段 / 钓点 / 鱼饵权重 / 稀有度 / 尺寸区间 / 挣扎模式（twitch / burst / heavy / suction / vanish）
- `data/bait.json`：鱼饵与库存（`count: -1` = 无限）
- `data/daycycle.json`：昼长（默认 24 分钟）、起始时刻、六时段色板与光照关键帧

## 架构（脚本 → Brief 章节）

| 脚本 | 职责 |
| --- | --- |
| `scripts/fishing_core.gd` | 钓鱼状态机**纯逻辑**（无节点依赖，可 headless 确定性测试） |
| `scripts/day_cycle.gd` | 昼夜关键帧插值（纯逻辑） |
| `scripts/fish_def.gd` / `game_data.gd` | 数据模型与 JSON 加载（Autoload） |
| `scripts/world_builder.gd` | 程序化世界：岛体高度函数 / 水面着色器 / 码头 / 渔屋 / 棕榈 / 小船 / 礁石 |
| `scripts/player.gd` | L0 行走（材质速度差 / 踩水限制 / 镜头呼吸感） |
| `scripts/fishing_controller.gd` | 钓鱼运行时：抛物线飞行 / 浮漂 / 鱼线 / 飞溅 / 结算 |
| `scripts/day_night.gd` | 太阳月亮轨迹 / 夜间灯光 / 萤火虫 |
| `scripts/hud.gd` | 零 UI 优先的情境化 HUD |
| `scripts/save_manager.gd` | 存档持久化（Autoload）：records / dex / inventory / settings |
| `scripts/fish_dex.gd` | 鱼谱图鉴 UI（Tab）：三态显示 + 纪录墙 + 筛选 |
| `scripts/audio_system.gd` | 音频：程序生成潮声 + 10 种音效 + ducking + 时段氛围 |
| `tests/run_tests.gd` | 129 条单元测试（`--script` headless） |
| `tests/integration_test.gd` + `integration_scene.tscn` | 37 条集成测试（主场景模式，autoload 正常） |

## 资产说明

`assets/` 里的 3D 模型与贴图是 AI 生成的二进制文件（约 13MB），可以按
[`tools/asset_pipeline/README.md`](tools/asset_pipeline/README.md) 重新生产。

如果仓库里缺这些文件，游戏仍能跑：`player.gd` 会退回程序化方块角色，鱼谱会退回 emoji。
这条 fallback 链是有意设计的（见教程第 07 篇）。

## 已知边界

- **骨骼是规则绑的，不是学习出来的**：走/站/持竿三段动作够用，但没有手指、没有表情骨、没有奔跑与跳跃；
  想要更高质量的动作库，得走混元 `hy-3d-rigging`（需 A/T Pose + 公网 URL + 无道具的模型），或 Blender 手工绑骨 + 动捕重定向。

- 亮片拟饵当前按高权重饵处理，ACTIVE_REEL 主动收线玩法待后续迭代
- 深水区暂可由满力远抛抵达；小船门槛在 M3 加
- 落水自救已修：只禁止向更深走，允许从深水爬回浅滩（A4 ✅）
- 岛体网格**有** trimesh 碰撞
- 渲染器为 GL Compatibility；水面为顶点波 + 菲涅尔 + blend_mix；无岸边泡沫
- BGM 当前由环境音床承担时段氛围（未接实际乐曲素材，可后补）
- Web 版需 HTTP 服务器打开；指针锁定与音频均在首次点击时解锁

## 2026-11-17 审计修复记录

全量代码审计发现并修复两处阻断缺陷（原 42 条纯逻辑测试未覆盖）：

1. **S1 永久冻结**：`fishing_core.reset()` 直接赋值 `state=IDLE` 吞掉 `state_changed` 信号 → `player.frozen` 永远为真、浮漂残留。改为统一走 `_set_state()` 发信号。
2. **S2 张力条空白**：`core.tension_changed` 从未连接到 `hud.set_tension()`。已补连接与回调。

同批修复：收线锚点漂移、水面 shader 缺 `blend_mix`、阴影每帧切换、时钟每帧重写、初始化信号丢失。测试从 42 增至 51 条全绿，主场景 240 帧冒烟零错误。
落地评估与详细设计见 `../outputs/潮汐小岛_落地可行性重估与详细设计_2026-11-17.html`。
