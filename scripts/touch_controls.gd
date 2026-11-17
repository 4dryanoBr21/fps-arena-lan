class_name TouchControls
extends Control
## Controles de toque (celular): joystick flutuante na metade esquerda,
## arrastar na metade direita para mirar e botões de atirar, pular, agachar,
## recarregar, trocar de arma, placar e pausa. Tudo desenhado em _draw; os
## toques são lidos em _input pelo índice do dedo e repassados ao GameInput.
## No modo de edição os botões são arrastados e a posição vai para Settings.

signal editing_finished

const STICK_RADIUS: float = 72.0
const KNOB_RADIUS: float = 30.0
const STICK_REST: Vector2 = Vector2(180.0, -180.0)
## Folga no toque dos botões (o dedo não acerta o círculo exato).
const HIT_SLACK: float = 1.25
## id -> [canto da tela (fração), deslocamento a partir dele, raio]
const BUTTONS := {
	"fire": [Vector2(1, 1), Vector2(-150, -200), 64.0],
	"jump": [Vector2(1, 1), Vector2(-290, -95), 46.0],
	"crouch": [Vector2(1, 1), Vector2(-60, -85), 36.0],
	"reload": [Vector2(1, 1), Vector2(-300, -235), 34.0],
	"weapon": [Vector2(1, 1), Vector2(-70, -350), 32.0],
	"scoreboard": [Vector2(0.5, 0), Vector2(-80, 44), 26.0],
	"pause": [Vector2(0.5, 0), Vector2(80, 44), 26.0],
}
const EDIT_DONE_SIZE: Vector2 = Vector2(150, 48)

var editing: bool = false

var _stick_finger: int = -1
var _stick_origin: Vector2
var _stick_pos: Vector2
## botão -> dedo que está segurando
var _held: Dictionary = {}
## Dedos que estão mirando (inclui o do botão de tiro) -> última posição.
var _look_fingers: Dictionary = {}
## Edição: dedo -> botão sendo arrastado.
var _dragging: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)
	Settings.changed.connect(queue_redraw)


func start_editing() -> void:
	editing = true
	_release_all()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var pos: Vector2 = (make_input_local(touch) as InputEventScreenTouch).position
		if editing:
			_edit_touch(touch.index, pos, touch.pressed)
		elif touch.pressed:
			_on_press(touch.index, pos)
		else:
			_on_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var pos: Vector2 = (make_input_local(drag) as InputEventScreenDrag).position
		if editing:
			_edit_drag(drag.index, pos)
		else:
			_on_drag(drag.index, pos)


func _on_press(finger: int, pos: Vector2) -> void:
	var button := _button_at(pos)
	match button:
		"pause":
			GameInput.release()
		"fire":
			GameInput.fire_held = true
			_look_fingers[finger] = pos
		"jump":
			GameInput.jump_pressed = true
		"crouch":
			GameInput.crouch_toggled = not GameInput.crouch_toggled
		"reload":
			GameInput.reload_pressed = true
		"weapon":
			GameInput.switch_weapon_pressed = true
		"scoreboard":
			GameInput.scoreboard_held = true
		_:
			if pos.x < size.x * 0.5 and _stick_finger < 0:
				_stick_finger = finger
				_stick_origin = pos
				_stick_pos = pos
			else:
				_look_fingers[finger] = pos
	if not button.is_empty():
		_held[button] = finger
	queue_redraw()


func _on_drag(finger: int, pos: Vector2) -> void:
	if finger == _stick_finger:
		var offset := pos - _stick_origin
		if offset.length() > STICK_RADIUS:
			# A base acompanha o dedo quando ele passa do limite.
			_stick_origin = pos - offset.normalized() * STICK_RADIUS
			offset = pos - _stick_origin
		_stick_pos = pos
		GameInput.move = offset / STICK_RADIUS
		queue_redraw()
	elif _look_fingers.has(finger):
		GameInput.add_look(pos - (_look_fingers[finger] as Vector2))
		_look_fingers[finger] = pos


func _on_release(finger: int) -> void:
	if finger == _stick_finger:
		_stick_finger = -1
		GameInput.move = Vector2.ZERO
	for button: String in _held.keys():
		if _held[button] == finger:
			_held.erase(button)
			if button == "fire":
				GameInput.fire_held = false
			elif button == "scoreboard":
				GameInput.scoreboard_held = false
	_look_fingers.erase(finger)
	queue_redraw()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_release_all()


func _release_all() -> void:
	_stick_finger = -1
	_held.clear()
	_look_fingers.clear()
	_dragging.clear()
	GameInput.reset_touch_state()


# --- Modo de edição -------------------------------------------------------------

func _edit_touch(finger: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		_dragging.erase(finger)
		return
	if _done_rect().has_point(pos):
		editing = false
		Settings.save_settings()
		editing_finished.emit()
	elif _reset_rect().has_point(pos):
		Settings.touch_layout = {}
	else:
		var button := _button_at(pos)
		if not button.is_empty():
			_dragging[finger] = button
	queue_redraw()


func _edit_drag(finger: int, pos: Vector2) -> void:
	if not _dragging.has(finger) or size.x <= 0.0 or size.y <= 0.0:
		return
	var clamped := pos.clamp(Vector2.ZERO, size)
	var layout := Settings.touch_layout.duplicate()
	layout[_dragging[finger]] = clamped / size
	Settings.touch_layout = layout
	queue_redraw()


func _done_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 + 8, size.y * 0.5 - EDIT_DONE_SIZE.y * 0.5), EDIT_DONE_SIZE)


