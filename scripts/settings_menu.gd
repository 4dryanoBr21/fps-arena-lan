class_name SettingsMenu
extends Control
## Painel de configurações. As mudanças valem na hora; o arquivo é salvo ao fechar.
## Linhas que não se aplicam à plataforma (tela cheia no celular, opções de
## toque no PC) ficam escondidas.

signal closed
signal touch_layout_requested
signal crosshair_requested

## Linha -> chave em Settings. Sliders mostram o valor ao lado.
const SLIDERS := {
	"Sensitivity": "mouse_sensitivity",
	"TouchSensitivity": "touch_sensitivity",
	"Fov": "fov",
	"Volume": "master_volume",
	"RenderScale": "render_scale",
	"ButtonScale": "button_scale",
}
const CHECKS := {
	"InvertY": "invert_y",
	"Fullscreen": "fullscreen",
	"Vsync": "vsync",
	"ShowFps": "show_fps",
	"DamageNumbers": "damage_numbers",
	"Vibration": "vibration",
	"AimAssist": "aim_assist",
	"Gyro": "gyro_aim",
}
const DESKTOP_ONLY := ["Sensitivity", "Fullscreen", "Vsync"]
const TOUCH_ONLY := ["TouchSensitivity", "ButtonScale", "Vibration", "AimAssist", "Gyro", "TouchLayout"]

@onready var grid: GridContainer = $Center/Panel/Margin/VBox/Scroll/Grid
@onready var quality_option: OptionButton = %QualityOption
@onready var touch_layout_button: Button = %TouchLayoutButton
@onready var note: Label = %Note
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	hide()
	var mobile := OS.has_feature("mobile")
	for row: String in DESKTOP_ONLY:
		if mobile:
			_hide_row(row)
	for row: String in TOUCH_ONLY:
		if not GameInput.touch:
			_hide_row(row)
	if GameInput.touch:
		note.text = "As mudanças valem na hora e são salvas ao fechar (voltar também fecha)."

	for row: String in SLIDERS:
		_slider(row).value_changed.connect(_on_setting_changed.bind(SLIDERS[row]))
	for row: String in CHECKS:
		_check(row).toggled.connect(_on_setting_changed.bind(CHECKS[row]))
	quality_option.item_selected.connect(_on_setting_changed.bind("quality"))
	touch_layout_button.pressed.connect(_on_touch_layout_pressed)
	%CrosshairButton.pressed.connect(crosshair_requested.emit)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## in_game: ajustar a posição dos botões só faz sentido com o HUD na tela.
func open(in_game: bool = false) -> void:
	touch_layout_button.disabled = not in_game
	_sync_controls()
	show()
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	Settings.save_settings()
	hide()
	closed.emit()


func _hide_row(row: String) -> void:
	for child in grid.get_children():
		if child.name.begins_with(row) and child.name.trim_prefix(row) in ["Label", "Slider", "Value", "Check", "Spacer", "Button", "Option"]:
			child.hide()


func _slider(row: String) -> HSlider:
	return grid.get_node(row + "Slider") as HSlider


func _check(row: String) -> CheckButton:
	return grid.get_node(row + "Check") as CheckButton


## Copia os valores atuais para os controles sem disparar os sinais.
func _sync_controls() -> void:
	for row: String in SLIDERS:
		_slider(row).set_value_no_signal(Settings.get(SLIDERS[row]))
	for row: String in CHECKS:
		_check(row).set_pressed_no_signal(Settings.get(CHECKS[row]))
	quality_option.select(Settings.quality)
	_update_value_labels()


func _update_value_labels() -> void:
	(grid.get_node("SensitivityValue") as Label).text = "%.2fx" % Settings.mouse_sensitivity
	(grid.get_node("TouchSensitivityValue") as Label).text = "%.2fx" % Settings.touch_sensitivity
	(grid.get_node("FovValue") as Label).text = "%d°" % roundi(Settings.fov)
	(grid.get_node("VolumeValue") as Label).text = "%d%%" % roundi(Settings.master_volume * 100.0)
	(grid.get_node("RenderScaleValue") as Label).text = "%d%%" % roundi(Settings.render_scale * 100.0)
	(grid.get_node("ButtonScaleValue") as Label).text = "%d%%" % roundi(Settings.button_scale * 100.0)


func _on_setting_changed(value: Variant, key: String) -> void:
	Settings.set(key, value)
	Settings.apply()
	_update_value_labels()


func _on_touch_layout_pressed() -> void:
	close()
	touch_layout_requested.emit()


func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_sync_controls()
