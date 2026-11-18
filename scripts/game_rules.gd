class_name GameRules
extends Resource
## Balanceamento do jogo num lugar só (data/game_rules.tres). Ajuste pelo
## inspetor do Godot sem mexer em código.

@export_group("Jogador")
@export var max_health: int = 100
@export var walk_speed: float = 7.0
@export var sprint_speed: float = 10.5
@export var crouch_speed: float = 3.5
## Pulo curto e rápido: com gravity_scale 2 sobe ~1,8 m (passa as bordas
## de 1,5 m dos mapas) e fica ~0,85 s no ar.
@export var jump_velocity: float = 8.2
## Multiplica a gravidade do projeto (9,8 m/s²) para o jogador cair firme.
@export var gravity_scale: float = 2.0
@export var respawn_time: float = 3.0
## Segundos invulnerável ao renascer (acaba antes se o jogador atirar).
@export var spawn_protection: float = 1.5
## Dano nas pernas em relação ao do corpo (hitboxes em scripts/hitboxes.gd).
@export var leg_damage_ratio: float = 0.75

@export_group("Partida")
## Mata-mata: duração (s) e limite de abates.
@export var deathmatch_time: float = 300.0
@export var deathmatch_kill_limit: int = 20
## Arena de Alvos: contra o relógio (s).
@export var arena_time: float = 60.0
## Segundos mostrando o resultado antes da próxima partida.
@export var results_time: float = 6.0
@export var target_respawn_time: float = 3.0

@export_group("Arsenal")
## Catálogo completo; cada jogador leva uma principal e uma secundária.
@export var weapons: Array[WeaponData] = []
@export var equipment: Array[EquipmentData] = []
## Armas com que todo mundo começa (precisam ter preço 0).
@export var default_primary: String = "rifle"
@export var default_secondary: String = "pistol"
## Arma branca que todo mundo leva na terceira vaga (não se compra).
@export var default_melee: String = "knife"
## Preço de cada nível de melhoria de arma (o tamanho define o nível máximo).
@export var upgrade_prices: Array[int] = [250, 500, 900]
## Por nível de melhoria: pente maior e recarga/recuo/dispersão menores.
@export var upgrade_magazine_bonus: float = 0.15
@export var upgrade_handling_bonus: float = 0.1

@export_group("Prêmios (moedas / XP)")
@export var kill_coins: int = 100
@export var kill_xp: int = 100
## Extra quando o abate sai com tiro na cabeça.
@export var headshot_coins: int = 25
@export var headshot_xp: int = 25
@export var target_coins: int = 10
@export var target_xp: int = 15
## Fim de partida: 1º, 2º e 3º lugar (só com 2 ou mais na partida).
@export var placement_coins: Array[int] = [200, 120, 80]
@export var placement_xp: Array[int] = [200, 120, 80]
## Todo mundo que termina a partida.
@export var finish_coins: int = 50
@export var finish_xp: int = 100

var max_upgrade_tier: int:
	get:
		return upgrade_prices.size()


func weapon_by_id(id: String) -> WeaponData:
	for weapon in weapons:
		if weapon.id == id:
			return weapon
	return null


func equipment_by_id(id: String) -> EquipmentData:
	for item in equipment:
		if item.id == id:
			return item
	return null


func item_by_id(id: String) -> ShopItem:
	var weapon := weapon_by_id(id)
	return weapon if weapon != null else equipment_by_id(id)


func weapons_for_slot(slot: WeaponData.Slot) -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	for weapon in weapons:
		if weapon.slot == slot:
			list.append(weapon)
	return list


## Confere o equipamento que chega pela rede: ids que existem, cada arma na
## vaga certa e melhorias dentro do limite. O que não confere volta ao padrão.
## (A posse dos itens fica no save de cada aparelho e não é verificável aqui.)
func sanitize_loadout(loadout: Dictionary) -> Dictionary:
	var primary := weapon_by_id(str(loadout.get("primary", "")))
	if primary == null or primary.slot != WeaponData.Slot.PRIMARY:
		primary = weapon_by_id(default_primary)
	var secondary := weapon_by_id(str(loadout.get("secondary", "")))
	if secondary == null or secondary.slot != WeaponData.Slot.SECONDARY:
		secondary = weapon_by_id(default_secondary)
	var gear := equipment_by_id(str(loadout.get("equipment", "")))
	return {
		"primary": primary.id,
		"secondary": secondary.id,
		"equipment": gear.id if gear != null else "",
		"primary_tier": clampi(int(loadout.get("primary_tier", 0)), 0, max_upgrade_tier),
		"secondary_tier": clampi(int(loadout.get("secondary_tier", 0)), 0, max_upgrade_tier),
	}


## Bots: armas e equipamento sorteados do catálogo, sem melhorias.
func random_loadout(rng: RandomNumberGenerator) -> Dictionary:
	var primaries := weapons_for_slot(WeaponData.Slot.PRIMARY)
	var secondaries := weapons_for_slot(WeaponData.Slot.SECONDARY)
	var gear_id := ""
	if not equipment.is_empty() and rng.randf() < 0.5:
		gear_id = equipment[rng.randi() % equipment.size()].id
	return sanitize_loadout({
		"primary": primaries[rng.randi() % primaries.size()].id,
		"secondary": secondaries[rng.randi() % secondaries.size()].id,
		"equipment": gear_id,
	})
