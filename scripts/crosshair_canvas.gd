class_name CrosshairCanvas
extends Control
## Grade para desenhar a mira, pixel a pixel. Botão esquerdo (ou o dedo)
## pinta, direito apaga; com `eraser` ligado o esquerdo também apaga. Com
## `mirror` cada pixel é repetido nos 4 quadrantes. Escreve direto em
## Settings.crosshair_pixels e avisa por Settings.changed.

signal painted

const GRID: int = Crosshair.GRID
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const CENTER_COLOR := Color(1.0, 0.4, 0.3, 0.6)
const BACKGROUND := Color(0.04, 0.05, 0.07, 1.0)

var eraser: bool = false
var mirror: bool = true

## Valor que o arraste atual escreve (1 pinta, 0 apaga); -1 = sem arraste.
var _stroke: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	Settings.changed.connect(queue_redraw)


func cell_size() -> float:
	return floorf(minf(size.x, size.y) / GRID)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
		if button.pressed:
			var erase := eraser or button.button_index == MOUSE_BUTTON_RIGHT
			_stroke = 0 if erase else 1
			_paint_at(button.position)
		else:
			_stroke = -1
		accept_event()
	elif event is InputEventMouseMotion and _stroke >= 0:
		_paint_at((event as InputEventMouseMotion).position)
		accept_event()


func _paint_at(local: Vector2) -> void:
	var cell := cell_size()
	if cell <= 0.0:
		return
	var origin := _grid_origin(cell)
	var x := floori((local.x - origin.x) / cell)
	var y := floori((local.y - origin.y) / cell)
	if x < 0 or y < 0 or x >= GRID or y >= GRID:
		return
	var pixels: PackedByteArray = Settings.crosshair_pixels
	if not Crosshair.is_valid_pixels(pixels):
		pixels = Crosshair.default_pixels()
	var changed := false
	for cell_pos in _mirrored(Vector2i(x, y)):
		var index := cell_pos.y * GRID + cell_pos.x
		if pixels[index] != _stroke:
			pixels[index] = _stroke
			changed = true
	if not changed:
		return
	Settings.crosshair_pixels = pixels
	Settings.changed.emit()
	painted.emit()


func _mirrored(cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	if mirror:
		var last := GRID - 1
		for other: Vector2i in [Vector2i(last - cell.x, cell.y), Vector2i(cell.x, last - cell.y),
				Vector2i(last - cell.x, last - cell.y)]:
			if not cells.has(other):
				cells.append(other)
	return cells


func _grid_origin(cell: float) -> Vector2:
	return ((size - Vector2.ONE * cell * GRID) * 0.5).floor()


func _draw() -> void:
	var cell := cell_size()
	var origin := _grid_origin(cell)
	var side := cell * GRID
	draw_rect(Rect2(origin, Vector2.ONE * side), BACKGROUND)
	var pixels: PackedByteArray = Settings.crosshair_pixels
	if Crosshair.is_valid_pixels(pixels):
		var color := Settings.crosshair_color
		color.a = 1.0
		for y in GRID:
			for x in GRID:
				if pixels[y * GRID + x] != 0:
					draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell), color)
	for i in GRID + 1:
		draw_line(origin + Vector2(i * cell, 0), origin + Vector2(i * cell, side), GRID_COLOR)
		draw_line(origin + Vector2(0, i * cell), origin + Vector2(side, i * cell), GRID_COLOR)
	# Marca a célula do centro (onde a bala vai).
	var mid := GRID / 2
	draw_rect(Rect2(origin + Vector2(mid, mid) * cell, Vector2.ONE * cell), CENTER_COLOR, false, 2.0)
