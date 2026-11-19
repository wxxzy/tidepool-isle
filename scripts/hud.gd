class_name Hud
extends CanvasLayer
## HUD —— 磨砂卡片视觉层（v0.4 视觉重做）
## 要点：① 自绘图标不依赖字体字形 ② 统一卡片样式（半透明底 + 1px 亮边 + 投影）
##       ③ 语义色换肤（文字/强调/危险各有 token，不被整体刷平）④ 按键徽章替代长文字

signal result_action(action: String, fish_info: Dictionary)

const PHASE_LABELS := {
	"dawn": "清晨", "morning": "上午", "noon": "正午",
	"golden": "黄金时刻", "dusk": "黄昏", "night": "夜晚",
}

# ---------- 节点引用 ----------
var _root: Control = null
var _time_panel: PanelContainer = null
var _time_icon: IconGlyph = null
var _time_phase: Label = null
var _time_clock: Label = null
var _goal_card: PanelContainer = null
var _goal_desc: Label = null
var _goal_meter: UiMeter = null
var _goal_count: Label = null
var _dex_chip: PanelContainer = null
var _dex_label: Label = null
var _dex_icon: IconGlyph = null
var _bait_panel: PanelContainer = null
var _bait_label: Label = null
var _bait_icon: IconGlyph = null
var _hint_panel: PanelContainer = null
var _hint_box: HBoxContainer = null
var _charge_panel: PanelContainer = null
var _charge_meter: UiMeter = null
var _charge_pct: Label = null
var _tension_panel: PanelContainer = null
var _tension_meter: UiMeter = null
var _tension_pct: Label = null
var _bite_label: Label = null
var _nibble_label: Label = null
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _result_panel: PanelContainer = null
var _result_icon: IconGlyph = null
var _result_title: Label = null
var _result_lines: Label = null
var _result_actions: HBoxContainer = null
var _dim_layer: ColorRect = null
var _achievement: PanelContainer = null
var _achievement_label: Label = null
var _achievement_icon: IconGlyph = null
var _pending_catch: Dictionary = {}

# ---------- 换肤登记 ----------
var _panels: Array[PanelContainer] = []
var _labels: Array[Label] = []

# ---------- 计时 ----------
var _toast_left := 0.0
var _nibble_left := 0.0
var _result_left := 0.0


func _ready() -> void:
	layer = 10
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_time_chip()
	_build_goal_card()
	_build_dex_chip()
	_build_bait_chip()
	_build_hint()
	_build_bars()
	_build_bite()
	_build_nibble()
	_build_toast()
	_build_result()
	_build_dim_layer()
	_build_achievement()


func _on_theme_changed(_phase: String, _colors: Dictionary) -> void:
	_apply_theme()


# ================= 换肤 =================

func _apply_theme() -> void:
	var c := ThemeManager.palette()
	for p in _panels:
		if p == null or not is_instance_valid(p):
			continue
		var alpha := float(p.get_meta("alpha", 0.80))
		var radius := int(p.get_meta("radius", 14))
		var shadow := int(p.get_meta("shadow", 10))
		p.add_theme_stylebox_override("panel", UiComponents.card_style(alpha, radius, shadow))
	for l in _labels:
		if l == null or not is_instance_valid(l):
			continue
		var sem := str(l.get_meta("sem", "text"))
		l.add_theme_color_override("font_color", c.get(sem, c["text"]))
	if _time_icon != null:
		_time_icon.tint = c["accent"]
	if _dex_icon != null:
		_dex_icon.tint = c["accent"]
	if _bait_icon != null:
		_bait_icon.tint = c["accent"]
	if _goal_meter != null:
		_goal_meter.fill_color = c["accent"]
	if _achievement_icon != null:
		_achievement_icon.tint = c["accent"]
	_refresh_tension_color()


# ================= 构建 =================

