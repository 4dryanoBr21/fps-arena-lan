class_name FPSPlayer
extends CharacterBody3D
## Controlador FPS. Só o peer com autoridade lê input; os outros recebem
## posição/rotação pelo MultiplayerSynchronizer. Vida, morte e respawn são
## decididos pelo servidor e replicados por RPC.

signal health_changed(health: int, max_health: int, damaged: bool)
signal died(killer_id: int)
signal respawned

const WALK_SPEED: float = 7.0
const JUMP_VELOCITY: float = 6.0
const ACCELERATION: float = 50.0
const DECELERATION: float = 40.0
const AIR_CONTROL: float = 0.3
const MOUSE_SENSITIVITY: float = 0.0025
## Radianos por pixel de arraste na tela (celular).
const TOUCH_SENSITIVITY: float = 0.006
const MAX_PITCH_DEG: float = 85.0
const FIRE_COOLDOWN: float = 0.15
const FALL_LIMIT_Y: float = -20.0

const MAX_HEALTH: int = 100
const BODY_DAMAGE: int = 25
const HEADSHOT_DAMAGE: int = 50
## Altura (a partir dos pés) acima da qual o acerto conta como na cabeça.
const HEAD_HEIGHT: float = 1.45
const RESPAWN_TIME: float = 3.0
const BAR_WIDTH: float = 0.9
const BAR_HEIGHT: float = 0.09

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health: int = MAX_HEALTH
var alive: bool = true

var _weapon_rest: Vector3
var _kick_tween: Tween
var _cooldown: float = 0.0
var _health_bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_fill_mesh: QuadMesh
var _bar_fill_mat: StandardMaterial3D

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_mesh: MeshInstance3D = $VisualMesh
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/RayCast3D
@onready var weapon: Node3D = $Head/Weapon
@onready var muzzle: Marker3D = $Head/Weapon/Muzzle


func _enter_tree() -> void:
	# O nome do nó é o peer_id do dono (definido pelo servidor antes do spawn).
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("players")
	var is_local := is_multiplayer_authority()
	visual_mesh.visible = not is_local
	camera.current = is_local
	raycast.enabled = is_local
	_weapon_rest = weapon.position
	_apply_player_color()

	if is_local:
		raycast.add_exception(self)
		GameInput.capture()
		Settings.changed.connect(_apply_settings)
		_apply_settings()
		request_spawn.rpc_id(1)
	else:
		_build_health_bar()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not alive or not GameInput.is_active():
		return
	# No celular o toque também gera eventos de mouse emulados; quem cuida
	# do toque é o TouchControls.
	if GameInput.touch:
		return

	if event is InputEventMouseMotion:
		_rotate_view((event as InputEventMouseMotion).relative, MOUSE_SENSITIVITY)
	elif event.is_action_pressed("shoot"):
		_try_shoot()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_multiplayer_authority() or not GameInput.touch:
		return
	var look := GameInput.consume_look()
	if not alive or not GameInput.is_active():
		return
	if look != Vector2.ZERO:
		_rotate_view(look, TOUCH_SENSITIVITY)
	# Segurar o botão atira sem parar (o cooldown limita a cadência).
	if GameInput.fire_held:
		_try_shoot()


func _rotate_view(relative: Vector2, base_sensitivity: float) -> void:
	var sensitivity := base_sensitivity * Settings.mouse_sensitivity
	var pitch_sign := -1.0 if Settings.invert_y else 1.0
	rotate_y(-relative.x * sensitivity)
	var max_pitch := deg_to_rad(MAX_PITCH_DEG)
	head.rotation.x = clampf(head.rotation.x - relative.y * sensitivity * pitch_sign, -max_pitch, max_pitch)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or not alive:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	var active := GameInput.is_active()
	var wants_jump := GameInput.consume_jump() or Input.is_action_just_pressed("jump")
	if active and wants_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	if active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		input_dir = (input_dir + GameInput.move).limit_length(1.0)
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity := direction * WALK_SPEED

	var accel := ACCELERATION if direction != Vector3.ZERO else DECELERATION
	if not is_on_floor():
		accel *= AIR_CONTROL
	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	move_and_slide()

	if global_position.y < FALL_LIMIT_Y:
		request_spawn.rpc_id(1)


func _apply_settings() -> void:
	camera.fov = Settings.fov


func _try_shoot() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = FIRE_COOLDOWN

	raycast.force_raycast_update()
	var hit_point := raycast.to_global(raycast.target_position)
	var hit := raycast.is_colliding()
	if hit:
		hit_point = raycast.get_collision_point()
		var collider := raycast.get_collider()
		if collider is ShootingTarget and (collider as Node).is_in_group("targets"):
			(collider as ShootingTarget).take_damage.rpc_id(1, multiplayer.get_unique_id())
		elif collider is FPSPlayer:
			var victim := collider as FPSPlayer
			victim.take_hit.rpc_id(1, hit_point.y - victim.global_position.y)

	_show_shot.rpc(muzzle.global_position, hit_point, hit)


