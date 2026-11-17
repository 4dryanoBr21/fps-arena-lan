class_name CombatMath
extends RefCounted
## Contas de tiro sem dependência de cena (testadas em tests/unit_tests.gd).


## Distância ao longo do raio até a cápsula vertical que começa em `feet`,
## ou -1 se o raio não passa por ela. `direction` precisa estar normalizada.
static func ray_capsule_distance(origin: Vector3, direction: Vector3, max_distance: float,
		feet: Vector3, height: float, radius: float) -> float:
	var ray_end := origin + direction * max_distance
	var axis_low := feet + Vector3.UP * radius
	var axis_high := feet + Vector3.UP * maxf(height - radius, radius)
	var points := Geometry3D.get_closest_points_between_segments(origin, ray_end, axis_low, axis_high)
	var gap := points[0].distance_to(points[1])
	if gap > radius:
		return -1.0
	var along := origin.distance_to(points[0])
	return maxf(along - sqrt(radius * radius - gap * gap), 0.0)


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


## Interpola um histórico [[msec, Vector3, bool], ...] (mais antigo primeiro) no instante pedido.
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
