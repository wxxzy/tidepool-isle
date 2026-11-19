class_name Palette
extends RefCounted
## 设计 Token —— 三套色板 + 统一尺寸/字号（UI/UX 方案 §1–§3）
## 纯逻辑，可 headless 测试；HUD / FishDex 均从这里取色，不再硬编码。

const PHASES := ["dawn", "morning", "noon", "golden", "dusk", "night"]

# 尺寸 token（所有控件共用）
const RADIUS := 12
const BORDER_WIDTH := 2
const PAD_X := 14
const PAD_Y := 7
const FONT_XS := 11
const FONT_SM := 12
const FONT_MD := 15
const FONT_LG := 20
const FONT_XL := 30

# 语义色 token（三时段）
# day: 海蓝沙金 / golden: 暖橙 / night: 深蓝暖灯
const SCHEMES := {
	"day": {
		"panel": Color(0.078, 0.345, 0.416, 0.86),      # #14586A
		"panel_alt": Color(0.118, 0.498, 0.549, 0.90),  # #1E7F8C
		"accent": Color(0.941, 0.863, 0.706),           # #F0DCB4 沙金
		"text": Color(1, 1, 1, 0.96),
		"text_muted": Color(0.749, 0.847, 0.863, 0.85),
		"border": Color(0.941, 0.863, 0.706, 0.35),
		"highlight": Color(0.910, 0.514, 0.239),        # 咬钩橙
		"safe": Color(0.373, 0.749, 0.561),
		"warn": Color(0.949, 0.757, 0.306),
		"danger": Color(0.910, 0.357, 0.239),
	},
	"golden": {
		"panel": Color(0.353, 0.239, 0.361, 0.90),      # #5A3D5C 暮山
		"panel_alt": Color(0.788, 0.416, 0.541, 0.90),  # #C96A8A 紫霞
		"accent": Color(1.0, 0.851, 0.557),             # #FFD98E 阳光
		"text": Color(1.0, 0.965, 0.890, 0.98),
		"text_muted": Color(0.949, 0.757, 0.306, 0.90),
		"border": Color(1.0, 0.851, 0.557, 0.45),
		"highlight": Color(0.910, 0.514, 0.239),
		"safe": Color(0.624, 0.749, 0.420),
		"warn": Color(0.949, 0.757, 0.306),
		"danger": Color(0.910, 0.357, 0.239),
	},
	"night": {
		"panel": Color(0.055, 0.118, 0.200, 0.93),      # #0E1E33 深海
		"panel_alt": Color(0.086, 0.157, 0.247, 0.95),  # #16283F 夜空
		"accent": Color(1.0, 0.824, 0.490),             # #FFD27D 灯光
		"text": Color(0.722, 0.780, 0.878, 0.98),       # 月白
		"text_muted": Color(0.639, 0.702, 0.788, 0.85),
		"border": Color(1.0, 0.824, 0.490, 0.30),
		"highlight": Color(1.0, 0.824, 0.490),
		"safe": Color(0.498, 0.890, 0.769),             # #7FE3C4 夜光藻
		"warn": Color(0.949, 0.757, 0.306),
		"danger": Color(0.910, 0.416, 0.365),
	},
}


## 时段名 → 色板组（dawn/morning/noon=day, golden/dusk=golden, night=night）
static func group_for_phase(phase: String) -> String:
	match phase:
		"golden", "dusk":
			return "golden"
		"night":
			return "night"
		_:
			return "day"


static func colors_for(phase: String) -> Dictionary:
	return SCHEMES[group_for_phase(phase)]


static func get_color(phase: String, semantic: String) -> Color:
	var scheme := colors_for(phase)
	return scheme.get(semantic, Color.MAGENTA)
