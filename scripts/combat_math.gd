class_name CombatMath
extends RefCounted
## Contas de tiro sem dependência de cena (testadas em tests/unit_tests.gd).


## Direção dentro de um cone de `spread_deg` graus em volta de `forward`.
static func spread_direction(forward: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return forward
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(forward).normalized()
	# Raiz no raio: distribui os pontos por igual na área do cone.
	var angle := deg_to_rad(spread_deg) * sqrt(rng.randf())
	var turn := rng.randf() * TAU
	var offset := (side * cos(turn) + up * sin(turn)) * tan(angle)
	return (forward + offset).normalized()


## Entrada do histórico [[msec, ...], ...] em vigor no instante pedido: a
## última com tempo <= msec (ou a primeira, se o instante é anterior a todas).
static func history_entry_at(history: Array, msec: int) -> Array:
	if history.is_empty():
		return []
	for i in range(history.size() - 1, -1, -1):
		if int(history[i][0]) <= msec:
			return history[i]
	return history[0]


## Interpola um histórico [[msec, Vector3, ...], ...] (mais antigo primeiro) no instante pedido.
static func sample_history(history: Array, msec: int, fallback: Vector3) -> Vector3:
	if history.is_empty():
		return fallback
	if msec <= int(history[0][0]):
		return history[0][1]
	for i in range(history.size() - 1, -1, -1):
		var older: Array = history[i]
		if int(older[0]) <= msec:
			if i == history.size() - 1:
				return older[1]
			var newer: Array = history[i + 1]
			var span := float(int(newer[0]) - int(older[0]))
			var t := 0.0 if span <= 0.0 else float(msec - int(older[0])) / span
			return (older[1] as Vector3).lerp(newer[1], t)
	return fallback


## Golpe pelas costas: a vítima (virada para `victim_yaw`) está de costas para
## o atacante, dentro de um cone de `half_angle_deg` atrás dela.
static func is_backstab(attacker: Vector3, victim: Vector3, victim_yaw: float, half_angle_deg: float = 60.0) -> bool:
	var to_victim := Vector2(victim.x - attacker.x, victim.z - attacker.z)
	if to_victim.length_squared() < 0.0001:
		return false
	var victim_forward := Vector2(-sin(victim_yaw), -cos(victim_yaw))
	return victim_forward.dot(to_victim.normalized()) > cos(deg_to_rad(half_angle_deg))