func _reset_rect() -> Rect2:
	return Rect2(Vector2(size.x * 0.5 - 8 - EDIT_DONE_SIZE.x, size.y * 0.5 - EDIT_DONE_SIZE.y * 0.5), EDIT_DONE_SIZE)


# --- Geometria ------------------------------------------------------------------

func button_center(id: String) -> Vector2:
	if Settings.touch_layout.has(id):
		return (Settings.touch_layout[id] as Vector2) * size
	var spec: Array = BUTTONS[id]
	return size * (spec[0] as Vector2) + (spec[1] as Vector2) * Settings.button_scale


func button_radius(id: String) -> float:
	return float(BUTTONS[id][2]) * Settings.button_scale


func _button_at(pos: Vector2) -> String:
	for id: String in BUTTONS:
		if pos.distance_to(button_center(id)) <= button_radius(id) * HIT_SLACK:
			return id
	return ""


# --- Desenho --------------------------------------------------------------------

func _draw() -> void:
	var white := Color(1.0, 1.0, 1.0, 0.85)

	# Joystick: parado no canto quando ninguém está tocando.
	if not editing:
		var base := _stick_origin if _stick_finger >= 0 else Vector2(STICK_REST.x, size.y + STICK_REST.y)
		var knob := _stick_pos if _stick_finger >= 0 else base
		var stick_alpha := 0.35 if _stick_finger >= 0 else 0.18
		draw_circle(base, STICK_RADIUS, Color(1.0, 1.0, 1.0, stick_alpha * 0.5))
		draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, stick_alpha + 0.2), 2.0, true)
		draw_circle(knob, KNOB_RADIUS, Color(1.0, 1.0, 1.0, stick_alpha + 0.3))

	_draw_button("fire", Color(0.9, 0.2, 0.15))
	_draw_button("jump", Color(0.2, 0.5, 0.95))
	_draw_button("crouch", Color(0.35, 0.75, 0.4), GameInput.crouch_toggled)
	_draw_button("reload", Color(0.85, 0.65, 0.15))
	_draw_button("weapon", Color(0.55, 0.4, 0.85))
	_draw_button("scoreboard", Color(0.0, 0.0, 0.0))
	_draw_button("pause", Color(0.0, 0.0, 0.0))

	var s := Settings.button_scale
	var fire := button_center("fire")
	draw_arc(fire, 18.0 * s, 0.0, TAU, 32, white, 3.0, true)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(fire + dir * 10.0 * s, fire + dir * 30.0 * s, white, 3.0)

	var jump := button_center("jump")
	draw_colored_polygon(_scaled(jump, s, [Vector2(0, -20), Vector2(18, 2), Vector2(7, 2),
		Vector2(7, 18), Vector2(-7, 18), Vector2(-7, 2), Vector2(-18, 2)]), white)

	var crouch := button_center("crouch")
	draw_colored_polygon(_scaled(crouch, s, [Vector2(0, 16), Vector2(16, -2), Vector2(6, -2),
		Vector2(6, -16), Vector2(-6, -16), Vector2(-6, -2), Vector2(-16, -2)]), white)

	var reload := button_center("reload")
	draw_arc(reload, 14.0 * s, 0.4, TAU - 0.4, 24, white, 3.0, true)
	draw_colored_polygon(_scaled(reload, s, [Vector2(14, -10), Vector2(20, 2), Vector2(8, 2)]), white)

	var weapon := button_center("weapon")
	var font := ThemeDB.fallback_font
	draw_string(font, weapon + Vector2(-14, 7) * s, "1/2", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s), white)

	var board := button_center("scoreboard")
	for i in 3:
		draw_rect(Rect2(board + Vector2(-10, -9 + i * 7) * s, Vector2(20, 3) * s), white)

	var pause := button_center("pause")
	draw_rect(Rect2(pause + Vector2(-9, -10) * s, Vector2(6, 20) * s), white)
	draw_rect(Rect2(pause + Vector2(3, -10) * s, Vector2(6, 20) * s), white)

	if editing:
		draw_string(font, Vector2(0, size.y * 0.5 - 48), "Arraste os botões para onde quiser",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, white)
		for rect_and_text: Array in [[_reset_rect(), "Restaurar"], [_done_rect(), "Pronto"]]:
			var rect: Rect2 = rect_and_text[0]
			draw_rect(rect, Color(0.1, 0.12, 0.16, 0.9))
			draw_rect(rect, white, false, 2.0)
			draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 + 7), rect_and_text[1],
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, white)


func _draw_button(id: String, color: Color, active: bool = false) -> void:
	var center := button_center(id)
	var radius := button_radius(id)
	var pressed := _held.has(id) or active or _dragging.values().has(id)
	color.a = 0.6 if pressed else 0.35
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.85), 2.0, true)


func _scaled(center: Vector2, scale_factor: float, points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(center + point * scale_factor)
	return out
