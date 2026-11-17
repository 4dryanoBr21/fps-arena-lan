extends SceneTree
## Gera os efeitos sonoros do jogo em assets/sfx/*.wav (sintetizados, sem
## arquivos de terceiros). Rode de novo só se mudar algum som:
##   godot --headless --path . --script res://tools/generate_sfx.gd

const MIX_RATE: int = 44100
const PEAK: float = 0.9
const OUT_DIR: String = "res://assets/sfx"

var _noise := RandomNumberGenerator.new()


func _initialize() -> void:
	# Semente fixa: o mesmo ruído toda vez que gerar.
	_noise.seed = 1337
	var sounds := {
		"shot": _synth_shot(),
		"shotgun": _synth_shotgun(),
		"impact": _synth_impact(),
		"hitmarker": _synth_hitmarker(),
		"kill": _synth_kill(),
		"target_hit": _synth_target_hit(),
		"hurt": _synth_hurt(),
		"death": _synth_death(),
		"respawn": _synth_respawn(),
		"reload": _synth_reload(),
		"empty": _synth_empty(),
		# Os dois últimos não usam ruído: os sons de cima continuam idênticos.
		"purchase": _synth_purchase(),
		"level_up": _synth_level_up(),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for sound: String in sounds:
		var path := "%s/%s.wav" % [OUT_DIR, sound]
		var err := _to_stream(sounds[sound]).save_to_wav(ProjectSettings.globalize_path(path))
		print("%s -> %s" % [path, "ok" if err == OK else "erro %d" % err])
	quit()


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


## Estouro mais grave e longo que o do rifle.
func _synth_shotgun() -> PackedFloat32Array:
	var out := _buffer(0.5)
	var lowpass := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var noise := _noise.randf_range(-1.0, 1.0)
		lowpass += (noise - lowpass) * lerpf(0.7, 0.04, minf(t / 0.2, 1.0))
		phase += TAU * lerpf(110.0, 35.0, minf(t / 0.25, 1.0)) / MIX_RATE
		var blast := lowpass * exp(-t / 0.09)
		var thump := sin(phase) * exp(-t / 0.12)
		var click := noise * exp(-t / 0.006)
		out[i] = blast * 1.0 + thump * 0.9 + click * 0.5
	return out


## Dois estalos metálicos: pente saindo e entrando.
func _synth_reload() -> PackedFloat32Array:
	var out := _buffer(0.45)
	for i in out.size():
		var t := float(i) / MIX_RATE
		var value := 0.0
		for start: float in [0.0, 0.28]:
			if t >= start:
				var dt := t - start
				value += (sin(TAU * 2400.0 * dt) * 0.6 + _noise.randf_range(-1.0, 1.0) * 0.5) * exp(-dt / 0.012)
		out[i] = value
	return out


## "Clique" seco de arma vazia.
func _synth_empty() -> PackedFloat32Array:
	var out := _buffer(0.06)
	for i in out.size():
		var t := float(i) / MIX_RATE
		out[i] = (sin(TAU * 3200.0 * t) + _noise.randf_range(-1.0, 1.0) * 0.4) * exp(-t / 0.006)
	return out


## Duas moedinhas: compra no Arsenal.
func _synth_purchase() -> PackedFloat32Array:
	var out := _buffer(0.35)
	for i in out.size():
		var t := float(i) / MIX_RATE
		out[i] = _bell_note(t, 0.0, 1975.5, 0.05) + _bell_note(t, 0.07, 2637.0, 0.12)
	return out


## Fanfarra curta subindo uma oitava: subiu de nível.
func _synth_level_up() -> PackedFloat32Array:
	var out := _buffer(0.9)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in out.size():
		var t := float(i) / MIX_RATE
		var value := 0.0
		for n in notes.size():
			var decay := 0.35 if n == notes.size() - 1 else 0.1
			value += _bell_note(t, n * 0.1, notes[n], decay) * 0.6
		out[i] = value
	return out
