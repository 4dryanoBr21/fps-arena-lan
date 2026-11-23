extends Node3D
## Junta as partes: carrega o mapa, cria e remove jogadores e bots (o
## MultiplayerSpawner replica), alterna menu e HUD, recoloca todo mundo no
## reinício da partida e trata o "voltar" do Android.
##
## Argumentos para testes automáticos (depois de "--" na linha de comando):
##   --host  --join=IP  --map=N  --bots=N  --name=X  --quit-after=SEGUNDOS
##   --loadout=PRINCIPAL,SECUNDÁRIA,EQUIPAMENTO (ids do GameRules)
##   --autopilot  o jogador local desvia mais para a direita, mira no inimigo
##                mais perto e atira (testa o aprendizado do Treino adaptativo)
##   --shot=ARQUIVO.png --screen=menu|hud|pause|settings|shop|habits|crosshair|results [--window=LxA]
##                captura a tela pedida e fecha (tools/capturar_telas.py roda
##                isso em várias resoluções para conferir a interface)
##   --perf (com --shot) objetos e draw calls com e sem occlusion culling
## Com --quit-after o jogo usa progresso e hábitos zerados e não salva nada.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _in_game: bool = false
## Cena carregada (treino e mata-mata usam a mesma: não recarrega à toa).
var _loaded_path: String = ""
var _autopilot: bool = false
var _autopilot_time: float = 0.0
## Teste: apelidos que apareceram no placar durante a sessão (relatório SEEN).
var _seen_names: Dictionary = {}

@onready var world: Node3D = $World
@onready var players: Node3D = $Players
@onready var menu_camera: Camera3D = $MenuCamera
@onready var menu: MainMenu = $UI/Menu
@onready var hud: GameHUD = $UI/HUD
@onready var settings_menu: SettingsMenu = $UI/SettingsMenu
@onready var shop: ShopMenu = $UI/Shop
@onready var habits_panel: HabitsPanel = $UI/HabitsPanel
@onready var crosshair_editor: CrosshairEditor = $UI/CrosshairEditor
@onready var fps_label: Label = %FpsLabel


func _ready() -> void:
	menu.map_selected.connect(_load_map)
	menu.settings_requested.connect(_open_settings)
	menu.shop_requested.connect(_open_shop)
	menu.training_requested.connect(_start_training)
	shop.closed.connect(menu.show)
	menu.habits_requested.connect(_open_habits)
	habits_panel.closed.connect(menu.show)
	hud.settings_requested.connect(_open_settings)
	hud.leave_requested.connect(_on_leave_pressed)
	settings_menu.closed.connect(_on_settings_closed)
	settings_menu.touch_layout_requested.connect(hud.touch_controls.start_editing)
	# Abre por cima das Configurações; ao fechar, elas continuam abertas.
	settings_menu.crosshair_requested.connect(crosshair_editor.open)
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()
	players.child_entered_tree.connect(_on_player_added)

	NetworkManager.map_changed.connect(_load_map)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.game_ended.connect(_on_game_ended)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_despawn_player)
	NetworkManager.match_restarted.connect(_on_match_restarted)

	_load_map(menu.selected_map())
	_show_menu("Desconectado. Crie uma partida ou entre numa.")
	_run_test_args()


