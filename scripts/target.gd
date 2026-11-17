class_name ShootingTarget
extends AnimatableBody3D
## Alvo da arena. O servidor decide o acerto (no raycast do tiro), soma o
## ponto e controla o respawn.

const RULES: GameRules = preload("res://data/game_rules.tres")

## Eixo local do movimento lateral. Amplitude 0 = alvo estático.
@export var move_axis: Vector3 = Vector3.RIGHT
@export var move_amplitude: float = 0.0
@export var move_speed: float = 1.0

var active: bool = true

var _home: Vector3
var _phase: float

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: Node3D = $Visual


func _ready() -> void:
	_home = position
	# Fase derivada da posição: igual em todos os peers.
	_phase = position.x * 0.37 + position.z * 0.11
	set_physics_process(move_amplitude > 0.0)


func _physics_process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var offset := transform.basis * move_axis.normalized() * sin(t * move_speed + _phase) * move_amplitude
	position = _home + offset


## Só no servidor, chamado pela validação do tiro em FPSPlayer.
func server_hit(shooter_id: int) -> void:
	if not multiplayer.is_server() or not active:
		return
	active = false
	NetworkManager.add_score(shooter_id)
	NetworkManager.reward_target(shooter_id)
	NetworkManager.confirm_hit(shooter_id, false)
	_set_active.rpc(false, true)
	# Timer conectado (e não await): se o mapa for descarregado, a conexão
	# morre junto com o nó e o respawn não roda num alvo liberado.
	get_tree().create_timer(RULES.target_respawn_time).timeout.connect(_respawn)


## Servidor, ao recomeçar a partida: todos os alvos de pé.
func server_reset() -> void:
	if multiplayer.is_server() and not active:
		_set_active.rpc(true, true)


## Fora de partida (menu): volta ao estado inicial sem rede.
func reset_local() -> void:
	active = true
	visible = true
	collision_shape.set_deferred("disabled", false)
	visual.scale = Vector3.ONE


func _respawn() -> void:
	if NetworkManager.is_online():
		_set_active.rpc(true, true)


@rpc("authority", "call_local", "reliable")
func _set_active(value: bool, with_effects: bool) -> void:
	active = value
	visible = value
	collision_shape.set_deferred("disabled", not value)
	if not with_effects:
		return
	if not value:
		Sfx.play_at(Sfx.TARGET_HIT, collision_shape.global_position, 0.0, 0.04)
	else:
		visual.scale = Vector3.ONE * 0.2
		var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", Vector3.ONE, 0.25)


## Quem entra no meio da partida recebe o estado dos alvos derrubados.
func sync_to_peer(peer_id: int) -> void:
	if multiplayer.is_server() and not active:
		_set_active.rpc_id(peer_id, false, false)
