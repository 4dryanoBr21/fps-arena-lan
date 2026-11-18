class_name Crosshair
extends Control
## Mira desenhada a partir das Configurações: estilos prontos (cruz, T,
## ponto, círculo, cruz com ponto) ou o desenho do jogador, pixel a pixel,
## numa grade GRID x GRID. Usada no HUD e na prévia do editor de mira.
## O HUD pinta o acerto com `flash` (0 a 1) na cor `flash_color`.

enum Style { CROSS, T_CROSS, DOT, CIRCLE, CROSS_DOT, DRAWN }

const STYLE_NAMES: Array[String] = ["Cruz", "Cruz em T", "Ponto", "Círculo", "Cruz com ponto", "Desenhada"]
## Lado da grade do desenho (ímpar: tem uma célula bem no centro).
const GRID: int = 21
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)

var flash: float = 0.0:
	set(value):
		flash = value
		queue_redraw()
var flash_color: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.changed.connect(queue_redraw)
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	pivot_offset = size * 0.5


## Desenho padrão: cruz pequena com espaço no meio.
static func default_pixels() -> PackedByteArray:
	var pixels := PackedByteArray()
	pixels.resize(GRID * GRID)
	var mid := GRID / 2
	for offset in range(2, 6):
		for cell: Vector2i in [Vector2i(mid + offset, mid), Vector2i(mid - offset, mid),
				Vector2i(mid, mid + offset), Vector2i(mid, mid - offset)]:
			pixels[cell.y * GRID + cell.x] = 1
	return pixels


static func is_valid_pixels(pixels: Variant) -> bool:
	return pixels is PackedByteArray and (pixels as PackedByteArray).size() == GRID * GRID


func _draw() -> void:
	var center := (size * 0.5).floor()
	var color := Settings.crosshair_color.lerp(flash_color, flash)
	color.a = Settings.crosshair_opacity
	var outline := Settings.crosshair_outline
	match Settings.crosshair_style:
		Style.DRAWN:
			_draw_pixels(center, color, outline)
		Style.DOT:
			_draw_dot(center, color, outline)
		Style.CIRCLE:
			_draw_circle_style(center, color, outline)
		_:
			_draw_cross(center, color, outline, Settings.crosshair_style == Style.T_CROSS)
			if Settings.crosshair_style == Style.CROSS_DOT:
				_draw_dot(center, color, outline)


func _draw_cross(center: Vector2, color: Color, outline: bool, t_shape: bool) -> void:
	var length := Settings.crosshair_size
	var thick := Settings.crosshair_thickness
	var gap := Settings.crosshair_gap
	var half := thick * 0.5
	var arms: Array[Rect2] = [
		Rect2(center.x + gap, center.y - half, length, thick),
		Rect2(center.x - gap - length, center.y - half, length, thick),
		Rect2(center.x - half, center.y + gap, thick, length),
	]
	if not t_shape:
		arms.append(Rect2(center.x - half, center.y - gap - length, thick, length))
	_draw_rects(arms, color, outline)


func _draw_dot(center: Vector2, color: Color, outline: bool) -> void:
	var side := maxf(Settings.crosshair_thickness * 1.5, 2.0)
	_draw_rects([Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side)], color, outline)


func _draw_circle_style(center: Vector2, color: Color, outline: bool) -> void:
	var radius := Settings.crosshair_gap + Settings.crosshair_size * 0.5
	var thick := Settings.crosshair_thickness
	if outline:
		draw_arc(center, radius, 0.0, TAU, 48, OUTLINE_COLOR, thick + 2.0, true)
	draw_arc(center, radius, 0.0, TAU, 48, color, thick, true)


func _draw_pixels(center: Vector2, color: Color, outline: bool) -> void:
	var pixels: PackedByteArray = Settings.crosshair_pixels
	if not is_valid_pixels(pixels):
		return
	var cell := maxf(roundf(Settings.crosshair_pixel_size), 1.0)
	var mid := GRID / 2
	var rects: Array[Rect2] = []
	for y in GRID:
		for x in GRID:
			if pixels[y * GRID + x] != 0:
				rects.append(Rect2(center + Vector2(x - mid - 0.5, y - mid - 0.5) * cell, Vector2.ONE * cell))
	_draw_rects(rects, color, outline)


## Contorno de todos primeiro, depois a cor: o contorno não cobre pixels vizinhos.
func _draw_rects(rects: Array[Rect2], color: Color, outline: bool) -> void:
	if outline:
		var outline_color := OUTLINE_COLOR
		outline_color.a *= color.a
		for rect in rects:
			draw_rect(rect.grow(1.0), outline_color)
	for rect in rects:
		draw_rect(rect, color)
