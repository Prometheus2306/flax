extends Node
## Tiny procedural sound bank. Every effect is synthesized at startup, so the project
## needs no audio assets.
## Flax hit / clear sounds use warm, relaxed marimba-chime harmonics instead of harsh
## square waves or white noise.

const RATE := 22050

var enabled := true
var _players: Array = []
var _bank := {}
var _next := 0


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Movement & action sounds (kept crisp and responsive)
	_bank["catch"] = _synth([[520.0, 780.0, 0.07]], "sine", 0.55)
	_bank["drop"] = _synth([[210.0, 70.0, 0.11]], "sine", 0.85)
	_bank["flip"] = _synth([[260.0, 760.0, 0.10]], "tri", 0.5)
	_bank["tick"] = _synth([[900.0, 900.0, 0.02]], "sine", 0.25)
	_bank["ui"] = _synth([[640.0, 900.0, 0.06]], "sine", 0.5)

	# Relaxed, warm marimba/kalimba chime when a Flax combination is hit
	_bank["clear"] = _synth([
		[392.00, 392.00, 0.085],
		[493.88, 493.88, 0.085],
		[587.33, 587.33, 0.100],
		[783.99, 783.99, 0.260],
	], "chime", 0.26)
	# Soft, warm low-register bass cushion instead of harsh static noise
	_bank["boom"] = _synth([
		[246.94, 196.00, 0.14],
		[196.00, 146.83, 0.22],
	], "warm", 0.18)
	# Gentle, musical wave-clear fanfare
	_bank["wave"] = _synth([
		[392.00, 392.00, 0.09],
		[493.88, 493.88, 0.09],
		[587.33, 587.33, 0.09],
		[783.99, 783.99, 0.11],
		[659.25, 659.25, 0.08],
		[783.99, 783.99, 0.30],
	], "chime", 0.34)
	_bank["miss"] = _synth([[230.0, 140.0, 0.12], [140.0, 95.0, 0.18]], "tri", 0.35)
	_bank["over"] = _synth([[392.0, 392.0, 0.18], [330.0, 330.0, 0.18], [262.0, 262.0, 0.18], [196.0, 174.6, 0.50]], "warm", 0.32)
	_bank["slowy"] = _synth([[523.25, 587.33, 0.08], [659.25, 783.99, 0.09], [1046.50, 783.99, 0.12], [659.25, 523.25, 0.24]], "chime", 0.30)


func play(sound: String, pitch: float = 1.0) -> void:
	if not enabled or not _bank.has(sound) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _bank[sound]
	p.pitch_scale = pitch
	p.play()


## Builds a mono 16-bit sample from [start_hz, end_hz, seconds] segments.
func _synth(segments: Array, wave: String, volume: float) -> AudioStreamWAV:
	var total := 0
	for s in segments:
		total += int(s[2] * RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	var index := 0
	var phase := 0.0
	for s in segments:
		var n := int(s[2] * RATE)
		for k in n:
			var t := float(k) / float(n)
			var freq: float = lerpf(s[0], s[1], t)
			phase += freq / float(RATE)
			var cycle := fmod(phase, 1.0)
			var v := 0.0
			match wave:
				"sine":
					v = sin(TAU * phase)
				"chime":
					# Warm marimba / kalimba tone: fundamental sine + soft octave & fifth overtones
					var overtone_decay := 1.0 - t * 0.75
					v = sin(TAU * phase) * 0.78 + sin(TAU * phase * 2.0) * 0.17 * overtone_decay + sin(TAU * phase * 3.0) * 0.05 * overtone_decay
				"warm":
					# Soft rounded sub-warmth with gentle second harmonic
					v = sin(TAU * phase) * 0.85 + sin(TAU * phase * 2.0) * 0.15 * (1.0 - t)
				"square":
					v = 0.6 if cycle < 0.5 else -0.6
				"saw":
					v = (cycle * 2.0 - 1.0) * 0.7
				"tri":
					v = absf(cycle * 4.0 - 2.0) - 1.0
				"noise":
					v = sin(TAU * phase) * 0.65 + (randf() * 2.0 - 1.0) * 0.55
				_:
					v = randf() * 2.0 - 1.0
			var env := 0.0
			if wave == "chime" or wave == "warm":
				# Soft rounded attack and smooth, relaxed bell decay (no clicks or harsh edges)
				var attack := minf(1.0, float(k) / 140.0)
				var release := minf(1.0, float(n - k) / 180.0)
				env = attack * release * pow(1.0 - 0.78 * t, 1.35)
			else:
				# Fast attack for crisp movement/UI feedback
				env = minf(1.0, float(k) / 60.0) * (1.0 - 0.8 * t)
			data.encode_s16(index * 2, int(clampf(v * env * volume, -1.0, 1.0) * 32767.0))
			index += 1
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
