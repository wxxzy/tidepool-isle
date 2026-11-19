class_name UiComponents
extends RefCounted
## UI 组件工厂 —— 统一"磨砂卡片"外观：半透明底 + 1px 亮边 + 柔和投影
## 所有组件从 ThemeManager 色板取色，宿主订阅 theme_changed 后重建即可换肤。


## 通用卡片样式（面板 / chip / 提示条共用，只有 alpha 与圆角不同）
static func card_style(alpha := 0.80, radius := 14, shadow := 10) -> StyleBoxFlat:
	var c := ThemeManager.palette()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c["panel"].r, c["panel"].g, c["panel"].b, alpha)
	sb.border_color = c["border"]
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0.02, 0.06, 0.09, 0.32)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb


## 次级块（按键徽章、chip 内小底）——更轻、无投影
static func inset_style(alpha := 0.55, radius := 6) -> StyleBoxFlat:
	var c := ThemeManager.palette()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c["panel_alt"].r, c["panel_alt"].g, c["panel_alt"].b, alpha)
	sb.border_color = Color(c["border"].r, c["border"].g, c["border"].b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.anti_aliasing = true
	return sb


## 按键徽章：[WASD] 圆角小块
static func key_badge(text: String, size := Palette.FONT_XS) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_meta("ui_key_badge", true)
	p.add_theme_stylebox_override("panel", inset_style(0.62, 6))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ThemeManager.palette()["accent"])
	p.add_child(l)
	return p


## 今日目标卡：星标标题 + 目标描述 + 圆角进度条 + 计数
static func goal_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "GoalCard"
	card.set_meta("ui_panel_alpha", 0.80)
	card.add_theme_stylebox_override("panel", card_style(0.80, 14, 12))
	card.custom_minimum_size = Vector2(238, 0)

	var vb := VBoxContainer.new()
	vb.name = "VBoxContainer"
	vb.add_theme_constant_override("separation", 7)
	card.add_child(vb)

	# 标题行：星标 + 小字标题
	var head := HBoxContainer.new()
	head.name = "GoalHead"
	head.add_theme_constant_override("separation", 6)
	vb.add_child(head)
	var star := IconGlyph.new()
	star.name = "GoalStar"
	star.kind = IconGlyph.Kind.STAR
	star.tint = ThemeManager.palette()["accent"]
	star.custom_minimum_size = Vector2(12, 12)
	head.add_child(star)
	var title := Label.new()
	title.name = "GoalTitle"
	title.text = "今日小目标"
	title.add_theme_font_size_override("font_size", Palette.FONT_XS)
	title.add_theme_color_override("font_color", ThemeManager.palette()["accent"])
	head.add_child(title)

	var desc := Label.new()
	desc.name = "GoalDesc"
	desc.text = "—"
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", ThemeManager.palette()["text"])
	desc.add_theme_constant_override("outline_size", 3)
	desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	vb.add_child(desc)

	# 进度：条 + 计数
	var prog := HBoxContainer.new()
	prog.name = "GoalProgress"
	prog.add_theme_constant_override("separation", 9)
	vb.add_child(prog)
	var meter := UiMeter.new()
	meter.name = "GoalTrack"
	meter.corner = 3
	meter.custom_minimum_size = Vector2(0, 7)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.fill_color = ThemeManager.palette()["accent"]
	prog.add_child(meter)
	var count := Label.new()
	count.name = "GoalCount"
	count.text = "0 / 0"
	count.add_theme_font_size_override("font_size", Palette.FONT_XS)
	count.add_theme_color_override("font_color", ThemeManager.palette()["text_muted"])
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog.add_child(count)
	return card
