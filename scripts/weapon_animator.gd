class_name WeaponAnimator
extends Node
## Animações procedurais da arma e da câmera, sem AnimationPlayer. A pose é
## refeita a cada quadro somando camadas a partir da posição de repouso:
## balanço ao andar, respiração, atraso da arma ao virar a mira, pose de
## corrida, recarga, sacar, recuo do tiro e afundada ao aterrissar. Assim uma
## animação nunca atropela a outra (como acontecia com tweens na mesma posição).
## Jogadores remotos e bots só têm as camadas que os outros veem: tiro,
## recarga e troca de arma. Câmera (tranco do tiro, aterrissagem e agachar
## suave) só no jogador local, por cima da posição de primeira ou terceira
## pessoa que o FPSPlayer calcula. O FPSPlayer chama kick/draw/reload/land/look.

## Balanço ao andar: ciclos por metro andado e amplitude (m).
const BOB_FREQUENCY: float = 0.95
const BOB_SIDE: float = 0.012
const BOB_DROP: float = 0.016
const BOB_ROLL_DEG: float = 1.2
## Respiração parado.
const BREATH_SPEED: float = 1.7
const BREATH_AMOUNT: float = 0.0015
## Atraso da arma ao virar a mira: radianos por pixel e limite em pixels.
const SWAY_PER_PIXEL: float = 0.0016
const SWAY_LIMIT: float = 40.0
const SWAY_RETURN: float = 12.0
## Pose de corrida: arma baixa e virada para dentro.
const SPRINT_OFFSET := Vector3(-0.06, -0.05, 0.04)
const SPRINT_ROTATION_DEG := Vector3(-12.0, 35.0, 10.0)
## Corrida fica de lado por este tempo depois de um tiro.
const SHOT_HOLD_MSEC: int = 400
## Recarga: arma desce e gira; um "tapa" no meio (pente entrando).
const RELOAD_OFFSET := Vector3(-0.02, -0.09, 0.03)
const RELOAD_ROTATION_DEG := Vector3(-25.0, 10.0, 30.0)
## Sacar: a arma sobe de baixo durante o tempo da troca.
const DRAW_OFFSET := Vector3(0.0, -0.16, 0.06)
const DRAW_ROTATION_DEG: float = -40.0
## Golpe de faca: varre de um lado para o outro (alternando a cada golpe).
const SLASH_TIME: float = 0.28
const SLASH_SIDE: float = 0.14
## Recuo do tiro (multiplicado pela força da arma) e quanto dura.
const KICK_OFFSET := Vector3(0.0, 0.012, 0.06)
const KICK_ROTATION_DEG: float = 6.0
const KICK_TIME: float = 0.1
const CAMERA_PUNCH_DEG: float = 0.8
const CAMERA_PUNCH_TIME: float = 0.08
## Aterrissagem: quanto a câmera e a arma afundam e quanto dura.
const LAND_CAMERA_DROP: float = 0.06
const LAND_WEAPON_DROP: float = 0.03
const LAND_TIME: float = 0.3
const LAND_MIN_SPEED: float = 4.0
## Arma vista de fora (outros jogadores, bots e você em terceira pessoa): na
## altura da mão, ao lado do tronco, em vez de na frente do rosto.
const BODY_REST := Vector3(0.42, -0.48, -0.3)
## Agachar: a câmera desliza até a altura nova (a colisão muda na hora).
const CROUCH_GLIDE: float = 18.0

var _player: FPSPlayer
var _rest: Vector3
var _time: float = 0.0
var _bob_time: float = 0.0
var _bob_amount: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _sprint: float = 0.0
var _kick: float = 0.0
var _kick_strength: float = 1.0
var _kick_roll: float = 0.0
var _camera_punch: float = 0.0
var _draw: float = 0.0
var _slash: float = 0.0
var _slash_side: float = 1.0
var _draw_time: float = 0.3
var _reload_start_msec: int = 0
var _reload_end_msec: int = 0
var _land: float = 0.0
var _crouch_offset: float = 0.0
var _last_shot_msec: int = -100000
var _rng := RandomNumberGenerator.new()
## Resultado das camadas deste quadro.
var _movement_offset := Vector3.ZERO
var _movement_rotation := Vector3.ZERO
var _action_offset := Vector3.ZERO
var _action_rotation := Vector3.ZERO


