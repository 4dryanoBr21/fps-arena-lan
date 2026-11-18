class_name FPSPlayer
extends CharacterBody3D
## Controlador FPS. Quem controla o corpo (o peer dono, ou o servidor no caso
## de bot) move e escreve o estado net_*; os outros recebem pelo
## MultiplayerSynchronizer e interpolam com um atraso de INTERP_DELAY_MSEC.
## O servidor confere movimento, cadência e munição e decide os acertos
## refazendo o tiro nas posições de alguns milissegundos atrás (compensação
## de latência). Vida, morte e respawn são replicados por RPC.
## As armas e o equipamento vêm do Arsenal: o servidor confere e espalha a
## lista (NetworkManager.loadouts) junto com o placar; cada peer aplica aqui.

signal health_changed(health: int, max_health: int, damaged: bool)
signal died(killer_id: int)
signal respawned
signal ammo_changed(ammo: int, magazine: int, reloading: bool)
signal weapon_changed(weapon: WeaponData)
signal damaged_from(world_position: Vector3)
## Jogador local trocou a câmera (primeira pessoa, atrás, de frente).
signal view_changed(mode: int)

## Câmera do jogador local (F5, como no Minecraft).
enum ViewMode { FIRST, BACK, FRONT }

const RULES: GameRules = preload("res://data/game_rules.tres")
## No chão a velocidade muda na hora (sem aceleração nem deslize). No ar o
## controle é parcial, mas rápido: m/s ganhos ou perdidos por segundo.
const AIR_ACCELERATION: float = 30.0
const MOUSE_SENSITIVITY: float = 0.0025
## Radianos por pixel de arraste na tela (celular).
const TOUCH_SENSITIVITY: float = 0.006
const MAX_PITCH_DEG: float = 85.0
const FALL_LIMIT_Y: float = -20.0
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.2
const EYE_BELOW_TOP: float = 0.2
const SWITCH_TIME: float = 0.3
const BAR_WIDTH: float = 0.9
const BAR_HEIGHT: float = 0.09

## Interpolação dos remotos e histórico do servidor para compensar latência.
const INTERP_DELAY_MSEC: int = 100
const HISTORY_MSEC: int = 1000
const MAX_REWIND_MSEC: int = 300
## Folgas das conferências do servidor.
const ORIGIN_TOLERANCE: float = 1.5
const COOLDOWN_TOLERANCE: float = 0.8
const RELOAD_TOLERANCE: float = 0.9
const MOVE_TOLERANCE: float = 1.0
const CORRECTION_GRACE_MSEC: int = 500
const TELEPORT_GRACE_MSEC: int = 1000
## Faca: o golpe é mais "largo" que a bala (folga somada às hitboxes).
const MELEE_HIT_RADIUS_BONUS: float = 0.3
## Bits do hit_mask de um golpe: acertou algo / acertou um jogador.
const MELEE_HIT_ANY: int = 1
const MELEE_HIT_PLAYER: int = 2
## Distância a partir da qual a interpolação desiste e pula direto (teleporte).
const SNAP_DISTANCE: float = 5.0

## Terceira pessoa: distância e altura da câmera, e onde o centro da tela
## encontra a linha do tiro (a câmera de trás inclina um pouco para baixo).
const THIRD_PERSON_DISTANCE: float = 3.2
const THIRD_PERSON_UP: float = 0.35
const THIRD_PERSON_CONVERGE: float = 25.0
## Folga entre a câmera e a parede que ela encosta.
const CAMERA_WALL_MARGIN: float = 0.2

## Assistência de mira (só toque): desacelera a mira perto de um inimigo.
const AIM_ASSIST_ANGLE_DEG: float = 6.0
const AIM_ASSIST_RANGE: float = 60.0
const AIM_ASSIST_SLOWDOWN: float = 0.55

## Estado sincronizado, escrito por quem controla o corpo.
var net_position: Vector3 = Vector3.ZERO: set = _set_net_position
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_crouch: bool = false: set = _set_net_crouch
var net_weapon: int = 0: set = _set_net_weapon

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health: int = RULES.max_health
var alive: bool = true
var protected: bool = false
var is_bot: bool = false
## [principal, secundária, faca], já com as melhorias aplicadas.
var weapons: Array[WeaponData] = []
var equipment: EquipmentData
var weapon_index: int = 0
## Munição por arma, prevista localmente por quem controla o corpo.
var ammo: Array[int] = []

## Vale para a sessão inteira (o nó do jogador é recriado a cada partida).
static var view_mode: ViewMode = ViewMode.FIRST

var _animator: WeaponAnimator
## Quem controla o corpo: correndo de verdade neste quadro (pose de corrida).
var _sprinting: bool = false
var _cooldown: float = 0.0
var _spread: float = 0.0
var _reload_until_msec: int = 0
var _crouching: bool = false
var _rng := RandomNumberGenerator.new()
var _loadout: Dictionary = {}
var _bot_brain: BotBrain
var _health_bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_fill_mesh: QuadMesh
var _bar_fill_mat: StandardMaterial3D
var _body_materials: Array[StandardMaterial3D] = []
## Remotos: [msec de chegada, posição, yaw, pitch].
var _snapshots: Array = []

