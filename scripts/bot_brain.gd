class_name BotBrain
extends Node
## IA dos bots, só no servidor. Escolhe o inimigo (ou alvo da arena)
## visível mais perto, vira para ele com velocidade limitada e erro de mira
## proposital, anda de lado e atira depois de um tempo de reação. Sem ninguém
## à vista, corre entre os pontos de spawn (de faca, que é mais rápido). Puxa
## a faca quando o alvo chega perto e a arma de fogo quando ele se afasta.
## O FPSPlayer lê move/jump/sprint/crouch/fire/weapon.
##
## No Treino adaptativo os bots usam o que o HabitTracker aprendeu do jogador:
## - Caçador: prevê para onde você vai desviar, patrulha os lugares onde você
##   mais fica e puxa a briga para a distância em que você mira pior.
## - Espelho: se move como você (lado e ritmo do desvio, pulos, agachar e
##   distância preferida), para treinar contra o próprio estilo.
## A dificuldade (skill, 0 a 1) acompanha seus duelos: sobe quando você vence.

enum Personality { STANDARD, HUNTER, MIRROR }

const SIGHT_RANGE: float = 45.0
const FIRE_ANGLE_DEG: float = 5.0
const THINK_INTERVAL: float = 0.2
const GOAL_REACHED: float = 2.0
const STUCK_SPEED: float = 1.0
## Bots fora do treino: dificuldade fixa.
const STANDARD_SKILL: float = 0.45
## Faixas que a skill interpola (fácil -> difícil).
const REACTION_RANGE := Vector2(0.75, 0.2)
const TURN_RANGE := Vector2(2.5, 6.0)
## Erro de mira em metros a 10 m (cresce com a distância).
const AIM_ERROR_RANGE := Vector2(0.6, 0.12)
## Caçador: quanto à frente mira no movimento lateral do alvo (s).
const LEAD_TIME: float = 0.3
## Caçador: chance de patrulhar um lugar preferido do jogador.
const HOT_SPOT_CHANCE: float = 0.75
## Margem em volta da distância desejada antes de avançar ou recuar.
const STANDARD_DISTANCE: float = 10.0
const STANDARD_BAND: float = 5.0
const ADAPTIVE_BAND: float = 3.0
## Índices das armas no FPSPlayer.weapons e quando usar cada uma.
const PRIMARY: int = 0
const KNIFE: int = 2
const KNIFE_SWITCH_DISTANCE: float = 3.0
const GUN_SWITCH_DISTANCE: float = 6.0
const KNIFE_FIRE_ANGLE_DEG: float = 20.0

var move: Vector2 = Vector2.ZERO
var jump: bool = false
var sprint: bool = false
var crouch: bool = false
var fire: bool = false
## Arma que o bot quer na mão.
var weapon: int = PRIMARY
var personality: Personality = Personality.STANDARD

var _player: FPSPlayer
var _target: Node3D
## Recalculados junto com o alvo (a cada THINK_INTERVAL), não a cada quadro.
var _habits: PlayerHabits
var _skill_value: float = STANDARD_SKILL
var _seen_for: float = 0.0
var _think_timer: float = 0.0
var _strafe: float = 1.0
var _strafe_timer: float = 0.0
var _crouch_timer: float = 0.0
var _aim_offset: Vector3 = Vector3.ZERO
var _goal: Vector3
var _has_goal: bool = false
var _stuck_for: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_player = get_parent() as FPSPlayer
	_rng.seed = hash(_player.name)
	if NetworkManager.get_mode() == "training":
		personality = NetworkManager.bot_personality(_player.name.to_int())


func think(delta: float) -> void:
	jump = false
	fire = false
	sprint = false
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_target = _find_target()
		_habits = _habits_of(_target)
		_skill_value = _compute_skill()

	if _target != null:
		_fight(delta)
	else:
		_seen_for = 0.0
		crouch = false
		_wander(delta)


func _fight(delta: float) -> void:
	_seen_for += delta
	var habits := _habits
	var aim_point := _aim_point(_target)
	var distance := _player.eye_position().distance_to(aim_point)
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_new_strafe(habits, distance)
	aim_point += _aim_offset
	if personality == Personality.HUNTER and habits != null:
		aim_point += _predicted_lead(_target as FPSPlayer, habits)
	_turn_toward(aim_point, delta)

	var desired := STANDARD_DISTANCE
	var band := STANDARD_BAND
	if habits != null and personality != Personality.STANDARD:
		band = ADAPTIVE_BAND
		desired = habits.weakest_range_distance() if personality == Personality.HUNTER else habits.preferred_distance
	# Faca: perto puxa e parte para cima; longe volta para a arma de fogo.
	if distance < KNIFE_SWITCH_DISTANCE or _target is ShootingTarget and distance < KNIFE_SWITCH_DISTANCE:
		weapon = KNIFE
	elif distance > GUN_SWITCH_DISTANCE:
		weapon = PRIMARY
	var knife := weapon == KNIFE
	if knife:
		desired = 0.8
		band = 0.4
	var forward := 0.0
	if distance > desired + band:
		forward = -0.7
	elif distance < desired - band:
		forward = 0.5
	move = Vector2(_strafe, forward).limit_length(1.0)

	if personality == Personality.MIRROR and habits != null:
		jump = _rng.randf() < habits.jump_rate * delta
		_crouch_timer -= delta
		if _crouch_timer <= 0.0:
			_crouch_timer = 1.5
			crouch = _rng.randf() < habits.crouch_ratio
	if knife:
		var reach := _player.weapon_data().max_range if _player.weapon_data().melee else 0.0
		fire = _seen_for > _reaction_time() and distance <= reach and _angle_to(aim_point) < KNIFE_FIRE_ANGLE_DEG
	else:
		fire = _seen_for > _reaction_time() and _angle_to(aim_point) < FIRE_ANGLE_DEG


