extends Node
## Autoload "UiScale": a interface com o mesmo tamanho físico em qualquer tela
## e um tema único para o jogo todo.
##
## Escala: o projeto estica o canvas pela altura da janela (stretch
## canvas_items, base de 648 px). Num monitor isso já deixa o texto grande,
## mas num celular de 6" com 1080 px de altura o texto de 16 px vira ~1,5 mm.
## Aqui medimos o tamanho físico do texto pela densidade da tela (DPI) e
## aumentamos o content_scale_factor até ele ter pelo menos TARGET_TEXT_MM. O
## jogador ainda pode ajustar em Configurações > Tamanho da interface.
## Para testes, "--ui-dpi=N" finge a densidade de um aparelho.
##
## Tema: botões, campos, listas, abas, sliders e barras de rolagem com o
## mesmo visual; no toque ficam mais altos e com barras de rolagem mais grossas.

signal scale_changed(factor: float)

## Altura do canvas com fator 1 (display/window/size/viewport_height).
const BASE_HEIGHT: float = 648.0
const BASE_FONT_SIZE: int = 16
## Altura física mínima do texto comum (mm). ~2,4 mm é o corpo de texto de app de celular.
const TARGET_TEXT_MM: float = 2.4
const MAX_AUTO_FACTOR: float = 1.5

const ACCENT := Color(0.33, 0.62, 1.0)
const ACCENT_DARK := Color(0.2, 0.42, 0.78)
const SURFACE := Color(0.2, 0.24, 0.32)
const SURFACE_HOVER := Color(0.26, 0.31, 0.41)
const SURFACE_PRESSED := Color(0.1, 0.12, 0.16)
const FIELD := Color(0.07, 0.08, 0.11)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.6, 0.64, 0.72)

var factor: float = 1.0
var theme: Theme

var _dpi_override: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-dpi="):
			_dpi_override = arg.trim_prefix("--ui-dpi=").to_int()
	theme = build_theme(GameInput.touch)
	get_tree().root.theme = theme
	# CanvasLayer corta a herança de tema da janela: cada Control de topo
	# (filho de CanvasLayer ou de nó 3D) recebe o tema direto.
	get_tree().node_added.connect(_theme_top_level)
	for node in get_tree().root.find_children("*", "Control", true, false):
		_theme_top_level(node)
	get_tree().root.size_changed.connect(apply)
	Settings.changed.connect(apply)
	apply()


func _theme_top_level(node: Node) -> void:
	var control := node as Control
	if control != null and control.theme == null and not (control.get_parent() is Control):
		control.theme = theme


func screen_dpi() -> int:
	if _dpi_override > 0:
		return _dpi_override
	return maxi(DisplayServer.screen_get_dpi(), 72)


## Fator para o texto comum ter TARGET_TEXT_MM nesta janela e nesta tela.
static func auto_factor(window_height: float, dpi: float) -> float:
	if window_height <= 0.0 or dpi <= 0.0:
		return 1.0
	var text_mm := BASE_FONT_SIZE * (window_height / BASE_HEIGHT) / dpi * 25.4
	return clampf(TARGET_TEXT_MM / text_mm, 1.0, MAX_AUTO_FACTOR)


func apply() -> void:
	var window_height := float(get_tree().root.size.y)
	var new_factor := auto_factor(window_height, screen_dpi()) * Settings.ui_scale
	# Nunca deixa o canvas com menos de 300 px de altura (nada caberia).
	new_factor = clampf(new_factor, 0.5, maxf(window_height / 300.0, 0.5)) if window_height > 0.0 else new_factor
	if is_equal_approx(new_factor, factor) and is_equal_approx(get_tree().root.content_scale_factor, factor):
		return
	factor = new_factor
	get_tree().root.content_scale_factor = factor
	scale_changed.emit(factor)


