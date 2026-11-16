extends Node3D
## Menu LAN, carregamento do mapa, HUD e spawn/despawn dos jogadores
## (o MultiplayerSpawner replica).

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const KILL_FEED_MAX: int = 5
const KILL_FEED_TIME: float = 4.0

var _in_game: bool = false
var _respawn_at_msec: int = 0
var _killer_text: String = ""
var _hitmarker_tween: Tween
var _flash_tween: Tween

@onready var world: Node3D = $World
@onready var players: Node3D = $Players
@onready var menu_camera: Camera3D = $MenuCamera
@onready var menu: Control = $UI/Menu
@onready var hud: Control = $UI/HUD
@onready var ip_edit: LineEdit = %IPEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var map_option: OptionButton = %MapOption
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var score_label: Label = %ScoreLabel
@onready var pause_panel: Control = %PausePanel
@onready var leave_button: Button = %LeaveButton
@onready var resume_button: Button = %ResumeButton
@onready var pause_hint: Label = %PauseHint
@onready var help_label: Label = %Help
@onready var touch_controls: Control = %TouchControls
@onready var cross: Control = %Cross
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var damage_flash: ColorRect = %DamageFlash
@onready var death_label: Label = %DeathLabel
@onready var kill_feed: VBoxContainer = %KillFeed
@onready var settings_button: Button = %SettingsButton
@onready var pause_settings_button: Button = %PauseSettingsButton
@onready var settings_menu: Control = %SettingsMenu
@onready var fps_label: Label = %FpsLabel


func _ready() -> void:
	for map: Dictionary in NetworkManager.MAPS:
		map_option.add_item(map["name"])
	map_option.item_selected.connect(_load_map)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	resume_button.pressed.connect(GameInput.capture)
	settings_button.pressed.connect(_open_settings)
	pause_settings_button.pressed.connect(_open_settings)
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()
	players.child_entered_tree.connect(_on_player_added)

	NetworkManager.status_changed.connect(_on_status_changed)
	NetworkManager.map_changed.connect(_load_map)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.game_ended.connect(_on_game_ended)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_despawn_player)
	NetworkManager.scores_changed.connect(_refresh_scoreboard)
	NetworkManager.hit_confirmed.connect(_on_hit_confirmed)
	NetworkManager.kill_announced.connect(_on_kill_announced)

	if GameInput.touch:
		help_label.text = "Joystick à esquerda move · arraste à direita mira · botões para atirar e pular"
		pause_hint.text = "Jogo pausado"

	_load_map(map_option.selected)
	_show_menu("Desconectado. Escolha Host LAN ou Entrar (Join).")


func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if not _in_game:
		return
	var active := GameInput.is_active()
	pause_panel.visible = not active and not settings_menu.visible
	touch_controls.visible = GameInput.touch and active
	if death_label.visible:
		var remaining := maxf((_respawn_at_msec - Time.get_ticks_msec()) / 1000.0, 0.0)
		death_label.text = "%s\nRenascendo em %.1f s" % [_killer_text, remaining]


func _unhandled_input(event: InputEvent) -> void:
	if not _in_game or settings_menu.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed() \
			and not GameInput.touch and not GameInput.is_active():
		# Clique na tela recaptura o mouse (o jogador não atira com o mouse livre).
		GameInput.capture()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Botão/gesto "voltar" do Android: fecha painel, pausa ou sai do app.
			if settings_menu.visible:
				settings_menu.call("close")
			elif _in_game:
				_toggle_pause()
			else:
				get_tree().quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Celular: ao sair do app, volta pausado.
			if _in_game and GameInput.touch:
				GameInput.release()


func _toggle_pause() -> void:
	if GameInput.is_active():
		GameInput.release()
	else:
		GameInput.capture()


## Troca o mapa mantendo o nome "Map" (os caminhos de RPC dos alvos dependem dele).
func _load_map(map_index: int) -> void:
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()
	var scene := load(NetworkManager.MAPS[map_index]["path"]) as PackedScene
	var map := scene.instantiate()
	map.name = "Map"
	world.add_child(map)
	if map_option.selected != map_index:
		map_option.select(map_index)


func _read_port() -> int:
	var port := port_edit.text.strip_edges().to_int()
	if port <= 0 or port > 65535:
		port = NetworkManager.DEFAULT_PORT
		port_edit.text = str(port)
	return port


func _on_host_pressed() -> void:
	NetworkManager.host_game(_read_port(), map_option.selected)


func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
		ip_edit.text = ip
	if NetworkManager.join_game(ip, _read_port()) == OK:
		host_button.disabled = true
		join_button.disabled = true
		map_option.disabled = true


func _open_settings() -> void:
	# Mouse livre enquanto o painel está aberto; ao fechar, clique na tela recaptura.
	GameInput.release()
	settings_menu.call("open")


func _on_settings_changed() -> void:
	fps_label.visible = Settings.show_fps


func _on_leave_pressed() -> void:
	NetworkManager.leave_game("Você saiu da partida.")