func _panel(alpha := 0.80, radius := 14, shadow := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_meta("alpha", alpha)
	p.set_meta("radius", radius)
	p.set_meta("shadow", shadow)
	p.add_theme_stylebox_override("panel", UiComponents.card_style(alpha, radius, shadow))
	_panels.append(p)
	return p


func _label(text: String, size: int, sem := "text") -> Label:
	var l := Label.new()
	l.text = text
	_style(l, size, sem)
	return l


func _style(l: Label, size: int, sem := "text") -> void:
	l.add_theme_font_size_override("font_size", size)
	l.set_meta("sem", sem)
	if not _labels.has(l):
		_labels.append(l)
	l.add_theme_color_override("font_color", _sem(sem))


func _sem(sem: String) -> Color:
	var c := ThemeManager.palette()
	return c.get(sem, c["text"])


## 按键徽章内含的 Label 也纳入换肤（否则换时段后徽章文字不跟着变色）
func _reg_badge(badge: PanelContainer) -> void:
	for ch in badge.get_children():
		if ch is Label:
			var l := ch as Label
			l.set_meta("sem", "accent")
			if not _labels.has(l):
				_labels.append(l)


func _build_time_chip() -> void:
	_time_panel = _panel(0.78, 20, 12)
	_time_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_panel.offset_left = -92
	_time_panel.offset_right = 92
	_time_panel.offset_top = 14
	_time_panel.offset_bottom = 62
	_root.add_child(_time_panel)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 9)
	_time_panel.add_child(hb)

	_time_icon = IconGlyph.new()
	_time_icon.kind = IconGlyph.Kind.SUN
	_time_icon.tint = _sem("accent")
	_time_icon.custom_minimum_size = Vector2(17, 17)
	_time_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_time_icon)

	_time_phase = _label("上午", 13, "text_muted")
	_time_phase.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_time_phase)

	_time_clock = _label("08:01", 18)
	_time_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_time_clock)


func _build_goal_card() -> void:
	_goal_card = UiComponents.goal_card()
	_goal_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_goal_card.offset_left = 16
	_goal_card.offset_top = 16
	_goal_card.offset_right = 254
	_goal_card.offset_bottom = 16  # 高度由内容撑开，避免底部空白
	_root.add_child(_goal_card)
	_goal_desc = _goal_card.get_node_or_null("VBoxContainer/GoalDesc")
	_goal_meter = _goal_card.get_node_or_null("VBoxContainer/GoalProgress/GoalTrack")
	_goal_count = _goal_card.get_node_or_null("VBoxContainer/GoalProgress/GoalCount")
	var _goal_title: Label = _goal_card.get_node_or_null("VBoxContainer/GoalHead/GoalTitle")
	# 换肤登记
	_goal_card.set_meta("alpha", 0.80)
	_goal_card.set_meta("radius", 14)
	_goal_card.set_meta("shadow", 12)
	_panels.append(_goal_card)
	for l in [_goal_title, _goal_desc, _goal_count]:
		if l != null and not _labels.has(l):
			_labels.append(l)
	if _goal_title != null:
		_goal_title.set_meta("sem", "accent")
	if _goal_count != null:
		_goal_count.set_meta("sem", "text_muted")
	if _goal_desc != null:
		_goal_desc.set_meta("sem", "text")
	update_goal_display()


func update_goal_display() -> void:
	if _goal_card == null or _goal_desc == null or GameData.goals.is_empty():
		return
	var shown: Dictionary = GameData.goals[0]
	for g in GameData.goals:
		if not SaveManager.is_goal_done(str(g["id"])):
			shown = g
			break
	var gid := str(shown["id"])
	var target := int(shown.get("target", 1))
	var progress: int = SaveManager.goal_progress(gid)
	var done := SaveManager.is_goal_done(gid)
	if done:
		progress = target
	_goal_desc.text = str(shown.get("title", "—"))
	_goal_meter.ratio = float(progress) / float(maxi(target, 1))
	_goal_meter.fill_color = _sem("safe") if done else _sem("accent")
	_goal_count.text = ("%d/%d" % [mini(progress, target), target]) + (" ✓" if done else "")


