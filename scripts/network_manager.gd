extends Node
## Autoload "NetworkManager": cria/encerra a sessão ENet, escolhe o mapa,
## mantém o placar autoritativo do servidor e distribui pontos de spawn.

signal status_changed(text: String)
signal map_changed(map_index: int)
signal game_started
signal game_ended(reason: String)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal scores_changed
signal hit_confirmed(killed: bool)
signal kill_announced(killer_id: int, victim_id: int)

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8
const MAPS := [
	{"name": "Arena de Alvos", "path": "res://scenes/arena.tscn"},
	{"name": "Mata-mata: Fundição", "path": "res://scenes/deathmatch.tscn"},
]

## peer_id (int) -> pontos / mortes (int). Só o servidor escreve; os clientes recebem via RPC.
var scores: Dictionary = {}
var deaths: Dictionary = {}
var current_map: int = 0

var _spawn_index: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT, map_index: int = 0) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		status_changed.emit("Erro ao criar servidor na porta %d (código %d)." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	scores = {1: 0}
	deaths = {1: 0}
	_spawn_index = 0
	current_map = clampi(map_index, 0, MAPS.size() - 1)
	var lan_ip := get_lan_ip()
	if lan_ip.is_empty():
		status_changed.emit("Hospedando na porta %d" % port)
	else:
		status_changed.emit("Hospedando em %s, porta %d" % [lan_ip, port])
	map_changed.emit(current_map)
	game_started.emit()
	scores_changed.emit()
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		status_changed.emit("Erro ao conectar em %s:%d (código %d)." % [ip, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Conectando a %s:%d..." % [ip, port])
	return OK


func leave_game(reason: String = "Desconectado.") -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scores.clear()
	deaths.clear()
	scores_changed.emit()
	game_ended.emit(reason)


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null \
		and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Primeiro IPv4 de rede local (192.168.x.x, 10.x.x.x, 172.16-31.x.x) para
## mostrar a quem vai entrar; vazio se não achar.
func get_lan_ip() -> String:
	for address: String in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var a := parts[0].to_int()
		var b := parts[1].to_int()
		if a == 192 and b == 168 or a == 10 or a == 172 and b >= 16 and b <= 31:
			return address
	return ""


func get_role_text() -> String:
	if not is_online():
		return "Desconectado"
	return "Host" if multiplayer.is_server() else "Cliente"


func get_map_name(map_index: int = current_map) -> String:
	return MAPS[map_index]["name"]


func get_player_label(peer_id: int) -> String:
	return "Host" if peer_id == 1 else "Jogador %04d" % (peer_id % 10000)


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
	if not multiplayer.is_server():
		return
	scores[peer_id] = int(scores.get(peer_id, 0)) + amount
	_sync_scores.rpc(scores, deaths)


func register_kill(killer_id: int, victim_id: int) -> void:
	if not multiplayer.is_server():
		return
	if killer_id != victim_id and scores.has(killer_id):
		scores[killer_id] = int(scores[killer_id]) + 1
	deaths[victim_id] = int(deaths.get(victim_id, 0)) + 1
	_sync_scores.rpc(scores, deaths)
	_announce_kill.rpc(killer_id, victim_id)


## Avisa o atirador que o acerto foi validado (hitmarker no HUD dele).
func confirm_hit(peer_id: int, killed: bool) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1 or multiplayer.get_peers().has(peer_id):
		_notify_hit.rpc_id(peer_id, killed)


@rpc("authority", "call_local", "reliable")
func _sync_scores(new_scores: Dictionary, new_deaths: Dictionary) -> void:
	scores = new_scores
	deaths = new_deaths
	scores_changed.emit()


@rpc("authority", "call_local", "reliable")
func _notify_hit(killed: bool) -> void:
	hit_confirmed.emit(killed)


@rpc("authority", "call_local", "reliable")
func _announce_kill(killer_id: int, victim_id: int) -> void:
	kill_announced.emit(killer_id, victim_id)


## Servidor -> cliente recém-conectado: qual mapa carregar.
@rpc("authority", "call_remote", "reliable")
func _receive_map(map_index: int) -> void:
	current_map = map_index
	map_changed.emit(map_index)
	game_started.emit()
	_client_ready.rpc_id(1)


## Cliente -> servidor: mapa carregado, pode criar meu jogador.
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	scores[peer_id] = 0
	deaths[peer_id] = 0
	_sync_scores.rpc(scores, deaths)
	player_joined.emit(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_receive_map.rpc_id(peer_id, current_map)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	scores.erase(peer_id)
	deaths.erase(peer_id)
	_sync_scores.rpc(scores, deaths)
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	status_changed.emit("Conectado como peer %d. Carregando mapa..." % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	leave_game("Falha ao conectar. Verifique o IP, a porta e o firewall.")


func _on_server_disconnected() -> void:
	leave_game("O host encerrou a partida.")
