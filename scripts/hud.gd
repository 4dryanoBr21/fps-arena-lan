class_name GameHUD
extends Control
## HUD da partida: vida, munição, placar, tempo, kill feed, mira, avisos de
## dano, números de dano sobre os inimigos, hotbar de armas, placar completo
## (Tab), prêmios em moedas/XP, tela de resultado, pausa e controles de toque.
## Liga-se ao jogador local por bind_player().

signal settings_requested
signal leave_requested

const RULES: GameRules = preload("res://data/game_rules.tres")
const KILL_FEED_MAX: int = 5
const KILL_FEED_TIME: float = 4.0
## Linhas de jogadores no painel pequeno do canto.
const SCORE_PANEL_LINES: int = 3
const REWARD_FEED_MAX: int = 4
const REWARD_TIME: float = 1.6
const COIN_COLOR := Color(1.0, 0.85, 0.3)
## Segundos entre as conferências da área segura (celular girado 180°).
const SAFE_AREA_CHECK_INTERVAL: float = 0.5

## O main liga enquanto o painel de configurações está aberto.
var settings_open: bool = false

var _player: FPSPlayer
var _respawn_at_msec: int = 0
var _killer_text: String = ""
var _results_until_msec: int = 0
var _hitmarker_tween: Tween
var _flash_tween: Tween
## Moedas e XP ganhos na partida atual (zera quando outra começa).
var _match_coins: int = 0
var _match_xp: int = 0
var _training_text: String = ""
## A grade do placar (Tab) só é refeita quando aparece.
var _grid_dirty: bool = true
var _last_safe_area := Rect2()
var _safe_area_timer: float = 0.0

@onready var damage_flash: ColorRect = %DamageFlash
@onready var damage_indicator: DamageIndicator = %DamageIndicator
@onready var cross: Crosshair = %Cross
@onready var score_label: Label = %ScoreLabel
@onready var timer_label: Label = %TimerLabel
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var hotbar: Hotbar = %Hotbar
@onready var kill_feed: VBoxContainer = %KillFeed
@onready var reward_feed: VBoxContainer = %RewardFeed
@onready var death_label: Label = %DeathLabel
@onready var scoreboard: Control = %Scoreboard
@onready var score_grid: GridContainer = %ScoreGrid
@onready var results: Control = %Results
@onready var winner_label: Label = %WinnerLabel
@onready var standings_label: Label = %StandingsLabel
@onready var record_label: Label = %RecordLabel
@onready var earned_label: Label = %EarnedLabel
@onready var next_label: Label = %NextLabel
@onready var pause_panel: Control = %PausePanel
@onready var pause_hint: Label = %PauseHint
@onready var touch_controls: TouchControls = %TouchControls


func _ready() -> void:
	%ResumeButton.pressed.connect(GameInput.capture)
	%PauseSettingsButton.pressed.connect(settings_requested.emit)
	%LeaveButton.pressed.connect(leave_requested.emit)
	if GameInput.touch:
		pause_hint.text = "Toque em Voltar ao jogo para continuar"

	NetworkManager.scores_changed.connect(_refresh_scores)
	NetworkManager.hit_confirmed.connect(_on_hit_confirmed)
	NetworkManager.damage_dealt.connect(_on_damage_dealt)
	NetworkManager.kill_announced.connect(_on_kill_announced)
	NetworkManager.match_state_changed.connect(_on_match_state_changed)
	NetworkManager.match_over.connect(_on_match_over)
	NetworkManager.training_feedback.connect(func(text: String) -> void: _training_text = text)
	Progress.reward_received.connect(_on_reward_received)
	Progress.leveled_up.connect(_on_leveled_up)
	touch_controls.weapon_slot_at = hotbar.slot_at
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _process(delta: float) -> void:
	if not visible:
		return
	if OS.has_feature("mobile"):
		_check_safe_area(delta)
	var active := GameInput.is_active()
	var editing := touch_controls.editing
	# Na tela de resultado os botões de toque ficariam por cima do placar.
	var results_up := Time.get_ticks_msec() < _results_until_msec
	touch_controls.visible = GameInput.touch and (active or editing) and not results_up
	pause_panel.visible = not active and not settings_open and not editing

	if NetworkManager.match_running:
		var left := NetworkManager.time_left()
		timer_label.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
		timer_label.modulate = Color(1.0, 0.4, 0.35) if left < 10.0 else Color.WHITE
	timer_label.visible = NetworkManager.match_running

	var showing_results := Time.get_ticks_msec() < _results_until_msec
	results.visible = showing_results
	if showing_results:
		next_label.text = "Próxima partida em %d s" % ceili((_results_until_msec - Time.get_ticks_msec()) / 1000.0)
	scoreboard.visible = not showing_results \
		and (Input.is_action_pressed("scoreboard") or GameInput.scoreboard_held)
	if scoreboard.visible and _grid_dirty:
		_rebuild_score_grid()

	if death_label.visible:
		var remaining := maxf((_respawn_at_msec - Time.get_ticks_msec()) / 1000.0, 0.0)
		death_label.text = "%s\nRenascendo em %.1f s" % [_killer_text, remaining]