func _build_dex_chip() -> void:
	_dex_chip = _panel(0.78, 20, 10)
	_dex_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dex_chip.offset_left = -186
	_dex_chip.offset_right = -16
	_dex_chip.offset_top = 14
	_dex_chip.offset_bottom = 62
	_root.add_child(_dex_chip)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 9)
	hb.alignment = BoxContainer.ALIGNMENT_END
	_dex_chip.add_child(hb)

	_dex_icon = IconGlyph.new()
	_dex_icon.kind = IconGlyph.Kind.FISH
	_dex_icon.tint = _sem("accent")
	_dex_icon.custom_minimum_size = Vector2(19, 19)
	_dex_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_dex_icon)

	_dex_label = _label("0 / 13", 16)
	_dex_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_dex_label)

	var badge := UiComponents.key_badge("Tab", 11)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(badge)
	_reg_badge(badge)
	update_dex_display()


func update_dex_display() -> void:
	if _dex_label == null:
		return
	var caught := SaveManager.caught_list().size()
	_dex_label.text = "%d / %d" % [caught, GameData.fish_defs.size()]


func _build_bait_chip() -> void:
	_bait_panel = _panel(0.78, 20, 10)
	_bait_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bait_panel.offset_left = -178
	_bait_panel.offset_right = -16
	_bait_panel.offset_top = -62
	_bait_panel.offset_bottom = -16
	_root.add_child(_bait_panel)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 9)
	hb.alignment = BoxContainer.ALIGNMENT_END
	_bait_panel.add_child(hb)

	_bait_icon = IconGlyph.new()
	_bait_icon.kind = IconGlyph.Kind.BAIT
	_bait_icon.tint = _sem("accent")
	_bait_icon.custom_minimum_size = Vector2(18, 18)
	_bait_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_bait_icon)

	_bait_label = _label("面团 ×∞", 15)
	_bait_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_bait_label)


func _build_hint() -> void:
	_hint_panel = _panel(0.62, 20, 8)
	_hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_root.add_child(_hint_panel)
	_hint_box = HBoxContainer.new()
	_hint_box.add_theme_constant_override("separation", 7)
	_hint_panel.add_child(_hint_box)
	_set_hint([
		[["WASD"], "行走"], [["左键"], "抛竿"], [["Tab"], "鱼谱"],
	])


## parts 形如 [[["WASD"], "行走"], [["左键"], "抛竿"]]
func _set_hint(parts: Array) -> void:
	if _hint_box == null:
		return
	for ch in _hint_box.get_children():
		_hint_box.remove_child(ch)
		ch.queue_free()
	for it in parts:
		var keys: Array = it[0]
		var text := str(it[1])
		for k in keys:
			var badge := UiComponents.key_badge(str(k), 11)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_hint_box.add_child(badge)
			_reg_badge(badge)
		var l := _label(text, 13)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hint_box.add_child(l)
	call_deferred("_resize_hint")


func _resize_hint() -> void:
	if _hint_panel == null:
		return
	var w := maxf(_hint_panel.get_combined_minimum_size().x, 120.0)
	var h := maxf(_hint_panel.get_combined_minimum_size().y, 40.0)
	_hint_panel.offset_left = 16
	_hint_panel.offset_right = 16 + w
	_hint_panel.offset_top = -18 - h
	_hint_panel.offset_bottom = -18


## 情境化键位提示：只显示当前该按的那一个
func set_situational_hint(state: int) -> void:
	if _hint_box == null:
		return
	var casts := int(SaveManager.get_setting("cast_count", 0))
	if casts < 2:
		_set_hint([[["WASD"], "行走"], [["左键"], "抛竿"], [["Tab"], "鱼谱"]])
		return
	match state:
		FishingCore.State.IDLE:
			_set_hint([[["WASD"], "行走"], [["左键"], "抛竿"], [["Tab"], "鱼谱"]])
		FishingCore.State.CHARGING:
			_set_hint([[["左键"], "按住蓄力，松开抛竿"]])
		FishingCore.State.CASTING:
			_set_hint([[[], "看浮漂落点"]])
		FishingCore.State.WAITING:
			_set_hint([[["空格"], "收杆"], [["Q"], "换饵"]])
		FishingCore.State.BITE:
			_set_hint([[["左键"], "刺鱼！"]])
		FishingCore.State.REELING:
			_set_hint([[["左键"], "收线"], [["右键"], "放线"], [[], "盯住张力条"]])
		_:
			_set_hint([])


