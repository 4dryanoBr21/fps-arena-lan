extends Node
## Autoload "GameInput": esconde a diferença entre PC e celular.
## No PC o jogo está "ativo" quando o mouse está capturado; no celular
## (controles de toque) quando não está pausado. Os controles de toque
## escrevem aqui o movimento, a mira e o tiro; o player só lê.

## Celular, ou PC iniciado com "-- --touch" (para testar os controles de toque).
var touch: bool = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")

## Joystick esquerdo, -1..1 em cada eixo (y negativo = frente).
var move: Vector2 = Vector2.ZERO
var jump_pressed: bool = false
var fire_held: bool = false

var _paused: bool = true
var _look_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	if touch:
		# Botões e textos maiores para o dedo.
		get_tree().root.content_scale_factor = 1.3


func is_active() -> bool:
	if touch:
		return not _paused
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Entra no jogo (captura o mouse / mostra os controles de toque).
func capture() -> void:
	if touch:
		_paused = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Libera para menus (solta o mouse / esconde os controles de toque).
func release() -> void:
	if touch:
		_paused = true
		reset_touch_state()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func add_look(delta: Vector2) -> void:
	_look_delta += delta


## Devolve o arraste de mira acumulado desde a última chamada, em pixels.
func consume_look() -> Vector2:
	var delta := _look_delta
	_look_delta = Vector2.ZERO
	return delta


## Pulo vale uma vez por toque.
func consume_jump() -> bool:
	var pressed := jump_pressed
	jump_pressed = false
	return pressed


func reset_touch_state() -> void:
	move = Vector2.ZERO
	jump_pressed = false
	fire_held = false
	_look_delta = Vector2.ZERO
