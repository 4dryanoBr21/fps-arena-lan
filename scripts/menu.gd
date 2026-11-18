class_name MainMenu
extends Control
## Menu inicial: apelido, nível/moedas com o botão do Arsenal, criar partida
## (mapa, bots, porta) e entrar, pela lista de partidas encontradas na rede
## ou digitando o IP.

signal map_selected(map_index: int)
signal settings_requested
signal shop_requested
signal habits_requested
signal training_requested(bot_count: int)

@onready var name_edit: LineEdit = %NameEdit
@onready var profile_label: Label = %ProfileLabel
@onready var map_option: OptionButton = %MapOption
@onready var bots_spin: SpinBox = %BotsSpin
@onready var port_edit: LineEdit = %PortEdit
@onready var host_button: Button = %HostButton
@onready var server_list: VBoxContainer = %ServerList
@onready var no_servers: Label = %NoServers
@onready var ip_edit: LineEdit = %IPEdit
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var help_label: Label = %Help


func _ready() -> void:
	# Só os mapas da LAN; o treino tem a linha própria (é solo e sem rede).
	for i in NetworkManager.MAPS.size():
		if NetworkManager.get_mode(i) != "training":
			map_option.add_item(NetworkManager.MAPS[i]["name"], i)
	bots_spin.max_value = NetworkManager.MAX_BOTS
	name_edit.text = Settings.nickname
	if GameInput.touch:
		help_label.text = "Joystick à esquerda move (todo para a frente corre) · arraste à direita mira · botões para atirar, pular, agachar e recarregar"

	map_option.item_selected.connect(func(index: int) -> void: map_selected.emit(map_option.get_item_id(index)))
	%TrainingButton.pressed.connect(func() -> void: training_requested.emit(int(%TrainingBotsSpin.value)))
	%TrainingBotsSpin.min_value = NetworkManager.MIN_TRAINING_BOTS
	%TrainingBotsSpin.max_value = NetworkManager.MAX_BOTS
	name_edit.text_changed.connect(_on_name_changed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	%SettingsButton.pressed.connect(settings_requested.emit)
	%ShopButton.pressed.connect(shop_requested.emit)
	%HabitsButton.pressed.connect(habits_requested.emit)
	Progress.changed.connect(_refresh_profile)
	_refresh_profile()
	NetworkManager.status_changed.connect(set_status)
	NetworkManager.discovery.servers_changed.connect(_refresh_servers)
	UiFit.keep_fitted(self, $Center/Panel)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


## Índice em NetworkManager.MAPS (a lista do menu não tem o treino).
func selected_map() -> int:
	return map_option.get_item_id(map_option.selected)


func select_map(map_index: int) -> void:
	var item := map_option.get_item_index(map_index)
	if item >= 0 and map_option.selected != item:
		map_option.select(item)


func set_status(text: String) -> void:
	status_label.text = text


func set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	%TrainingButton.disabled = busy
	map_option.disabled = busy
	for child in server_list.get_children():
		if child is Button:
			(child as Button).disabled = busy


## Escuta anúncios só enquanto o menu está na tela.
func _on_visibility_changed() -> void:
	if visible:
		NetworkManager.discovery.start_listening()
		set_busy(false)
	else:
		NetworkManager.discovery.stop_listening()
	_refresh_servers()


func _refresh_profile() -> void:
	var profile := Progress.profile
	var gear := PlayerProfile.RULES.equipment_by_id(profile.equipment)
	profile_label.text = "Nível %d · %d moedas · %s + %s%s" % [
		profile.level(), profile.coins,
		PlayerProfile.RULES.weapon_by_id(profile.primary).display_name,
		PlayerProfile.RULES.weapon_by_id(profile.secondary).display_name,
		" + " + gear.display_name if gear != null else ""]


func _read_port() -> int:
	var port := port_edit.text.strip_edges().to_int()
	if port <= 0 or port > 65535:
		port = NetworkManager.DEFAULT_PORT
		port_edit.text = str(port)
	return port


func _on_name_changed(text: String) -> void:
	Settings.nickname = text.strip_edges()
	Settings.save_settings()


func _on_host_pressed() -> void:
	NetworkManager.host_game(_read_port(), selected_map(), int(bots_spin.value))


func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
		ip_edit.text = ip
	_join(ip, _read_port())


func _join(ip: String, port: int) -> void:
	if NetworkManager.join_game(ip, port) == OK:
		set_busy(true)


func _refresh_servers() -> void:
	for child in server_list.get_children():
		if child != no_servers:
			server_list.remove_child(child)
			child.queue_free()
	var servers := NetworkManager.discovery.servers
	no_servers.visible = servers.is_empty()
	if not NetworkManager.discovery.is_listening():
		no_servers.text = "Busca automática indisponível. Digite o IP do host abaixo."
	else:
		no_servers.text = "Procurando partidas na rede..."
	for key: String in servers:
		var server: Dictionary = servers[key]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var same_version: bool = server["version"] == NetworkManager.get_version()
		button.text = "%s · %s · %d jogador(es)%s" % [server["host"], server["map"], server["players"],
			"" if same_version else " · versão %s" % server["version"]]
		button.disabled = not same_version
		button.pressed.connect(_join.bind(server["ip"], server["port"]))
		server_list.add_child(button)
