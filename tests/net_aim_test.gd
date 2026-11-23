extends Node
## Teste de precisão do tiro PELA REDE (o hitbox_test só cobre o host).
## Um host com 1 bot e um cliente de verdade, em dois processos. O host move o
## bot de lado (vai e volta a 7 m/s, 60 m acima do mapa, sem paredes). O
## cliente mira exatamente no centro da cabeça do bot COMO ELE O VÊ NA TELA
## (posição interpolada) e atira a cada 0,3 s. Cada processo registra um tiro
## por linha; tools/net_aim_report.py junta as duas listas e mede quanto a
## posição que o servidor usou (compensação de latência) difere da que o
## cliente viu, e quantos tiros "certos na tela" o servidor recusou.
##   host:    godot --headless --path . res://tests/net_aim_test.tscn -- --role=host
##   cliente: godot --headless --path . res://tests/net_aim_test.tscn -- --role=client --join=127.0.0.1
## Com tools/proxy_latencia.py no meio dá para simular ping de internet.

const HEIGHT: float = 60.0
const DISTANCE: float = 8.0
const SPEED: float = 7.0
const HALF_PATH: float = 3.0
const SHOT_INTERVAL: float = 0.3
## Primeiros tiros com o bot parado (controle: têm que acertar todos).
const STILL_SHOTS: int = 8
const TOTAL_SHOTS: int = 70
const HEAD_Y: float = 1.62
const BIG_HEALTH: int = 1000000

var _args := {}
var _main: Node
var _players: Node
var _bot: FPSPlayer
var _shooter: FPSPlayer
var _bot_x: float = 0.0
var _bot_dir: float = 1.0
var _moving: bool = false
var _last_seen_shot: int = -100000
var _sv_shots: int = 0
var _cl_shots: int = 0
var _shot_timer: float = 0.0
var _ready_to_shoot: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	Progress.persistent = false
	Progress.profile = PlayerProfile.new()
	Habits.persistent = false
	Habits.profile = PlayerHabits.new()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_players = _main.get_node("Players")
	await get_tree().process_frame
	if _args.get("role", "host") == "host":
		_main.call("_load_map", 1)
		NetworkManager.host_game(NetworkManager.DEFAULT_PORT, 1, 1)
		await _host_setup()
	else:
		NetworkManager.join_game(str(_args.get("join", "127.0.0.1")), NetworkManager.DEFAULT_PORT, _args.has("ws"))
		await _client_setup()
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("TIMEOUT")
		get_tree().quit(1))


# --- Host ---------------------------------------------------------------------

func _host_setup() -> void:
	while _players.get_node_or_null("1000") == null:
		await get_tree().process_frame
	_bot = _players.get_node("1000")
	_bot.set_physics_process(false)
	var host := _players.get_node("1") as FPSPlayer
	host.set_physics_process(false)
	host.global_position = Vector3(40, HEIGHT, 40)
	host.net_position = host.global_position
	print("HOST pronto, esperando o cliente")
	while _shooter == null:
		for node in _players.get_children():
			var id := node.name.to_int()
			if id != 1 and not NetworkManager.is_bot_id(id):
				_shooter = node
		await get_tree().process_frame
	await get_tree().create_timer(NetworkManager.RULES.spawn_protection + 0.5).timeout
	_bot.health = BIG_HEALTH
	_bot.protected = false
	print("HOST cliente %s conectado" % _shooter.name)


func _physics_process(delta: float) -> void:
	if _args.get("role", "host") == "host":
		_host_physics(delta)
	else:
		_client_physics(delta)


func _host_physics(delta: float) -> void:
	if _bot == null:
		return
	if _moving:
		_bot_x += _bot_dir * SPEED * delta
		if absf(_bot_x) > HALF_PATH:
			_bot_x = clampf(_bot_x, -HALF_PATH, HALF_PATH)
			_bot_dir = -_bot_dir
	_bot.global_position = Vector3(_bot_x, HEIGHT, 0)
	_bot.rotation.y = 0.0
	_bot.net_yaw = 0.0
	_bot.net_crouch = false
	_bot.net_stamp = Time.get_ticks_msec()
	_bot.net_position = _bot.global_position
	if _shooter == null:
		return
	# Teste de mira, não de validação: libera munição e movimento do cliente.
	_shooter.set("_sv_grace_until_msec", Time.get_ticks_msec() + 1000)
	var sv_ammo: Array[int] = _shooter.get("_sv_ammo")
	for i in sv_ammo.size():
		sv_ammo[i] = 99
	_shooter.set("_sv_reload_until_msec", 0)
	var shot_msec: int = _shooter.get("_sv_last_shot_msec")
	if shot_msec != _last_seen_shot:
		_last_seen_shot = shot_msec
		var seen: int = _shooter.get("_sv_last_seen_msec")
		var rewind := shot_msec - seen
		var used := _bot.position_at(seen)
		var hit := _bot.health < BIG_HEALTH
		var dmg := BIG_HEALTH - _bot.health
		print("SSHOT %d x=%.4f rewind=%d rtt=%d hit=%d dmg=%d moving=%d" % [
			_sv_shots, used.x, rewind, NetworkManager.get_peer_rtt(_shooter.name.to_int()),
			1 if hit else 0, dmg, 1 if _moving else 0])
		_sv_shots += 1
		_bot.health = BIG_HEALTH
		if _sv_shots >= STILL_SHOTS:
			_moving = true
		if _sv_shots >= TOTAL_SHOTS:
			print("HOST fim")
			get_tree().create_timer(1.0).timeout.connect(get_tree().quit)


# --- Cliente ------------------------------------------------------------------

func _client_setup() -> void:
	var my_id := 0
	while _shooter == null or _bot == null:
		my_id = multiplayer.get_unique_id()
		_shooter = _players.get_node_or_null(str(my_id))
		_bot = _players.get_node_or_null("1000")
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_shooter.set_physics_process(false)
	_shooter.global_position = Vector3(0, HEIGHT, DISTANCE)
	_shooter.net_position = _shooter.global_position
	await get_tree().create_timer(NetworkManager.RULES.spawn_protection + 1.5).timeout
	print("CLIENTE pronto (%d)" % my_id)
	_ready_to_shoot = true


func _client_physics(delta: float) -> void:
	if not _ready_to_shoot or _cl_shots >= TOTAL_SHOTS:
		if _ready_to_shoot and _cl_shots >= TOTAL_SHOTS:
			_ready_to_shoot = false
			get_tree().create_timer(2.0).timeout.connect(get_tree().quit)
		return
	_shooter.net_position = _shooter.global_position
	_shot_timer += delta
	if _shot_timer < SHOT_INTERVAL:
		return
	_shot_timer = 0.0
	# Mira no centro da cabeça do bot como ele está desenhado agora.
	var seen := _bot.global_position
	var head := seen + Vector3(0, HEAD_Y, 0)
	var to := head - _shooter.eye_position()
	_shooter.rotation.y = atan2(-to.x, -to.z)
	_shooter.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	var dir := to.normalized()
	var predicted: Dictionary = _shooter.call("_local_hit", _shooter.eye_position(), dir, 110.0, 0.0)
	_shooter.set("_cooldown", 0.0)
	_shooter.set("_spread", 0.0)
	_shooter.set("_reload_until_msec", 0)
	_shooter.ammo[_shooter.weapon_index] = 25
	_shooter.call("_try_shoot")
	print("CSHOT %d x=%.4f pred=%d" % [_cl_shots, seen.x, 1 if predicted["player"] != null else 0])
	_cl_shots += 1
