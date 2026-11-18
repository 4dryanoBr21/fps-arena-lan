extends SceneTree
## Gera os efeitos sonoros do jogo em assets/sfx/*.wav (sintetizados, sem
## arquivos de terceiros). Rode de novo só se mudar algum som:
##   godot --headless --path . --script res://tools/generate_sfx.gd

const MIX_RATE: int = 44100
const PEAK: float = 0.9
const OUT_DIR: String = "res://assets/sfx"

var _noise := RandomNumberGenerator.new()


## Tiros: um timbre por arma (pesos de cada camada do som) e VARIANTS
## variações de cada, sorteadas pelo Sfx a cada disparo.
## crack = estalo de ruído; filter = abertura do filtro (início -> fim);
## thump = "soco" grave (Hz início -> fim, decaimento, ganho); tail = cauda
## abafada; ring = toque metálico; echo = (atraso, ganho); peak = volume.
const VARIANTS: int = 3
const GUNSHOTS := {
	"shot_pistol": {"length": 0.3, "crack": Vector2(0.03, 0.9), "filter": Vector2(0.95, 0.12),
		"thump": [190.0, 70.0, 0.045, 0.7], "tail": Vector3(0.08, 0.3, 0.2), "peak": 0.78},
	"shot_revolver": {"length": 0.75, "crack": Vector2(0.05, 1.0), "filter": Vector2(0.9, 0.06),
		"thump": [130.0, 40.0, 0.1, 0.95], "tail": Vector3(0.2, 0.45, 0.1), "ring": Vector3(2300.0, 0.12, 0.15),
		"echo": Vector2(0.14, 0.2), "peak": 0.92},
	"shot_smg": {"length": 0.17, "crack": Vector2(0.018, 0.9), "filter": Vector2(0.98, 0.2),
		"thump": [220.0, 100.0, 0.025, 0.5], "tail": Vector3(0.05, 0.2, 0.25), "peak": 0.68},
	"shot_rifle": {"length": 0.55, "crack": Vector2(0.045, 0.9), "filter": Vector2(0.9, 0.08),
		"thump": [150.0, 45.0, 0.07, 0.8], "tail": Vector3(0.18, 0.4, 0.12), "echo": Vector2(0.18, 0.15), "peak": 0.85},
	"shot_assault": {"length": 0.42, "crack": Vector2(0.035, 0.9), "filter": Vector2(0.92, 0.1),
		"thump": [140.0, 50.0, 0.06, 0.85], "tail": Vector3(0.12, 0.35, 0.14), "peak": 0.8},
	"shot_shotgun": {"length": 0.75, "crack": Vector2(0.09, 1.0), "filter": Vector2(0.7, 0.04),
		"thump": [110.0, 35.0, 0.12, 0.9], "tail": Vector3(0.25, 0.5, 0.08), "echo": Vector2(0.2, 0.2), "peak": 0.95},
	"shot_sniper": {"length": 1.5, "crack": Vector2(0.06, 1.0), "filter": Vector2(0.85, 0.05),
		"thump": [90.0, 28.0, 0.15, 1.0], "tail": Vector3(0.5, 0.6, 0.06), "echo": Vector2(0.28, 0.3), "peak": 0.95},
}