## Volta ao estado inicial (ao sair de uma partida).
func reset() -> void:
	_player = null
	for child in kill_feed.get_children():
		child.queue_free()
	for child in reward_feed.get_children():
		child.queue_free()
	_match_coins = 0
	_match_xp = 0
	death_label.hide()
	results.hide()
	scoreboard.hide()
	_results_until_msec = 0
	cross.show()
	hotbar.clear()
	damage_indicator.clear()
	damage_indicator.player = null


## Liga o HUD aos sinais do jogador local quando ele aparece.
func bind_player(player: FPSPlayer) -> void:
	_player = player
	damage_indicator.player = player
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_died)
	player.respawned.connect(_on_respawned)
	player.view_changed.connect(_on_view_changed)
	hotbar.bind(player)
	_on_view_changed(FPSPlayer.view_mode)
	player.damaged_from.connect(damage_indicator.add_hit)
	_on_health_changed(player.max_health(), player.max_health(), false)


func _on_health_changed(health: int, max_health: int, damaged: bool) -> void:
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


## Visão de frente (terceira pessoa olhando para o jogador): sem mira.
func _on_view_changed(mode: int) -> void:
	cross.visible = mode != FPSPlayer.ViewMode.FRONT and (_player == null or _player.alive)


func _on_died(killer_id: int) -> void:
	_respawn_at_msec = Time.get_ticks_msec() + int(RULES.respawn_time * 1000.0)
	_killer_text = "Eliminado por %s" % NetworkManager.get_player_label(killer_id) \
		if killer_id > 0 else "Você foi eliminado"
	death_label.show()
	cross.hide()


func _on_respawned() -> void:
	death_label.hide()
	_on_view_changed(FPSPlayer.view_mode)


func _on_hit_confirmed(killed: bool) -> void:
	Sfx.play(Sfx.KILL if killed else Sfx.HITMARKER, -3.0)
	GameInput.vibrate(40 if killed else 20)
	if _hitmarker_tween != null:
		_hitmarker_tween.kill()
	# Tinge a mira (em vez de multiplicar a cor): aparece em qualquer cor escolhida.
	cross.flash_color = Color(1.0, 0.15, 0.15) if killed else Color(1.0, 0.85, 0.2)
	cross.flash = 1.0
	cross.scale = Vector2.ONE * (1.8 if killed else 1.35)
	_hitmarker_tween = create_tween().set_parallel(true)
	_hitmarker_tween.tween_property(cross, "flash", 0.0, 0.25)
	_hitmarker_tween.tween_property(cross, "scale", Vector2.ONE, 0.2)


func _on_damage_dealt(amount: int, at: Vector3, headshot: bool, killed: bool) -> void:
	if Settings.damage_numbers:
		Fx.damage_number(at, amount, headshot, killed)


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


func _on_match_state_changed() -> void:
	if NetworkManager.match_running:
		_results_until_msec = 0
		_match_coins = 0
		_match_xp = 0


func _on_reward_received(coins: int, xp: int, reason: String) -> void:
	_match_coins += coins
	_match_xp += xp
	if visible:
		_show_reward("+%d moedas  +%d XP  %s" % [coins, xp, reason], COIN_COLOR)


func _on_leveled_up(level: int) -> void:
	Sfx.play(Sfx.LEVEL_UP, -4.0)
	if visible:
		_show_reward("Nível %d! Veja o que liberou no Arsenal" % level, Color(0.6, 0.85, 1.0))


func _show_reward(text: String, color: Color) -> void:
	var entry := Label.new()
	entry.text = text
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.add_theme_color_override("font_color", color)
	entry.add_theme_color_override("font_outline_color", Color.BLACK)
	entry.add_theme_constant_override("outline_size", 4)
	reward_feed.add_child(entry)
	while reward_feed.get_child_count() > REWARD_FEED_MAX:
		var oldest := reward_feed.get_child(0)
		reward_feed.remove_child(oldest)
		oldest.queue_free()
	var tween := entry.create_tween()
	tween.tween_interval(REWARD_TIME)
	tween.tween_property(entry, "modulate:a", 0.0, 0.4)
	tween.tween_callback(entry.queue_free)


