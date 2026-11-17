class_name WeaponData
extends ShopItem
## Dados de uma arma. O servidor usa os mesmos valores para validar cadência,
## munição e dano, então alterar aqui vale para todo mundo.

enum Slot { PRIMARY, SECONDARY }

@export var slot: Slot = Slot.PRIMARY
@export var body_damage: int = 25
@export var head_damage: int = 50
## Segundos entre disparos.
@export var fire_cooldown: float = 0.15
@export var magazine: int = 12
@export var reload_time: float = 1.5
## Projéteis por disparo (escopeta > 1). O dano é por projétil.
@export var pellets: int = 1
@export var max_range: float = 100.0

@export_group("Dispersão e recuo (graus)")
@export var base_spread: float = 0.0
## Quanto a dispersão cresce a cada tiro seguido.
@export var spread_per_shot: float = 0.6
@export var max_spread: float = 3.0
## Quanto a dispersão volta por segundo.
@export var spread_recovery: float = 6.0
## Quanto a mira sobe a cada tiro.
@export var recoil: float = 0.6

@export_group("Som e visual")
@export var sound: StringName = &"shot"
@export var sound_pitch: float = 1.0
## Escala do modelo da arma (o mesmo bloco serve para todas).
@export var model_scale: Vector3 = Vector3.ONE

## Nível de melhoria aplicado (0 = de fábrica). Só existe nas cópias de upgraded().
var tier: int = 0


## Cópia com as melhorias do Arsenal aplicadas: cada nível aumenta o pente
## e encurta recarga, recuo e dispersão nas frações de `rules`.
func upgraded(level: int, rules: GameRules) -> WeaponData:
	var copy := duplicate() as WeaponData
	copy.tier = clampi(level, 0, rules.max_upgrade_tier)
	if copy.tier == 0:
		return copy
	copy.magazine = ceili(magazine * (1.0 + rules.upgrade_magazine_bonus * copy.tier))
	var reduce := maxf(1.0 - rules.upgrade_handling_bonus * copy.tier, 0.1)
	copy.reload_time = reload_time * reduce
	copy.recoil = recoil * reduce
	copy.spread_per_shot = spread_per_shot * reduce
	copy.max_spread = max_spread * reduce
	return copy


## Disparos por minuto, para mostrar no Arsenal.
func rate_per_minute() -> int:
	return roundi(60.0 / fire_cooldown)


func stats_text() -> String:
	var damage := "%d" % body_damage if pellets == 1 else "%d por projétil, %d projéteis" % [body_damage, pellets]
	var reload := ("%.1f" % reload_time).replace(".", ",")
	return "Dano %s (cabeça %d) · %d tiros/min · pente %d · recarga %s s · alcance %d m" % [
		damage, head_damage, rate_per_minute(), magazine, reload, roundi(max_range)]