func _initialize() -> void:
	var sounds := {
		"impact": _synth_impact,
		"hitmarker": _synth_hitmarker,
		"kill": _synth_kill,
		"target_hit": _synth_target_hit,
		"hurt": _synth_hurt,
		"death": _synth_death,
		"respawn": _synth_respawn,
		"reload": _synth_reload,
		"empty": _synth_empty,
		"purchase": _synth_purchase,
		"level_up": _synth_level_up,
		"equip": _synth_equip,
		"knife_hit": _synth_knife_hit,
		"knife_wall": _synth_knife_wall,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for sound: String in sounds:
		# Semente pelo nome: cada som sai sempre igual, sem depender da ordem.
		_noise.seed = hash(sound)
		_save(sound, sounds[sound].call(), PEAK)
	# Golpe da faca: "vush" com variações, como os tiros.
	for variant in VARIANTS:
		var swing := "knife_swing_%d" % (variant + 1)
		_noise.seed = hash(swing)
		_save(swing, _synth_swing(), 0.7)
	for shot: String in GUNSHOTS:
		for variant in VARIANTS:
			var sound := "%s_%d" % [shot, variant + 1]
			_noise.seed = hash(sound)
			_save(sound, _gunshot(GUNSHOTS[shot]), GUNSHOTS[shot]["peak"])
	quit()


func _save(sound: String, samples: PackedFloat32Array, peak: float) -> void:
	var path := "%s/%s.wav" % [OUT_DIR, sound]
	var err := _to_stream(samples, peak).save_to_wav(ProjectSettings.globalize_path(path))
	print("%s -> %s" % [path, "ok" if err == OK else "erro %d" % err])


func _to_stream(samples: PackedFloat32Array, target_peak: float) -> AudioStreamWAV:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := target_peak / peak if peak > 0.0 else 1.0

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


## Tiro genérico, montado pelas camadas de GUNSHOTS. Cada variação mexe
## até 8% nos tempos e tons, além do ruído diferente.
func _gunshot(spec: Dictionary) -> PackedFloat32Array:
	var jitter := func(value: float) -> float: return value * _noise.randf_range(0.92, 1.08)
	var out := _buffer(spec["length"])
	var crack: Vector2 = spec["crack"]
	var crack_decay: float = jitter.call(crack.x)
	var filter: Vector2 = spec["filter"]
	var thump: Array = spec["thump"]
	var thump_from: float = jitter.call(thump[0])
	var thump_to: float = jitter.call(thump[1])
	var thump_decay: float = jitter.call(thump[2])
	var tail: Vector3 = spec.get("tail", Vector3.ZERO)
	var tail_decay: float = jitter.call(maxf(tail.x, 0.001))
	var ring: Vector3 = spec.get("ring", Vector3.ZERO)
	var ring_freq: float = jitter.call(maxf(ring.x, 1.0))
	var lowpass := 0.0
	var tail_lowpass := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var noise := _noise.randf_range(-1.0, 1.0)
		lowpass += (noise - lowpass) * lerpf(filter.x, filter.y, minf(t / 0.12, 1.0))
		tail_lowpass += (noise - tail_lowpass) * tail.z
		phase += TAU * lerpf(thump_from, thump_to, minf(t / (thump_decay * 2.0), 1.0)) / MIX_RATE
		var value := lowpass * exp(-t / crack_decay) * crack.y
		value += sin(phase) * exp(-t / thump_decay) * float(thump[3])
		value += noise * exp(-t / 0.004) * 0.5
		value += tail_lowpass * exp(-t / tail_decay) * minf(t / 0.02, 1.0) * tail.y
		if ring.z > 0.0:
			value += sin(TAU * ring_freq * t) * exp(-t / ring.y) * ring.z
		out[i] = value
	if spec.has("echo"):
		# Eco simples: uma cópia atrasada e mais baixa (como a parede devolvendo).
		var echo: Vector2 = spec["echo"]
		var delay := int(jitter.call(echo.x) * MIX_RATE)
		for i in range(out.size() - 1, delay - 1, -1):
			out[i] += out[i - delay] * echo.y
	return out


## Dois cliques curtos e abafados: arma sacada.
func _synth_equip() -> PackedFloat32Array:
	var out := _buffer(0.22)
	var lowpass := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		lowpass += (_noise.randf_range(-1.0, 1.0) - lowpass) * 0.35
		var value := 0.0
		for start: float in [0.0, 0.11]:
			if t >= start:
				var dt := t - start
				value += (lowpass * 0.8 + sin(TAU * 1600.0 * dt) * 0.4) * exp(-dt / 0.01)
		out[i] = value
	return out


## "Vush": ruído com filtro que abre e fecha (a lâmina cortando o ar).
func _synth_swing() -> PackedFloat32Array:
	var length := _noise.randf_range(0.2, 0.26)
	var peak_at := length * _noise.randf_range(0.4, 0.55)
	var out := _buffer(length)
	var lowpass := 0.0
	var bandpass := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var envelope := sin(PI * clampf(t / length, 0.0, 1.0))
		envelope *= envelope
		# Filtro mais aberto no meio do golpe (mais rápido = mais agudo).
		var opening := 0.04 + 0.22 * exp(-pow((t - peak_at) / (length * 0.25), 2.0))
		lowpass += (_noise.randf_range(-1.0, 1.0) - lowpass) * opening
		bandpass += (lowpass - bandpass) * 0.5
		out[i] = (lowpass - bandpass * 0.6) * envelope
	return out


## Faca acertando alguém: pancada surda e curta.
func _synth_knife_hit() -> PackedFloat32Array:
	var out := _buffer(0.25)
	var lowpass := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		lowpass += (_noise.randf_range(-1.0, 1.0) - lowpass) * 0.12
		phase += TAU * lerpf(160.0, 60.0, minf(t / 0.12, 1.0)) / MIX_RATE
		out[i] = sin(phase) * exp(-t / 0.06) + lowpass * exp(-t / 0.04) * 1.2
	return out


## Faca batendo em parede: "tlin" metálico com raspada.
func _synth_knife_wall() -> PackedFloat32Array:
	var out := _buffer(0.4)
	var partials := [Vector3(2600.0, 0.6, 0.09), Vector3(4100.0, 0.35, 0.05), Vector3(6300.0, 0.2, 0.03)]
	for i in out.size():
		var t := float(i) / MIX_RATE
		var value := _noise.randf_range(-1.0, 1.0) * exp(-t / 0.012) * 0.8
		for p: Vector3 in partials:
			value += sin(TAU * p.x * t) * p.y * exp(-t / p.z)
		out[i] = value
	return out

