extends Control
## Teste do editor de mira em cena (com os autoloads): pinta na grade com
## eventos de mouse simulados e confere o desenho salvo em Settings, o
## espelhamento, a borracha e a troca automática para o estilo desenhado.
## Mexe só em memória: não chama close() (que salvaria as configurações).
##   godot --headless --path . res://tests/crosshair_test.tscn

const GRID: int = Crosshair.GRID

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	var editor := (load("res://scenes/crosshair_editor.tscn") as PackedScene).instantiate() as CrosshairEditor
	add_child(editor)
	editor.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var canvas := editor.canvas

	var pixels := Crosshair.default_pixels()
	var mid := GRID / 2
	_check(Crosshair.is_valid_pixels(pixels), "desenho padrão tem o tamanho da grade")
	_check(pixels[mid * GRID + mid] == 0, "desenho padrão deixa o centro livre")
	_check(_count(pixels) == 16 and _symmetric(pixels), "desenho padrão: cruz simétrica de 16 pixels")

	Settings.crosshair_style = Crosshair.Style.CROSS
	editor._set_pixels(PackedByteArray(), "")
	_check(_count(Settings.crosshair_pixels) == 0, "Limpar apaga o desenho")

	# Pinta a célula (2, 3) com espelho: aparecem as 4 cópias.
	canvas.mirror = true
	_click(canvas, Vector2i(2, 3), MOUSE_BUTTON_LEFT)
	var drawn: PackedByteArray = Settings.crosshair_pixels
	var last := GRID - 1
	_check(_count(drawn) == 4, "espelho pinta os 4 quadrantes (%d)" % _count(drawn))
	_check(drawn[3 * GRID + 2] == 1 and drawn[3 * GRID + last - 2] == 1 \
		and drawn[(last - 3) * GRID + 2] == 1 and drawn[(last - 3) * GRID + last - 2] == 1, "cópias nos lugares certos")
	_check(Settings.crosshair_style == Crosshair.Style.DRAWN, "pintar troca a mira para Desenhada")

	# Arraste sem espelho: uma linha de 5 células.
	canvas.mirror = false
	_drag(canvas, Vector2i(5, mid), Vector2i(9, mid))
	_check(_count(Settings.crosshair_pixels) == 9, "arraste pinta a linha (%d)" % _count(Settings.crosshair_pixels))

	# Botão direito apaga; borracha ligada faz o esquerdo apagar.
	_click(canvas, Vector2i(5, mid), MOUSE_BUTTON_RIGHT)
	canvas.eraser = true
	_click(canvas, Vector2i(6, mid), MOUSE_BUTTON_LEFT)
	_check(_count(Settings.crosshair_pixels) == 7, "botão direito e borracha apagam (%d)" % _count(Settings.crosshair_pixels))

	# Fora da grade não faz nada.
	canvas.eraser = false
	var before := Settings.crosshair_pixels.duplicate()
	_press(canvas, Vector2(-50, -50), MOUSE_BUTTON_LEFT, true)
	_press(canvas, Vector2(-50, -50), MOUSE_BUTTON_LEFT, false)
	_check(Settings.crosshair_pixels == before, "clique fora da grade é ignorado")

	# A mira desenha sem erro em todos os estilos.
	var cross := Crosshair.new()
	cross.custom_minimum_size = Vector2(128, 128)
	add_child(cross)
	for style in Crosshair.Style.size():
		Settings.crosshair_style = style
		cross.queue_redraw()
		await get_tree().process_frame
	_check(true, "todos os estilos desenham")

	print("%d verificações, %d falha(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _cell_center(canvas: CrosshairCanvas, cell: Vector2i) -> Vector2:
	var side := canvas.cell_size()
	return canvas._grid_origin(side) + (Vector2(cell) + Vector2.ONE * 0.5) * side


func _press(canvas: CrosshairCanvas, at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	canvas._gui_input(event)


func _click(canvas: CrosshairCanvas, cell: Vector2i, button: MouseButton) -> void:
	_press(canvas, _cell_center(canvas, cell), button, true)
	_press(canvas, _cell_center(canvas, cell), button, false)


func _drag(canvas: CrosshairCanvas, from: Vector2i, to: Vector2i) -> void:
	_press(canvas, _cell_center(canvas, from), MOUSE_BUTTON_LEFT, true)
	for x in range(from.x, to.x + 1):
		var motion := InputEventMouseMotion.new()
		motion.position = _cell_center(canvas, Vector2i(x, from.y))
		canvas._gui_input(motion)
	_press(canvas, _cell_center(canvas, to), MOUSE_BUTTON_LEFT, false)


func _count(pixels: PackedByteArray) -> int:
	var total := 0
	for value in pixels:
		total += value
	return total


func _symmetric(pixels: PackedByteArray) -> bool:
	for y in GRID:
		for x in GRID:
			if pixels[y * GRID + x] != pixels[y * GRID + GRID - 1 - x] or pixels[y * GRID + x] != pixels[(GRID - 1 - y) * GRID + x]:
				return false
	return true


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALHOU: " + label)
