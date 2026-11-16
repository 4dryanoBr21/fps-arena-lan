extends Control
## Controles de toque (celular): joystick flutuante na metade esquerda,
## arrastar na metade direita para mirar, botões de atirar e pular e o de pausa.
## Tudo desenhado em _draw; os toques são lidos em _input pelo índice do dedo
## e repassados ao GameInput.

const STICK_RADIUS: float = 72.0
const KNOB_RADIUS: float = 30.0
## Posições relativas aos cantos da tela.
const STICK_REST: Vector2 = Vector2(180.0, -180.0)
const FIRE_CENTER: Vector2 = Vector2(-150.0, -200.0)
const FIRE_RADIUS: float = 64.0
const JUMP_CENTER: Vector2 = Vector2(-290.0, -95.0)
const JUMP_RADIUS: float = 46.0
const PAUSE_CENTER: Vector2 = Vector2(0.0, 44.0)
const PAUSE_RADIUS: float = 26.0
## Folga no toque dos botões (o dedo não acerta o círculo exato).
const HIT_SLACK: float = 1.25

var _stick_finger: int = -1
var _stick_origin: Vector2
var _stick_pos: Vector2
var _fire_finger: int = -1
var _jump_finger: int = -1
## Dedos que estão mirando (inclui o do botão de tiro) -> última posição.
var _look_fingers: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var pos: Vector2 = (make_input_local(touch) as InputEventScreenTouch).position
		if touch.pressed:
			_on_press(touch.index, pos)
		else:
			_on_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_drag(drag.index, (make_input_local(drag) as InputEventScreenDrag).position)


func _on_press(finger: int, pos: Vector2) -> void:
	if _hit(pos, _pause_center(), PAUSE_RADIUS):
		GameInput.release()
	elif _hit(pos, _fire_center(), FIRE_RADIUS):
		_fire_finger = finger
		GameInput.fire_held = true
		_look_fingers[finger] = pos
	elif _hit(pos, _jump_center(), JUMP_RADIUS):
		_jump_finger = finger
		GameInput.jump_pressed = true
	elif pos.x < size.x * 0.5 and _stick_finger < 0:
		_stick_finger = finger
		_stick_origin = pos
		_stick_pos = pos
	else:
		_look_fingers[finger] = pos
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
	if finger == _fire_finger:
		_fire_finger = -1
		GameInput.fire_held = false
	if finger == _jump_finger:
		_jump_finger = -1
	_look_fingers.erase(finger)
	queue_redraw()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		return
	_stick_finger = -1
	_fire_finger = -1
	_jump_finger = -1
	_look_fingers.clear()
	GameInput.reset_touch_state()


func _hit(pos: Vector2, center: Vector2, radius: float) -> bool:
	return pos.distance_to(center) <= radius * HIT_SLACK


func _fire_center() -> Vector2:
	return size + FIRE_CENTER


func _jump_center() -> Vector2:
	return size + JUMP_CENTER


func _pause_center() -> Vector2:
	return Vector2(size.x * 0.5, 0.0) + PAUSE_CENTER


func _draw() -> void:
	var white := Color(1.0, 1.0, 1.0, 0.85)

	# Joystick: parado no canto quando ninguém está tocando.
	var base := _stick_origin if _stick_finger >= 0 else Vector2(STICK_REST.x, size.y + STICK_REST.y)
	var knob := _stick_pos if _stick_finger >= 0 else base
	var stick_alpha := 0.35 if _stick_finger >= 0 else 0.18
	draw_circle(base, STICK_RADIUS, Color(1.0, 1.0, 1.0, stick_alpha * 0.5))
	draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, stick_alpha + 0.2), 2.0, true)
	draw_circle(knob, KNOB_RADIUS, Color(1.0, 1.0, 1.0, stick_alpha + 0.3))

	# Atirar.
	var fire := _fire_center()
	var fire_alpha := 0.6 if _fire_finger >= 0 else 0.35
	draw_circle(fire, FIRE_RADIUS, Color(0.9, 0.2, 0.15, fire_alpha))
	draw_arc(fire, FIRE_RADIUS, 0.0, TAU, 48, white, 2.0, true)
	draw_arc(fire, 18.0, 0.0, TAU, 32, white, 3.0, true)
	draw_line(fire + Vector2(-30, 0), fire + Vector2(-10, 0), white, 3.0)
	draw_line(fire + Vector2(10, 0), fire + Vector2(30, 0), white, 3.0)
	draw_line(fire + Vector2(0, -30), fire + Vector2(0, -10), white, 3.0)
	draw_line(fire + Vector2(0, 10), fire + Vector2(0, 30), white, 3.0)

	# Pular: seta para cima.
	var jump := _jump_center()
	var jump_alpha := 0.55 if _jump_finger >= 0 else 0.3
	draw_circle(jump, JUMP_RADIUS, Color(0.2, 0.5, 0.95, jump_alpha))
	draw_arc(jump, JUMP_RADIUS, 0.0, TAU, 48, white, 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		jump + Vector2(0, -20), jump + Vector2(18, 2), jump + Vector2(7, 2),
		jump + Vector2(7, 18), jump + Vector2(-7, 18), jump + Vector2(-7, 2),
		jump + Vector2(-18, 2)]), white)

	# Pausa: duas barras.
	var pause := _pause_center()
	draw_circle(pause, PAUSE_RADIUS, Color(0.0, 0.0, 0.0, 0.4))
	draw_arc(pause, PAUSE_RADIUS, 0.0, TAU, 32, white, 2.0, true)
	draw_rect(Rect2(pause + Vector2(-9, -10), Vector2(6, 20)), white)
	draw_rect(Rect2(pause + Vector2(3, -10), Vector2(6, 20)), white)
