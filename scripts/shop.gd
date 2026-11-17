class_name ShopMenu
extends Control
## Arsenal: compra, melhora e equipa armas e equipamentos com as moedas do
## Progress. Abre só pelo menu; o equipamento vale na próxima partida.
## As linhas de cada aba são montadas a partir do catálogo em GameRules.

signal closed

const RULES: GameRules = preload("res://data/game_rules.tres")
const OWNED_COLOR := Color(0.6, 0.85, 1.0)
const LOCKED_COLOR := Color(0.55, 0.55, 0.6)
const EQUIPPED_COLOR := Color(0.45, 0.9, 0.5)

var _row_style: StyleBoxFlat
var _opening: bool = false

@onready var level_label: Label = %LevelLabel
@onready var xp_bar: ProgressBar = %XpBar
@onready var xp_label: Label = %XpLabel
@onready var coins_label: Label = %CoinsLabel
@onready var primary_list: VBoxContainer = %PrimaryList
@onready var secondary_list: VBoxContainer = %SecondaryList
@onready var equipment_list: VBoxContainer = %EquipmentList
@onready var status_label: Label = %StatusLabel
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	hide()
	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Color(0.04, 0.05, 0.07, 0.8)
	_row_style.set_corner_radius_all(6)
	_row_style.set_content_margin_all(10)
	close_button.pressed.connect(close)
	# Adiado: a lista é refeita e o botão clicado não pode sumir no meio do próprio sinal.
	Progress.changed.connect(_refresh, CONNECT_DEFERRED)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	status_label.text = "Cada melhoria: pente +%d%%, recarga, recuo e dispersão %d%% menores." % [
		roundi(RULES.upgrade_magazine_bonus * 100.0), roundi(RULES.upgrade_handling_bonus * 100.0)]
	_opening = true
	_refresh()
	_opening = false
	show()
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _refresh() -> void:
	# Fechado não precisa: open() refaz (os prêmios da partida mudam o perfil toda hora).
	if not is_node_ready() or not visible and not _opening:
		return
	var profile := Progress.profile
	var level := profile.level()
	level_label.text = "Nível %d" % level
	xp_bar.value = profile.level_progress()
	if level >= PlayerProfile.MAX_LEVEL:
		xp_label.text = "%d XP (máximo)" % profile.xp
	else:
		xp_label.text = "%d / %d XP" % [profile.xp, PlayerProfile.xp_for_level(level + 1)]
	coins_label.text = "%d moedas" % profile.coins

	var lists := [primary_list, secondary_list, equipment_list]
	for list: VBoxContainer in lists:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	for weapon in RULES.weapons_for_slot(WeaponData.Slot.PRIMARY):
		primary_list.add_child(_make_row(weapon))
	for weapon in RULES.weapons_for_slot(WeaponData.Slot.SECONDARY):
		secondary_list.add_child(_make_row(weapon))
	for item in RULES.equipment:
		equipment_list.add_child(_make_row(item))


func _make_row(item: ShopItem) -> Control:
	var profile := Progress.profile
	var owned := profile.owns(item)
	var equipped := profile.is_equipped(item)
	var weapon := item as WeaponData

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := Label.new()
	title.text = item.display_name
	if weapon != null and profile.upgrade_tier(weapon.id) > 0:
		title.text += "  ·  melhoria %d/%d" % [profile.upgrade_tier(weapon.id), RULES.max_upgrade_tier]
	if equipped:
		title.text += "  ·  equipado"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color",
		EQUIPPED_COLOR if equipped else OWNED_COLOR if owned else Color.WHITE)
	info.add_child(title)
	info.add_child(_small_label(item.description, Color(0.8, 0.8, 0.85)))
	var stats := ""
	if weapon != null:
		# Mostra a arma como ela está para este jogador (com as melhorias).
		stats = weapon.upgraded(profile.upgrade_tier(weapon.id), RULES).stats_text()
	elif item is EquipmentData:
		stats = (item as EquipmentData).stats_text()
	info.add_child(_small_label(stats, Color(0.65, 0.65, 0.7)))

	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(190, 0)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(actions)
	actions.add_child(_action_button(item, owned, equipped))
	if weapon != null and owned:
		actions.add_child(_upgrade_button(weapon))
	return panel


func _action_button(item: ShopItem, owned: bool, equipped: bool) -> Button:
	var button := _button()
	if owned:
		if item is EquipmentData:
			button.text = "Tirar" if equipped else "Equipar"
		else:
			button.text = "Equipado" if equipped else "Equipar"
			button.disabled = equipped
		button.pressed.connect(_on_equip.bind(item))
		return button
	var reason := Progress.profile.buy_block_reason(item)
	if Progress.profile.level() < item.unlock_level:
		button.text = "Libera no nível %d" % item.unlock_level
		button.disabled = true
		button.modulate = LOCKED_COLOR
	else:
		button.text = "Comprar · %d" % item.price
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
	button.pressed.connect(_on_buy.bind(item))
	return button


func _upgrade_button(weapon: WeaponData) -> Button:
	var button := _button()
	var price := Progress.profile.upgrade_price(weapon.id)
	if price < 0:
		button.text = "Melhoria máxima"
		button.disabled = true
	else:
		button.text = "Melhorar · %d" % price
		var reason := Progress.profile.upgrade_block_reason(weapon)
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
	button.pressed.connect(_on_upgrade.bind(weapon))
	return button


func _button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 36)
	return button


func _small_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	return label


func _on_buy(item: ShopItem) -> void:
	if Progress.buy(item):
		Sfx.play(Sfx.PURCHASE, -4.0)
		status_label.text = "%s comprado e equipado." % item.display_name
	else:
		status_label.text = Progress.profile.buy_block_reason(item)


func _on_upgrade(weapon: WeaponData) -> void:
	if Progress.upgrade(weapon):
		Sfx.play(Sfx.PURCHASE, -4.0)
		status_label.text = "%s agora na melhoria %d." % [weapon.display_name, Progress.profile.upgrade_tier(weapon.id)]
	else:
		status_label.text = Progress.profile.upgrade_block_reason(weapon)


func _on_equip(item: ShopItem) -> void:
	if Progress.equip(item):
		var equipped := Progress.profile.is_equipped(item)
		status_label.text = "%s %s." % [item.display_name, "equipado" if equipped else "guardado"]
