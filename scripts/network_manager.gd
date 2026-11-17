extends Node
## Autoload "NetworkManager": cria/encerra a sessão ENet, confere a versão de
## quem entra, guarda apelidos, equipamentos e o placar autoritativo do
## servidor, controla a partida (tempo, fim, reinício), os bots, os prêmios
## em moedas/XP, o aprendizado dos bots de treino (HabitTracker) e o anúncio
## na rede local.

signal status_changed(text: String)
signal map_changed(map_index: int)
signal game_started
signal game_ended(reason: String)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal scores_changed
signal hit_confirmed(killed: bool)
signal kill_announced(killer_id: int, victim_id: int)
## Partida começou/recomeçou ou o tempo foi ressincronizado.
signal match_state_changed
signal match_over(winner_id: int)
## Só no servidor: hora de recolocar todo mundo e os alvos no lugar.
signal match_restarted
## Fim de um Treino adaptativo: a dica sobre os hábitos deste jogador.
signal training_feedback(text: String)

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8
const MAX_BOTS: int = 6
## Treino adaptativo sem bots não faz sentido: cria pelo menos estes.
const MIN_TRAINING_BOTS: int = 2
## Bots usam ids fixos nessa faixa; peers reais ganham ids aleatórios enormes.
const BOT_ID_MIN: int = 1000
const BOT_ID_MAX: int = 1099
const PING_INTERVAL: float = 2.0
const NICKNAME_MAX: int = 16
const RULES: GameRules = preload("res://data/game_rules.tres")
const MAPS := [
	{"name": "Arena de Alvos", "path": "res://scenes/arena.tscn", "mode": "arena"},
	{"name": "Mata-mata: Fundição", "path": "res://scenes/deathmatch.tscn", "mode": "deathmatch"},
	{"name": "Treino adaptativo: Fundição", "path": "res://scenes/deathmatch.tscn", "mode": "training"},
]

## peer_id (int) -> pontos / mortes / apelido / ping. Só o servidor escreve;
## os clientes recebem via RPC.
var scores: Dictionary = {}
var deaths: Dictionary = {}
var names: Dictionary = {}
var pings: Dictionary = {}
## peer_id -> equipamento conferido pelo servidor (GameRules.sanitize_loadout).
## Vai junto com o placar, que chega aos clientes antes do spawn dos jogadores.
var loadouts: Dictionary = {}
var current_map: int = 0
var match_running: bool = false
## Relógio local (Time.get_ticks_msec) em que a partida acaba.
var match_end_msec: int = 0
var discovery: LanDiscovery
var habits: HabitTracker

var _spawn_index: int = 0
var _ready_peers: Dictionary = {}
var _ping_timer: float = 0.0
var _reject_reason: String = ""
var _rng := RandomNumberGenerator.new()
var _default_loadout: Dictionary = RULES.sanitize_loadout({})


func _ready() -> void:
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	habits = HabitTracker.new()
	habits.name = "HabitTracker"
	add_child(habits)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if not is_online() or not multiplayer.is_server():
		return
	if match_running and Time.get_ticks_msec() >= match_end_msec:
		_end_match()
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_INTERVAL
		for peer_id in multiplayer.get_peers():
			pings[peer_id] = get_peer_rtt(peer_id)
		_broadcast_scores()
		discovery.update_info({"players": scores.size(), "map": get_map_name()})


static func get_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


static func is_bot_id(peer_id: int) -> bool:
	return peer_id >= BOT_ID_MIN and peer_id <= BOT_ID_MAX


## Treino: bots alternam entre Caçador e Espelho.
static func bot_personality(peer_id: int) -> BotBrain.Personality:
	return BotBrain.Personality.HUNTER if (peer_id - BOT_ID_MIN) % 2 == 0 else BotBrain.Personality.MIRROR


static func clean_nickname(text: String) -> String:
	var nickname := text.strip_edges().replace("\n", " ").left(NICKNAME_MAX)
	return nickname if not nickname.is_empty() else "Jogador"