## Só no servidor.
var _sv_ammo: Array[int] = []
var _sv_weapon: int = 0
var _sv_reload_until_msec: int = 0
var _sv_last_shot_msec: int = -100000
var _sv_last_move_msec: int = 0
var _sv_grace_until_msec: int = 0
var _sv_protected_until_msec: int = 0
## [[msec, posição, yaw, agachado], ...] do mais antigo para o mais novo.
var _sv_history: Array = []

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: Node3D = $Visual
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Node3D = $Head/Weapon
@onready var muzzle: Marker3D = $Head/Weapon/Muzzle
@onready var weapon_model: MeshInstance3D = $Head/Weapon/Model
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer


func _enter_tree() -> void:
	# O nome do nó é o peer_id do dono (definido pelo servidor antes do spawn);
	# bots usam ids reservados e quem os controla é o servidor.
	var id := name.to_int()
	is_bot = NetworkManager.is_bot_id(id)
	set_multiplayer_authority(1 if is_bot else id)


func _ready() -> void:
	add_to_group("players")
	_rng.seed = hash(name) ^ Time.get_ticks_usec()
	# A cápsula vem compartilhada da cena; agachar muda a altura só deste jogador.
	collision_shape.shape = collision_shape.shape.duplicate()
	_apply_loadout(NetworkManager.get_loadout(name.to_int()))
	health = max_health()
	# Quem entrou depois pode criar este nó antes de a lista chegar.
	NetworkManager.scores_changed.connect(_refresh_loadout)
	_animator = WeaponAnimator.new()
	_animator.name = "WeaponAnimator"
	add_child(_animator)
	_animator.setup(self)

	var is_local := is_local_player()
	visual.visible = _body_visible(true)
	camera.current = is_local
	_apply_player_color()
	_apply_weapon_visual(net_weapon)
	_apply_crouch_shape(net_crouch)

	if is_multiplayer_authority():
		net_position = global_position
	else:
		global_position = net_position
		rotation.y = net_yaw
		head.rotation.x = net_pitch
		synchronizer.synchronized.connect(_on_synchronized)

	if is_local:
		GameInput.capture()
		Settings.changed.connect(_apply_settings)
		_apply_settings()
		request_spawn.rpc_id(1)
	else:
		_build_health_bar()
	if is_bot and multiplayer.is_server():
		_bot_brain = BotBrain.new()
		add_child(_bot_brain)
		_teleport_to(NetworkManager.get_spawn_position_for(name.to_int()))
		# Espera o spawn chegar aos clientes antes de mandar RPCs deste nó.
		get_tree().create_timer(0.2).timeout.connect(_server_spawn_protection)


## Jogador humano deste computador (não vale para bot no host).
func is_local_player() -> bool:
	return is_multiplayer_authority() and not is_bot


func weapon_data(index: int = weapon_index) -> WeaponData:
	return weapons[index]


func max_health() -> int:
	return RULES.max_health + (equipment.bonus_health if equipment != null else 0)


## Equipamento x arma na mão (a faca é mais leve que as armas de fogo).
func speed_multiplier() -> float:
	var gear := equipment.speed_multiplier if equipment != null else 1.0
	var held := weapons[weapon_index].move_speed_multiplier if weapon_index < weapons.size() else 1.0
	return gear * held


## Só no servidor: a maior velocidade possível com este equipamento (a troca
## de arma chega por RPC e pode atrasar em relação ao movimento).
func max_speed_multiplier() -> float:
	var held := 1.0
	for weapon_item in weapons:
		held = maxf(held, weapon_item.move_speed_multiplier)
	return (equipment.speed_multiplier if equipment != null else 1.0) * held


func body_height() -> float:
	return CROUCH_HEIGHT if net_crouch else STAND_HEIGHT


func eye_position() -> Vector3:
	return head.global_position


func is_sprinting() -> bool:
	return _sprinting


func is_reloading() -> bool:
	return _reload_until_msec > 0


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player() or not alive or not GameInput.is_active():
		return
	# No celular o toque também gera eventos de mouse emulados; quem cuida
	# do toque é o TouchControls.
	if GameInput.touch:
		return

	if event is InputEventMouseMotion:
		_rotate_view((event as InputEventMouseMotion).relative, MOUSE_SENSITIVITY * Settings.mouse_sensitivity)
	elif event.is_action_pressed("shoot"):
		_try_shoot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("weapon_1"):
		select_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		select_weapon(1)
	elif event.is_action_pressed("weapon_3"):
		select_weapon(2)
	elif event.is_action_pressed("toggle_view"):
		cycle_view()
	elif event.is_action_pressed("next_weapon"):
		select_weapon((weapon_index + 1) % weapons.size())


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		_interpolate_remote()
	elif is_local_player() and GameInput.touch:
		_process_touch(delta)


## Celular: mira, giroscópio, botões e tiro contínuo.
func _process_touch(delta: float) -> void:
	var look := GameInput.consume_look()
	if not alive or not GameInput.is_active():
		return
	var sensitivity := TOUCH_SENSITIVITY * Settings.touch_sensitivity
	if look != Vector2.ZERO:
		if Settings.aim_assist and _enemy_near_crosshair():
			sensitivity *= AIM_ASSIST_SLOWDOWN
		_rotate_view(look, sensitivity)
	if Settings.gyro_aim:
		_apply_gyro(delta)
	if GameInput.consume_reload():
		start_reload()
	if GameInput.consume_view():
		cycle_view()
	if GameInput.consume_switch_weapon():
		select_weapon((weapon_index + 1) % weapons.size())
	# Segurar o botão atira sem parar (o cooldown limita a cadência).
	if GameInput.fire_held:
		_try_shoot()


# --- Câmera em primeira / terceira pessoa ---------------------------------------

