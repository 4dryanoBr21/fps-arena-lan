class_name ShopItem
extends Resource
## Base de tudo que aparece no Arsenal (armas e equipamentos): identificação,
## preço em moedas e nível mínimo para comprar.

## Chave estável usada no save e na rede; não mude depois de publicar.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## 0 = vem de graça desde o começo.
@export var price: int = 0
@export var unlock_level: int = 1


func is_free() -> bool:
	return price <= 0