static func build_theme(touch: bool) -> Theme:
	var t := Theme.new()
	t.default_font_size = BASE_FONT_SIZE
	var pad_y := 10.0 if touch else 7.0

	var normal := _box(SURFACE, 8, pad_y)
	normal.set_border_width_all(1)
	normal.border_color = Color(1, 1, 1, 0.1)
	var hover := _box(SURFACE_HOVER, 8, pad_y)
	hover.set_border_width_all(1)
	hover.border_color = Color(ACCENT, 0.6)
	var pressed := _box(ACCENT_DARK, 8, pad_y)
	var disabled := _box(Color(SURFACE, 0.5), 8, pad_y)
	var focus := _box(Color(0, 0, 0, 0), 8, pad_y)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = ACCENT
	for type: String in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		var flat := type in ["CheckButton", "CheckBox"]
		t.set_stylebox("normal", type, _box(Color(0, 0, 0, 0), 8, pad_y) if flat else normal)
		t.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.05), 8, pad_y) if flat else hover)
		t.set_stylebox("pressed", type, _box(Color(0, 0, 0, 0), 8, pad_y) if flat else pressed)
		t.set_stylebox("hover_pressed", type, _box(Color(1, 1, 1, 0.05), 8, pad_y) if flat else pressed)
		t.set_stylebox("disabled", type, _box(Color(0, 0, 0, 0), 8, pad_y) if flat else disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_DIM)

	# Ação principal da tela (Treinar, Entrar, Voltar ao jogo...): cor de destaque.
	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	var primary := _box(ACCENT_DARK, 8, pad_y)
	var primary_hover := _box(ACCENT, 8, pad_y)
	t.set_stylebox("normal", "PrimaryButton", primary)
	t.set_stylebox("hover", "PrimaryButton", primary_hover)
	t.set_stylebox("pressed", "PrimaryButton", _box(ACCENT_DARK.darkened(0.25), 8, pad_y))
	t.set_stylebox("hover_pressed", "PrimaryButton", _box(ACCENT_DARK.darkened(0.25), 8, pad_y))

	var field := _box(FIELD, 6, pad_y)
	field.set_border_width_all(1)
	field.border_color = Color(1, 1, 1, 0.08)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	for type: String in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, _box(Color(FIELD, 0.5), 6, pad_y))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_placeholder_color", type, TEXT_DIM)
		t.set_color("caret_color", type, ACCENT)
		t.set_color("selection_color", type, Color(ACCENT, 0.35))

	var popup := _box(Color(0.1, 0.11, 0.15, 0.98), 8, 6.0)
	popup.set_border_width_all(1)
	popup.border_color = Color(1, 1, 1, 0.1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(ACCENT_DARK, 6, 4.0))
	t.set_constant("v_separation", "PopupMenu", 12 if touch else 6)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	# Sliders: trilho fino, parte preenchida na cor de destaque, área de toque maior.
	var track := _box(Color(1, 1, 1, 0.12), 3, 0.0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(ACCENT, 3, 0.0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	var bar_bg := _box(Color(1, 1, 1, 0.1), 4, 0.0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 4, 0.0))

	# Abas: a selecionada com a cor de destaque embaixo.
	var tab := _box(Color(0, 0, 0, 0), 6, pad_y)
	tab.content_margin_left = 16
	tab.content_margin_right = 16
	var tab_selected := _box(SURFACE, 6, pad_y)
	tab_selected.content_margin_left = 16
	tab_selected.content_margin_right = 16
	tab_selected.border_width_bottom = 3
	tab_selected.border_color = ACCENT
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(1, 1, 1, 0.05), 6, pad_y))
	t.set_stylebox("tab_selected", "TabContainer", tab_selected)
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0.2), 8, 8.0))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)

	# Barras de rolagem: grossas no toque (dá para arrastar com o dedo).
	var thickness := 12 if touch else 8
	for type: String in ["VScrollBar", "HScrollBar"]:
		var scroll_bg := _box(Color(1, 1, 1, 0.04), thickness / 2, 0.0)
		scroll_bg.content_margin_left = thickness / 2
		scroll_bg.content_margin_right = thickness / 2
		scroll_bg.content_margin_top = thickness / 2
		scroll_bg.content_margin_bottom = thickness / 2
		t.set_stylebox("scroll", type, scroll_bg)
		t.set_stylebox("grabber", type, _box(Color(1, 1, 1, 0.25), thickness / 2, 0.0))
		t.set_stylebox("grabber_highlight", type, _box(Color(1, 1, 1, 0.4), thickness / 2, 0.0))
		t.set_stylebox("grabber_pressed", type, _box(ACCENT, thickness / 2, 0.0))

	# Interruptor desenhado aqui: o padrão quase some no painel escuro.
	var switch_scale := 1.25 if touch else 1.0
	t.set_icon("checked", "CheckButton", _switch_icon(true, false, switch_scale))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false, false, switch_scale))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true, true, switch_scale))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, true, switch_scale))

	t.set_color("font_color", "Label", TEXT)
	return t


## Trilho arredondado com bolinha: azul e à direita quando ligado.
static func _switch_icon(on: bool, disabled: bool, scale: float) -> ImageTexture:
	var w := roundi(44 * scale)
	var h := roundi(24 * scale)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(0.32, 0.36, 0.45)
	var knob := Color.WHITE if on else Color(0.85, 0.87, 0.92)
	if disabled:
		track.a = 0.4
		knob.a = 0.5
	var r := h * 0.5
	var knob_r := r - 3.0 * scale
	var knob_x := (w - r) if on else r
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distância até o segmento central do trilho (cápsula).
			var cx := clampf(p.x, r, w - r)
			var track_alpha := clampf(r - p.distance_to(Vector2(cx, r)) + 0.5, 0.0, 1.0)
			var knob_alpha := clampf(knob_r - p.distance_to(Vector2(knob_x, r)) + 0.5, 0.0, 1.0)
			var color := Color(track, track.a * track_alpha).blend(Color(knob, knob.a * knob_alpha))
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _box(color: Color, radius: int, pad_y: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	box.anti_aliasing = true
	return box