## Primeira pessoa -> atrás -> de frente -> primeira pessoa.
func cycle_view() -> void:
	view_mode = ((view_mode + 1) % ViewMode.size()) as ViewMode
	visual.visible = _body_visible(alive)
	view_changed.emit(view_mode)


## O próprio corpo só aparece para quem está em terceira pessoa.
func _body_visible(is_alive: bool) -> bool:
	return is_alive and (not is_local_player() or view_mode != ViewMode.FIRST)


## Onde a câmera fica, relativa à cabeça (o animador soma os efeitos). Em
## terceira pessoa ela encosta antes de atravessar uma parede.
func view_camera_transform() -> Transform3D:
	if view_mode == ViewMode.FIRST or not is_local_player():
		return Transform3D.IDENTITY
	var front := view_mode == ViewMode.FRONT
	var offset := Vector3(0.0, THIRD_PERSON_UP, -THIRD_PERSON_DISTANCE if front else THIRD_PERSON_DISTANCE)
	var from := head.global_position
	var query := PhysicsRayQueryParameters3D.create(from, head.global_transform * offset)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var wall: Vector3 = hit["position"]
		offset = head.global_transform.affine_inverse() * (wall + (from - wall).normalized() * CAMERA_WALL_MARGIN)
	var basis := Basis(Vector3.UP, PI) if front \
		else Basis(Vector3.RIGHT, -atan2(THIRD_PERSON_UP, THIRD_PERSON_DISTANCE + THIRD_PERSON_CONVERGE))
	return Transform3D(basis, offset)


func _rotate_view(relative: Vector2, sensitivity: float) -> void:
	_animator.look(relative)
	var pitch_sign := -1.0 if Settings.invert_y else 1.0
	rotate_y(-relative.x * sensitivity)
	var max_pitch := deg_to_rad(MAX_PITCH_DEG)
	head.rotation.x = clampf(head.rotation.x - relative.y * sensitivity * pitch_sign, -max_pitch, max_pitch)


## Celular deitado: girar o aparelho em volta do eixo vertical vira a mira;
## inclinar para trás olha para cima.
func _apply_gyro(delta: float) -> void:
	var rate := Input.get_gyroscope()
	var orientation_sign := -1.0 if DisplayServer.screen_get_orientation() == DisplayServer.SCREEN_REVERSE_LANDSCAPE else 1.0
	var pitch_sign := -1.0 if Settings.invert_y else 1.0
	rotate_y(rate.x * orientation_sign * delta * Settings.touch_sensitivity)
	var max_pitch := deg_to_rad(MAX_PITCH_DEG)
	head.rotation.x = clampf(head.rotation.x + rate.y * orientation_sign * pitch_sign * delta * Settings.touch_sensitivity,
		-max_pitch, max_pitch)


func _enemy_near_crosshair() -> bool:
	var eye := eye_position()
	var forward := -head.global_basis.z
	var max_angle := deg_to_rad(AIM_ASSIST_ANGLE_DEG)
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as FPSPlayer
		if other == null or other == self or not other.alive:
			continue
		var to := other.global_position + Vector3.UP * other.body_height() * 0.6 - eye
		if to.length() < AIM_ASSIST_RANGE and forward.angle_to(to) < max_angle:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or not alive:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_spread = maxf(_spread - weapon_data().spread_recovery * delta, 0.0)
	_update_reload()

	var move := Vector2.ZERO
	var wants_jump := false
	var wants_sprint := false
	var wants_crouch := false
	if is_bot:
		_bot_brain.think(delta)
		move = _bot_brain.move
		wants_jump = _bot_brain.jump
		wants_sprint = _bot_brain.sprint
		wants_crouch = _bot_brain.crouch
		if _bot_brain.weapon != weapon_index:
			select_weapon(_bot_brain.weapon)
	else:
		wants_jump = GameInput.consume_jump() or Input.is_action_just_pressed("jump")
		if GameInput.is_active():
			move = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
			move = (move + GameInput.move).limit_length(1.0)
			# No toque, joystick todo para a frente corre.
			wants_sprint = Input.is_action_pressed("sprint") \
				or GameInput.move.y < -0.7 and GameInput.move.length() > 0.95
			wants_crouch = Input.is_action_pressed("crouch") or GameInput.crouch_toggled
		else:
			wants_jump = false
	_set_crouching(wants_crouch)

	if not is_on_floor():
		velocity.y -= gravity * RULES.gravity_scale * delta
	if wants_jump and is_on_floor() and not _crouching:
		velocity.y = RULES.jump_velocity

	var speed := RULES.walk_speed
	if _crouching:
		speed = RULES.crouch_speed
	elif wants_sprint and move.y < 0.0:
		speed = RULES.sprint_speed
	speed *= speed_multiplier()
	var direction := transform.basis * Vector3(move.x, 0.0, move.y)
	var target_velocity := direction * speed
	if is_on_floor():
		velocity.x = target_velocity.x
		velocity.z = target_velocity.z
	else:
		velocity.x = move_toward(velocity.x, target_velocity.x, AIR_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, AIR_ACCELERATION * delta)

	var was_on_floor := is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor():
		_animator.land(fall_speed)
	_sprinting = is_on_floor() and speed > RULES.walk_speed * speed_multiplier() \
		and Vector2(velocity.x, velocity.z).length() > RULES.walk_speed * 0.5

	if global_position.y < FALL_LIMIT_Y:
		_request_new_spawn()
	# Yaw antes da posição: o histórico do servidor é gravado junto com ela.
	net_yaw = rotation.y
	net_pitch = head.rotation.x
	net_position = global_position

	if is_bot and _bot_brain.fire:
		_try_shoot()


