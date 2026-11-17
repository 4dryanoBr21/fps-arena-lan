class_name EquipmentData
extends ShopItem
## Equipamento do Arsenal: um por jogador, vale enquanto estiver equipado.

## Vida extra somada à vida base das regras.
@export var bonus_health: int = 0
## Multiplica as velocidades de andar, correr e agachado.
@export var speed_multiplier: float = 1.0


func stats_text() -> String:
	var parts := PackedStringArray()
	if bonus_health != 0:
		parts.append("%+d de vida" % bonus_health)
	if not is_equal_approx(speed_multiplier, 1.0):
		parts.append("velocidade %+d%%" % roundi((speed_multiplier - 1.0) * 100.0))
	return " · ".join(parts)