func _on_status_changed(text: String) -> void:
	status_label.text = text


func _on_game_started() -> void:
	_in_game = true
	menu.hide()
	hud.show()
	death_label.hide()
	GameInput.capture()
	if multiplayer.is_server():
		_spawn_player(1)
	_refresh_scoreboard()


func _on_game_ended(reason: String) -> void:
	for child in players.get_children():
		child.queue_free()
	for child in kill_feed.get_children():
		child.queue_free()
	_load_map(map_option.selected)
	_show_menu(reason)


func _show_menu(status: String) -> void:
	_in_game = false
	settings_menu.call("close")
	menu.show()
	hud.hide()
	host_button.disabled = false
	join_button.disabled = false
	map_option.disabled = false
	menu_camera.current = true
	GameInput.release()
	status_label.text = status


## Só no servidor: um cliente terminou de carregar o mapa.
func _on_player_joined(peer_id: int) -> void:
	get_tree().call_group("targets", "sync_to_peer", peer_id)
	for child in players.get_children():
		(child as FPSPlayer).sync_to_peer(peer_id)
	_spawn_player(peer_id)


## Só no servidor: adicionar o nó sob Players faz o spawner replicá-lo.
func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server() or players.has_node(str(peer_id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	players.add_child(player, true)


func _despawn_player(peer_id: int) -> void:
	var player := players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


## Liga o HUD aos sinais do jogador local quando ele aparece (em qualquer peer).
func _on_player_added(node: Node) -> void:
	var player := node as FPSPlayer
	if player == null or player.name.to_int() != multiplayer.get_unique_id():
		return
	player.health_changed.connect(_on_local_health_changed)
	player.died.connect(_on_local_died)
	player.respawned.connect(_on_local_respawned)
	_on_local_health_changed(FPSPlayer.MAX_HEALTH, FPSPlayer.MAX_HEALTH, false)


func _on_local_health_changed(health: int, max_health: int, damaged: bool) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "%d" % health
	var fill := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = FPSPlayer.health_color(float(health) / max_health)
	if damaged:
		if _flash_tween != null:
			_flash_tween.kill()
		damage_flash.color.a = 0.4
		_flash_tween = create_tween()
		_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.35)


func _on_local_died(killer_id: int) -> void:
	_respawn_at_msec = Time.get_ticks_msec() + int(FPSPlayer.RESPAWN_TIME * 1000.0)
	_killer_text = "Eliminado por %s" % NetworkManager.get_player_label(killer_id) \
		if killer_id > 0 else "Você foi eliminado"
	death_label.show()
	cross.hide()


func _on_local_respawned() -> void:
	death_label.hide()
	cross.show()


func _on_hit_confirmed(killed: bool) -> void:
	Sfx.play(&"kill" if killed else &"hitmarker", -3.0)
	if _hitmarker_tween != null:
		_hitmarker_tween.kill()
	cross.modulate = Color(1.0, 0.15, 0.15) if killed else Color(1.0, 0.85, 0.2)
	cross.scale = Vector2.ONE * (1.8 if killed else 1.35)
	_hitmarker_tween = create_tween().set_parallel(true)
	_hitmarker_tween.tween_property(cross, "modulate", Color.WHITE, 0.25)
	_hitmarker_tween.tween_property(cross, "scale", Vector2.ONE, 0.2)


func _on_kill_announced(killer_id: int, victim_id: int) -> void:
	var entry := Label.new()
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.add_theme_color_override("font_outline_color", Color.BLACK)
	entry.add_theme_constant_override("outline_size", 4)
	var my_id := multiplayer.get_unique_id()
	if killer_id == my_id or victim_id == my_id:
		entry.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	entry.text = "%s eliminou %s" % [
		NetworkManager.get_player_label(killer_id), NetworkManager.get_player_label(victim_id)]
	kill_feed.add_child(entry)
	while kill_feed.get_child_count() > KILL_FEED_MAX:
		var oldest := kill_feed.get_child(0)
		kill_feed.remove_child(oldest)
		oldest.queue_free()

	var tween := entry.create_tween()
	tween.tween_interval(KILL_FEED_TIME)
	tween.tween_property(entry, "modulate:a", 0.0, 0.5)
	tween.tween_callback(entry.queue_free)


func _refresh_scoreboard() -> void:
	var my_id := multiplayer.get_unique_id()
	var lines := PackedStringArray()
	lines.append("%s  |  ID: %d" % [NetworkManager.get_role_text(), my_id])
	lines.append("Mapa: %s" % NetworkManager.get_map_name())
	lines.append("— Placar (pontos / mortes) —")
	var ids: Array = NetworkManager.scores.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return int(NetworkManager.scores[a]) > int(NetworkManager.scores[b]))
	for id: int in ids:
		var label := NetworkManager.get_player_label(id)
		if id == my_id:
			label += " (você)"
		lines.append("%s: %d / %d" % [label, int(NetworkManager.scores[id]), int(NetworkManager.deaths.get(id, 0))])
	score_label.text = "\n".join(lines)