func _apply_settings() -> void:
	camera.fov = Settings.fov


# --- Agachar -----------------------------------------------------------------

func _set_crouching(value: bool) -> void:
	if value == _crouching:
		return
	# Não levanta se tiver teto em cima.
	if not value and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT)):
		return
	_crouching = value
	net_crouch = value


func _apply_crouch_shape(crouched: bool) -> void:
	if collision_shape == null:
		return
	var height := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = height
	collision_shape.position.y = height * 0.5
	var old_eye := head.position.y
	head.position.y = height - EYE_BELOW_TOP
	if _animator != null:
		# A câmera desliza até a altura nova (a colisão já mudou).
		_animator.crouch_changed(old_eye - head.position.y)
	visual.scale.y = height / STAND_HEIGHT


func _set_net_crouch(value: bool) -> void:
	net_crouch = value
	if is_inside_tree():
		_apply_crouch_shape(value)


# --- Armas, munição e recarga -------------------------------------------------

func _refresh_loadout() -> void:
	# Lista vazia = saindo da partida (leave_game limpa antes de remover os nós).
	if NetworkManager.loadouts.is_empty():
		return
	var loadout := NetworkManager.get_loadout(name.to_int())
	if loadout != _loadout:
		_apply_loadout(loadout)


## Troca armas e equipamento e enche os pentes.
func _apply_loadout(loadout: Dictionary) -> void:
	_loadout = loadout
	var clean := RULES.sanitize_loadout(loadout)
	weapons = [
		RULES.weapon_by_id(clean["primary"]).upgraded(clean["primary_tier"], RULES),
		RULES.weapon_by_id(clean["secondary"]).upgraded(clean["secondary_tier"], RULES),
		RULES.weapon_by_id(RULES.default_melee).upgraded(0, RULES),
	]
	equipment = RULES.equipment_by_id(clean["equipment"])
	ammo.clear()
	for weapon_item in weapons:
		ammo.append(weapon_item.magazine)
	_sv_ammo = ammo.duplicate()
	_apply_weapon_visual(net_weapon)
	_update_health_bar()
	if is_local_player() and is_node_ready():
		weapon_changed.emit(weapon_data())
		health_changed.emit(health, max_health(), false)
		_emit_ammo()


func select_weapon(index: int) -> void:
	if index == weapon_index or index < 0 or index >= weapons.size() or not alive:
		return
	_reload_until_msec = 0
	weapon_index = index
	_cooldown = SWITCH_TIME
	_spread = 0.0
	net_weapon = index
	# O setter de net_weapon só redesenha nos outros peers; aqui é quem controla.
	_apply_weapon_visual(index)
	_animator.draw(SWITCH_TIME)
	if is_local_player():
		Sfx.play(Sfx.EQUIP, -8.0, 0.05)
	if is_bot:
		_server_select(index)
	else:
		_server_select_weapon.rpc_id(1, index)
	weapon_changed.emit(weapon_data())
	_emit_ammo()


func start_reload() -> void:
	var w := weapon_data()
	if w.melee or is_reloading() or ammo[weapon_index] >= w.magazine or not alive:
		return
	_reload_until_msec = Time.get_ticks_msec() + int(w.reload_time * 1000.0)
	_show_reload.rpc(w.reload_time)
	if is_bot:
		_server_start_reload()
	else:
		_server_reload.rpc_id(1)
		Sfx.play(Sfx.RELOAD, -6.0)
	_emit_ammo()


## Animação de recarga para todos (só visual; a munição é conferida no servidor).
@rpc("authority", "call_local", "unreliable")
func _show_reload(duration: float) -> void:
	_animator.reload(duration)
	if not is_local_player():
		Sfx.play_at(Sfx.RELOAD, global_position + Vector3.UP, -10.0, 0.05)


func _update_reload() -> void:
	if is_reloading() and Time.get_ticks_msec() >= _reload_until_msec:
		_reload_until_msec = 0
		ammo[weapon_index] = weapon_data().magazine
		_emit_ammo()


func _emit_ammo() -> void:
	if is_local_player() and weapon_data().melee:
		ammo_changed.emit(0, 0, false)
	elif is_local_player():
		ammo_changed.emit(ammo[weapon_index], weapon_data().magazine, is_reloading())


func _set_net_weapon(value: int) -> void:
	net_weapon = clampi(value, 0, 2)
	if is_inside_tree() and not is_multiplayer_authority():
		_apply_weapon_visual(net_weapon)
		if _animator != null:
			_animator.draw(SWITCH_TIME)


func _apply_weapon_visual(index: int) -> void:
	if weapon == null or weapons.is_empty():
		return
	# Modelo low poly da arma (malha compartilhada) e a boca do cano dela.
	var id := weapons[index].id
	weapon_model.mesh = WeaponModels.mesh(id)
	weapon_model.transform = WeaponModels.hold_transform(id)
	muzzle.position = WeaponModels.muzzle(id)


# --- Tiro ----------------------------------------------------------------------

