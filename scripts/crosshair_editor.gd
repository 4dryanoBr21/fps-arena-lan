class_name CrosshairEditor
extends Control
## Editor da mira: estilos prontos com cor e medidas, ou desenho livre na
## grade (CrosshairCanvas). As mudanças valem na hora (o HUD e a prévia leem
## Settings) e são salvas ao fechar. Abre pelas Configurações.

signal closed

## Linha -> chave em Settings.
const SLIDERS := {
	"OpacitySlider": "crosshair_opacity",
	"SizeSlider": "crosshair_size",
	"ThicknessSlider": "crosshair_thickness",
	"GapSlider": "crosshair_gap",
	"PixelSizeSlider": "crosshair_pixel_size",
}

@onready var canvas: CrosshairCanvas = %Canvas
@onready var style_option: OptionButton = %StyleOption
@onready var color_picker: ColorPickerButton = %ColorPicker
@onready var outline_check: CheckButton = %OutlineCheck
@onready var eraser_check: CheckButton = %EraserCheck
@onready var mirror_check: CheckButton = %MirrorCheck
@onready var draw_hint: Label = %DrawHint
@onready var status_label: Label = %StatusLabel
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	hide()
	for style_name in Crosshair.STYLE_NAMES:
		style_option.add_item(style_name)
	if GameInput.touch:
		draw_hint.text = "Arraste o dedo para pintar; ligue a Borracha para apagar. O quadrado vermelho é o centro (onde a bala vai)."
	style_option.item_selected.connect(_set_setting.bind("crosshair_style"))
	color_picker.color_changed.connect(_set_setting.bind("crosshair_color"))
	outline_check.toggled.connect(_set_setting.bind("crosshair_outline"))
	for slider_name: String in SLIDERS:
		(get_node("%" + slider_name) as HSlider).value_changed.connect(_set_setting.bind(SLIDERS[slider_name]))
	eraser_check.toggled.connect(func(on: bool) -> void: canvas.eraser = on)
	mirror_check.toggled.connect(func(on: bool) -> void: canvas.mirror = on)
	canvas.painted.connect(_on_painted)
	%ClearButton.pressed.connect(_set_pixels.bind(PackedByteArray(), "Desenho apagado."))
	%DefaultDrawingButton.pressed.connect(func() -> void: _set_pixels(Crosshair.default_pixels(), "Desenho padrão restaurado."))
	%ResetButton.pressed.connect(_on_reset_pressed)
	UiFit.keep_fitted(self, $Center/Panel)
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	status_label.text = ""
	eraser_check.button_pressed = false
	_sync_controls()
	show()
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	Settings.save_settings()
	hide()
	closed.emit()


## Copia os valores atuais para os controles sem disparar os sinais.
func _sync_controls() -> void:
	style_option.select(Settings.crosshair_style)
	color_picker.color = Settings.crosshair_color
	outline_check.set_pressed_no_signal(Settings.crosshair_outline)
	for slider_name: String in SLIDERS:
		(get_node("%" + slider_name) as HSlider).set_value_no_signal(Settings.get(SLIDERS[slider_name]))


## Só emite changed (não Settings.apply): mexer na mira não precisa
## reaplicar janela, áudio e sombras a cada movimento do slider.
func _set_setting(value: Variant, key: String) -> void:
	Settings.set(key, value)
	Settings.changed.emit()


## Pintar já põe a mira no modo desenhado.
func _on_painted() -> void:
	if Settings.crosshair_style != Crosshair.Style.DRAWN:
		Settings.crosshair_style = Crosshair.Style.DRAWN
		style_option.select(Crosshair.Style.DRAWN)
		status_label.text = "Mira trocada para \"Desenhada\"."
		Settings.changed.emit()


func _set_pixels(pixels: PackedByteArray, message: String) -> void:
	if pixels.size() != Crosshair.GRID * Crosshair.GRID:
		pixels.resize(Crosshair.GRID * Crosshair.GRID)
		pixels.fill(0)
	Settings.crosshair_pixels = pixels
	Settings.changed.emit()
	status_label.text = message


func _on_reset_pressed() -> void:
	Settings.reset_crosshair()
	_sync_controls()
	status_label.text = "Mira padrão (o desenho continua guardado)."
