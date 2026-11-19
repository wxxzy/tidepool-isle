class_name AudioSystem
extends Node
## 音频系统（P3）—— 三总线 + 程序生成环境床 + 关键音效
## 程序生成避免外部素材依赖：潮声 = 白噪声 + 低通 + 缓慢 LFO；
## 音效 = 短促正弦/噪声包络。BGM 用极简和弦循环（AudioStreamGenerator 太重，改用短 WAV 资源占位 + 提示）。
## 三套 BGM 以「时段标签 + 音量曲线」形式接入，实际素材可后补。

var _ambience: AudioStreamPlayer = null
var _sfx: AudioStreamPlayer = null
var _music: AudioStreamPlayer = null
var _ambience_stream: AudioStreamWAV = null
var _night_mode := false
var _current_bgm := ""


func _ready() -> void:
	_build_buses()
	_build_ambience()
	_apply_volumes()


func _build_buses() -> void:
	# AudioServer 总线（Master/Ambience/SFX/Music）
	_ensure_bus("Ambience")
	_ensure_bus("SFX")
	_ensure_bus("Music")


func _ensure_bus(name: String) -> void:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == name:
			return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")


func _build_ambience() -> void:
	# 生成 4 秒无缝潮声：白噪声经低通 + 两个慢速 LFO 调幅
	var duration := 4.0
	var rate := 22050
	var n := int(duration * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	var lowpass := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var white := rng.randf_range(-1.0, 1.0)
		lowpass = lerpf(lowpass, white, 0.035)  # 一阶低通 → 柔和"沙沙"
		var wave := 0.55 + 0.30 * sin(t * TAU / 2.0) + 0.15 * sin(t * TAU * 0.7 + 1.3)
		var val := clampf(lowpass * 2.2 * wave, -1.0, 1.0)
		var s := int(val * 24000.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n
	_ambience_stream = stream

	_ambience = AudioStreamPlayer.new()
	_ambience.stream = stream
	_ambience.bus = "Ambience"
	_ambience.volume_db = -14.0
	_ambience.autoplay = true
	add_child(_ambience)

	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.volume_db = -6.0
	add_child(_sfx)

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -12.0
	add_child(_music)


func _apply_volumes() -> void:
	var master := float(SaveManager.get_setting("master_volume", 1.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(clampf(master, 0.0, 1.0)))


# ================= 音效 =================

## 生成短促音效（frequency / duration / 噪声比例）
func _make_tone(freq: float, dur: float, noise_ratio := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 100.0) + n
	for i in n:
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(n)
		env = env * env
		var tone := sin(t * TAU * freq)
		var noise := rng.randf_range(-1.0, 1.0)
		var val := clampf(lerpf(tone, noise, noise_ratio) * env * 0.8, -1.0, 1.0)
		var s := int(val * 24000.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream


func play_sfx(kind: String) -> void:
	if _sfx == null:
		return
	var freq := 440.0
	var dur := 0.16
	var noise := 0.0
	match kind:
		"cast":      freq = 320.0; dur = 0.20; noise = 0.35   # 抛竿呼啸
		"splash":    freq = 180.0; dur = 0.28; noise = 0.7    # 入水
		"nibble":    freq = 880.0; dur = 0.08; noise = 0.0    # 浮漂轻点（木鱼）
		"bite":      freq = 140.0; dur = 0.30; noise = 0.2    # 沉漂
		"hook":      freq = 520.0; dur = 0.12; noise = 0.1    # 刺鱼
		"reel":      freq = 240.0; dur = 0.05; noise = 0.15   # 渔轮咔哒
		"snap":      freq = 90.0;  dur = 0.35; noise = 0.5    # 断线
		"catch":     freq = 660.0; dur = 0.35; noise = 0.0    # 出水
		"step_sand": freq = 200.0; dur = 0.07; noise = 0.6
		"step_wood": freq = 300.0; dur = 0.07; noise = 0.3
		"step_rock": freq = 380.0; dur = 0.06; noise = 0.4
		_: return
	_sfx.stream = _make_tone(freq, dur, noise)
	_sfx.play()


func set_reel_pitch(speed_factor: float) -> void:
	if _sfx != null and _sfx.playing:
		_sfx.pitch_scale = clampf(0.7 + speed_factor * 0.6, 0.7, 1.5)


# ================= 昼夜 / BGM =================

func set_phase(phase: String, night: bool) -> void:
	if night != _night_mode:
		_night_mode = night
		if _ambience != null:
			# 夜晚压低环境床并加一点低通感（用音量模拟）
			_ambience.volume_db = -18.0 if night else -14.0
	var target := "day"
	if phase in ["golden", "dusk"]:
		target = "golden"
	elif night:
		target = "night"
	if target != _current_bgm:
		_current_bgm = target
		# 实际 BGM 素材可后补；当前以环境音床承担时段氛围（无突兀静音）
		_music.volume_db = -18.0


func duck(amount_db := -6.0) -> void:
	if _ambience == null:
		return
	var tween := create_tween()
	tween.tween_property(_ambience, "volume_db", _ambience.volume_db + amount_db, 0.05)
	tween.tween_property(_ambience, "volume_db", _ambience.volume_db, 0.35).set_delay(0.4)


func unlock_audio() -> void:
	# Web 浏览器需用户手势解锁 AudioContext：在首次点击的同一帧调用
	if _ambience != null and not _ambience.playing:
		_ambience.play()
	_apply_volumes()
