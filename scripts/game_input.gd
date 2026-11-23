extends Node
## Autoload "GameInput": esconde a diferença entre PC e celular.
## No PC o jogo está "ativo" quando o mouse está capturado; no celular
## (controles de toque) quando não está pausado. Os controles de toque
## escrevem aqui o movimento, a mira e o tiro; o player só lê.

## Celular (app ou navegador do celular), ou PC iniciado com "-- --touch"
## (para testar os controles de toque).
var touch: bool = is_phone() or OS.get_cmdline_user_args().has("--touch")

## Joystick esquerdo, -1..1 em cada eixo (y negativo = frente).
var move: Vector2 = Vector2.ZERO
var jump_pressed: bool = false
var fire_held: bool = false
## Agachar no toque é liga/desliga.
var crouch_toggled: bool = false
var reload_pressed: bool = false
var switch_weapon_pressed: bool = false
var scoreboard_held: bool = false
## Trocar a câmera (primeira / terceira pessoa); vale uma vez por toque.
var view_pressed: bool = false
## Vaga da barra de armas tocada (-1 = nenhuma); vale uma vez.
var weapon_slot_pressed: int = -1

var _paused: bool = true
var _look_delta: Vector2 = Vector2.ZERO


## App de celular ou o jogo aberto no navegador de um celular/tablet.
static func is_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


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


## Pulo, recarga e troca de arma valem uma vez por toque.
func consume_jump() -> bool:
	var pressed := jump_pressed
	jump_pressed = false
	return pressed


func consume_reload() -> bool:
	var pressed := reload_pressed
	reload_pressed = false
	return pressed


func consume_view() -> bool:
	var pressed := view_pressed
	view_pressed = false
	return pressed


func consume_weapon_slot() -> int:
	var slot := weapon_slot_pressed
	weapon_slot_pressed = -1
	return slot


func consume_switch_weapon() -> bool:
	var pressed := switch_weapon_pressed
	switch_weapon_pressed = false
	return pressed


## Vibração curta no celular (respeita a opção das Configurações).
func vibrate(duration_ms: int) -> void:
	if is_phone() and Settings.vibration:
		Input.vibrate_handheld(duration_ms)


func reset_touch_state() -> void:
	move = Vector2.ZERO
	jump_pressed = false
	fire_held = false
	reload_pressed = false
	switch_weapon_pressed = false
	scoreboard_held = false
	view_pressed = false
	weapon_slot_pressed = -1
	_look_delta = Vector2.ZERO