func _try_shoot() -> void:
	if _cooldown > 0.0 or is_reloading() or not alive:
		return
	var w := weapon_data()
	if w.melee:
		_try_slash(w)
		return
	if ammo[weapon_index] <= 0:
		if is_local_player():
			Sfx.play(Sfx.EMPTY, -4.0)
		_cooldown = w.fire_cooldown
		start_reload()
		return
	_cooldown = w.fire_cooldown
	ammo[weapon_index] -= 1

	var origin := eye_position()
	var forward := -head.global_basis.z
	var directions := PackedVector3Array()
	for i in w.pellets:
		directions.append(CombatMath.spread_direction(forward, w.base_spread + _spread, _rng))
	_spread = minf(_spread + w.spread_per_shot, w.max_spread)

	if is_bot:
		_server_resolve_shot(name.to_int(), origin, directions)
	else:
		_server_fire.rpc_id(1, origin, directions)

	# Efeito visual imediato, com o mesmo teste do servidor (paredes + hitboxes
	# dos jogadores como estão na tela); o dano é decidido no servidor.
	var ends := PackedVector3Array()
	var hit_mask := 0
	for i in directions.size():
		var hit := _local_hit(origin, directions[i], w.max_range, 0.0)
		ends.append(hit["end"])
		if hit["hit"]:
			hit_mask |= 1 << i
	_show_shot.rpc(muzzle.global_position, ends, hit_mask, weapon_index)

	if is_local_player():
		head.rotation.x = minf(head.rotation.x + deg_to_rad(w.recoil), deg_to_rad(MAX_PITCH_DEG))
	if ammo[weapon_index] == 0:
		start_reload()
	_emit_ammo()


## Golpe de faca: sem munição; o servidor confere alcance e dano.
func _try_slash(w: WeaponData) -> void:
	_cooldown = w.fire_cooldown
	var origin := eye_position()
	var direction := -head.global_basis.z
	if is_bot:
		_server_resolve_shot(name.to_int(), origin, PackedVector3Array([direction]))
	else:
		_server_fire.rpc_id(1, origin, PackedVector3Array([direction]))
	# Som de acerto imediato com o mesmo teste do servidor (o dano é dele).
	var hit := _local_hit(origin, direction, w.max_range, MELEE_HIT_RADIUS_BONUS)
	var hit_mask := 0
	if hit["hit"]:
		hit_mask = MELEE_HIT_ANY | (MELEE_HIT_PLAYER if hit["player"] != null else 0)
	_show_shot.rpc(hit["end"], PackedVector3Array([hit["end"]]), hit_mask, weapon_index)


## Onde o tiro para na tela de quem atira: parede/alvo pela física, ou a
## hitbox de um jogador na posição desenhada. {"end", "hit", "player"}.
func _local_hit(origin: Vector3, direction: Vector3, max_range: float, grow: float) -> Dictionary:
	var exclude: Array[RID] = []
	var others: Array[FPSPlayer] = []
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as FPSPlayer
		exclude.append(player.get_rid())
		if player != self and player.alive:
			others.append(player)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var distance := max_range if hit.is_empty() else origin.distance_to(hit["position"])
	var target: FPSPlayer = null
	for player in others:
		var body_hit := Hitboxes.ray_test(origin, direction, distance, player.global_position,
			player.rotation.y, player.body_height(), grow)
		if not body_hit.is_empty():
			distance = body_hit["distance"]
			target = player
	return {"end": origin + direction * distance, "hit": target != null or not hit.is_empty(), "player": target}


## Feedback visual replicado: recuo da arma + traços + impactos (ou o golpe da faca).
@rpc("authority", "call_local", "unreliable")
func _show_shot(from: Vector3, ends: PackedVector3Array, hit_mask: int, weapon_used: int) -> void:
	var w := weapon_data(clampi(weapon_used, 0, weapons.size() - 1))
	if w.melee:
		_show_slash(w, from, hit_mask)
		return
	_animator.kick(w.kick_strength())
	Fx.muzzle_flash(from, w.kick_strength())
	if is_local_player():
		Sfx.play(w.sound, -4.0, 0.03)
	else:
		Sfx.play_at(w.sound, from, 0.0, 0.03)
	var impact_sounds := 0
	for i in ends.size():
		Fx.tracer(from, ends[i])
		if hit_mask & (1 << i):
			Fx.impact(ends[i])
			# Um som de impacto basta para a rajada da escopeta.
			if impact_sounds < 2:
				Sfx.play_at(Sfx.IMPACT, ends[i], -6.0, 0.15)
				impact_sounds += 1


func _show_slash(w: WeaponData, point: Vector3, hit_mask: int) -> void:
	_animator.slash()
	if is_local_player():
		Sfx.play(w.sound, -6.0, 0.05)
	else:
		Sfx.play_at(w.sound, global_position + Vector3.UP * 1.4, -4.0, 0.05)
	if hit_mask & MELEE_HIT_PLAYER:
		Sfx.play_at(Sfx.KNIFE_HIT, point, -2.0, 0.08)
	elif hit_mask & MELEE_HIT_ANY:
		Sfx.play_at(Sfx.KNIFE_WALL, point, -4.0, 0.1)


## Atirador -> servidor: origem e direções de cada projétil.
@rpc("any_peer", "call_local", "reliable")
func _server_fire(origin: Vector3, directions: PackedVector3Array) -> void:
	if not multiplayer.is_server():
		return
	var shooter_id := multiplayer.get_remote_sender_id()
	if shooter_id != name.to_int():
		return
	_server_resolve_shot(shooter_id, origin, directions)


