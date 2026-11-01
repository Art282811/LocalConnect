class_name Sound
extends Node
## Sound effects and a looping tune, synthesised in code at start-up so the
## game needs no audio files. Swap in recorded sounds later by replacing
## the streams in `_streams`.

const RATE := 16000
const VOICES := 6

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _next := 0
var _last_played := {}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	_streams["click"] = _wav(_tone(0.05, 880.0, 0.0, 0.5, 60.0))
	_streams["coin"] = _wav(_mix([_tone(0.12, 1320.0, 0.0, 0.35, 25.0), _delay(_tone(0.25, 1760.0, 0.0, 0.35, 12.0), 0.07)]))
	_streams["bell"] = _wav(_mix([_tone(1.4, 660.0, 0.0, 0.45, 3.0), _tone(1.4, 990.0, 0.0, 0.2, 4.0), _tone(1.4, 1650.0, 0.0, 0.12, 6.0)]))
	_streams["horn"] = _wav(_horn())
	_streams["clash"] = _wav(_mix([_noise(0.35, 0.5, 14.0), _tone(0.4, 2400.0, 0.0, 0.25, 10.0), _delay(_noise(0.2, 0.35, 18.0), 0.12)]))
	_streams["toll"] = _wav(_mix([_tone(2.2, 220.0, 0.0, 0.5, 1.6), _tone(2.2, 330.0, 0.0, 0.25, 2.2), _tone(2.2, 523.0, 0.0, 0.1, 3.0)]))
	_build_music.call_deferred()


func play(sound_name: String) -> void:
	if not Settings.sfx or not _streams.has(sound_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound_name, -10000)) < 120:
		return
	_last_played[sound_name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound_name]
	p.play()


func set_music(on: bool) -> void:
	if on and _music.stream != null and not _music.playing:
		_music.play()
	elif not on:
		_music.stop()


# --- Synthesis -----------------------------------------------------------------------------------

func _tone(seconds: float, freq: float, slide: float, amp: float, decay: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (freq + slide * t) / RATE
		var attack := minf(t * 200.0, 1.0)
		out[i] = sin(phase) * amp * attack * exp(-decay * t)
	return out


func _noise(seconds: float, amp: float, decay: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.5)
		out[i] = last * amp * exp(-decay * t)
	return out


func _horn() -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := 196.0 if t < 0.45 else 294.0
		phase += TAU * freq / RATE
		var env := minf(t * 12.0, 1.0) * (1.0 if t < 0.9 else maxf(1.0 - (t - 0.9) * 5.0, 0.0))
		# A brassy tone: fundamental plus odd and even harmonics.
		var v := sin(phase) * 0.5 + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.15 + sin(phase * 4.0) * 0.07
		out[i] = v * env * 0.6
	return out


func _delay(a: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	out.append_array(a)
	return out


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var arr: PackedFloat32Array = p
		for i in arr.size():
			out[i] += arr[i]
	return out


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


## A slow modal tune: a drone with plucked lute-like notes in D dorian.
func _build_music() -> void:
	var seconds := 16.0
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var drone_phase := 0.0
	var fifth_phase := 0.0
	for i in n:
		var t := float(i) / RATE
		drone_phase += TAU * 73.4 / RATE
		fifth_phase += TAU * 110.0 / RATE
		var swell := 0.75 + 0.25 * sin(TAU * t / seconds)
		out[i] = (sin(drone_phase) * 0.10 + sin(fifth_phase) * 0.06) * swell
	var scale := [293.7, 329.6, 349.2, 392.0, 440.0, 493.9, 523.3, 587.3]
	var melody := [0, 2, 4, 3, 2, 1, 0, -1, 2, 4, 5, 4, 3, 2, 1, 0, 4, 5, 7, 6, 4, 3, 2, -1, 0, 1, 2, 4, 3, 1, 0, -1]
	var step := seconds / melody.size()
	for k in melody.size():
		var note: int = melody[k]
		if note < 0:
			continue
		var freq: float = scale[note]
		var start := int(k * step * RATE)
		var length := int(step * 1.8 * RATE)
		var phase := 0.0
		for j in length:
			var idx := (start + j) % n
			var t := float(j) / RATE
			phase += TAU * freq / RATE
			var pluck := (sin(phase) + 0.4 * sin(phase * 2.0) + 0.15 * sin(phase * 3.0)) * exp(-4.5 * t)
			out[idx] += pluck * 0.12 * minf(t * 300.0, 1.0)
	_music.stream = _wav(out, true)
	if Settings.music:
		_music.play()
