extends Node
## Autoload "Settings": preferências locais do jogador, salvas em user://settings.cfg.
## Cada peer tem as suas; nada aqui passa pela rede (o apelido vai uma vez, ao entrar).

signal changed

const SAVE_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const QUALITY_LOW: int = 0
const QUALITY_MEDIUM: int = 1
const QUALITY_HIGH: int = 2

var nickname: String = ""
## Multiplicador sobre a sensibilidade base do player.gd.
var mouse_sensitivity: float = 1.0
var touch_sensitivity: float = 1.0
var invert_y: bool = false
var fov: float = 80.0
## 0.0 a 1.0 (linear).
var master_volume: float = 0.8
var fullscreen: bool = false
var vsync: bool = true
## Baixa: sem sombras nem glow. Média: sombras. Alta: sombras maiores, glow e MSAA 2x.
var quality: int = QUALITY_HIGH
## Escala da renderização 3D (0.5 = metade da resolução, mais leve).
var render_scale: float = 1.0
var show_fps: bool = false
## Controles de toque.
var button_scale: float = 1.0
## id do botão -> posição (fração da tela). Vazio = posições padrão.
var touch_layout: Dictionary = {}
var vibration: bool = true
var aim_assist: bool = true
var gyro_aim: bool = false
## Melhor pontuação na Arena de Alvos (contra o relógio).
var arena_record: int = 0


func _ready() -> void:
	reset_to_defaults(false)
	load_settings()
	apply()


## Padrões por plataforma: no celular começa leve para poupar bateria e calor.
static func defaults() -> Dictionary:
	var mobile := OS.has_feature("mobile")
	return {
		"nickname": "",
		"mouse_sensitivity": 1.0,
		"touch_sensitivity": 1.0,
		"invert_y": false,
		"fov": 80.0,
		"master_volume": 0.8,
		"fullscreen": false,
		"vsync": true,
		"quality": QUALITY_LOW if mobile else QUALITY_HIGH,
		"render_scale": 0.75 if mobile else 1.0,
		"show_fps": false,
		"button_scale": 1.0,
		"touch_layout": {},
		"vibration": true,
		"aim_assist": true,
		"gyro_aim": false,
		"arena_record": 0,
	}


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var values := defaults()
	for key: String in values:
		set(key, config.get_value(SECTION, key, values[key]))


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in defaults():
		config.set_value(SECTION, key, get(key))
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("Não foi possível salvar as configurações (código %d)." % err)


## Volta aos padrões (o apelido e o recorde ficam).
func reset_to_defaults(apply_now: bool = true) -> void:
	var values := defaults()
	for key: String in values:
		if key in ["nickname", "arena_record"] and apply_now:
			continue
		set(key, values[key])
	if apply_now:
		apply()


## Aplica o que é global (janela, áudio, render) e avisa quem depende do resto.
func apply() -> void:
	# No celular a janela é sempre tela cheia e o VSync é do sistema; limita a
	# 60 FPS para não esquentar.
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
	else:
		var window_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != window_mode:
			DisplayServer.window_set_mode(window_mode)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))

	var viewport := get_viewport()
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = Viewport.MSAA_2X if quality >= QUALITY_HIGH else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality >= QUALITY_HIGH else 2048, true)
	apply_quality_to(get_tree().root)
	changed.emit()


## Sombras e glow do mapa conforme a qualidade. Guarda o valor original de
## cada luz/ambiente para poder voltar ao subir a qualidade.
func apply_quality_to(root: Node) -> void:
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if not light.has_meta("base_shadow"):
			light.set_meta("base_shadow", light.shadow_enabled)
		light.shadow_enabled = bool(light.get_meta("base_shadow")) and quality >= QUALITY_MEDIUM
		light.directional_shadow_max_distance = 60.0 if quality >= QUALITY_HIGH else 35.0
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		if not env.has_meta("base_glow"):
			env.set_meta("base_glow", env.glow_enabled)
		env.glow_enabled = bool(env.get_meta("base_glow")) and quality >= QUALITY_HIGH