## Só no servidor: confere cadência, munição e origem e aplica o dano.
func _server_resolve_shot(shooter_id: int, origin: Vector3, directions: PackedVector3Array) -> void:
	if not alive:
		return
	var w := weapon_data(_sv_weapon)
	var now := Time.get_ticks_msec()
	if now - _sv_last_shot_msec < int(w.fire_cooldown * 1000.0 * COOLDOWN_TOLERANCE):
		return
	_server_update_reload(now)
	if directions.size() != w.pellets:
		return
	if not w.melee and (_sv_reload_until_msec > 0 or _sv_ammo[_sv_weapon] <= 0):
		return
	_sv_last_shot_msec = now
	if not w.melee:
		_sv_ammo[_sv_weapon] -= 1
	if protected:
		_set_protected.rpc(false)
	_sv_protected_until_msec = 0

	var eye := net_position + Vector3.UP * (body_height() - EYE_BELOW_TOP)
	if origin.distance_to(eye) > ORIGIN_TOLERANCE:
		origin = eye

	# Cada vítima volta no tempo o quanto o atirador a via atrasada.
	var players: Array[FPSPlayer] = []
	var states: Array = []
	var exclude: Array[RID] = []
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as FPSPlayer
		exclude.append(player.get_rid())
		if player != self and player.alive:
			players.append(player)
			states.append(player.state_at(now - _rewind_msec(shooter_id, player)))

	var space := get_world_3d().direct_space_state
	var grow := MELEE_HIT_RADIUS_BONUS if w.melee else 0.0
	var damage_by_victim: Dictionary = {}
	var headshot_victims: Dictionary = {}
	var targets_hit: Dictionary = {}
	for raw_direction in directions:
		if raw_direction.length_squared() < 0.0001:
			continue
		var direction := raw_direction.normalized()
		# Paredes e alvos pela física; jogadores pelas hitboxes do boneco.
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * w.max_range)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		var wall_distance := w.max_range if hit.is_empty() else origin.distance_to(hit["position"])

		var victim: FPSPlayer = null
		var victim_distance := wall_distance
		var part := Hitboxes.Part.NONE
		var victim_state: Array = []
		for i in players.size():
			var state: Array = states[i]
			var body_hit := Hitboxes.ray_test(origin, direction, victim_distance, state[0], state[1], state[2], grow)
			if not body_hit.is_empty():
				victim = players[i]
				victim_distance = body_hit["distance"]
				part = body_hit["part"]
				victim_state = state
		if victim != null and w.melee:
			# Faca: sem tiro na cabeça; pelas costas usa o dano de golpe pelas costas.
			var backstab := w.backstab_damage > 0 and CombatMath.is_backstab(net_position, victim_state[0], victim_state[1])
			damage_by_victim[victim] = w.backstab_damage if backstab else w.body_damage
		elif victim != null:
			var damage := w.body_damage
			if part == Hitboxes.Part.HEAD:
				damage = w.head_damage
				headshot_victims[victim] = true
			elif part == Hitboxes.Part.LEGS:
				damage = roundi(w.body_damage * RULES.leg_damage_ratio)
			damage_by_victim[victim] = int(damage_by_victim.get(victim, 0)) + damage
		elif not hit.is_empty() and hit["collider"] is ShootingTarget:
			targets_hit[hit["collider"]] = true

	if not is_bot and directions.size() > 0:
		NetworkManager.habits.observe_shot(self, origin, directions[0].normalized(), not damage_by_victim.is_empty())
	for target: ShootingTarget in targets_hit:
		target.server_hit(shooter_id)
	for victim: FPSPlayer in damage_by_victim:
		victim.server_apply_damage(shooter_id, damage_by_victim[victim], net_position, headshot_victims.has(victim))


## Quanto voltar no tempo para conferir um tiro: o quanto o atirador via a
## vítima atrasada. Um cliente vê o estado que o servidor tinha um ping inteiro
## antes (ida do estado até ele + volta do tiro) mais a interpolação dos
## remotos. O host vê no presente quem ele mesmo simula (bots e ele próprio)
## e com o atraso da interpolação os humanos remotos. Bots enxergam o presente.
func _rewind_msec(shooter_id: int, victim: FPSPlayer) -> int:
	if NetworkManager.is_bot_id(shooter_id):
		return 0
	if shooter_id == 1:
		return 0 if victim.is_multiplayer_authority() else INTERP_DELAY_MSEC
	return clampi(NetworkManager.get_peer_rtt(shooter_id) + INTERP_DELAY_MSEC, 0, MAX_REWIND_MSEC)


## Só no servidor: onde estavam os pés deste jogador no instante pedido.
func position_at(msec: int) -> Vector3:
	return CombatMath.sample_history(_sv_history, msec, net_position)


## Só no servidor: [pés, yaw, altura do corpo] no instante pedido (hitboxes).
func state_at(msec: int) -> Array:
	var entry := CombatMath.history_entry_at(_sv_history, msec)
	if entry.size() < 4:
		return [net_position, net_yaw, body_height()]
	return [position_at(msec), float(entry[2]), CROUCH_HEIGHT if bool(entry[3]) else STAND_HEIGHT]


## Só no servidor: velocidade média nos últimos 150 ms (do histórico).
func server_velocity() -> Vector3:
	var now := Time.get_ticks_msec()
	return (position_at(now) - position_at(now - 150)) / 0.15


@rpc("any_peer", "call_local", "reliable")
func _server_reload() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == name.to_int():
		_server_start_reload()


func _server_start_reload() -> void:
	var w := weapon_data(_sv_weapon)
	if _sv_reload_until_msec == 0 and _sv_ammo[_sv_weapon] < w.magazine:
		_sv_reload_until_msec = Time.get_ticks_msec() + int(w.reload_time * 1000.0 * RELOAD_TOLERANCE)


func _server_update_reload(now: int) -> void:
	if _sv_reload_until_msec > 0 and now >= _sv_reload_until_msec:
		_sv_reload_until_msec = 0
		_sv_ammo[_sv_weapon] = weapon_data(_sv_weapon).magazine


