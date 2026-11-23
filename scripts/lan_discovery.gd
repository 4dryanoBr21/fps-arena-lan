class_name LanDiscovery
extends Node
## Anúncio e busca de partidas na rede local por broadcast UDP.
## O host manda um pacote por segundo; o menu escuta e lista quem apareceu
## nos últimos segundos.

signal servers_changed

const PORT: int = 7778
const ANNOUNCE_INTERVAL: float = 1.0
const EXPIRE_MSEC: int = 3500
const MAGIC: String = "FPSARENA1"

## "ip:porta" -> {ip, port, host, map, players, version}
var servers: Dictionary = {}

var _advert: PacketPeerUDP
var _listener: PacketPeerUDP
var _info: Dictionary = {}
var _announce_timer: float = 0.0
var _seen_msec: Dictionary = {}


func start_listening() -> void:
	# O navegador não tem UDP: a lista fica vazia e o menu pede o IP.
	if _listener != null or OS.has_feature("web"):
		return
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(PORT)
	if err != OK:
		# Outra instância no mesmo PC já escuta a porta; a lista fica vazia.
		push_warning("Busca de partidas indisponível (porta %d, código %d)." % [PORT, err])
		_listener = null


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	servers.clear()
	_seen_msec.clear()
	servers_changed.emit()


func is_listening() -> bool:
	return _listener != null


## info: {port, host, map, players, version}
func start_advertising(info: Dictionary) -> void:
	_advert = PacketPeerUDP.new()
	_advert.set_broadcast_enabled(true)
	_advert.set_dest_address("255.255.255.255", PORT)
	_info = info
	_announce_timer = 0.0


func update_info(info: Dictionary) -> void:
	_info.merge(info, true)


func stop_advertising() -> void:
	if _advert != null:
		_advert.close()
		_advert = null


func _process(delta: float) -> void:
	if _advert != null:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_INTERVAL
			var payload := _info.duplicate()
			payload["magic"] = MAGIC
			_advert.put_packet(JSON.stringify(payload).to_utf8_buffer())

	if _listener == null:
		return
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var entry := parse_announcement(packet.get_string_from_utf8(), _listener.get_packet_ip())
		if entry.is_empty():
			continue
		var key := "%s:%d" % [entry["ip"], entry["port"]]
		if servers.get(key) != entry:
			changed = true
		servers[key] = entry
		_seen_msec[key] = Time.get_ticks_msec()

	var now := Time.get_ticks_msec()
	for key: String in servers.keys():
		if now - int(_seen_msec.get(key, 0)) > EXPIRE_MSEC:
			servers.erase(key)
			_seen_msec.erase(key)
			changed = true
	if changed:
		servers_changed.emit()


## Valida um anúncio recebido; devolve {} se não for do jogo.
static func parse_announcement(text: String, ip: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if not (data is Dictionary) or data.get("magic") != MAGIC or ip.is_empty():
		return {}
	var port := int(data.get("port", 0))
	if port <= 0 or port > 65535:
		return {}
	return {
		"ip": ip,
		"port": port,
		"host": str(data.get("host", "?")).left(24),
		"map": str(data.get("map", "?")).left(32),
		"players": int(data.get("players", 0)),
		"version": str(data.get("version", "?")).left(16),
	}


## 192.168.x.x, 10.x.x.x ou 172.16-31.x.x.
static func is_private_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	return a == 192 and b == 168 or a == 10 or a == 172 and b >= 16 and b <= 31