func _process(delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if _autopilot:
		_drive_autopilot(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _in_game or settings_menu.visible or crosshair_editor.visible or hud.touch_controls.editing:
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
			if crosshair_editor.visible:
				crosshair_editor.close()
			elif settings_menu.visible:
				settings_menu.close()
			elif shop.visible:
				shop.close()
			elif habits_panel.visible:
				habits_panel.close()
			elif _in_game:
				_toggle_pause()
			elif not OS.has_feature("web"):
				# No navegador "sair" só congelaria a página.
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


## Troca o mapa mantendo o nome "Map" (os caminhos de RPC dos alvos dependem
## dele; tests/smoke_test.sh confere). Não recarrega se a cena já for a mesma.
func _load_map(map_index: int) -> void:
	menu.select_map(map_index)
	var path: String = NetworkManager.MAPS[map_index]["path"]
	if path == _loaded_path:
		return
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()
	var scene := load(path) as PackedScene
	var map := scene.instantiate()
	map.name = "Map"
	world.add_child(map)
	Settings.apply_quality_to(map)
	_loaded_path = path


func _open_settings() -> void:
	# Mouse livre enquanto o painel está aberto; ao fechar, clique na tela recaptura.
	GameInput.release()
	hud.settings_open = true
	settings_menu.open(_in_game)


## O Arsenal só abre pelo menu (fora da partida): o equipamento vale a
## partir da próxima vez que entrar.
func _open_shop() -> void:
	menu.hide()
	shop.open()


func _start_training(bot_count: int) -> void:
	_load_map(NetworkManager.training_map_index())
	NetworkManager.start_training(bot_count)


func _open_habits() -> void:
	menu.hide()
	habits_panel.open()


func _on_settings_closed() -> void:
	hud.settings_open = false


func _on_settings_changed() -> void:
	fps_label.visible = Settings.show_fps


func _on_leave_pressed() -> void:
	NetworkManager.leave_game("Você saiu da partida.")


func _on_game_started() -> void:
	_in_game = true
	shop.close()
	habits_panel.close()
	menu.hide()
	hud.reset()
	hud.show()
	GameInput.capture()
	if multiplayer.is_server():
		_spawn_player(1)
		for bot_id in NetworkManager.get_bot_ids():
			_spawn_player(bot_id)


func _on_game_ended(reason: String) -> void:
	# Fora da árvore já: uma partida nova no mesmo quadro cria o jogador "1"
	# de novo (com queue_free sozinho o nome antigo ainda estaria ocupado).
	for child in players.get_children():
		players.remove_child(child)
		child.queue_free()
	hud.reset()
	get_tree().call_group("targets", "reset_local")
	_show_menu(reason)


func _show_menu(status: String) -> void:
	_in_game = false
	crosshair_editor.close()
	settings_menu.close()
	shop.close()
	habits_panel.close()
	menu.show()
	hud.hide()
	menu_camera.current = true
	GameInput.release()
	menu.set_status(status)


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


## Só no servidor: partida nova, todo mundo de volta com vida cheia.
func _on_match_restarted() -> void:
	get_tree().call_group("targets", "server_reset")
	for child in players.get_children():
		(child as FPSPlayer).server_respawn_now()


## Liga o HUD ao jogador local quando ele aparece (em qualquer peer).
func _on_player_added(node: Node) -> void:
	var player := node as FPSPlayer
	if player == null or player.name.to_int() != multiplayer.get_unique_id():
		return
	if not player.is_node_ready():
		await player.ready
	hud.bind_player(player)
	print("LOCAL_PLAYER_SPAWNED %s" % player.name)


func _run_test_args() -> void:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if args.has("name"):
		Settings.nickname = args["name"]
	if args.has("quit-after"):
		NetworkManager.scores_changed.connect(func() -> void:
			for id: int in NetworkManager.names:
				_seen_names[NetworkManager.get_player_label(id)] = true)
		# Teste automático: perfis zerados e só em memória (não lê nem grava o save).
		Progress.persistent = false
		Progress.profile = PlayerProfile.new()
		Habits.persistent = false
		Habits.profile = PlayerHabits.new()
	if args.has("autopilot"):
		# Pelo caminho do toque: funciona sem mouse capturado (headless).
		GameInput.touch = true
		_autopilot = true
	if args.has("loadout"):
		var parts: PackedStringArray = args["loadout"].split(",")
		parts.resize(3)
		Progress.profile.primary = parts[0]
		Progress.profile.secondary = parts[1]
		Progress.profile.equipment = parts[2]
	var map_index := clampi(int(args.get("map", menu.selected_map())), 0, NetworkManager.MAPS.size() - 1)
	if args.has("host"):
		_load_map(map_index)
		NetworkManager.host_game(NetworkManager.DEFAULT_PORT, map_index, int(args.get("bots", 0)))
	elif args.has("join"):
		# --ws: entra por WebSocket, como a versão de navegador (teste do servidor duplo).
		NetworkManager.join_game(args["join"], NetworkManager.DEFAULT_PORT,
			args.has("ws") or NetworkManager.is_web())
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(_quit_with_report)
	if args.has("shot"):
		_capture_screen(str(args.get("screen", "menu")), args["shot"])


## Teste: 1,2 s desviando para a direita e 0,4 s para a esquerda, mirando
## no inimigo mais perto com o tiro apertado.
func _drive_autopilot(delta: float) -> void:
	var me := players.get_node_or_null(str(multiplayer.get_unique_id())) as FPSPlayer
	if me == null or not me.alive:
		GameInput.fire_held = false
		return
	_autopilot_time = fmod(_autopilot_time + delta, 1.6)
	GameInput.move = Vector2(1.0 if _autopilot_time < 1.2 else -1.0, 0.0)
	var target: FPSPlayer = null
	for child in players.get_children():
		var other := child as FPSPlayer
		if other != me and other.alive and (target == null \
				or me.global_position.distance_to(other.global_position) < me.global_position.distance_to(target.global_position)):
			target = other
	GameInput.fire_held = target != null
	if target != null:
		var to := target.global_position + Vector3.UP * target.body_height() * 0.6 - me.eye_position()
		me.rotation.y = atan2(-to.x, -to.z)
		me.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


## Teste visual: abre a tela pedida, espera assentar, salva a imagem e sai.
func _capture_screen(screen: String, path: String) -> void:
	Progress.persistent = false
	Habits.persistent = false
	# Janela sem borda no tamanho de --window=LxA, mesmo que as configurações
	# salvas estejam em tela cheia.
	var window_arg := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--window="):
			window_arg = arg.trim_prefix("--window=")
	if not window_arg.is_empty():
		var parts := window_arg.split("x")
		# Só na memória (a captura nunca salva as configurações).
		Settings.fullscreen = false
		var wanted := Vector2i(parts[0].to_int(), parts[1].to_int())
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		# Sair da tela cheia é assíncrono no Windows: insiste até a janela obedecer.
		for i in 30:
			DisplayServer.window_set_size(wanted)
			DisplayServer.window_set_position(Vector2i.ZERO)
			await get_tree().process_frame
			if DisplayServer.window_get_size() == wanted and i > 3:
				break
	if screen in ["hud", "pause", "results"]:
		_start_training(3)
		await get_tree().create_timer(2.5).timeout
		# Mostra tudo que o HUD pode ter ao mesmo tempo (pior caso de espaço).
		hud.settings_open = false
		NetworkManager.kill_announced.emit(1000, 1001)
		NetworkManager.kill_announced.emit(1, 1002)
		if screen == "pause":
			GameInput.release()
		elif screen == "results":
			NetworkManager.match_over.emit(1)
		else:
			GameInput.capture()
	else:
		match screen:
			"settings":
				_open_settings()
			"shop":
				_open_shop()
			"habits":
				_open_habits()
			"crosshair":
				_open_settings()
				crosshair_editor.open()
	for i in 20:
		await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--perf"):
		await _report_render_cost()
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s %s %s janela=%s modo=%d viewport=%s" % [screen, path, "ok" if err == OK else "erro %d" % err,
		DisplayServer.window_get_size(), DisplayServer.window_get_mode(), get_viewport().get_visible_rect().size])
	get_tree().quit()


