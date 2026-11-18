extends Node
## Teste das hitboxes e da detecção de tiro numa partida de verdade (Treino
## adaptativo, sem rede): o host atira de rifle em bots que o teste posiciona
## e confere o dano que o servidor confirma (cabeça, pernas, rente ao tronco,
## alvo correndo e agachado). Não grava nada.
##   godot --headless --path . res://tests/hitbox_test.tscn

const DISTANCE: float = 8.0
const RUN_SPEED: float = 7.0

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _host: FPSPlayer
var _bot: FPSPlayer
## [dano, cabeça] de cada acerto confirmado pelo servidor.
var _hits: Array = []
## Alvo correndo: posição e velocidade (movido a cada quadro de física).
var _running: bool = false
var _run_position: Vector3
var _fire_on_frame: int = -1
var _frame: int = 0


func _ready() -> void:
	Progress.persistent = false
	Progress.profile = PlayerProfile.new()
	Habits.persistent = false
	Habits.profile = PlayerHabits.new()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame
	_main.call("_start_training", 2)
	NetworkManager.damage_dealt.connect(func(amount: int, _at: Vector3, headshot: bool, _killed: bool) -> void:
		_hits.append([amount, headshot]))
	await _wait(0.3)
	_host = _main.get_node("Players/1")
	_bot = _main.get_node("Players/1000")
	for node in _main.get_node("Players").get_children():
		(node as FPSPlayer).set_physics_process(false)
	_main.get_node("Players/1001").global_position = Vector3(0, -50, 0)
	await _wait(NetworkManager.RULES.spawn_protection + 0.3)

	var rifle := _host.weapon_data(0)
	_check(rifle.id == "rifle" and rifle.base_spread == 0.0, "host de rifle (sem dispersão inicial)")
	var spot := _host.global_position + Vector3(0, 0, -DISTANCE)

	# 1) Cabeça.
	await _place(spot, false)
	await _shoot_at(spot + Vector3(0, 1.62, 0))
	_check(_last() == [rifle.head_damage, true], "tiro na cabeça: %s" % [_last()])

	# 2) Pernas: 75% do dano do corpo.
	await _shoot_at(spot + Vector3(0, 0.5, 0))
	_check(_last() == [roundi(rifle.body_damage * NetworkManager.RULES.leg_damage_ratio), false], "tiro nas pernas: %s" % [_last()])

	# 3) Rente ao tronco (42 cm do centro): a cápsula antiga contava, o boneco não.
	var before := _hits.size()
	await _shoot_at(spot + Vector3(0.42, 1.15, 0))
	_check(_hits.size() == before, "tiro rente ao tronco erra (%d acertos novos)" % (_hits.size() - before))

	# 4) Alvo correndo de lado: o host o vê no presente, então o tiro na
	# posição atual tem que acertar (antes o servidor voltava 100 ms e errava).
	before = _hits.size()
	_run_position = spot + Vector3(-3, 0, 0)
	_running = true
	_fire_on_frame = _frame + 20
	await _wait(0.6)
	_running = false
	_check(_hits.size() == before + 1, "alvo correndo a %d m/s: acerto (%d)" % [roundi(RUN_SPEED), _hits.size() - before])

	# 5) Agachado: a cabeça desce.
	await _place(spot, true)
	before = _hits.size()
	await _shoot_at(spot + Vector3(0, 1.66, 0))
	_check(_hits.size() == before, "agachado: altura da cabeça em pé erra")
	await _shoot_at(spot + Vector3(0, 1.08, 0))
	_check(_last() == [rifle.head_damage, true], "agachado: tiro na cabeça mais baixa: %s" % [_last()])

	print("%d verificações, %d falha(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _physics_process(delta: float) -> void:
	_frame += 1
	if not _running:
		return
	_run_position += Vector3(RUN_SPEED * delta, 0, 0)
	_bot.global_position = _run_position
	_bot.net_position = _run_position
	if _frame == _fire_on_frame:
		_aim(_run_position + Vector3(0, 1.15, 0))
		_fire()


func _place(position: Vector3, crouched: bool) -> void:
	_bot.global_position = position
	_bot.rotation.y = 0.0
	_bot.net_yaw = 0.0
	_bot.net_crouch = crouched
	_bot.net_position = position
	await _wait(0.1)
	_bot.net_position = position


func _shoot_at(point: Vector3) -> void:
	_aim(point)
	_fire()
	await _wait(0.1)


func _aim(point: Vector3) -> void:
	var to := point - _host.eye_position()
	_host.rotation.y = atan2(-to.x, -to.z)
	_host.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _fire() -> void:
	_host.set("_cooldown", 0.0)
	_host.set("_spread", 0.0)
	_host.ammo[0] = 12
	_host.set("_sv_last_shot_msec", -100000)
	_host.call("_try_shoot")


func _last() -> Array:
	return _hits[-1] if not _hits.is_empty() else []


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALHOU: " + label)
	else:
		print("ok: " + label)