func _on_match_over(winner_id: int) -> void:
	_results_until_msec = Time.get_ticks_msec() + int(RULES.results_time * 1000.0)
	var arena := NetworkManager.get_mode() == "arena"
	var unit := "alvos" if arena else "abates"
	winner_label.text = "Vencedor: %s (%d %s)" % [
		NetworkManager.get_player_label(winner_id), int(NetworkManager.scores.get(winner_id, 0)), unit]
	standings_label.text = NetworkManager.standings_text()
	earned_label.text = "Nesta partida: +%d moedas, +%d XP (total %d moedas, nível %d)" % [
		_match_coins, _match_xp, Progress.profile.coins, Progress.profile.level()]
	record_label.text = ""
	if arena:
		var mine := int(NetworkManager.scores.get(multiplayer.get_unique_id(), 0))
		if mine > Settings.arena_record:
			Settings.arena_record = mine
			Settings.save_settings()
			record_label.text = "Novo recorde: %d alvos!" % mine
		else:
			record_label.text = "Seu recorde: %d alvos" % Settings.arena_record
	elif NetworkManager.get_mode() == "training":
		record_label.text = _training_text
	_training_text = ""


func _refresh_scores() -> void:
	var my_id := multiplayer.get_unique_id()
	var ranking := NetworkManager.standings()
	var lines := PackedStringArray()
	lines.append("%s  |  %s" % [NetworkManager.get_role_text(), NetworkManager.get_map_name()])
	for i in ranking.size():
		var id: int = ranking[i]
		if i >= SCORE_PANEL_LINES and id != my_id:
			continue
		var label := NetworkManager.get_player_label(id)
		if id == my_id:
			label += " (você)"
		lines.append("%dº %s: %d" % [i + 1, label, int(NetworkManager.scores[id])])
	score_label.text = "\n".join(lines)
	_grid_dirty = true
	if scoreboard.visible:
		_rebuild_score_grid()


func _rebuild_score_grid() -> void:
	_grid_dirty = false
	var my_id := multiplayer.get_unique_id()
	var ranking := NetworkManager.standings()
	for child in score_grid.get_children():
		score_grid.remove_child(child)
		child.queue_free()
	for header: String in ["Jogador", "Pontos", "Mortes", "Ping"]:
		_add_cell(header, Color(0.6, 0.85, 1.0))
	for id: int in ranking:
		var color := Color(1.0, 0.85, 0.3) if id == my_id else Color.WHITE
		_add_cell(NetworkManager.get_player_label(id), color)
		_add_cell(str(int(NetworkManager.scores[id])), color)
		_add_cell(str(int(NetworkManager.deaths.get(id, 0))), color)
		_add_cell("bot" if NetworkManager.is_bot_id(id) else "%d ms" % int(NetworkManager.pings.get(id, 0)), color)


func _add_cell(text: String, color: Color) -> void:
	var cell := Label.new()
	cell.text = text
	cell.add_theme_color_override("font_color", color)
	score_grid.add_child(cell)


## Celular: afasta o HUD (e os controles de toque) do entalhe e das bordas arredondadas.
## A mira, o flash e os arcos de dano ficam fora disso: eles precisam do
## centro da TELA (para onde a câmera aponta e o tiro vai), não do centro da
## área segura. Antes a mira andava metade da largura do entalhe e o tiro
## parecia sair para o lado dela.
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var window_size := Vector2(get_window().size)
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	apply_safe_rect(_current_safe_area(window_size), window_size)


## Encolhe o HUD até `safe` (pixels da janela) e devolve a tela inteira às
## camadas que dependem do centro. Separado para o teste poder simular um entalhe.
func apply_safe_rect(safe: Rect2, window_size: Vector2) -> void:
	_last_safe_area = safe
	var to_canvas := get_viewport_rect().size / window_size
	offset_left = safe.position.x * to_canvas.x
	offset_top = safe.position.y * to_canvas.y
	offset_right = -(window_size.x - safe.end.x) * to_canvas.x
	offset_bottom = -(window_size.y - safe.end.y) * to_canvas.y
	for layer: Control in [cross.get_parent() as Control, damage_flash, damage_indicator]:
		layer.offset_left = -offset_left
		layer.offset_top = -offset_top
		layer.offset_right = -offset_right
		layer.offset_bottom = -offset_bottom


## Área segura em coordenadas da janela (no Android a janela pode não começar
## no 0: tela dividida, janela flutuante).
func _current_safe_area(window_size: Vector2) -> Rect2:
	var safe := Rect2(DisplayServer.get_display_safe_area())
	safe.position -= Vector2(DisplayServer.window_get_position())
	safe = safe.intersection(Rect2(Vector2.ZERO, window_size))
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Rect2(Vector2.ZERO, window_size)
	return safe


## Girar o celular 180° (paisagem <-> paisagem invertida) troca o lado do
## entalhe sem mudar o tamanho da janela, e size_changed não avisa.
func _check_safe_area(delta: float) -> void:
	_safe_area_timer -= delta
	if _safe_area_timer > 0.0:
		return
	_safe_area_timer = SAFE_AREA_CHECK_INTERVAL
	var window_size := Vector2(get_window().size)
	if window_size.x > 0.0 and window_size.y > 0.0 \
			and not _current_safe_area(window_size).is_equal_approx(_last_safe_area):
		_apply_safe_area()