## Teste de desempenho: objetos e draw calls do quadro com e sem occlusion
## culling, de 8 direções a partir do jogador (média).
func _report_render_cost() -> void:
	var me := players.get_node_or_null("1") as FPSPlayer
	if me == null:
		return
	for occlusion: bool in [true, false]:
		get_viewport().use_occlusion_culling = occlusion
		var objects := 0
		var draws := 0
		for i in 8:
			me.rotation.y = TAU * i / 8.0
			for f in 4:
				await RenderingServer.frame_post_draw
			objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		print("PERF occlusion=%s objetos=%.1f draw_calls=%.1f" % [occlusion, objects / 8.0, draws / 8.0])
	get_viewport().use_occlusion_culling = true


## Resumo legível por script (tests/smoke_test.sh) e sai.
func _quit_with_report() -> void:
	var total_deaths := 0
	for id: int in NetworkManager.deaths:
		total_deaths += int(NetworkManager.deaths[id])
	print("RESULT online=%s role=%s map_ok=%s players=%d deaths=%d" % [
		NetworkManager.is_online(), NetworkManager.get_role_text(), world.has_node("Map"),
		players.get_child_count(), total_deaths])
	print("SCORES %s" % NetworkManager.standings_text().replace("\n", " | "))
	print("SEEN %s" % ",".join(PackedStringArray(_seen_names.keys())))
	var loadouts := PackedStringArray()
	for child in players.get_children():
		var player := child as FPSPlayer
		loadouts.append("%s=%s+%s+%s" % [NetworkManager.get_player_label(player.name.to_int()),
			player.weapons[0].id, player.weapons[1].id, player.equipment.id if player.equipment != null else "-"])
	print("LOADOUTS %s" % " ".join(loadouts))
	var profile := Progress.profile
	print("PROGRESS coins=%d xp=%d level=%d" % [profile.coins, profile.xp, profile.level()])
	var habits := NetworkManager.habits.habits_for(multiplayer.get_unique_id())
	if habits != null and multiplayer.is_server():
		print("HABITS combat=%.1f bias=%.2f shots=%d skill=%.2f duels=%d/%d" % [habits.combat_time,
			habits.strafe_bias, roundi(habits.shots[0] + habits.shots[1] + habits.shots[2]),
			habits.skill, habits.duels_won, habits.duels_lost])
		print("HABITS_TIP %s" % habits.insights(NetworkManager.habits.map_key())[0])
	get_tree().quit()
