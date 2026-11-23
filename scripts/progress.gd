extends Node
## Autoload "Progress": o PlayerProfile deste aparelho, salvo em
## user://progress.cfg. Os prêmios chegam do servidor (NetworkManager) e
## as compras vêm do Arsenal. Durante a partida só marca para salvar; grava
## no fim da partida, ao sair, ao fechar e quando o celular troca de app.

signal changed
signal reward_received(coins: int, xp: int, reason: String)
signal leveled_up(level: int)

const SAVE_PATH: String = "user://progress.cfg"
const SECTION: String = "progress"

var profile := PlayerProfile.new()
## Falso nos testes automáticos: nada é gravado no save de verdade.
var persistent: bool = true

var _dirty: bool = false


func _ready() -> void:
	load_progress()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_EXIT_TREE,
			NOTIFICATION_APPLICATION_FOCUS_OUT]:
		save_if_dirty()


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK or not config.has_section(SECTION):
		return
	var data := {}
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	profile.load_dict(data)
	changed.emit()


func save_progress() -> void:
	_dirty = false
	if not persistent:
		return
	var config := ConfigFile.new()
	var data := profile.to_dict()
	for key: String in data:
		config.set_value(SECTION, key, data[key])
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("Não foi possível salvar o progresso (código %d)." % err)


func save_if_dirty() -> void:
	if _dirty:
		save_progress()


## Prêmio decidido pelo servidor.
func grant(coins: int, xp: int, reason: String) -> void:
	var levels := profile.add_reward(coins, xp)
	_dirty = true
	reward_received.emit(coins, xp, reason)
	if levels > 0:
		leveled_up.emit(profile.level())
	changed.emit()


func buy(item: ShopItem) -> bool:
	if not profile.buy(item):
		return false
	# Comprou, já equipa.
	profile.equip(item)
	_commit()
	return true


func upgrade(weapon: WeaponData) -> bool:
	if not profile.upgrade(weapon):
		return false
	_commit()
	return true


func equip(item: ShopItem) -> bool:
	if not profile.equip(item):
		return false
	_commit()
	return true


func _commit() -> void:
	save_progress()
	changed.emit()
