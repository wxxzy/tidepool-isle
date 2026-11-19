class_name WaterMath
extends RefCounted
## 水面波动数学 —— 着色器与浮漂共用同一公式（保持视觉同步）

const AMP_A := 0.12
const AMP_B := 0.09


static func wave_height(x: float, z: float, t: float) -> float:
	return AMP_A * sin(x * 0.5 + t * 1.2) + AMP_B * sin(z * 0.7 + t * 0.9)


static func sea_level(t: float, x: float, z: float) -> float:
	return wave_height(x, z, t)