func _build_bars() -> void:
	# 蓄力
	_charge_panel = _panel(0.82, 14, 12)
	_charge_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_charge_panel.offset_left = -130
	_charge_panel.offset_right = 130
	_charge_panel.offset_top = -158
	_charge_panel.offset_bottom = -100
	_charge_panel.visible = false
	_root.add_child(_charge_panel)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 8)
	_charge_panel.add_child(cvb)
	var ch := HBoxContainer.new()
	cvb.add_child(ch)
	ch.add_child(_label("蓄力", 13, "text_muted"))
	var csp := Control.new()
	csp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(csp)
	_charge_pct = _label("0%", 13, "accent")
	ch.add_child(_charge_pct)
	_charge_meter = UiMeter.new()
	_charge_meter.custom_minimum_size = Vector2(0, 9)
	_charge_meter.fill_color = _sem("accent")
	cvb.add_child(_charge_meter)

	# 张力
	_tension_panel = _panel(0.82, 14, 14)
	_tension_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tension_panel.offset_left = -170
	_tension_panel.offset_right = 170
	_tension_panel.offset_top = -158
	_tension_panel.offset_bottom = -100
	_tension_panel.visible = false
	_root.add_child(_tension_panel)
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 8)
	_tension_panel.add_child(tvb)
	var th := HBoxContainer.new()
	tvb.add_child(th)
	th.add_child(_label("线张力", 13, "text_muted"))
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tsp)
	_tension_pct = _label("0%", 13, "safe")
	th.add_child(_tension_pct)
	_tension_meter = UiMeter.new()
	_tension_meter.custom_minimum_size = Vector2(0, 9)
	tvb.add_child(_tension_meter)


func _build_bite() -> void:
	_bite_label = Label.new()
	_bite_label.text = "就是现在  ·  左键"
	_bite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_bite_label, 34, "text")
	_bite_label.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.11, 0.95))
	_bite_label.add_theme_constant_override("outline_size", 12)
	_root.add_child(_bite_label)
	_bite_label.set_anchors_preset(Control.PRESET_CENTER)
	_bite_label.offset_left = -260
	_bite_label.offset_right = 260
	_bite_label.offset_top = -168
	_bite_label.offset_bottom = -106
	_bite_label.visible = false


func _build_nibble() -> void:
	_nibble_label = Label.new()
	_style(_nibble_label, 17, "text")
	_nibble_label.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.11, 0.9))
	_nibble_label.add_theme_constant_override("outline_size", 8)
	_root.add_child(_nibble_label)
	_nibble_label.set_anchors_preset(Control.PRESET_CENTER)
	_nibble_label.offset_left = -240
	_nibble_label.offset_right = 240
	_nibble_label.offset_top = 44
	_nibble_label.offset_bottom = 90
	_nibble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nibble_label.visible = false


func _build_toast() -> void:
	_toast_panel = _panel(0.84, 18, 14)
	# 顶部居中、时段 chip 之下：不遮挡第三人称角色
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_left = -290
	_toast_panel.offset_right = 290
	_toast_panel.offset_top = 74
	_toast_panel.offset_bottom = 130
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_panel)
	_toast_label = _label("", 17)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false