## Novo trecho de desvio lateral e novo erro de mira.
func _new_strafe(habits: PlayerHabits, distance: float) -> void:
	var interval := Vector2(0.6, 1.6)
	var right_chance := 0.5
	if personality == Personality.MIRROR and habits != null:
		interval = Vector2(0.7, 1.3) * habits.strafe_switch_time
		right_chance = 0.5 + 0.5 * habits.strafe_bias
	_strafe_timer = _rng.randf_range(interval.x, interval.y)
	_strafe = 1.0 if _rng.randf() < right_chance else -1.0
	var error := _aim_error() * maxf(distance / 10.0, 0.5)
	_aim_offset = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * error


## Caçador: mira à frente do desvio do alvo; se pelo ritmo dele a troca de
## lado está chegando, mira um pouco do lado de onde ele vai voltar.
func _predicted_lead(target: FPSPlayer, habits: PlayerHabits) -> Vector3:
	if target == null:
		return Vector3.ZERO
	var to := target.global_position - _player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return Vector3.ZERO
	to = to.normalized()
	var side := Vector3(-to.z, 0.0, to.x)
	var lead := side * target.server_velocity().dot(side) * LEAD_TIME
	if habits.expects_reversal():
		lead *= -0.5
	return lead * habits.confidence()


## Dificuldade contra o alvo atual (ou contra o jogador principal).
func _compute_skill() -> float:
	if personality == Personality.STANDARD:
		return STANDARD_SKILL
	var habits := _habits if _habits != null else NetworkManager.habits.focus_habits()
	return habits.skill if habits != null else STANDARD_SKILL


func _reaction_time() -> float:
	return lerpf(REACTION_RANGE.x, REACTION_RANGE.y, _skill_value)


func _turn_speed() -> float:
	return lerpf(TURN_RANGE.x, TURN_RANGE.y, _skill_value)


func _aim_error() -> float:
	return lerpf(AIM_ERROR_RANGE.x, AIM_ERROR_RANGE.y, _skill_value)


func _habits_of(node: Node3D) -> PlayerHabits:
	if personality == Personality.STANDARD or not node is FPSPlayer:
		return null
	return NetworkManager.habits.habits_for(node.name.to_int())


func _wander(delta: float) -> void:
	# Sem ninguém à vista, corre de faca (é mais leve).
	weapon = KNIFE
	if not _has_goal or _flat_distance(_goal) < GOAL_REACHED:
		_pick_goal()
	_turn_toward(_goal + Vector3.UP * 1.5, delta)
	move = Vector2(0.0, -1.0)
	sprint = true
	var flat_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_stuck_for = _stuck_for + delta if flat_speed < STUCK_SPEED else 0.0
	if _stuck_for > 0.5:
		jump = true
	if _stuck_for > 1.5:
		_stuck_for = 0.0
		_pick_goal()


func _pick_goal() -> void:
	_has_goal = true
	if personality == Personality.HUNTER and _rng.randf() < HOT_SPOT_CHANCE:
		var habits := NetworkManager.habits.focus_habits()
		if habits != null and habits.confidence() > 0.2:
			var spots := habits.hot_spots(NetworkManager.habits.map_key(), 4)
			if not spots.is_empty():
				_goal = spots[_rng.randi() % spots.size()]
				return
	var points := get_tree().get_nodes_in_group("spawn_points")
	if points.is_empty():
		_goal = Vector3(_rng.randf_range(-10, 10), 0.0, _rng.randf_range(-10, 10))
	else:
		_goal = (points[_rng.randi() % points.size()] as Node3D).global_position


## Inimigo vivo ou alvo ativo mais perto e com linha de visão.
func _find_target() -> Node3D:
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as FPSPlayer
		if other != null and other != _player and other.alive:
			candidates.append(other)
	for node in get_tree().get_nodes_in_group("targets"):
		var target := node as ShootingTarget
		if target != null and target.active:
			candidates.append(target)

	var eye := _player.eye_position()
	var best: Node3D = null
	var best_distance := SIGHT_RANGE
	for candidate in candidates:
		var point := _aim_point(candidate)
		var distance := eye.distance_to(point)
		if distance < best_distance and _can_see(eye, point, candidate):
			best = candidate
			best_distance = distance
	return best


func _can_see(from: Vector3, to: Vector3, candidate: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == candidate


func _aim_point(node: Node3D) -> Vector3:
	if node is FPSPlayer:
		return (node as FPSPlayer).global_position + Vector3.UP * (node as FPSPlayer).body_height() * 0.6
	if node is ShootingTarget:
		return (node as ShootingTarget).collision_shape.global_position
	return node.global_position


func _turn_toward(point: Vector3, delta: float) -> void:
	var to := point - _player.eye_position()
	var yaw := atan2(-to.x, -to.z)
	var turn_speed := _turn_speed()
	_player.rotation.y = rotate_toward(_player.rotation.y, yaw, turn_speed * delta)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	_player.head.rotation.x = move_toward(_player.head.rotation.x, pitch, turn_speed * 0.7 * delta)


func _angle_to(point: Vector3) -> float:
	var forward := -_player.head.global_basis.z
	return rad_to_deg(forward.angle_to(point - _player.eye_position()))


func _flat_distance(point: Vector3) -> float:
	var offset := point - _player.global_position
	return Vector2(offset.x, offset.z).length()