func host_game(port: int = DEFAULT_PORT, map_index: int = 0, bot_count: int = 0) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		status_changed.emit("Erro ao criar servidor na porta %d (código %d)." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	scores = {1: 0}
	deaths = {1: 0}
	names = {1: clean_nickname(Settings.nickname)}
	pings = {1: 0}
	loadouts = {1: Progress.profile.network_loadout()}
	_ready_peers.clear()
	_spawn_index = 0
	current_map = clampi(map_index, 0, MAPS.size() - 1)
	habits.reset_session()
	var training := get_mode() == "training"
	if training:
		bot_count = maxi(bot_count, MIN_TRAINING_BOTS)
	for i in clampi(bot_count, 0, MAX_BOTS):
		var bot_id := BOT_ID_MIN + i
		scores[bot_id] = 0
		deaths[bot_id] = 0
		names[bot_id] = "Bot %d" % (i + 1)
		if training:
			var hunter := bot_personality(bot_id) == BotBrain.Personality.HUNTER
			names[bot_id] = "%s %d" % ["Caçador" if hunter else "Espelho", i + 1]
		pings[bot_id] = 0
		loadouts[bot_id] = RULES.random_loadout(_rng)

	var lan_ip := get_lan_ip()
	if lan_ip.is_empty():
		status_changed.emit("Hospedando na porta %d" % port)
	else:
		status_changed.emit("Hospedando em %s, porta %d" % [lan_ip, port])
	discovery.start_advertising({
		"port": port, "host": names[1], "map": get_map_name(),
		"players": scores.size(), "version": get_version()})
	map_changed.emit(current_map)
	game_started.emit()
	_start_match()
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		status_changed.emit("Erro ao conectar em %s:%d (código %d)." % [ip, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	_reject_reason = ""
	status_changed.emit("Conectando a %s:%d..." % [ip, port])
	return OK


func leave_game(reason: String = "Desconectado.") -> void:
	discovery.stop_advertising()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var final_scores := standings_text()
	scores.clear()
	deaths.clear()
	names.clear()
	pings.clear()
	loadouts.clear()
	match_running = false
	Progress.save_if_dirty()
	Habits.save_if_dirty()
	scores_changed.emit()
	if not final_scores.is_empty():
		reason += "\n\nPlacar final:\n" + final_scores
	game_ended.emit(reason)


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null \
		and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func get_role_text() -> String:
	if not is_online():
		return "Desconectado"
	return "Host" if multiplayer.is_server() else "Cliente"


func get_map_name(map_index: int = current_map) -> String:
	return MAPS[map_index]["name"]


func get_mode(map_index: int = current_map) -> String:
	return MAPS[map_index]["mode"]


func get_player_label(peer_id: int) -> String:
	if names.has(peer_id):
		return names[peer_id]
	return "Host" if peer_id == 1 else "Jogador %04d" % (peer_id % 10000)


## Equipamento do jogador; o padrão enquanto a lista do servidor não chegou.
func get_loadout(peer_id: int) -> Dictionary:
	return loadouts.get(peer_id, _default_loadout)


func get_bot_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in scores:
		if is_bot_id(id):
			ids.append(id)
	return ids


## Segundos que faltam na partida (0 se não estiver rodando).
func time_left() -> float:
	if not match_running:
		return 0.0
	return maxf((match_end_msec - Time.get_ticks_msec()) / 1000.0, 0.0)


## ids ordenados por pontos (desempate: menos mortes).
func standings() -> Array:
	var ids: Array = scores.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		if int(scores[a]) != int(scores[b]):
			return int(scores[a]) > int(scores[b])
		return int(deaths.get(a, 0)) < int(deaths.get(b, 0)))
	return ids


func standings_text() -> String:
	var lines := PackedStringArray()
	for id: int in standings():
		lines.append("%s: %d / %d" % [get_player_label(id), int(scores[id]), int(deaths.get(id, 0))])
	return "\n".join(lines)


## Ida e volta (ms) até um peer; 0 se não houver conexão ENet com ele.
func get_peer_rtt(peer_id: int) -> int:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or not multiplayer.is_server():
		return 0
	var packet_peer := enet.get_peer(peer_id)
	if packet_peer == null:
		return 0
	return int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## Primeiro IPv4 de rede local para mostrar a quem vai entrar; vazio se não achar.
func get_lan_ip() -> String:
	for address: String in IP.get_local_addresses():
		if LanDiscovery.is_private_ipv4(address):
			return address
	return ""


## Usado só no servidor: o Marker3D do grupo "spawn_points" mais longe dos
## jogadores vivos (evita nascer na cara de alguém).
func get_spawn_position_for(peer_id: int) -> Vector3:
	var points := get_tree().get_nodes_in_group("spawn_points")
	if points.is_empty():
		return Vector3(0.0, 1.0, 0.0)

	var others: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as FPSPlayer
		if player != null and player.alive and player.name.to_int() != peer_id:
			others.append(player.global_position)

	if others.is_empty():
		var point := points[_spawn_index % points.size()] as Node3D
		_spawn_index += 1
		return point.global_position

	var best_position := Vector3.ZERO
	var best_distance := -1.0
	for node in points:
		var candidate := (node as Node3D).global_position
		var nearest := INF
		for other in others:
			nearest = minf(nearest, candidate.distance_to(other))
		if nearest > best_distance:
			best_distance = nearest
			best_position = candidate
	return best_position


func add_score(peer_id: int, amount: int = 1) -> void:
	if not multiplayer.is_server() or not match_running or not scores.has(peer_id):
		return
	scores[peer_id] = int(scores[peer_id]) + amount
	_broadcast_scores()


func register_kill(killer_id: int, victim_id: int, headshot: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if match_running:
		if killer_id != victim_id and scores.has(killer_id):
			scores[killer_id] = int(scores[killer_id]) + 1
			if headshot:
				grant(killer_id, RULES.kill_coins + RULES.headshot_coins, RULES.kill_xp + RULES.headshot_xp, "Abate na cabeça")
			else:
				grant(killer_id, RULES.kill_coins, RULES.kill_xp, "Abate")
		deaths[victim_id] = int(deaths.get(victim_id, 0)) + 1
		_broadcast_scores()
	habits.observe_kill(killer_id, victim_id)
	_announce_kill.rpc(killer_id, victim_id)
	if match_running and get_mode() != "arena" \
			and int(scores.get(killer_id, 0)) >= RULES.deathmatch_kill_limit:
		_end_match()


## Avisa o atirador que o acerto foi validado (hitmarker no HUD dele).
func confirm_hit(peer_id: int, killed: bool) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1 or multiplayer.get_peers().has(peer_id):
		_notify_hit.rpc_id(peer_id, killed)


## Só no servidor: alvo da arena derrubado.
func reward_target(peer_id: int) -> void:
	if multiplayer.is_server() and match_running:
		grant(peer_id, RULES.target_coins, RULES.target_xp, "Alvo")


## Só no servidor: manda moedas e XP para o jogador (bots não ganham nada).
func grant(peer_id: int, coins: int, xp: int, reason: String) -> void:
	if not multiplayer.is_server() or is_bot_id(peer_id):
		return
	if peer_id == 1 or multiplayer.get_peers().has(peer_id):
		_grant.rpc_id(peer_id, coins, xp, reason)


## Só no servidor: prêmio de colocação (com 2 ou mais na partida) e de
## participação para todos os humanos.
func _grant_match_rewards(ranking: Array) -> void:
	for place in ranking.size():
		var id: int = ranking[place]
		var coins := RULES.finish_coins
		var xp := RULES.finish_xp
		var reason := "Fim de partida"
		if ranking.size() >= 2 and place < RULES.placement_coins.size():
			coins += RULES.placement_coins[place]
			xp += RULES.placement_xp[place] if place < RULES.placement_xp.size() else 0
			reason = "%dº lugar" % (place + 1)
		grant(id, coins, xp, reason)


func _broadcast_scores() -> void:
	_sync_scores.rpc(scores, deaths, names, pings, loadouts)


## Só no servidor: zera o placar e começa a contagem.
func _start_match() -> void:
	for id: int in scores:
		scores[id] = 0
		deaths[id] = 0
	var duration: float = RULES.arena_time if get_mode() == "arena" else RULES.deathmatch_time
	match_running = true
	match_end_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	_broadcast_scores()
	_sync_match.rpc(duration, true)
	match_restarted.emit()


func _end_match() -> void:
	if not match_running:
		return
	match_running = false
	var ranking := standings()
	var winner: int = ranking[0] if not ranking.is_empty() else 0
	# Prêmios e dicas antes do resultado: a tela de fim já mostra tudo.
	_grant_match_rewards(ranking)
	# Partida terminada: o passado passa a pesar menos (sair no meio não conta).
	habits.new_match()
	if get_mode() == "training":
		for id: int in ranking:
			var player_habits := habits.habits_for(id)
			if player_habits != null and (id == 1 or multiplayer.get_peers().has(id)):
				_training_feedback.rpc_id(id, player_habits.summary_line(habits.map_key()))
	_match_over.rpc(winner)
	get_tree().create_timer(RULES.results_time).timeout.connect(func() -> void:
		if is_online() and multiplayer.is_server():
			_start_match())


@rpc("authority", "call_local", "reliable")
func _sync_scores(new_scores: Dictionary, new_deaths: Dictionary, new_names: Dictionary,
		new_pings: Dictionary, new_loadouts: Dictionary) -> void:
	scores = new_scores
	deaths = new_deaths
	names = new_names
	pings = new_pings
	loadouts = new_loadouts
	scores_changed.emit()


@rpc("authority", "call_local", "reliable")
func _sync_match(remaining: float, running: bool) -> void:
	match_running = running
	match_end_msec = Time.get_ticks_msec() + int(remaining * 1000.0)
	match_state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _match_over(winner_id: int) -> void:
	match_running = false
	match_over.emit(winner_id)
	Progress.save_if_dirty()
	Habits.save_if_dirty()


@rpc("authority", "call_local", "reliable")
func _training_feedback(text: String) -> void:
	training_feedback.emit(text)


@rpc("authority", "call_local", "reliable")
func _grant(coins: int, xp: int, reason: String) -> void:
	Progress.grant(coins, xp, reason)


@rpc("authority", "call_local", "reliable")
func _notify_hit(killed: bool) -> void:
	hit_confirmed.emit(killed)


@rpc("authority", "call_local", "reliable")
func _announce_kill(killer_id: int, victim_id: int) -> void:
	kill_announced.emit(killer_id, victim_id)


## Cliente -> servidor, logo ao conectar: versão do jogo e apelido.
@rpc("any_peer", "call_remote", "reliable")
func _hello(version: String, nickname: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if version != get_version():
		_rejected.rpc_id(peer_id, "Versão diferente: o host tem %s e você tem %s. Atualizem o jogo." % [get_version(), version])
		# Dá tempo da mensagem chegar antes de derrubar a conexão.
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if is_online() and multiplayer.get_peers().has(peer_id):
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id))
		return
	names[peer_id] = clean_nickname(nickname)
	_receive_map.rpc_id(peer_id, current_map, time_left(), match_running)


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_reject_reason = reason


## Servidor -> cliente aceito: qual mapa carregar e quanto falta da partida.
@rpc("authority", "call_remote", "reliable")
func _receive_map(map_index: int, remaining: float, running: bool) -> void:
	current_map = map_index
	map_changed.emit(map_index)
	game_started.emit()
	_sync_match(remaining, running)
	_client_ready.rpc_id(1, Progress.profile.network_loadout())


## Cliente -> servidor: mapa carregado, pode criar meu jogador com este
## equipamento. Vale uma vez por peer.
@rpc("any_peer", "call_remote", "reliable")
func _client_ready(loadout: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _ready_peers.has(peer_id) or not names.has(peer_id):
		return
	_ready_peers[peer_id] = true
	loadouts[peer_id] = RULES.sanitize_loadout(loadout)
	scores[peer_id] = 0
	deaths[peer_id] = 0
	pings[peer_id] = get_peer_rtt(peer_id)
	_broadcast_scores()
	player_joined.emit(peer_id)


func _on_peer_connected(_peer_id: int) -> void:
	# O servidor espera o _hello do cliente antes de mandar o mapa.
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	scores.erase(peer_id)
	deaths.erase(peer_id)
	names.erase(peer_id)
	pings.erase(peer_id)
	loadouts.erase(peer_id)
	habits.forget(peer_id)
	_ready_peers.erase(peer_id)
	_broadcast_scores()
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	status_changed.emit("Conectado como peer %d. Carregando mapa..." % multiplayer.get_unique_id())
	_hello.rpc_id(1, get_version(), clean_nickname(Settings.nickname))


func _on_connection_failed() -> void:
	leave_game("Falha ao conectar. Verifique o IP, a porta e o firewall.")


func _on_server_disconnected() -> void:
	leave_game(_reject_reason if not _reject_reason.is_empty() else "O host encerrou a partida.")
