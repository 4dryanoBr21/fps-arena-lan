class_name HabitTracker
extends Node
## Só no servidor: observa os jogadores humanos 10 vezes por segundo e
## alimenta um PlayerHabits por jogador (movimento em combate, lugares no
## mapa, reação, precisão por distância e duelos contra bots de treino).
## O do host é o perfil salvo no autoload Habits; o dos outros vale a sessão.
## Fica como filho do NetworkManager; o BotBrain lê daqui.

const TICK: float = 0.1
const SIGHT_RANGE: float = 45.0
## Meio ângulo de visão: inimigo dentro dele conta para o tempo de reação.
const VIEW_HALF_ANGLE_DEG: float = 35.0
## Até quantos graus da mira um inimigo conta como alvo do tiro.
const AIM_TARGET_ANGLE_DEG: float = 10.0
const JUMP_SPEED: float = 2.5

## peer_id -> PlayerHabits.
var _habits: Dictionary = {}
## peer_id -> {"pos": Vector3, "vy": float, "seen": {id: msec ou -1}}.
var _state: Dictionary = {}
var _timer: float = 0.0


## Começo de sessão (host_game): esquece os clientes da sessão anterior.
func reset_session() -> void:
	_habits.clear()
	_state.clear()
	_timer = 0.0


## Jogador saiu: esquece o estado dele (o perfil do host fica no Habits).
func forget(peer_id: int) -> void:
	_habits.erase(peer_id)
	_state.erase(peer_id)


## Fim de partida: o passado pesa menos.
func new_match() -> void:
	for habits: PlayerHabits in _habits.values():
		habits.new_match()


func habits_for(peer_id: int) -> PlayerHabits:
	if peer_id <= 0 or NetworkManager.is_bot_id(peer_id):
		return null
	if not _habits.has(peer_id):
		_habits[peer_id] = Habits.profile if peer_id == 1 else PlayerHabits.new()
	return _habits[peer_id]


## Hábitos do humano em quem os bots se baseiam quando não estão mirando
## ninguém: o de menor id (o host, se ele estiver jogando).
func focus_habits() -> PlayerHabits:
	var best := 0
	for node in get_tree().get_nodes_in_group("players"):
		var id := (node as Node).name.to_int()
		if not NetworkManager.is_bot_id(id) and (best == 0 or id < best):
			best = id
	return habits_for(best)


func map_key() -> String:
	return NetworkManager.MAPS[NetworkManager.current_map]["path"]


func _physics_process(delta: float) -> void:
	if not _is_learning():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	var players: Array[FPSPlayer] = []
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as FPSPlayer
		if player != null and player.alive:
			players.append(player)
	for player in players:
		if not player.is_bot:
			_observe(player, players)


func _is_learning() -> bool:
	return NetworkManager.is_online() and multiplayer.is_server() \
		and NetworkManager.match_running and NetworkManager.get_mode() != "arena"


func _observe(player: FPSPlayer, players: Array[FPSPlayer]) -> void:
	var id := player.name.to_int()
	var habits := habits_for(id)
	var position := player.net_position
	var state: Dictionary = _state.get(id, {})
	if state.is_empty() or (state["pos"] as Vector3).distance_to(position) > 5.0:
		# Primeira amostra ou teleporte (spawn): só guarda a posição.
		_state[id] = {"pos": position, "vy": 0.0, "seen": {}}
		return
	var velocity := (position - (state["pos"] as Vector3)) / TICK
	var right := Vector3(cos(player.net_yaw), 0.0, -sin(player.net_yaw))
	var jumped := velocity.y > JUMP_SPEED and float(state["vy"]) <= JUMP_SPEED
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var sprinting := flat_speed > NetworkManager.RULES.walk_speed * player.speed_multiplier() * 1.1

	var in_combat := false
	var seen: Dictionary = state["seen"]
	var now := Time.get_ticks_msec()
	var forward := _forward(player)
	for other in players:
		if other == player:
			continue
		var visible := _can_see(player, other)
		in_combat = in_combat or visible
		var other_id := other.name.to_int()
		var to := _chest(other) - player.eye_position()
		if visible and rad_to_deg(forward.angle_to(to)) < VIEW_HALF_ANGLE_DEG:
			if not seen.has(other_id):
				seen[other_id] = now
		else:
			seen.erase(other_id)

	habits.observe_tick(TICK, map_key(), position, velocity.dot(right), jumped,
		player.net_crouch, sprinting, in_combat)
	state["pos"] = position
	state["vy"] = velocity.y
	if id == 1:
		Habits.mark_dirty()


## Chamado pelo FPSPlayer no servidor a cada tiro validado de um humano.
func observe_shot(shooter: FPSPlayer, origin: Vector3, direction: Vector3, hit: bool) -> void:
	if not _is_learning() or shooter.is_bot:
		return
	var id := shooter.name.to_int()
	var habits := habits_for(id)
	# Alvo pretendido: o inimigo mais perto da linha da mira.
	var best_angle := deg_to_rad(AIM_TARGET_ANGLE_DEG)
	var target: FPSPlayer = null
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as FPSPlayer
		if other == null or other == shooter or not other.alive:
			continue
		var angle := direction.angle_to(_chest(other) - origin)
		if angle < best_angle:
			best_angle = angle
			target = other
	if target == null:
		return
	habits.observe_shot(origin.distance_to(_chest(target)), hit)

	# Reação: do inimigo aparecer na frente até este tiro (só o primeiro conta).
	var state: Dictionary = _state.get(id, {})
	var seen: Dictionary = state.get("seen", {})
	var target_id := target.name.to_int()
	if int(seen.get(target_id, -1)) > 0:
		habits.observe_reaction((Time.get_ticks_msec() - int(seen[target_id])) / 1000.0)
		seen[target_id] = -1
	if id == 1:
		Habits.mark_dirty()


## Chamado pelo NetworkManager a cada abate: duelos humano x bot de treino
## ajustam a dificuldade.
func observe_kill(killer_id: int, victim_id: int) -> void:
	if not _is_learning() or NetworkManager.get_mode() != "training":
		return
	var killer_is_bot := NetworkManager.is_bot_id(killer_id)
	var victim_is_bot := NetworkManager.is_bot_id(victim_id)
	if victim_is_bot and not killer_is_bot:
		_duel(killer_id, true)
	elif killer_is_bot and not victim_is_bot:
		_duel(victim_id, false)


func _duel(human_id: int, won: bool) -> void:
	var habits := habits_for(human_id)
	if habits == null:
		return
	habits.observe_duel(won)
	if human_id == 1:
		Habits.mark_dirty()


func _can_see(player: FPSPlayer, other: FPSPlayer) -> bool:
	var from := player.eye_position()
	var to := _chest(other)
	if from.distance_to(to) > SIGHT_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == other


static func _chest(player: FPSPlayer) -> Vector3:
	return player.global_position + Vector3.UP * player.body_height() * 0.6


static func _forward(player: FPSPlayer) -> Vector3:
	var yaw := player.net_yaw
	var pitch := player.net_pitch
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
