extends Node
## Autoload "Settings": preferências locais do jogador, salvas em user://settings.cfg.
## Cada peer tem as suas; nada aqui passa pela rede.

signal changed

const SAVE_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const DEFAULTS := {
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fov": 80.0,
	"master_volume": 0.8,
	"fullscreen": false,
	"vsync": true,
	"render_scale": 1.0,
	"show_fps": false,
}

## Multiplicador sobre a sensibilidade base do player.gd.
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var fov: float = 80.0
## 0.0 a 1.0 (linear).
var master_volume: float = 0.8
var fullscreen: bool = false
var vsync: bool = true
## Escala da renderização 3D (0.5 = metade da resolução, mais leve).
var render_scale: float = 1.0
var show_fps: bool = false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for key: String in DEFAULTS:
		set(key, config.get_value(SECTION, key, DEFAULTS[key]))


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in DEFAULTS:
		config.set_value(SECTION, key, get(key))
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("Não foi possível salvar as configurações (código %d)." % err)


func reset_to_defaults() -> void:
	for key: String in DEFAULTS:
		set(key, DEFAULTS[key])
	apply()


## Aplica o que é global (janela, áudio, render) e avisa quem depende do resto.
func apply() -> void:
	# No celular a janela é sempre tela cheia e o VSync é do sistema.
	if not OS.has_feature("mobile"):
		var window_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != window_mode:
			DisplayServer.window_set_mode(window_mode)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))

	get_viewport().scaling_3d_scale = render_scale
	changed.emit()