@rpc("any_peer", "call_local", "reliable")
func _server_select_weapon(index: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == name.to_int():
		_server_select(index)


func _server_select(index: int) -> void:
	if index >= 0 and index < weapons.size():
		_sv_weapon = index
		_sv_reload_until_msec = 0


# --- Vida, dano, morte e proteção ----------------------------------------------

## Só no servidor.
func server_apply_damage(attacker_id: int, damage: int, from_position: Vector3, headshot: bool = false) -> void:
	if not alive or protected:
		return
	var attacker := get_parent().get_node_or_null(str(attacker_id)) as FPSPlayer
	if attacker == null or attacker == self or not attacker.alive:
		return
	_sync_health.rpc(maxi(health - damage, 0))
	if not is_bot:
		_damaged.rpc_id(name.to_int(), from_position)
	var killed := health == 0
	# Número de dano sobre a cabeça (só na tela de quem atirou).
	NetworkManager.confirm_hit(attacker_id, killed, damage,
		global_position + Vector3.UP * (body_height() + 0.35), headshot)
	if killed:
		_die(attacker_id, headshot)


@rpc("any_peer", "call_local", "reliable")
func _damaged(from_position: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		damaged_from.emit(from_position)


## Só no servidor.
func _die(killer_id: int, headshot: bool = false) -> void:
	_set_alive.rpc(false, killer_id, Vector3.ZERO)
	NetworkManager.register_kill(killer_id, name.to_int(), headshot)
	# Conectado (e não await): se o jogador sair durante a contagem, a conexão
	# some junto com o nó.
	get_tree().create_timer(RULES.respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	if not NetworkManager.is_online() or alive:
		return
	server_respawn_now()


## Só no servidor: vida cheia e nasce num ponto livre (também no reinício da partida).
func server_respawn_now() -> void:
	_sync_health.rpc(max_health())
	_sv_ammo.clear()
	for weapon_item in weapons:
		_sv_ammo.append(weapon_item.magazine)
	_sv_reload_until_msec = 0
	_sv_grace_until_msec = Time.get_ticks_msec() + TELEPORT_GRACE_MSEC
	_server_spawn_protection()
	_set_alive.rpc(true, 0, NetworkManager.get_spawn_position_for(name.to_int()))


func _server_spawn_protection() -> void:
	_sv_protected_until_msec = Time.get_ticks_msec() + int(RULES.spawn_protection * 1000.0)
	_set_protected.rpc(true)
	var until := _sv_protected_until_msec
	get_tree().create_timer(RULES.spawn_protection).timeout.connect(func() -> void:
		if _sv_protected_until_msec == until and NetworkManager.is_online():
			_set_protected.rpc(false))


@rpc("any_peer", "call_local", "reliable")
func _set_protected(value: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	protected = value
	for mat in _body_materials:
		mat.albedo_color.a = 0.45 if value else 1.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if value else BaseMaterial3D.TRANSPARENCY_DISABLED


@rpc("any_peer", "call_local", "reliable")
func _sync_health(value: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var damaged := value < health
	health = value
	_update_health_bar()
	if damaged and is_local_player():
		Sfx.play(Sfx.HURT, -2.0, 0.08)
		GameInput.vibrate(80)
	health_changed.emit(health, max_health(), damaged)


@rpc("any_peer", "call_local", "reliable")
func _set_alive(value: bool, killer_id: int, spawn_pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	alive = value
	collision_shape.set_deferred("disabled", not value)
	var is_local := is_local_player()
	visual.visible = _body_visible(value)
	weapon.visible = value
	if _health_bar != null:
		_health_bar.visible = value
	var silent := killer_id < 0
	if value:
		for i in ammo.size():
			ammo[i] = weapons[i].magazine
		_reload_until_msec = 0
		_spread = 0.0
		_animator.reset()
		if is_multiplayer_authority():
			_teleport_to(spawn_pos)
		if is_local:
			Sfx.play(Sfx.RESPAWN, -8.0)
			_emit_ammo()
		respawned.emit()
	else:
		velocity = Vector3.ZERO
		if not silent:
			if is_local:
				Sfx.play(Sfx.DEATH, -2.0)
			else:
				Sfx.play_at(Sfx.DEATH, global_position + Vector3.UP, 0.0, 0.05)
		died.emit(killer_id)


## Servidor -> peer recém-chegado: estado atual deste jogador.
func sync_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_sync_health.rpc_id(peer_id, health)
	if not alive:
		_set_alive.rpc_id(peer_id, false, -1, Vector3.ZERO)
	if protected:
		_set_protected.rpc_id(peer_id, true)


# --- Spawn e teleporte -----------------------------------------------------------

func _request_new_spawn() -> void:
	if is_bot:
		_teleport_to(NetworkManager.get_spawn_position_for(name.to_int()))
	else:
		request_spawn.rpc_id(1)


## O cliente pede ao servidor um ponto de spawn livre.
@rpc("any_peer", "call_local", "reliable")
func request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var owner_id := name.to_int()
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	_sv_grace_until_msec = Time.get_ticks_msec() + TELEPORT_GRACE_MSEC
	_server_spawn_protection()
	_teleport.rpc_id(owner_id, NetworkManager.get_spawn_position_for(owner_id))


@rpc("any_peer", "call_local", "reliable")
func _teleport(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_teleport_to(pos)


func _teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	# Nasce olhando para o centro do mapa.
	var to_center := -Vector3(pos.x, 0.0, pos.z)
	if to_center.length() > 0.01:
		rotation.y = atan2(-to_center.x, -to_center.z)
	head.rotation.x = 0.0
	net_position = global_position
	net_yaw = rotation.y
	net_pitch = 0.0


# --- Sincronização, validação de movimento e interpolação --------------------------

func _set_net_position(value: Vector3) -> void:
	if is_inside_tree() and multiplayer.is_server():
		if not is_multiplayer_authority() and not _server_accepts_move(value):
			return
		net_position = value
		_sv_history.append([Time.get_ticks_msec(), value, net_yaw, net_crouch])
		var oldest := Time.get_ticks_msec() - HISTORY_MSEC
		while _sv_history.size() > 2 and int(_sv_history[0][0]) < oldest:
			_sv_history.pop_front()
		return
	net_position = value


## Recusa saltos maiores do que a velocidade máxima permite e devolve o
## cliente para a última posição aceita.
func _server_accepts_move(value: Vector3) -> bool:
	var now := Time.get_ticks_msec()
	var elapsed := maxf((now - _sv_last_move_msec) / 1000.0, 0.05)
	_sv_last_move_msec = now
	if now < _sv_grace_until_msec or not alive:
		return true
	var step := value - net_position
	var max_flat := RULES.sprint_speed * max_speed_multiplier() * elapsed * 1.25 + MOVE_TOLERANCE
	var max_up := RULES.jump_velocity * elapsed * 1.5 + MOVE_TOLERANCE
	if Vector2(step.x, step.z).length() <= max_flat and step.y <= max_up:
		return true
	_sv_grace_until_msec = now + CORRECTION_GRACE_MSEC
	_teleport.rpc_id(name.to_int(), net_position)
	return false


func _on_synchronized() -> void:
	# A posição chega antes do yaw no pacote: completa a última entrada do
	# histórico do servidor com o yaw e o agachamento do mesmo pacote.
	if multiplayer.is_server() and not _sv_history.is_empty():
		var last: Array = _sv_history[-1]
		last[2] = net_yaw
		last[3] = net_crouch
	_snapshots.append([Time.get_ticks_msec(), net_position, net_yaw, net_pitch])
	if _snapshots.size() > 32:
		_snapshots.pop_front()


## Desenha os remotos INTERP_DELAY_MSEC no passado, entre os dois estados
## recebidos que cercam esse instante.
func _interpolate_remote() -> void:
	if _snapshots.is_empty():
		return
	var render_msec := Time.get_ticks_msec() - INTERP_DELAY_MSEC
	while _snapshots.size() > 2 and int(_snapshots[1][0]) <= render_msec:
		_snapshots.pop_front()
	var a: Array = _snapshots[0]
	var b: Array = _snapshots[1] if _snapshots.size() > 1 else a
	var t := 0.0
	if int(b[0]) > int(a[0]):
		t = clampf(float(render_msec - int(a[0])) / (int(b[0]) - int(a[0])), 0.0, 1.0)
	if (a[1] as Vector3).distance_to(b[1]) > SNAP_DISTANCE:
		t = 1.0 if t > 0.0 else 0.0
	global_position = (a[1] as Vector3).lerp(b[1], t)
	rotation.y = lerp_angle(a[2], b[2], t)
	head.rotation.x = lerpf(a[3], b[3], t)


# --- Visual -------------------------------------------------------------------------

func _apply_player_color() -> void:
	var color := Color.from_hsv(fmod(float(name.to_int()) * 0.618034, 1.0), 0.65, 0.9)
	for part: MeshInstance3D in [$Visual/Torso, $Visual/HeadMesh, $Visual/Legs]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.darkened(0.35) if part.name == "Legs" else color
		mat.roughness = 0.7
		part.material_override = mat
		_body_materials.append(mat)


## Barra de vida flutuante (billboard) vista pelos outros jogadores.
func _build_health_bar() -> void:
	_health_bar = Node3D.new()
	_health_bar.position = Vector3(0.0, 2.15, 0.0)
	add_child(_health_bar)

	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(BAR_WIDTH + 0.06, BAR_HEIGHT + 0.06)
	bg_mesh.material = _make_bar_material(Color(0.05, 0.05, 0.07))
	var bg := MeshInstance3D.new()
	bg.mesh = bg_mesh
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_health_bar.add_child(bg)

	_bar_fill_mat = _make_bar_material(Color.GREEN)
	_bar_fill_mesh = QuadMesh.new()
	_bar_fill_mesh.material = _bar_fill_mat
	_bar_fill = MeshInstance3D.new()
	_bar_fill.mesh = _bar_fill_mesh
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_health_bar.add_child(_bar_fill)
	_update_health_bar()


func _make_bar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


func _update_health_bar() -> void:
	if _bar_fill == null:
		return
	var ratio := clampf(float(health) / max_health(), 0.0, 1.0)
	_bar_fill.visible = ratio > 0.0
	var width := BAR_WIDTH * ratio
	_bar_fill_mesh.size = Vector2(maxf(width, 0.001), BAR_HEIGHT)
	# Ancorada à esquerda; z positivo = levemente à frente do fundo no billboard.
	_bar_fill_mesh.center_offset = Vector3(-BAR_WIDTH * 0.5 + width * 0.5, 0.0, 0.01)
	_bar_fill_mat.albedo_color = health_color(ratio)


static func health_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.3, 0.85, 0.35)
	if ratio > 0.3:
		return Color(0.95, 0.8, 0.2)
	return Color(0.95, 0.25, 0.2)
