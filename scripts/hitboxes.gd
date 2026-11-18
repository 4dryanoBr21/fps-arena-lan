class_name Hitboxes
extends RefCounted
## Hitboxes do jogador no formato do boneco (scenes/player.tscn): cabeça,
## tronco e pernas, cada uma uma caixa que gira com o jogador (yaw) e encolhe
## em altura ao agachar, como o visual. Usadas pelo servidor para decidir o
## acerto e pelo atirador para desenhar o traço; testadas em tests/unit_tests.gd.

enum Part { NONE, HEAD, TORSO, LEGS }

## Centro e tamanho de cada parte (metros, de pé, olhando para -Z), um pouco
## maiores que o visual para o acerto na borda não parecer injusto.
const PARTS := {
	Part.HEAD: [Vector3(0.0, 1.62, -0.01), Vector3(0.4, 0.4, 0.42)],
	Part.TORSO: [Vector3(0.0, 1.13, 0.0), Vector3(0.66, 0.74, 0.42)],
	Part.LEGS: [Vector3(0.0, 0.41, 0.0), Vector3(0.54, 0.82, 0.34)],
}
## Altura de pé usada no desenho do boneco (o agachado escala por esta).
const STAND_HEIGHT: float = 1.8


## Parte mais perto atingida pelo raio: {"distance", "part"}, ou vazio se
## errou. `grow` aumenta todas as caixas (golpe de faca é mais largo).
static func ray_test(origin: Vector3, direction: Vector3, max_distance: float, feet: Vector3,
		yaw: float, body_height: float = STAND_HEIGHT, grow: float = 0.0) -> Dictionary:
	var best := {}
	var best_distance := max_distance
	var height_scale := body_height / STAND_HEIGHT
	for part: Part in PARTS:
		var spec: Array = PARTS[part]
		var center: Vector3 = spec[0]
		var size: Vector3 = spec[1]
		center.y *= height_scale
		size.y *= height_scale
		var world_center := feet + Basis(Vector3.UP, yaw) * center
		var distance := ray_box_distance(origin, direction, best_distance, world_center,
			size * 0.5 + Vector3.ONE * grow, yaw)
		if distance >= 0.0 and distance <= best_distance:
			best_distance = distance
			best = {"distance": distance, "part": part}
	return best


## Distância ao longo do raio até a caixa girada `yaw` em volta de Y, ou -1.
## `direction` normalizada; começando dentro da caixa, a distância é 0.
static func ray_box_distance(origin: Vector3, direction: Vector3, max_distance: float,
		center: Vector3, half_size: Vector3, yaw: float) -> float:
	var to_local := Basis(Vector3.UP, -yaw)
	var local_origin := to_local * (origin - center)
	var local_direction := to_local * direction
	var near := -INF
	var far := INF
	for axis in 3:
		var o := local_origin[axis]
		var d := local_direction[axis]
		var half := half_size[axis]
		if absf(d) < 0.000001:
			if absf(o) > half:
				return -1.0
			continue
		var t1 := (-half - o) / d
		var t2 := (half - o) / d
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
	if far < maxf(near, 0.0):
		return -1.0
	var distance := maxf(near, 0.0)
	return distance if distance <= max_distance else -1.0
