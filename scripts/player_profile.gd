class_name PlayerProfile
extends RefCounted
## Progresso de um jogador: moedas, XP (nível), itens comprados, melhorias
## das armas e o equipamento escolhido. Sem cena nem arquivo (o autoload
## Progress salva); testado em tests/unit_tests.gd.

const RULES: GameRules = preload("res://data/game_rules.tres")
const MAX_LEVEL: int = 30

var coins: int = 0
var xp: int = 0
## ids comprados (os gratuitos contam como comprados sem estar aqui).
var owned: PackedStringArray = []
## id da arma -> nível de melhoria.
var upgrades: Dictionary = {}
var primary: String = RULES.default_primary
var secondary: String = RULES.default_secondary
## "" = sem equipamento.
var equipment: String = ""


## XP total para chegar ao nível pedido: 200, 600, 1200, 2000...
static func xp_for_level(level: int) -> int:
	return 100 * (level - 1) * level


static func level_for_xp(total_xp: int) -> int:
	var level := 1
	while level < MAX_LEVEL and total_xp >= xp_for_level(level + 1):
		level += 1
	return level


func level() -> int:
	return level_for_xp(xp)


## Fração do caminho até o próximo nível (1.0 no nível máximo).
func level_progress() -> float:
	var current := level()
	if current >= MAX_LEVEL:
		return 1.0
	var start := xp_for_level(current)
	return float(xp - start) / (xp_for_level(current + 1) - start)


func owns(item: ShopItem) -> bool:
	return item != null and (item.is_free() or owned.has(item.id))


## Motivo para não poder comprar ("" = pode).
func buy_block_reason(item: ShopItem) -> String:
	if item == null:
		return "Item desconhecido"
	if owns(item):
		return "Já é seu"
	if level() < item.unlock_level:
		return "Nível %d" % item.unlock_level
	if coins < item.price:
		return "Faltam %d moedas" % (item.price - coins)
	return ""


func buy(item: ShopItem) -> bool:
	if not buy_block_reason(item).is_empty():
		return false
	coins -= item.price
	owned.append(item.id)
	return true


func upgrade_tier(weapon_id: String) -> int:
	return int(upgrades.get(weapon_id, 0))


## Preço do próximo nível de melhoria; -1 se já está no máximo.
func upgrade_price(weapon_id: String) -> int:
	var tier := upgrade_tier(weapon_id)
	return RULES.upgrade_prices[tier] if tier < RULES.max_upgrade_tier else -1


func upgrade_block_reason(weapon: WeaponData) -> String:
	if weapon == null or not owns(weapon):
		return "Compre a arma antes"
	var price := upgrade_price(weapon.id)
	if price < 0:
		return "Melhoria máxima"
	if coins < price:
		return "Faltam %d moedas" % (price - coins)
	return ""


func upgrade(weapon: WeaponData) -> bool:
	if not upgrade_block_reason(weapon).is_empty():
		return false
	coins -= upgrade_price(weapon.id)
	upgrades[weapon.id] = upgrade_tier(weapon.id) + 1
	return true


func is_equipped(item: ShopItem) -> bool:
	return item != null and item.id in [primary, secondary, equipment]


## Põe o item na vaga dele. Equipamento já equipado é tirado (fica sem nenhum).
func equip(item: ShopItem) -> bool:
	if not owns(item):
		return false
	if item is WeaponData:
		if (item as WeaponData).slot == WeaponData.Slot.PRIMARY:
			primary = item.id
		else:
			secondary = item.id
	elif item is EquipmentData:
		equipment = "" if equipment == item.id else item.id
	return true


## Soma o prêmio e devolve quantos níveis subiu.
func add_reward(coin_amount: int, xp_amount: int) -> int:
	var before := level()
	coins = maxi(coins + coin_amount, 0)
	xp = maxi(xp + xp_amount, 0)
	return level() - before


## O que vai para o servidor ao entrar numa partida.
func network_loadout() -> Dictionary:
	return RULES.sanitize_loadout({
		"primary": primary,
		"secondary": secondary,
		"equipment": equipment,
		"primary_tier": upgrade_tier(primary),
		"secondary_tier": upgrade_tier(secondary),
	})


func to_dict() -> Dictionary:
	return {
		"coins": coins, "xp": xp, "owned": owned, "upgrades": upgrades,
		"primary": primary, "secondary": secondary, "equipment": equipment,
	}


## Lê um save, descartando ids que não existem mais e voltando ao padrão
## o que estiver equipado sem ter sido comprado.
func load_dict(data: Dictionary) -> void:
	coins = maxi(int(data.get("coins", 0)), 0)
	xp = maxi(int(data.get("xp", 0)), 0)
	owned = PackedStringArray()
	for id in data.get("owned", []):
		if RULES.item_by_id(str(id)) != null and not owned.has(str(id)):
			owned.append(str(id))
	upgrades = {}
	var saved_upgrades = data.get("upgrades", {})
	if saved_upgrades is Dictionary:
		for id in saved_upgrades:
			if RULES.weapon_by_id(str(id)) != null:
				upgrades[str(id)] = clampi(int(saved_upgrades[id]), 0, RULES.max_upgrade_tier)
	primary = str(data.get("primary", RULES.default_primary))
	secondary = str(data.get("secondary", RULES.default_secondary))
	equipment = str(data.get("equipment", ""))
	var loadout := RULES.sanitize_loadout({"primary": primary, "secondary": secondary, "equipment": equipment})
	primary = loadout["primary"] if owns(RULES.weapon_by_id(loadout["primary"])) else RULES.default_primary
	secondary = loadout["secondary"] if owns(RULES.weapon_by_id(loadout["secondary"])) else RULES.default_secondary
	equipment = loadout["equipment"] if owns(RULES.equipment_by_id(loadout["equipment"])) else ""