func _build_result() -> void:
	_result_panel = _panel(0.90, 18, 18)
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.offset_left = -200
	_result_panel.offset_right = 200
	_result_panel.offset_top = -120
	_result_panel.offset_bottom = 40
	_root.add_child(_result_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_result_panel.add_child(vb)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	_result_icon = IconGlyph.new()
	_result_icon.kind = IconGlyph.Kind.STAR
	_result_icon.tint = _sem("accent")
	_result_icon.custom_minimum_size = Vector2(22, 22)
	_result_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_result_icon.visible = false
	hb.add_child(_result_icon)
	_result_title = _label("", 21, "accent")
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(_result_title)

	_result_lines = _label("", 15)
	_result_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_result_lines)

	_result_actions = HBoxContainer.new()
	_result_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_actions.add_theme_constant_override("separation", 12)
	_result_actions.visible = false
	vb.add_child(_result_actions)
	_result_actions.add_child(_action_button("保留", "keep"))
	_result_actions.add_child(_action_button("放生", "release"))
	_result_panel.visible = false


func _action_button(text: String, action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 36)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", _sem("text"))
	b.add_theme_color_override("font_hover_color", _sem("accent"))
	b.add_theme_color_override("font_pressed_color", _sem("text"))
	b.add_theme_stylebox_override("normal", UiComponents.inset_style(0.5, 10))
	b.add_theme_stylebox_override("hover", UiComponents.card_style(0.9, 10, 6))
	b.add_theme_stylebox_override("pressed", UiComponents.inset_style(0.85, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: _on_result_action(action))
	return b


func _build_dim_layer() -> void:
	_dim_layer = ColorRect.new()
	_dim_layer.color = Color(0.02, 0.06, 0.10, 0.0)
	_dim_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim_layer)
	_root.move_child(_dim_layer, 0)  # 压暗层垫在最底，避免盖住其他 UI


func _build_achievement() -> void:
	_achievement = _panel(0.88, 18, 14)
	_achievement.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_achievement.offset_left = -170
	_achievement.offset_right = 170
	_achievement.offset_top = 138
	_achievement.offset_bottom = 188
	_root.add_child(_achievement)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 9)
	_achievement.add_child(hb)
	_achievement_icon = IconGlyph.new()
	_achievement_icon.kind = IconGlyph.Kind.STAR
	_achievement_icon.tint = _sem("accent")
	_achievement_icon.custom_minimum_size = Vector2(18, 18)
	_achievement_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_achievement_icon)
	_achievement_label = _label("", 15, "accent")
	_achievement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_achievement_label)
	_achievement.modulate.a = 0.0
	_achievement.visible = false


# ================= 每帧 =================

func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0 and _toast_panel != null:
			_fade_out(_toast_panel, 0.28)
	if _nibble_left > 0.0:
		_nibble_left -= dt
		if _nibble_left <= 0.0 and _nibble_label != null:
			_nibble_label.visible = false
	if _result_left > 0.0:
		_result_left -= dt
		if _result_left <= 0.0 and _result_panel != null:
			_fade_out(_result_panel, 0.3)


func _fade_out(c: Control, dur: float) -> void:
	if not c.visible:
		return
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 0.0, dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		c.visible = false
		c.modulate.a = 1.0)


func _fade_in(c: Control, dur := 0.18) -> void:
	c.visible = true
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 1.0, dur).set_ease(Tween.EASE_OUT)


# ================= 公开 API =================

func set_time(_phase_label: String, clock: String, phase_name := "") -> void:
	if _time_clock != null:
		_time_clock.text = clock
	if _time_phase != null:
		_time_phase.text = str(PHASE_LABELS.get(phase_name, _phase_label))
	if _time_icon != null:
		_time_icon.kind = IconGlyph.Kind.MOON if phase_name == "night" else IconGlyph.Kind.SUN


func set_bait(text: String) -> void:
	if _bait_label != null:
		_bait_label.text = text


func set_mode(state: int) -> void:
	if _charge_panel != null:
		_charge_panel.visible = state == FishingCore.State.CHARGING
	if _tension_panel != null:
		_tension_panel.visible = state == FishingCore.State.REELING
	set_situational_hint(state)