func setup(player: FPSPlayer) -> void:
	_player = player
	_rest = player.weapon.position


func reset() -> void:
	_bob_amount = 0.0
	_sway = Vector2.ZERO
	_sprint = 0.0
	_kick = 0.0
	_slash = 0.0
	_camera_punch = 0.0
	_draw = 0.0
	_reload_end_msec = 0
	_land = 0.0
	_crouch_offset = 0.0


## Tiro: força ~0,6 (submetralhadora) a ~2,4 (rifle de precisão).
func kick(strength: float) -> void:
	_kick = 1.0
	_kick_strength = strength
	_kick_roll = _rng.randf_range(-1.0, 1.0)
	_camera_punch = 1.0
	_last_shot_msec = Time.get_ticks_msec()


## Golpe de faca (alterna o lado a cada golpe).
func slash() -> void:
	_slash = 1.0
	_slash_side = -_slash_side
	_last_shot_msec = Time.get_ticks_msec()


## Troca de arma: a nova sobe de baixo (e uma recarga em andamento acaba).
func draw(duration: float) -> void:
	_draw = 1.0
	_draw_time = maxf(duration, 0.05)
	_reload_end_msec = 0
	_slash = 0.0


func reload(duration: float) -> void:
	_reload_start_msec = Time.get_ticks_msec()
	_reload_end_msec = _reload_start_msec + int(duration * 1000.0)


## Velocidade da queda ao tocar o chão (m/s, positiva).
func land(fall_speed: float) -> void:
	if fall_speed >= LAND_MIN_SPEED:
		_land = clampf((fall_speed - LAND_MIN_SPEED) / 8.0 + 0.4, 0.0, 1.0)


## Movimento da mira (pixels): a arma atrasa e volta.
func look(relative: Vector2) -> void:
	_sway = (_sway + relative).limit_length(SWAY_LIMIT)


## A cabeça mudou de altura (agachar): a câmera começa na altura antiga.
func crouch_changed(head_drop: float) -> void:
	if _player != null and _player.is_local_player():
		_crouch_offset += head_drop


func _process(delta: float) -> void:
	if _player == null or not _player.alive:
		return
	_time += delta
	var local := _player.is_local_player()
	_movement_offset = Vector3.ZERO
	_movement_rotation = Vector3.ZERO
	if local:
		_update_movement(delta)
	_update_actions(delta)
	var first_person := local and FPSPlayer.view_mode == FPSPlayer.ViewMode.FIRST
	_player.weapon.position = (_rest if first_person else BODY_REST) + _movement_offset + _action_offset
	_player.weapon.rotation = _movement_rotation + _action_rotation
	if local:
		_update_camera(delta)


## Camadas do próprio jogador: balanço, respiração, atraso da mira e corrida.
func _update_movement(delta: float) -> void:
	var velocity := _player.velocity
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var on_floor := _player.is_on_floor()
	var target_bob := clampf(flat_speed / NetworkManager.RULES.walk_speed, 0.0, 1.5) if on_floor else 0.0
	_bob_amount = move_toward(_bob_amount, target_bob, delta * 6.0)
	if on_floor:
		_bob_time += delta * flat_speed * BOB_FREQUENCY * PI
	var bob := Vector3(sin(_bob_time) * BOB_SIDE, -absf(sin(_bob_time)) * BOB_DROP, 0.0) * _bob_amount
	var breath := Vector3(sin(_time * BREATH_SPEED * 0.5), sin(_time * BREATH_SPEED), 0.0) * BREATH_AMOUNT
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-delta * SWAY_RETURN))

	var sprinting := _player.is_sprinting() and Time.get_ticks_msec() - _last_shot_msec > SHOT_HOLD_MSEC \
		and _reload_end_msec == 0
	_sprint = move_toward(_sprint, 1.0 if sprinting else 0.0, delta * 7.0)

	_movement_offset = bob + breath + Vector3(-_sway.x * 0.0004, 0.0, 0.0) + SPRINT_OFFSET * _sprint
	_movement_rotation = Vector3(_sway.y * SWAY_PER_PIXEL, _sway.x * SWAY_PER_PIXEL,
		sin(_bob_time) * deg_to_rad(BOB_ROLL_DEG) * _bob_amount) + _deg(SPRINT_ROTATION_DEG) * _sprint


