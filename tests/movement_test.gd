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
				_finish()


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
