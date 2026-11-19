extends Node
## ThemeManager —— Autoload：持有当前时段色板，向 UI 广播换肤（阶段1 全局换肤）
## 任何一个 UI 只需连接 theme_changed 并在回调里从 palette() 取色，即可统一换肤。

signal theme_changed(phase: String, colors: Dictionary)

var current_phase: String = "morning"


func _ready() -> void:
	# 从存档恢复昼长偏好等（换肤本身不需要持久化，时段由 DayNight 驱动）
	pass


func set_phase(phase: String) -> void:
	if phase == current_phase:
		return
	current_phase = phase
	var colors := Palette.colors_for(phase)
	theme_changed.emit(phase, colors)


func palette() -> Dictionary:
	return Palette.colors_for(current_phase)


func color(semantic: String) -> Color:
	return Palette.get_color(current_phase, semantic)
