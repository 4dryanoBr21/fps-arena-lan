extends Node
## Teste da faca numa partida de verdade (Treino adaptativo, sem rede): os
## bots ficam parados onde o teste manda e o jogador golpeia. Confere o golpe
## pelas costas (mata), de frente (55 de dano), fora do alcance e através da
## parede (nada), e os números de dano que chegam a quem golpeou. Não grava
## nada: progresso e hábitos ficam só em memória.
##   godot --headless --path . res://tests/knife_test.tscn

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _host: FPSPlayer
var _bots: Array[FPSPlayer] = []
## [dano, cabeça, abate] de cada número de dano recebido.
var _numbers: Array = []


func _ready() -> void:
	Progress.persistent = false
	Progress.profile = PlayerProfile.new()
	Habits.persistent = false
	Habits.profile = PlayerHabits.new()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame
	_main.call("_start_training", 2)
	NetworkManager.damage_dealt.connect(func(amount: int, _at: Vector3, headshot: bool, killed: bool) -> void:
		_numbers.append([amount, headshot, killed]))
	await _wait(0.3)
	_host = _main.get_node("Players/1")
	for id in [1000, 1001]:
		var bot := _main.get_node("Players/%d" % id) as FPSPlayer
		# Parado: sem IA nem física (o servidor ainda aceita o dano).
		bot.set_physics_process(false)
		_bots.append(bot)
	_host.set_physics_process(false)
	# Espera a proteção ao renascer acabar.
	await _wait(RULES().spawn_protection + 0.3)

	var knife := RULES().weapon_by_id(RULES().default_melee)
	var forward := Vector3(0, 0, -1)
	_host.rotation.y = 0.0
	_host.head.rotation.x = 0.0
	_host.select_weapon(2)
	_check(_host.weapon_data().melee, "jogador puxou a faca")

	# 1) Pelas costas: o bot olha para o mesmo lado que o jogador.
	# Jogador machucado (20 de vida) para conferir a cura por abate.
	_host._sync_health.rpc(20)
	var heals: Array[int] = []
	_host.kill_healed.connect(func(amount: int) -> void: heals.append(amount))
	var victim := _bots[0]
	await _place(victim, _host.global_position + forward * 1.4, 0.0)
	await _slash()
	_check(not victim.alive, "pelas costas mata (vida %d de %d)" % [victim.health, victim.max_health()])
	var expected := RULES().health_after_kill(20, _host.max_health())
	_check(_host.health == expected and heals == [expected - 20],
		"abate cura o jogador: vida %d (esperado %d), avisos %s" % [_host.health, expected, heals])
	_check(_numbers.size() == 1 and _numbers[0] == [knife.backstab_damage, false, true],
		"número de dano do golpe pelas costas: %s" % [_numbers])
	var shown: Array = Fx.get("_numbers").filter(func(label: Label3D) -> bool: return label.visible)
	_check(shown.size() == 1 and shown[0].text == str(knife.backstab_damage), "número aparece sobre o inimigo")

	# 2) De frente: o bot olha para o jogador.
	var front := _bots[1]
	await _place(front, _host.global_position + forward * 1.4, PI)
	await _slash()
	_check(front.alive and front.health == front.max_health() - knife.body_damage,
		"de frente tira %d (vida %d de %d)" % [knife.body_damage, front.health, front.max_health()])
	_check(_numbers.size() == 2 and _numbers[1] == [knife.body_damage, false, false],
		"número de dano do golpe de frente: %s" % [_numbers])

	# 3) Fora do alcance: nada acontece.
	var before := front.health
	await _place(front, _host.global_position + forward * 3.5, PI)
	await _slash()
	_check(front.health == before, "a 3,5 m a faca não alcança (vida %d)" % front.health)
	_check(_numbers.size() == 2, "golpe no ar não mostra número")

	# 4) Parede no meio: um bloco entre os dois, a 0,7 m.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	_main.get_node("World").add_child(wall)
	wall.global_position = _host.global_position + forward * 0.7 + Vector3.UP
	await _place(front, _host.global_position + forward * 1.6, 0.0)
	await _slash()
	_check(front.health == before, "a faca não atravessa a parede (vida %d)" % front.health)

	print("%d verificações, %d falha(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func RULES() -> GameRules:
	return NetworkManager.RULES


## Põe o bot no lugar e espera o histórico do servidor passar da janela de
## compensação de latência (senão o golpe "vê" a posição antiga).
func _place(bot: FPSPlayer, position: Vector3, yaw: float) -> void:
	bot.global_position = position
	bot.rotation.y = yaw
	bot.net_yaw = yaw
	bot.net_position = position
	await _wait(0.45)
	bot.net_position = position


func _slash() -> void:
	_host.set("_cooldown", 0.0)
	_host.call("_try_shoot")
	await _wait(0.1)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALHOU: " + label)
	else:
		print("ok: " + label)
