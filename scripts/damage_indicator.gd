class_name DamageIndicator
extends Control
## Arcos vermelhos em volta da mira apontando de onde veio cada tiro levado.
## A direção é recalculada todo quadro, então o arco gira junto com a câmera.

const LIFETIME: float = 1.2
const RADIUS: float = 90.0
const ARC_WIDTH_DEG: float = 40.0

var player: Node3D
## [posição do atirador, segundos restantes]
var _hits: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_hit(from_position: Vector3) -> void:
	_hits.append([from_position, LIFETIME])
	if _hits.size() > 6:
		_hits.pop_front()


func clear() -> void:
	_hits.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for hit: Array in _hits:
		hit[1] = float(hit[1]) - delta
	_hits = _hits.filter(func(hit: Array) -> bool: return float(hit[1]) > 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var center := size * 0.5
	var half := deg_to_rad(ARC_WIDTH_DEG) * 0.5
	for hit: Array in _hits:
		var local := player.global_transform.affine_inverse() * (hit[0] as Vector3)
		# 0 = na frente (topo da tela), sentido horário.
		var angle := atan2(local.x, -local.z) - PI * 0.5
		var alpha := clampf(float(hit[1]) / LIFETIME, 0.0, 1.0)
		draw_arc(center, RADIUS, angle - half, angle + half, 16, Color(1.0, 0.15, 0.1, 0.85 * alpha), 8.0, true)
