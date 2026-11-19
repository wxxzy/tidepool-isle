class_name UiMeter
extends Control
## 圆角进度条 —— 用 StyleBoxFlat 画圆角轨道与填充（ColorRect 无法圆角）
## 用于今日目标进度 / 蓄力 / 线张力

var ratio: float = 0.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()

var fill_color: Color = Color(0.373, 0.749, 0.561):
	set(v):
		fill_color = v
		queue_redraw()

var track_color: Color = Color(0.0, 0.0, 0.0, 0.38)
var corner: int = 4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(120, 8)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = track_color
	sb.set_corner_radius_all(corner)
	sb.anti_aliasing = true
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if ratio <= 0.001:
		return
	# 最小宽度保证极小进度也可见（避免"看起来坏了"）
	var w := clampf(size.x * ratio, float(corner * 2), size.x)
	var f := StyleBoxFlat.new()
	f.bg_color = fill_color
	f.set_corner_radius_all(corner)
	f.anti_aliasing = true
	draw_style_box(f, Rect2(Vector2.ZERO, Vector2(w, size.y)))
