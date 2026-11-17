extends Node
## Autoload "Habits": o que a IA de treino aprendeu sobre o jogador deste
## aparelho, salvo em user://habits.cfg para continuar de onde parou. Só o
## host observa (HabitTracker); clientes aprendem durante a sessão no host.

signal changed

const SAVE_PATH: String = "user://habits.cfg"
const SECTION: String = "habits"

var profile := PlayerHabits.new()
## Falso nos testes automáticos: nada é gravado no save de verdade.
var persistent: bool = true

var _dirty: bool = false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK or not config.has_section(SECTION):
		return
	var data := {}
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	profile.load_dict(data)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		save_if_dirty()


## O HabitTracker avisa que o perfil mudou.
func mark_dirty() -> void:
	_dirty = true


func save_if_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	if not persistent:
		return
	var config := ConfigFile.new()
	var data := profile.to_dict()
	for key: String in data:
		config.set_value(SECTION, key, data[key])
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("Não foi possível salvar os hábitos (código %d)." % err)
	changed.emit()


## Apaga tudo o que a IA aprendeu (botão da tela de hábitos).
func reset() -> void:
	profile = PlayerHabits.new()
	_dirty = true
	save_if_dirty()
	changed.emit()
