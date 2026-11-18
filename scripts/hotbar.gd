class_name Hotbar
extends HBoxContainer
## Barra de armas na parte de baixo do HUD: uma vaga por arma do jogador
## (principal, secundária, faca) com a tecla, a miniatura 3D, o nome e a
## munição. A arma na mão fica destacada. Liga-se ao jogador por bind().

const SLOT_SIZE := Vector2(132, 96)
const PREVIEW_SIZE := Vector2i(116, 44)
## Mesma escala de tamanho das miniaturas do Arsenal.
const PREVIEW_MIN_WIDTH: float = 0.5
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
const IDLE_COLOR := Color(0.75, 0.75, 0.8)

var _player: FPSPlayer
## Ids das armas das vagas atuais (refaz as vagas se o equipamento mudar).
var _slot_ids: PackedStringArray = []
var _slots: Array[PanelContainer] = []
var _ammo_labels: Array[Label] = []
var _key_labels: Array[Label] = []
var _selected_style: StyleBoxFlat
var _idle_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	_idle_style = _make_style(Color(0.06, 0.07, 0.1, 0.72), Color(1, 1, 1, 0.12))
	_selected_style = _make_style(Color(0.12, 0.13, 0.17, 0.9), SELECTED_COLOR)


func bind(player: FPSPlayer) -> void:
	_player = player
	player.weapon_changed.connect(func(_w: WeaponData) -> void: refresh())
	player.ammo_changed.connect(func(_a: int, _m: int, _r: bool) -> void: refresh())
	refresh()


## Fim de partida: solta o jogador e apaga as vagas.
func clear() -> void:
	_player = null
	_clear_slots()


func _clear_slots() -> void:
	_slot_ids = []
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_slots.clear()
	_ammo_labels.clear()
	_key_labels.clear()


func refresh() -> void:
	if _player == null or _player.weapons.is_empty():
		return
	var ids := PackedStringArray()
	for weapon in _player.weapons:
		ids.append(weapon.id)
	if ids != _slot_ids:
		_build(ids)
	for i in _slots.size():
		var weapon := _player.weapons[i]
		var selected := i == _player.weapon_index
		_slots[i].add_theme_stylebox_override("panel", _selected_style if selected else _idle_style)
		_slots[i].modulate.a = 1.0 if selected else 0.8
		_key_labels[i].add_theme_color_override("font_color", SELECTED_COLOR if selected else IDLE_COLOR)
		_ammo_labels[i].text = _ammo_text(i, weapon, selected)


func _ammo_text(index: int, weapon: WeaponData, selected: bool) -> String:
	if weapon.melee:
		return "—"
	if selected and _player.is_reloading():
		return "recarregando"
	return "%d / %d" % [_player.ammo[index], weapon.magazine]


func _build(ids: PackedStringArray) -> void:
	_clear_slots()
	_slot_ids = ids
	for i in ids.size():
		var weapon := _player.weapons[i]
		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		slot.add_child(box)

		var top := HBoxContainer.new()
		box.add_child(top)
		var key := _label(str(i + 1), 16)
		top.add_child(key)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		var ammo := _label("", 13)
		top.add_child(ammo)

		box.add_child(WeaponPreview.create(weapon.id, PREVIEW_SIZE, PREVIEW_MIN_WIDTH))
		var title := _label(weapon.display_name, 12)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(title)

		add_child(slot)
		_slots.append(slot)
		_key_labels.append(key)
		_ammo_labels.append(ammo)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _make_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
