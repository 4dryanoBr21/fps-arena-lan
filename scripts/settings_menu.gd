extends Control
## Painel de configurações. As mudanças valem na hora; o arquivo é salvo ao fechar.

signal closed

@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var sensitivity_value: Label = %SensitivityValue
@onready var invert_y_check: CheckButton = %InvertYCheck
@onready var fov_slider: HSlider = %FovSlider
@onready var fov_value: Label = %FovValue
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var render_scale_slider: HSlider = %RenderScaleSlider
@onready var render_scale_value: Label = %RenderScaleValue
@onready var show_fps_check: CheckButton = %ShowFpsCheck
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton
@onready var grid: GridContainer = $Center/Panel/Margin/VBox/Grid
@onready var note: Label = $Center/Panel/Margin/VBox/Note


func _ready() -> void:
	hide()
	if OS.has_feature("mobile"):
		# Tela cheia e VSync não se aplicam no celular.
		for row: String in ["Fullscreen", "Vsync"]:
			for suffix: String in ["Label", "Check", "Spacer"]:
				grid.get_node(row + suffix).hide()
	if GameInput.touch:
		note.text = "As mudanças valem na hora e são salvas ao fechar (voltar também fecha)."
		(grid.get_node("SensitivityLabel") as Label).text = "Sensibilidade da mira"
	sensitivity_slider.value_changed.connect(_on_setting_changed.bind("mouse_sensitivity"))
	fov_slider.value_changed.connect(_on_setting_changed.bind("fov"))
	volume_slider.value_changed.connect(_on_setting_changed.bind("master_volume"))
	render_scale_slider.value_changed.connect(_on_setting_changed.bind("render_scale"))
	invert_y_check.toggled.connect(_on_setting_changed.bind("invert_y"))
	fullscreen_check.toggled.connect(_on_setting_changed.bind("fullscreen"))
	vsync_check.toggled.connect(_on_setting_changed.bind("vsync"))
	show_fps_check.toggled.connect(_on_setting_changed.bind("show_fps"))
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
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
	sensitivity_slider.set_value_no_signal(Settings.mouse_sensitivity)
	fov_slider.set_value_no_signal(Settings.fov)
	volume_slider.set_value_no_signal(Settings.master_volume)
	render_scale_slider.set_value_no_signal(Settings.render_scale)
	invert_y_check.set_pressed_no_signal(Settings.invert_y)
	fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	vsync_check.set_pressed_no_signal(Settings.vsync)
	show_fps_check.set_pressed_no_signal(Settings.show_fps)
	_update_value_labels()


func _update_value_labels() -> void:
	sensitivity_value.text = "%.2fx" % Settings.mouse_sensitivity
	fov_value.text = "%d°" % roundi(Settings.fov)
	volume_value.text = "%d%%" % roundi(Settings.master_volume * 100.0)
	render_scale_value.text = "%d%%" % roundi(Settings.render_scale * 100.0)


func _on_setting_changed(value: Variant, key: String) -> void:
	Settings.set(key, value)
	Settings.apply()
	_update_value_labels()


func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_sync_controls()
