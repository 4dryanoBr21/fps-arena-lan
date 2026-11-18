extends Node3D
## Teste da movimentação com física de verdade: um jogador local num chão
## plano, dirigido pelo GameInput (caminho do toque, funciona sem janela).
## Confere que andar e parar são instantâneos no chão e a altura do pulo.
## Roda como cena (com os autoloads), e não com --script:
##   godot --headless --path . res://tests/movement_test.tscn

const RULES: GameRules = preload("res://data/game_rules.tres")
## A borda mais alta que dá para subir pulando nos mapas.
const HIGHEST_LEDGE: float = 1.5

var _failures: int = 0
var _checks: int = 0
var _player: FPSPlayer
var _frame: int = 0
var _phase: String = "settle"
var _phase_start: int = 0
var _start_y: float = 0.0
var _apex: float = 0.0
var _air_frames: int = 0


func _ready() -> void:
	GameInput.touch = true
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	_player.name = "1"
	add_child(_player)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame > 600:
		_check(false, "tempo esgotado na fase " + _phase)
		_finish()
		return
	var flat := Vector2(_player.velocity.x, _player.velocity.z).length()
	match _phase:
		"settle":
			GameInput.capture()
			if _frame > 30 and _player.is_on_floor():
				# De lado: velocidade de andar (todo para a frente, no toque, corre).
				GameInput.move = Vector2(1.0, 0.0)
				_next("walk")
		"walk":
			# Um quadro depois de apertar já está na velocidade cheia.
			if _frame == _phase_start + 1:
				_check(absf(flat - RULES.walk_speed) < 0.01, "andar é instantâneo (%.2f m/s)" % flat)
				GameInput.move = Vector2(-1.0, 0.0)
				_next("reverse")
		"reverse":
			if _frame == _phase_start + 1:
				var lateral := _player.velocity.dot(_player.global_basis.x)
				_check(absf(lateral + RULES.walk_speed) < 0.01, "inverter o lado é instantâneo (%.2f m/s)" % lateral)
				GameInput.move = Vector2(0.0, -1.0)
				_next("sprint")
		"sprint":
			if _frame == _phase_start + 1:
				_check(absf(flat - RULES.sprint_speed) < 0.01, "correr é instantâneo (%.2f m/s)" % flat)
				# Faca na mão: andando de lado, mais rápido que com arma.
				_player.select_weapon(2)
				GameInput.move = Vector2(1.0, 0.0)
				_next("knife")
		"knife":
			if _frame == _phase_start + 1:
				var knife := RULES.weapon_by_id(RULES.default_melee)
				var expected := RULES.walk_speed * knife.move_speed_multiplier
				_check(_player.weapon_data().melee and absf(flat - expected) < 0.01, "faca anda mais rápido (%.2f m/s, esperado %.2f)" % [flat, expected])
				_player.select_weapon(0)
				GameInput.move = Vector2(1.0, 0.0)
				_next("gun_again")
		"gun_again":
			if _frame == _phase_start + 1:
				_check(absf(flat - RULES.walk_speed) < 0.01, "de volta à arma, velocidade normal (%.2f m/s)" % flat)
				GameInput.move = Vector2.ZERO
				_next("stop")
		"stop":
			if _frame == _phase_start + 1:
				_check(flat < 0.01, "parar é instantâneo (%.2f m/s)" % flat)
				_start_y = _player.global_position.y
				GameInput.jump_pressed = true
				_next("jump")
		"jump":
			_apex = maxf(_apex, _player.global_position.y - _start_y)
			if not _player.is_on_floor():
				_air_frames += 1
			elif _frame > _phase_start + 5:
				var air_time := _air_frames / float(Engine.physics_ticks_per_second)
				_check(_apex > HIGHEST_LEDGE + 0.1, "pulo passa a borda de %.1f m (%.2f m)" % [HIGHEST_LEDGE, _apex])
				_check(_apex < 1.9, "pulo não ficou mais alto que antes (%.2f m)" % _apex)
				_check(air_time < 1.0, "pulo curto no ar (%.2f s)" % air_time)
				_next("third_person")
				_third_person_then_finish()


func _third_person_then_finish() -> void:
	await _test_third_person()
	_finish()


## Terceira pessoa: câmera atrás, encosta na parede, de frente e de volta.
func _test_third_person() -> void:
	_check(FPSPlayer.view_mode == FPSPlayer.ViewMode.FIRST and not _player.visual.visible, "começa em primeira pessoa sem o próprio corpo")
	_player.cycle_view()
	var back := _player.view_camera_transform()
	_check(FPSPlayer.view_mode == FPSPlayer.ViewMode.BACK and _player.visual.visible, "F5: câmera atrás e corpo visível")
	_check(absf(back.origin.z - FPSPlayer.THIRD_PERSON_DISTANCE) < 0.01 and back.origin.y > 0.0, "câmera atrás e acima da cabeça (%s)" % back.origin)
	# O centro da tela cruza a linha do tiro na distância de convergência.
	var center_ray := back * Vector3(0, 0, -(FPSPlayer.THIRD_PERSON_DISTANCE + FPSPlayer.THIRD_PERSON_CONVERGE))
	_check(absf(center_ray.y) < 0.05 and absf(center_ray.x) < 0.01, "mira da câmera de trás encontra a linha do tiro (%s)" % center_ray)

	# Parede logo atrás do jogador: a câmera encosta nela em vez de atravessar.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.3)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = _player.head.global_position + _player.head.global_basis.z * 1.5
	# Física precisa de um passo para registrar a parede nova.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blocked := _player.view_camera_transform()
	# Face da parede virada para o jogador, na mesma referência da câmera (cabeça).
	var face := (_player.head.global_transform.affine_inverse() * wall.global_position).z - box.size.z * 0.5
	_check(blocked.origin.z < FPSPlayer.THIRD_PERSON_DISTANCE - 0.5 and blocked.origin.z < face,
		"câmera encosta antes da parede (câmera z = %.2f, parede z = %.2f)" % [blocked.origin.z, face])
	wall.queue_free()

	_player.cycle_view()
	var front := _player.view_camera_transform()
	_check(FPSPlayer.view_mode == FPSPlayer.ViewMode.FRONT and front.origin.z < -1.0, "segundo F5: câmera de frente (%s)" % front.origin)
	_check((front.basis * Vector3.FORWARD).z > 0.9, "câmera de frente olha para o jogador")
	_player.cycle_view()
	_check(FPSPlayer.view_mode == FPSPlayer.ViewMode.FIRST and not _player.visual.visible \
		and _player.view_camera_transform() == Transform3D.IDENTITY, "terceiro F5: volta à primeira pessoa")


func _finish() -> void:
	print("%d verificações, %d falha(s)" % [_checks, _failures])
	set_physics_process(false)
	get_tree().quit(1 if _failures > 0 else 0)


func _next(phase: String) -> void:
	_phase = phase
	_phase_start = _frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALHOU: " + label)
	else:
		print("ok: " + label)
