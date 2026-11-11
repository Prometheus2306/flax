extends Node
## Tiny procedural sound bank. Every effect is synthesized at startup, so the project
## needs no audio assets.

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
	_bank["catch"] = _synth([[520.0, 780.0, 0.07]], "sine", 0.55)
	_bank["drop"] = _synth([[210.0, 70.0, 0.11]], "sine", 0.85)
	_bank["flip"] = _synth([[260.0, 760.0, 0.10]], "tri", 0.5)
	_bank["clear"] = _synth([[523.0, 523.0, 0.07], [659.0, 659.0, 0.07], [784.0, 784.0, 0.07], [1047.0, 1047.0, 0.16]], "square", 0.3)
	_bank["miss"] = _synth([[230.0, 110.0, 0.12], [110.0, 60.0, 0.20]], "saw", 0.45)
	_bank["wave"] = _synth([[523.0, 523.0, 0.09], [659.0, 659.0, 0.09], [784.0, 784.0, 0.09], [1047.0, 1047.0, 0.09], [784.0, 784.0, 0.07], [1047.0, 1047.0, 0.28]], "tri", 0.6)
	_bank["over"] = _synth([[392.0, 392.0, 0.18], [330.0, 330.0, 0.18], [262.0, 262.0, 0.18], [196.0, 160.0, 0.55]], "saw", 0.4)
	_bank["ui"] = _synth([[640.0, 900.0, 0.06]], "sine", 0.5)
	_bank["tick"] = _synth([[900.0, 900.0, 0.02]], "sine", 0.25)


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
				"square":
					v = 0.6 if cycle < 0.5 else -0.6
				"saw":
					v = (cycle * 2.0 - 1.0) * 0.7
				"tri":
					v = absf(cycle * 4.0 - 2.0) - 1.0
				_:
					v = randf() * 2.0 - 1.0
			# Fast attack to avoid clicks, then a decay inside each segment.
			var env := minf(1.0, float(k) / 60.0) * (1.0 - 0.8 * t)
			data.encode_s16(index * 2, int(clampf(v * env * volume, -1.0, 1.0) * 32767.0))
			index += 1
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
