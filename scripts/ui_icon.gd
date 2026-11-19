class_name IconGlyph
extends Control
## 自绘图标 —— 不依赖字体字形（默认字体没有 ☀/☾/鱼 等符号，会渲染成小圆点）
## 支持：sun / moon / fish / bait / star / drop

enum Kind { SUN, MOON, FISH, BAIT, STAR, DROP }

var kind: Kind = Kind.SUN:
	set(v):
		kind = v
		queue_redraw()

var tint: Color = Color.WHITE:
	set(v):
		tint = v
		queue_redraw()


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(18, 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		s = 18.0
	var c := Vector2(size.x, size.y) * 0.5
	var r := s * 0.5
	match kind:
		Kind.SUN:
			_draw_sun(c, r)
		Kind.MOON:
			_draw_moon(c, r)
		Kind.FISH:
			_draw_fish(c, r)
		Kind.BAIT:
			_draw_bait(c, r)
		Kind.STAR:
			_draw_star(c, r)
		Kind.DROP:
			_draw_drop(c, r)


func _draw_sun(c: Vector2, r: float) -> void:
	draw_circle(c, r * 0.52, tint, true, -1.0, true)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.72, c + d * r * 0.98, tint, maxf(r * 0.14, 1.0), true)


## 粗弧线画月牙：比两圆相减更稳（不受面板半透明合成影响）
func _draw_moon(c: Vector2, r: float) -> void:
	draw_arc(c, r * 0.62, deg_to_rad(42.0), deg_to_rad(318.0), 28, tint,
		maxf(r * 0.5, 1.5), true)


func _draw_fish(c: Vector2, r: float) -> void:
	var body := PackedVector2Array()
	var bc := c - Vector2(r * 0.16, 0.0)
	var rx := r * 0.68
	var ry := r * 0.36
	for i in 20:
		var a := TAU * float(i) / 20.0
		body.append(bc + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(body, tint)
	var tail := PackedVector2Array([
		Vector2(bc.x + rx * 0.82, c.y),
		Vector2(c.x + r * 0.98, c.y - r * 0.42),
		Vector2(c.x + r * 0.98, c.y + r * 0.42),
	])
	draw_colored_polygon(tail, tint)
	# 背鳍
	var fin := PackedVector2Array([
		Vector2(bc.x - rx * 0.1, c.y - ry * 0.85),
		Vector2(bc.x + rx * 0.35, c.y - ry * 0.7),
		Vector2(bc.x + rx * 0.2, c.y - ry * 1.35),
	])
	draw_colored_polygon(fin, tint)


func _draw_bait(c: Vector2, r: float) -> void:
	# 绕线轮：圆环 + 摇柄
	draw_arc(c - Vector2(0.0, r * 0.08), r * 0.52, 0.0, TAU, 28, tint,
		maxf(r * 0.2, 1.4), true)
	draw_line(c + Vector2(r * 0.5, -r * 0.1), c + Vector2(r * 0.92, r * 0.16), tint,
		maxf(r * 0.16, 1.2), true)
	draw_circle(c + Vector2(r * 0.92, r * 0.16), maxf(r * 0.11, 1.0), tint, true, -1.0, true)


func _draw_star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		var rad := r * (0.98 if i % 2 == 0 else 0.44)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, tint)


func _draw_drop(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var top := c - Vector2(0.0, r * 0.86)
	pts.append(top)
	for i in 15:
		var a := deg_to_rad(-140.0 + 280.0 * float(i) / 14.0)
		pts.append(c + Vector2(r * 0.52, 0.0) + Vector2(cos(a), sin(a)) * r * 0.52)
	draw_colored_polygon(pts, tint)
