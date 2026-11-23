class_name DualServerPeer
extends MultiplayerPeerExtension
## Servidor que aceita dois tipos de cliente na mesma partida: ENet (UDP, PC e
## celular, como sempre) e WebSocket (TCP, a versão de navegador, que não tem
## acesso a UDP). Para o SceneMultiplayer é um peer só: os dois servidores
## ficam por baixo, cada pacote vai para o servidor onde o destino está
## conectado e os recebidos entram numa fila única.
## Os ids vêm dos dois servidores (aleatórios de 31 bits); colisão é praticamente
## impossível, e se acontecer o segundo cliente é derrubado.

var _enet: ENetMultiplayerPeer
## Nulo quando a porta do WebSocket não abriu (a partida segue só com ENet).
var _ws: WebSocketMultiplayerPeer
## peer_id -> servidor onde ele está.
var _owner: Dictionary = {}
## Fila de recebidos: [dados, peer, canal, modo].
var _queue: Array = []
var _target_peer: int = 0
var _transfer_channel: int = 0
var _transfer_mode: TransferMode = TRANSFER_MODE_RELIABLE
var _refusing: bool = false
var _closed: bool = true
## Resultado da abertura do WebSocket (OK = aceita jogadores do navegador).
var web_error: Error = OK


## Abre o ENet em `port` (obrigatório) e o WebSocket em `web_port` (opcional:
## se falhar, `web_error` fica com o código e a partida segue sem navegador).
func create(port: int, web_port: int, max_clients: int) -> Error:
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_server(port, max_clients)
	if err != OK:
		_enet = null
		return err
	_ws = WebSocketMultiplayerPeer.new()
	web_error = _ws.create_server(web_port)
	if web_error != OK:
		_ws = null
	for sub: MultiplayerPeer in _servers():
		sub.peer_connected.connect(_on_sub_connected.bind(sub))
		sub.peer_disconnected.connect(_on_sub_disconnected)
	_closed = false
	return OK


## ENet por baixo (para estatísticas como o ping); nulo depois de fechar.
func enet() -> ENetMultiplayerPeer:
	return _enet


func is_web_peer(peer_id: int) -> bool:
	return _ws != null and _owner.get(peer_id) == _ws


func accepts_web() -> bool:
	return _ws != null


func _servers() -> Array[MultiplayerPeer]:
	var list: Array[MultiplayerPeer] = []
	if _enet != null:
		list.append(_enet)
	if _ws != null:
		list.append(_ws)
	return list


func _on_sub_connected(peer_id: int, sub: MultiplayerPeer) -> void:
	if _owner.has(peer_id) or _refusing:
		sub.disconnect_peer(peer_id)
		return
	_owner[peer_id] = sub
	peer_connected.emit(peer_id)


func _on_sub_disconnected(peer_id: int) -> void:
	if _owner.erase(peer_id):
		peer_disconnected.emit(peer_id)


func _poll() -> void:
	for sub in _servers():
		sub.poll()
		while sub.get_available_packet_count() > 0:
			var from := sub.get_packet_peer()
			var channel := sub.get_packet_channel()
			var mode := sub.get_packet_mode()
			var data := sub.get_packet()
			# Pacote de quem foi recusado (id repetido) ou já saiu: descarta.
			if _owner.get(from) == sub:
				_queue.append([data, from, channel, mode])


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	return _queue.pop_front()[0]


func _get_packet_peer() -> int:
	return _queue[0][1] if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return _queue[0][2] if not _queue.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _queue[0][3] if not _queue.is_empty() else TRANSFER_MODE_RELIABLE


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _closed:
		return ERR_UNCONFIGURED
	if _target_peer > 0:
		var sub: MultiplayerPeer = _owner.get(_target_peer)
		if sub == null:
			return ERR_INVALID_PARAMETER
		return _send(sub, _target_peer, buffer)
	# 0 = todos; negativo = todos menos um (quem não tem esse peer manda a todos).
	var result := OK
	for sub in _servers():
		if sub.get_connection_status() == CONNECTION_CONNECTED:
			var err := _send(sub, _target_peer, buffer)
			if err != OK:
				result = err
	return result


func _send(sub: MultiplayerPeer, target: int, buffer: PackedByteArray) -> Error:
	sub.transfer_channel = _transfer_channel
	sub.transfer_mode = _transfer_mode
	sub.set_target_peer(target)
	return sub.put_packet(buffer)


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _transfer_mode


func _get_max_packet_size() -> int:
	return 1 << 24


func _is_server() -> bool:
	return true


func _is_server_relay_supported() -> bool:
	return true


func _get_unique_id() -> int:
	return 1


func _get_connection_status() -> ConnectionStatus:
	return CONNECTION_DISCONNECTED if _closed else CONNECTION_CONNECTED


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	for sub in _servers():
		sub.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, force: bool) -> void:
	var sub: MultiplayerPeer = _owner.get(peer)
	if sub == null:
		return
	sub.disconnect_peer(peer, force)
	if force:
		_on_sub_disconnected(peer)


func _close() -> void:
	for sub in _servers():
		sub.close()
	_enet = null
	_ws = null
	_owner.clear()
	_queue.clear()
	_closed = true
