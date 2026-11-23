class_name UiFit
extends RefCounted
## Encaixa uma tela (menu, Arsenal, Configurações, editores) em qualquer janela,
## sem deixar o texto ilegível:
##  1. Colunas lado a lado (BoxContainer chamado "Columns") viram uma coluna só
##     quando não cabem na largura (celular estreito, janela em pé, 4:3 com a
##     interface grande).
##  2. Listas roláveis internas (ScrollContainer/TabContainer com altura mínima
##     fixa) cedem altura até FLEX_MIN.
##  3. Se ainda faltar espaço, encolhe um pouco (até MIN_SCALE) e, abaixo disso,
##     o painel inteiro rola em vez de diminuir mais.
## Antes ele só encolhia: num celular deitado o menu ficava com letra de 1 mm.

const MARGIN: float = 12.0
## Menor escala aceita antes de passar a rolar.
const MIN_SCALE: float = 0.85
## Altura mínima de uma lista rolável interna.
const FLEX_MIN: float = 140.0
const FLEX_META := &"ui_fit_flex_height"
const SCROLL_NAME := "FitScroll"


## Ajusta sempre que a tela aparece ou a janela muda de tamanho.
static func keep_fitted(root: Control, panel: Control) -> void:
	var scroll := _wrap_in_scroll(panel)
	_mark_flex(panel)
	var refit := func() -> void:
		if not root.visible:
			return
		# Espera o layout assentar: antes dele os textos com quebra de linha
		# ainda não sabem a largura e o painel parece enorme.
		await root.get_tree().process_frame
		await root.get_tree().process_frame
		if root.visible:
			fit(root, panel, scroll)
	root.visibility_changed.connect(refit)
	root.get_viewport().size_changed.connect(refit)
	refit.call()


static func fit(root: Control, panel: Control, scroll: ScrollContainer = null) -> void:
	var view := root.get_viewport_rect().size
	var avail := view - Vector2.ONE * MARGIN * 2.0
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	root.scale = Vector2.ONE
	root.offset_right = 0.0
	root.offset_bottom = 0.0

	# 1. Colunas: tenta lado a lado; empilha se não couber na largura.
	for box in _columns(panel):
		box.vertical = false
	var needed := panel.get_combined_minimum_size()
	if needed.x > avail.x / MIN_SCALE:
		for box in _columns(panel):
			box.vertical = true
		needed = panel.get_combined_minimum_size()

	# 2. Listas internas: crescem até mostrar tudo se sobrar altura (monitor
	# grande) e cedem altura se faltar (celular).
	var flex := _flex_controls(panel)
	for control in flex:
		control.custom_minimum_size.y = float(control.get_meta(FLEX_META))
	needed = panel.get_combined_minimum_size()
	var spare := avail.y - needed.y
	for control in flex:
		if spare <= 0.0:
			break
		var grow := minf(spare, _content_height(control) - control.custom_minimum_size.y)
		if grow > 0.0:
			control.custom_minimum_size.y += grow
			spare -= grow
	needed = panel.get_combined_minimum_size()
	var overflow := needed.y - avail.y
	for control in flex:
		if overflow <= 0.0:
			break
		var give := minf(overflow, control.custom_minimum_size.y - FLEX_MIN)
		if give > 0.0:
			control.custom_minimum_size.y -= give
			overflow -= give
	needed = panel.get_combined_minimum_size()

	# 3. Encolhe até MIN_SCALE; o que faltar, rola.
	var factor := 1.0
	if needed.x > 0.0 and needed.y > 0.0:
		factor = clampf(minf(avail.x / needed.x, avail.y / needed.y), MIN_SCALE, 1.0)
	root.scale = Vector2.ONE * factor
	root.offset_right = view.x * (1.0 / factor - 1.0)
	root.offset_bottom = view.y * (1.0 / factor - 1.0)
	if scroll != null:
		scroll.custom_minimum_size = Vector2(0.0, minf(needed.y, avail.y / factor))


## Coloca o painel dentro de um ScrollContainer só vertical (uma vez).
static func _wrap_in_scroll(panel: Control) -> ScrollContainer:
	var parent := panel.get_parent()
	if parent is ScrollContainer and parent.name == SCROLL_NAME:
		return parent
	var scroll := ScrollContainer.new()
	scroll.name = SCROLL_NAME
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.size_flags_horizontal = panel.size_flags_horizontal
	scroll.size_flags_vertical = panel.size_flags_vertical
	var index := panel.get_index()
	parent.add_child(scroll)
	parent.move_child(scroll, index)
	# reparent mantém o dono dos nós: os nomes únicos (%Botao) continuam valendo.
	scroll.owner = panel.owner
	panel.reparent(scroll, false)
	return scroll


## Listas roláveis e abas com altura mínima fixa podem ceder espaço.
static func _mark_flex(panel: Control) -> void:
	for node in panel.find_children("*", "Control", true, false):
		var control := node as Control
		if (control is ScrollContainer or control is TabContainer) and control.custom_minimum_size.y > FLEX_MIN \
				and not control.has_meta(FLEX_META):
			control.set_meta(FLEX_META, control.custom_minimum_size.y)


## Altura que a lista precisa para mostrar tudo sem rolar.
static func _content_height(control: Control) -> float:
	if control is ScrollContainer:
		for child in control.get_children():
			if child is Control and not (child is ScrollBar):
				return (child as Control).get_combined_minimum_size().y
	elif control is TabContainer:
		# Abas (Arsenal): a lista da aba aberta mais a barra das abas.
		var page := (control as TabContainer).get_current_tab_control()
		if page is ScrollContainer and page.size.y > 0.0:
			return _content_height(page) + (control.size.y - page.size.y)
	return float(control.get_meta(FLEX_META))


static func _flex_controls(panel: Control) -> Array[Control]:
	var list: Array[Control] = []
	for node in panel.find_children("*", "Control", true, false):
		if (node as Control).has_meta(FLEX_META):
			list.append(node)
	return list


static func _columns(panel: Control) -> Array[BoxContainer]:
	var list: Array[BoxContainer] = []
	for node in panel.find_children("Columns", "BoxContainer", true, false):
		list.append(node)
	return list
