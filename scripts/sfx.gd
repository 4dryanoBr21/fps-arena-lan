extends Node
## Autoload "Sfx": efeitos sonoros sintetizados em código na inicialização
## (sem arquivos de áudio). play() toca em 2D; play_at() toca posicional em 3D.

const MIX_RATE: int = 44100
const PEAK: float = 0.9

var _streams: Dictionary = {}
var _noise := RandomNumberGenerator.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Semente fixa: o "mesmo" ruído em toda execução e em todo peer.
	_noise.seed = 1337
	_streams[&"shot"] = _to_stream(_synth_shot())
	_streams[&"impact"] = _to_stream(_synth_impact())
	_streams[&"hitmarker"] = _to_stream(_synth_hitmarker())
	_streams[&"kill"] = _to_stream(_synth_kill())
	_streams[&"target_hit"] = _to_stream(_synth_target_hit())
	_streams[&"hurt"] = _to_stream(_synth_hurt())
	_streams[&"death"] = _to_stream(_synth_death())
	_streams[&"respawn"] = _to_stream(_synth_respawn())


func play(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	add_child(player)
	player.play()
	_free_when_done(player, player.stream, player.pitch_scale)


func play_at(sound: StringName, position: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.unit_size = 6.0
	player.max_distance = 70.0
	scene.add_child(player)
	player.global_position = position
	player.play()
	_free_when_done(player, player.stream, player.pitch_scale)


## Timer em vez do sinal finished: libera o nó mesmo sem driver de áudio (headless).
func _free_when_done(player: Node, stream: AudioStream, pitch: float) -> void:
	get_tree().create_timer(stream.get_length() / pitch + 0.1).timeout.connect(player.queue_free)


func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := PEAK / peak if peak > 0.0 else 1.0

	# Fade-out curtinho no fim para não estalar.
	var fade := mini(int(0.005 * MIX_RATE), samples.size())
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := samples[i] * gain
		var from_end := samples.size() - 1 - i
		if from_end < fade:
			value *= float(from_end) / fade
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * MIX_RATE))
	return out


## Estalo de ruído com filtro fechando + "soco" grave descendo de tom.
func _synth_shot() -> PackedFloat32Array:
	var out := _buffer(0.32)
	var lowpass := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var noise := _noise.randf_range(-1.0, 1.0)
		lowpass += (noise - lowpass) * lerpf(0.9, 0.08, minf(t / 0.12, 1.0))
		phase += TAU * lerpf(150.0, 45.0, minf(t / 0.15, 1.0)) / MIX_RATE
		var crack := lowpass * exp(-t / 0.045)
		var thump := sin(phase) * exp(-t / 0.07)
		var click := noise * exp(-t / 0.004)
		out[i] = crack * 0.9 + thump * 0.8 + click * 0.5
	return out


## Bala batendo numa superfície.
func _synth_impact() -> PackedFloat32Array:
	var out := _buffer(0.12)
	var lowpass := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		lowpass += (_noise.randf_range(-1.0, 1.0) - lowpass) * 0.25
		out[i] = lowpass * exp(-t / 0.025) + sin(TAU * 90.0 * t) * exp(-t / 0.03) * 0.5
	return out


## "Tic" agudo de acerto confirmado.
func _synth_hitmarker() -> PackedFloat32Array:
	var out := _buffer(0.07)
	for i in out.size():
		var t := float(i) / MIX_RATE
		var attack := minf(t / 0.001, 1.0)
		out[i] = (sin(TAU * 1900.0 * t) + 0.5 * sin(TAU * 3100.0 * t)) * exp(-t / 0.012) * attack
	return out


## Duas notas subindo: confirmação de abate.
func _synth_kill() -> PackedFloat32Array:
	var out := _buffer(0.32)
	for i in out.size():
		var t := float(i) / MIX_RATE
		var value := _bell_note(t, 0.0, 988.0, 0.07)
		value += _bell_note(t, 0.09, 1480.0, 0.09)
		out[i] = value
	return out


func _bell_note(t: float, start: float, freq: float, decay: float) -> float:
	if t < start:
		return 0.0
	var dt := t - start
	var attack := minf(dt / 0.002, 1.0)
	return (sin(TAU * freq * dt) + 0.3 * sin(TAU * freq * 2.0 * dt)) * exp(-dt / decay) * attack


## "Ding" metálico com parciais inarmônicas (alvo derrubado).
func _synth_target_hit() -> PackedFloat32Array:
	var out := _buffer(0.7)
	var partials := [Vector3(1200.0, 1.0, 0.25), Vector3(2950.0, 0.5, 0.15), Vector3(5100.0, 0.3, 0.08)]
	for i in out.size():
		var t := float(i) / MIX_RATE
		var value := 0.0
		for p: Vector3 in partials:
			value += sin(TAU * p.x * t) * p.y * exp(-t / p.z)
		out[i] = value * minf(t / 0.001, 1.0)
	return out


## Pancada surda para quem leva o tiro.
func _synth_hurt() -> PackedFloat32Array:
	var out := _buffer(0.25)
	var lowpass := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		phase += TAU * lerpf(200.0, 70.0, minf(t / 0.2, 1.0)) / MIX_RATE
		lowpass += (_noise.randf_range(-1.0, 1.0) - lowpass) * 0.15
		out[i] = sin(phase) * exp(-t / 0.09) + lowpass * exp(-t / 0.03) * 0.6
	return out


## Tom áspero descendo: jogador eliminado.
func _synth_death() -> PackedFloat32Array:
	var out := _buffer(0.7)
	var phase := 0.0
	var lowpass := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		phase += TAU * lerpf(420.0, 70.0, minf(t / 0.6, 1.0)) / MIX_RATE
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		lowpass += (saw - lowpass) * 0.12
		out[i] = lowpass * exp(-t / 0.3)
	return out


## Arpejo curto subindo: de volta ao jogo.
func _synth_respawn() -> PackedFloat32Array:
	var out := _buffer(0.4)
	var notes := [523.25, 659.25, 783.99]
	for i in out.size():
		var t := float(i) / MIX_RATE
		var value := 0.0
		for n in notes.size():
			value += _bell_note(t, n * 0.08, notes[n], 0.12) * 0.6
		out[i] = value
	return out
