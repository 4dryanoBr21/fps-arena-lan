extends Node
## Autoload "Sfx": toca os efeitos de assets/sfx/ (gerados por
## tools/generate_sfx.gd). play() toca em 2D; play_at() toca posicional em 3D.
## Os players vêm de pools fixos: nenhum nó é criado durante o jogo.

const SHOT := &"shot"
const SHOTGUN := &"shotgun"
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
const ALL: Array[StringName] = [SHOT, SHOTGUN, IMPACT, HITMARKER, KILL, TARGET_HIT, HURT, DEATH, RESPAWN, RELOAD, EMPTY, PURCHASE, LEVEL_UP]

const POOL_2D: int = 8
const POOL_3D: int = 24

var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for sound in ALL:
		_streams[sound] = load("res://assets/sfx/%s.wav" % sound)
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
	player.set("stream", _streams[sound])
	player.set("volume_db", volume_db)
	player.set("pitch_scale", pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)))
	player.call("play")


## Primeiro player livre a partir de `start`; se todos estiverem tocando,
## reaproveita o de `start` (o mais antigo, na ordem circular).
func _free_index(pool: Array, start: int) -> int:
	for offset in pool.size():
		var index := (start + offset) % pool.size()
		if not pool[index].playing:
			return index
	return start