func set_charge(v: float) -> void:
	if _charge_meter == null:
		return
	_charge_meter.ratio = v
	if _charge_pct != null:
		_charge_pct.text = "%d%%" % int(clampf(v, 0.0, 1.0) * 100.0)


func set_tension(v: float) -> void:
	if _tension_meter == null:
		return
	_tension_meter.ratio = v / 100.0
	var c := ThemeManager.palette()
	if v > 95.0:
		_tension_meter.fill_color = c["danger"]
	elif v > 70.0:
		_tension_meter.fill_color = c["warn"]
	else:
		_tension_meter.fill_color = c["safe"]
	if _tension_pct != null:
		_tension_pct.text = "%d%%" % int(clampf(v, 0.0, 100.0))
		_tension_pct.set_meta("sem", "danger" if v > 95.0 else ("warn" if v > 70.0 else "safe"))
		_tension_pct.add_theme_color_override("font_color", c.get(str(_tension_pct.get_meta("sem")), c["text"]))


func _refresh_tension_color() -> void:
	if _tension_meter != null:
		set_tension(_tension_meter.ratio * 100.0)


func show_bite(b: bool) -> void:
	if _bite_label != null:
		_bite_label.visible = b
		if b:
			_bite_label.add_theme_color_override("font_color", _sem("highlight"))
			_bite_label.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(_bite_label, "modulate:a", 1.0, 0.12)
	if _dim_layer != null and b:
		_dim_layer.color.a = 0.30
		var tw2 := create_tween()
		tw2.tween_property(_dim_layer, "color:a", 0.0, 0.55).set_ease(Tween.EASE_OUT)


func show_achievement(text: String) -> void:
	if _achievement == null:
		return
	_achievement_label.text = text
	_fade_in(_achievement, 0.22)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(_achievement, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _achievement.visible = false)


func pulse_bobber_hint(text: String) -> void:
	if _nibble_label == null:
		return
	_nibble_label.text = text
	_nibble_label.visible = true
	_nibble_left = 1.6


func toast(text: String, dur := 2.2) -> void:
	if _toast_panel == null:
		return
	_toast_label.text = text
	# 宽度贴合文字（240–660）；用字体实测宽度，避免 autowrap 的最小宽度把短句折成两行
	var font := _toast_label.get_theme_font("font")
	var fs := _toast_label.get_theme_font_size("font_size")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := clampf(tw + 56.0, 240.0, 660.0)
	_toast_panel.offset_left = -w * 0.5
	_toast_panel.offset_right = w * 0.5
	_fade_in(_toast_panel, 0.16)
	_toast_left = dur


func show_result(title: String, lines: Array, fish_info := {}) -> void:
	if _result_panel == null:
		return
	# 结算卡出现时收起 toast，避免叠在一起
	_toast_left = 0.0
	if _toast_panel != null:
		_toast_panel.visible = false
	_pending_catch = fish_info
	var is_record := false
	var body: Array[String] = []
	for l in lines:
		var s := str(l)
		if s.contains("新纪录"):
			is_record = true
			continue
		if s.strip_edges() != "":
			body.append(s)
	_result_title.text = title
	_result_lines.text = "\n".join(body)
	_result_icon.visible = is_record
	if is_record:
		_result_title.add_theme_constant_override("outline_size", 8)
		_result_title.add_theme_color_override("font_outline_color", Color(1.0, 0.85, 0.4, 0.45))
	else:
		_result_title.add_theme_constant_override("outline_size", 0)
	if _result_actions != null:
		_result_actions.visible = not fish_info.is_empty()
	_fade_in(_result_panel, 0.2)
	_result_left = 6.0 if not fish_info.is_empty() else 2.8


func _on_result_action(action: String) -> void:
	var info := _pending_catch
	if action == "release":
		toast("轻轻放回水里。它摆了摆尾。", 1.8)
	else:
		toast("收进鱼篓了。", 1.6)
	result_action.emit(action, info)
	_pending_catch = {}
	_result_left = 0.35