## Atirador -> servidor. Executa no nó da VÍTIMA; o servidor descobre quem
## atirou pelo remetente do RPC e calcula o dano.
@rpc("any_peer", "call_local", "reliable")
func take_hit(hit_height: float) -> void:
	if not multiplayer.is_server() or not alive:
		return
	var attacker_id := multiplayer.get_remote_sender_id()
	var attacker := get_parent().get_node_or_null(str(attacker_id)) as FPSPlayer
	if attacker == null or attacker == self or not attacker.alive:
		return

	var damage := HEADSHOT_DAMAGE if hit_height >= HEAD_HEIGHT else BODY_DAMAGE
	_sync_health.rpc(maxi(health - damage, 0))
	var killed := health == 0
	NetworkManager.confirm_hit(attacker_id, killed)
	if killed:
		_die(attacker_id)


## Só no servidor.
func _die(killer_id: int) -> void:
	_set_alive.rpc(false, killer_id, Vector3.ZERO)
	NetworkManager.register_kill(killer_id, name.to_int())
	# Conectado (e não await): se o jogador sair durante a contagem, a conexão
	# some junto com o nó.
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)


func _respawn() -> void:
	if not NetworkManager.is_online():
		return
	_sync_health.rpc(MAX_HEALTH)
	_set_alive.rpc(true, 0, NetworkManager.get_spawn_position_for(name.to_int()))


@rpc("any_peer", "call_local", "reliable")
func _sync_health(value: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var damaged := value < health
	health = value
	_update_health_bar()
	if damaged and is_multiplayer_authority():
		Sfx.play(&"hurt", -2.0, 0.08)
	health_changed.emit(health, MAX_HEALTH, damaged)


@rpc("any_peer", "call_local", "reliable")
func _set_alive(value: bool, killer_id: int, spawn_pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	alive = value
	collision_shape.set_deferred("disabled", not value)
	var is_local := is_multiplayer_authority()
	visual_mesh.visible = value and not is_local
	weapon.visible = value
	if _health_bar != null:
		_health_bar.visible = value
	var silent := killer_id < 0
	if value:
		if is_local:
			_teleport_to(spawn_pos)
			Sfx.play(&"respawn", -8.0)
		respawned.emit()
	else:
		velocity = Vector3.ZERO
		if not silent:
			if is_local:
				Sfx.play(&"death", -2.0)
			else:
				Sfx.play_at(&"death", global_position + Vector3.UP, 0.0, 0.05)
		died.emit(killer_id)


## Servidor -> peer recém-chegado: estado atual deste jogador.
func sync_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_sync_health.rpc_id(peer_id, health)
	if not alive:
		_set_alive.rpc_id(peer_id, false, -1, Vector3.ZERO)


## Feedback visual replicado: recuo da arma + traço + impacto.
@rpc("authority", "call_local", "unreliable")
func _show_shot(from: Vector3, to: Vector3, hit: bool) -> void:
	_kick_weapon()
	_spawn_tracer(from, to)
	if is_multiplayer_authority():
		Sfx.play(&"shot", -4.0, 0.05)
	else:
		Sfx.play_at(&"shot", from, 0.0, 0.05)
	if hit:
		_spawn_impact(to)
		Sfx.play_at(&"impact", to, -6.0, 0.15)


## O cliente pede ao servidor um ponto de spawn livre.
@rpc("any_peer", "call_local", "reliable")
func request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var owner_id := name.to_int()
	if multiplayer.get_remote_sender_id() != owner_id:
		return
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


func _kick_weapon() -> void:
	if _kick_tween != null:
		_kick_tween.kill()
	weapon.position = _weapon_rest + Vector3(0.0, 0.02, 0.08)
	weapon.rotation.x = deg_to_rad(10.0)
	_kick_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_kick_tween.tween_property(weapon, "position", _weapon_rest, 0.12)
	_kick_tween.tween_property(weapon, "rotation:x", 0.0, 0.12)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.35, 0.9)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, length)
	mesh.material = mat

	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(tracer)

	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	tracer.look_at_from_position((from + to) * 0.5, to, up)

	var tween := tracer.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(tracer.queue_free)


func _spawn_impact(point: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.1, 1.0)

	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.material = mat

	var impact := MeshInstance3D.new()
	impact.mesh = mesh
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(impact)
	impact.global_position = point

	var tween := impact.create_tween().set_parallel(true)
	tween.tween_property(impact, "scale", Vector3.ONE * 2.5, 0.25)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_callback(impact.queue_free)


func _apply_player_color() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(float(name.to_int()) * 0.618034, 1.0), 0.65, 0.9)
	visual_mesh.material_override = mat


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
	var ratio := clampf(float(health) / MAX_HEALTH, 0.0, 1.0)
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
