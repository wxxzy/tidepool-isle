class_name FishDex
extends CanvasLayer
## 鱼谱图鉴界面（P2）—— Tab 打开，13 种鱼三态显示 + 尺寸纪录墙 + 时段/钓点筛选
## 数据源：GameData.fish_defs + SaveManager（caught / seen / records）
## 零 UI 原则：关闭时完全不可见；开放时半透明覆盖，保留世界可见。

var _panel: PanelContainer = null
var _backdrop: ColorRect = null
var _grid: GridContainer = null
var _title: Label = null
var _filter_label: Label = null
var _filter_phase := -1     # -1 = 全部；0..5 = 时段索引
var _filter_spot := -1      # -1 = 全部；0=dock 1=shallow 2=deep
var _open := false

const PHASES := ["dawn", "morning", "noon", "golden", "dusk", "night"]
const SPOTS := ["dock", "shallow", "deep"]
const PHASE_NAMES := ["清晨", "上午", "正午", "黄金时刻", "黄昏", "夜晚"]
const SPOT_NAMES := ["码头", "浅滩", "深水"]


func _ready() -> void:
	layer = 20
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_build()
	_panel.visible = false
	if _backdrop != null:
		_backdrop.visible = false


func _on_theme_changed(_phase: String, _colors: Dictionary) -> void:
	_apply_theme()


func _apply_theme() -> void:
	if _panel == null:
		return
	var c := ThemeManager.palette()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c["panel"].r, c["panel"].g, c["panel"].b, 0.95)
	sb.border_color = c["border"]
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)
	if _title != null:
		_title.add_theme_color_override("font_color", c["accent"])
	if _filter_label != null:
		_filter_label.add_theme_color_override("font_color", c["text_muted"])
	_refresh()  # 卡片色随主题重建


func _build() -> void:
	# 背景压暗层：让面板从世界里"浮起来"
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.05, 0.08, 0.42)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_panel = PanelContainer.new()
	add_child(_panel)
	# 显式矩形：PRESET_CENTER 会把左上角放在屏幕中心，尺寸靠 min size 向右下溢出
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -420
	_panel.offset_right = 420
	_panel.offset_top = -300
	_panel.offset_bottom = 300
	_apply_theme()

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	_title = Label.new()
	_title.text = "鱼谱 · 潮汐小岛"
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1.0, 0.824, 0.49))
	vb.add_child(_title)

	var sub := Label.new()
	sub.text = "Tab 关闭 · 1–6 按时段筛选 · 7–9 按钓点筛选 · 0 显示全部"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vb.add_child(sub)

	_filter_label = Label.new()
	_filter_label.add_theme_font_size_override("font_size", 13)
	_filter_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.95))
	vb.add_child(_filter_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_refresh()


func toggle() -> void:
	_open = not _open
	_panel.visible = _open
	if _backdrop != null:
		_backdrop.visible = _open
	if _open:
		_refresh()


func is_open() -> bool:
	return _open


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if KEY_1 <= k and k <= KEY_6:
			_filter_phase = k - KEY_1
			_filter_spot = -1
			_refresh()
			return true
		if KEY_7 <= k and k <= KEY_9:
			_filter_spot = k - KEY_7
			_filter_phase = -1
			_refresh()
			return true
		if k == KEY_0:
			_filter_phase = -1
			_filter_spot = -1
			_refresh()
			return true
	return false


func _refresh() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	var phase_txt: String = str(PHASE_NAMES[_filter_phase]) if _filter_phase >= 0 else "全部时段"
	var spot_txt: String = str(SPOT_NAMES[_filter_spot]) if _filter_spot >= 0 else "全部钓点"
	_filter_label.text = "筛选：%s · %s" % [phase_txt, spot_txt]
	var caught_n := 0

	for f in GameData.fish_defs:
		if _filter_phase >= 0 and not f.phases.has(PHASES[_filter_phase]):
			continue
		if _filter_spot >= 0 and not f.spots.has(SPOTS[_filter_spot]):
			continue
		var card := _make_card(f)
		_grid.add_child(card)
		if SaveManager.is_caught(f.id):
			caught_n += 1

	_title.text = "鱼谱 · %d / %d 已捕获" % [caught_n, GameData.fish_defs.size()]


func _make_card(f: FishDef) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var caught := SaveManager.is_caught(f.id)
	var seen := SaveManager.is_seen(f.id)
	var c := ThemeManager.palette()
	if caught:
		sb.bg_color = Color(c["panel_alt"].r, c["panel_alt"].g, c["panel_alt"].b, 0.9)
		sb.border_color = c["accent"]
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(c["panel"].r, c["panel"].g, c["panel"].b, 0.8)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(188, 152)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.name = "VBoxContainer"
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	# 鱼种图标：优先用 fish.json 指向的插画，缺失时用符号占位（渐进增强）
	var icon_node: Control = null
	if (caught or seen) and f.icon != "" and ResourceLoader.exists(f.icon):
		var tex := TextureRect.new()
		tex.texture = load(f.icon) as Texture2D
		# 关键：不设 EXPAND_IGNORE_SIZE 时，TextureRect 最小尺寸 = 贴图尺寸（512px 会把卡片撑爆）
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(74, 74)
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_node = tex
	else:
		var ph := Label.new()
		ph.text = "？" if not (caught or seen) else "🐟"
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.custom_minimum_size = Vector2(74, 60)
		ph.add_theme_font_size_override("font_size", 26)
		ph.add_theme_color_override("font_color", c["text_muted"])
		icon_node = ph
	vb.add_child(icon_node)
	var name_l := Label.new()
	name_l.text = f.fish_name if (caught or seen) else "？？？"
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", c["accent"] if caught else c["text_muted"])
	vb.add_child(name_l)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", c["text"])
	if caught:
		var best := SaveManager.get_record(f.id)
		var stars := "★".repeat(maxi(f.rarity, 1)) if f.rarity > 0 else "事件"
		info.text = "最佳 %.0f cm · %s" % [best, stars]
	elif seen:
		info.text = "见过 · 未上岸"
	else:
		info.text = "未发现"
	vb.add_child(info)

	var meta := Label.new()
	meta.add_theme_font_size_override("font_size", 10)
	meta.add_theme_color_override("font_color", c["text_muted"])
	var spots: Array[String] = []
	for s in f.spots:
		var idx := SPOTS.find(s)
		spots.append(str(SPOT_NAMES[idx]) if idx >= 0 else str(s))
	meta.text = " · ".join(spots)
	vb.add_child(meta)
	return card
