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
## Números de dano sobre a cabeça do inimigo (como no Fortnite).
var damage_numbers: bool = true
## Controles de toque.
var button_scale: float = 1.0
## id do botão -> posição (fração da tela). Vazio = posições padrão.
var touch_layout: Dictionary = {}
var vibration: bool = true
var aim_assist: bool = true
var gyro_aim: bool = false
## Melhor pontuação na Arena de Alvos (contra o relógio).
var arena_record: int = 0
## Mira (Crosshair): estilo, cor e medidas em pixels; o desenho fica em
## crosshair_pixels (grade Crosshair.GRID², 1 = pintado).
var crosshair_style: int = Crosshair.Style.CROSS
var crosshair_color: Color = Color.WHITE
var crosshair_opacity: float = 1.0
var crosshair_size: float = 8.0
var crosshair_thickness: float = 2.0
var crosshair_gap: float = 3.0
var crosshair_outline: bool = true
var crosshair_pixel_size: float = 2.0
var crosshair_pixels: PackedByteArray = Crosshair.default_pixels()


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
		"damage_numbers": true,
		"button_scale": 1.0,
		"touch_layout": {},
		"vibration": true,
		"aim_assist": true,
		"gyro_aim": false,
		"arena_record": 0,
		"crosshair_style": Crosshair.Style.CROSS,
		"crosshair_color": Color.WHITE,
		"crosshair_opacity": 1.0,
		"crosshair_size": 8.0,
		"crosshair_thickness": 2.0,
		"crosshair_gap": 3.0,
		"crosshair_outline": true,
		"crosshair_pixel_size": 2.0,
		"crosshair_pixels": Crosshair.default_pixels(),
	}


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var values := defaults()
	for key: String in values:
		var value: Variant = config.get_value(SECTION, key, values[key])
		# Save de outra versão ou editado à mão: tipo errado volta ao padrão.
		if typeof(value) != typeof(values[key]) and not (value is float and values[key] is int) \
				and not (value is int and values[key] is float):
			value = values[key]
		set(key, value)
	if not Crosshair.is_valid_pixels(crosshair_pixels):
		crosshair_pixels = Crosshair.default_pixels()
	crosshair_style = clampi(crosshair_style, 0, Crosshair.Style.size() - 1)


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in defaults():
		config.set_value(SECTION, key, get(key))
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("Não foi possível salvar as configurações (código %d)." % err)


## Volta aos padrões (o apelido, o recorde e o desenho da mira ficam).
func reset_to_defaults(apply_now: bool = true) -> void:
	var values := defaults()
	for key: String in values:
		if key in ["nickname", "arena_record", "crosshair_pixels"] and apply_now:
			continue
		set(key, values[key])
	if apply_now:
		apply()


## Volta a mira aos padrões, menos o desenho (que tem botões próprios no editor).
func reset_crosshair() -> void:
	var values := defaults()
	for key: String in values:
		if key.begins_with("crosshair_") and key != "crosshair_pixels":
			set(key, values[key])
	changed.emit()


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