## Camadas que todos veem: recarga, sacar, recuo e aterrissagem.
func _update_actions(delta: float) -> void:
	_action_offset = Vector3.ZERO
	_action_rotation = Vector3.ZERO
	var now := Time.get_ticks_msec()
	if _reload_end_msec > 0:
		if now >= _reload_end_msec:
			_reload_end_msec = 0
		else:
			var progress := float(now - _reload_start_msec) / maxf(_reload_end_msec - _reload_start_msec, 1)
			var amount := smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.8, 1.0, progress))
			var slap := exp(-pow((progress - 0.55) / 0.05, 2.0))
			_action_offset += RELOAD_OFFSET * amount + Vector3(0.0, 0.015, 0.0) * slap
			_action_rotation += _deg(RELOAD_ROTATION_DEG) * amount

	_draw = move_toward(_draw, 0.0, delta / _draw_time)
	var draw_amount := _draw * _draw
	_action_offset += DRAW_OFFSET * draw_amount
	_action_rotation.x += deg_to_rad(DRAW_ROTATION_DEG) * draw_amount

	_kick = move_toward(_kick, 0.0, delta / (KICK_TIME * clampf(_kick_strength, 1.0, 2.0)))
	var kick_amount := _kick * _kick_strength
	_action_offset += KICK_OFFSET * kick_amount
	_action_rotation += Vector3(deg_to_rad(KICK_ROTATION_DEG), 0.0, deg_to_rad(2.0) * _kick_roll) * kick_amount

	_slash = move_toward(_slash, 0.0, delta / SLASH_TIME)
	if _slash > 0.0:
		# p vai de 0 a 1: a lâmina atravessa a tela e volta ao repouso.
		var p := 1.0 - _slash
		var sweep := ease(p, 0.4) * 2.0 - 1.0
		var reach := sin(PI * p)
		_action_offset += Vector3(-sweep * SLASH_SIDE * _slash_side, 0.03 * reach, -0.12 * reach)
		_action_rotation += Vector3(-0.3 * reach, sweep * 0.9 * _slash_side, -sweep * 0.8 * _slash_side) * reach

	_land = move_toward(_land, 0.0, delta / LAND_TIME)
	_action_offset.y -= LAND_WEAPON_DROP * _land_curve()


func _update_camera(delta: float) -> void:
	_camera_punch = move_toward(_camera_punch, 0.0, delta / CAMERA_PUNCH_TIME)
	_crouch_offset = lerpf(_crouch_offset, 0.0, 1.0 - exp(-delta * CROUCH_GLIDE))
	# Base: primeira pessoa (identidade) ou terceira pessoa (atrás / de frente).
	var view := _player.view_camera_transform()
	var punch := Basis(Vector3.RIGHT, deg_to_rad(CAMERA_PUNCH_DEG) * _kick_strength * _camera_punch)
	var lift := Vector3(0.0, _crouch_offset - LAND_CAMERA_DROP * _land_curve(), 0.0)
	_player.camera.transform = Transform3D(view.basis * punch, view.origin + lift)


## Afunda e volta: 0 no toque, máximo no meio, 0 no fim.
func _land_curve() -> float:
	return 4.0 * _land * (1.0 - _land)


static func _deg(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
