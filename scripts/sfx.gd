extends Node
## Autoload "Sfx": toca os efeitos de assets/sfx/ (gerados por
## tools/generate_sfx.gd). play() toca em 2D; play_at() toca posicional em 3D.
## Os players vêm de pools fixos: nenhum nó é criado durante o jogo.
## Os tiros têm VARIANTS variações por arma (shot_<arma>_1..3); cada disparo
## sorteia uma diferente da anterior, para a rajada não soar repetida.

const IMPACT := &"impact"
const HITMARKER := &"hitmarker"
const KILL := &"kill"
const TARGET_HIT := &"target_hit"
const HURT := &"hurt"
const DEATH := &"death"
const RESPAWN := &"respawn"
const RELOAD := &"reload"
const EMPTY := &"empty"
const PURCHASE := &"purchase"
const LEVEL_UP := &"level_up"
const EQUIP := &"equip"
const KNIFE_HIT := &"knife_hit"
const KNIFE_WALL := &"knife_wall"
const ALL: Array[StringName] = [IMPACT, HITMARKER, KILL, TARGET_HIT, HURT, DEATH, RESPAWN, RELOAD, EMPTY, PURCHASE, LEVEL_UP, EQUIP, KNIFE_HIT, KNIFE_WALL]
const VARIANTS: int = 3
const RULES: GameRules = preload("res://data/game_rules.tres")

const POOL_2D: int = 8
const POOL_3D: int = 24

var _streams: Dictionary = {}
## som -> [variações]; som -> índice da última tocada.
var _variants: Dictionary = {}
var _last_variant: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for sound in ALL:
		_streams[sound] = load("res://assets/sfx/%s.wav" % sound)
	for weapon in RULES.weapons:
		if _variants.has(weapon.sound):
			continue
		var streams: Array[AudioStream] = []
		for i in VARIANTS:
			streams.append(load("res://assets/sfx/%s_%d.wav" % [weapon.sound, i + 1]))
		_variants[weapon.sound] = streams
	for i in POOL_2D:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players_2d.append(player)
	for i in POOL_3D:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 6.0
		player.max_distance = 70.0
		add_child(player)
		_players_3d.append(player)


## `pitch` muda o tom base (cada arma soa diferente com o mesmo arquivo).
func play(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.0, pitch: float = 1.0) -> void:
	var index := _free_index(_players_2d, _next_2d)
	_next_2d = (index + 1) % _players_2d.size()
	_start(_players_2d[index], sound, volume_db, pitch_jitter, pitch)


func play_at(sound: StringName, position: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.0, pitch: float = 1.0) -> void:
	var index := _free_index(_players_3d, _next_3d)
	_next_3d = (index + 1) % _players_3d.size()
	var player := _players_3d[index]
	player.global_position = position
	_start(player, sound, volume_db, pitch_jitter, pitch)


func _start(player: Node, sound: StringName, volume_db: float, pitch_jitter: float, pitch: float) -> void:
	player.set("stream", _stream_for(sound))
	player.set("volume_db", volume_db)
	player.set("pitch_scale", pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)))
	player.call("play")


## Tiro: uma variação diferente da última; os outros sons têm um arquivo só.
func _stream_for(sound: StringName) -> AudioStream:
	if not _variants.has(sound):
		return _streams[sound]
	var streams: Array = _variants[sound]
	var index := _rng.randi() % streams.size()
	if streams.size() > 1 and index == int(_last_variant.get(sound, -1)):
		index = (index + 1) % streams.size()
	_last_variant[sound] = index
	return streams[index]


## Primeiro player livre a partir de `start`; se todos estiverem tocando,
## reaproveita o de `start` (o mais antigo, na ordem circular).
func _free_index(pool: Array, start: int) -> int:
	for offset in pool.size():
		var index := (start + offset) % pool.size()
		if not pool[index].playing:
			return index
	return start
