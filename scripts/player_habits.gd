class_name PlayerHabits
extends RefCounted
## O que a IA de treino sabe sobre um jogador: como ele se move em combate,
## de onde atira, quão rápido reage e onde gosta de ficar em cada mapa. Tudo
## são médias móveis, então o costume recente pesa mais que o antigo.
## Alimentado pelo HabitTracker (no servidor) e lido pelo BotBrain; sem cena
## nem arquivo (o autoload Habits salva). Testado em tests/unit_tests.gd.

## Faixas de distância da precisão: perto, médio, longe (metros).
const RANGE_LIMITS: Array[float] = [8.0, 20.0]
const RANGE_NAMES: Array[String] = ["perto", "médio", "longe"]
const RANGE_CENTERS: Array[float] = [5.0, 14.0, 28.0]
## Lado de cada célula do mapa de calor (metros).
const CELL_SIZE: float = 4.0
const MAX_CELLS_PER_MAP: int = 48
## Segundos de combate para a IA confiar totalmente no que aprendeu.
const FULL_CONFIDENCE_TIME: float = 60.0
## Velocidade lateral (m/s) a partir da qual conta como desvio.
const STRAFE_SPEED: float = 2.0
## Constantes de tempo (s) das médias contínuas.
const BIAS_TAU: float = 8.0
const RATIO_TAU: float = 12.0
## Ajuste da dificuldade por duelo: vencer sobe mais devagar do que perder
## desce, então o jogador fica ganhando um pouco mais da metade (~55%).
const SKILL_UP: float = 0.04
const SKILL_DOWN: float = 0.05
const SKILL_MIN: float = 0.05
const SKILL_MAX: float = 1.0
const MIN_SHOTS_FOR_ACCURACY: float = 8.0
## Trocas de lado vistas antes de usar o ritmo (previsão e dica).
const MIN_SWITCHES: int = 6
## Variação até a qual o ritmo conta como "regular" (fração da média).
const REGULAR_RHYTHM: float = 0.35

## Segundos de combate observados.
var combat_time: float = 0.0
## -1 = sempre desvia para a esquerda, +1 = sempre para a direita.
var strafe_bias: float = 0.0
## Segundos, em média, entre trocas de direção do desvio, quantas trocas
## foram vistas e quanto o intervalo varia (desvio médio, em segundos).
var strafe_switch_time: float = 1.0
var strafe_switches: int = 0
var strafe_switch_jitter: float = 0.5
## Pulos por segundo de combate.
var jump_rate: float = 0.0
## Fração do combate agachado / correndo.
var crouch_ratio: float = 0.0
var sprint_ratio: float = 0.0
## Distância (m) de onde costuma atirar.
var preferred_distance: float = 14.0
## Segundos entre um inimigo aparecer na frente e o primeiro tiro.
var reaction_time: float = 0.6
var reaction_samples: int = 0
## Tiros e acertos por faixa de distância.
var shots: Array[float] = [0.0, 0.0, 0.0]
var hits: Array[float] = [0.0, 0.0, 0.0]
## Dificuldade dos bots de treino contra este jogador (0 a 1).
var skill: float = 0.4
var duels_won: int = 0
var duels_lost: int = 0
## mapa -> {Vector2i célula: segundos ali}.
var heatmap: Dictionary = {}

## Estado do momento (não é salvo): desvio atual e há quanto tempo.
var current_strafe_sign: int = 0
var current_strafe_time: float = 0.0


func confidence() -> float:
	return clampf(combat_time / FULL_CONFIDENCE_TIME, 0.0, 1.0)


## Uma amostra do jogador. `lateral` é a velocidade (m/s) para a direita da
## mira; `in_combat` diz se havia inimigo à vista.
func observe_tick(delta: float, map_key: String, position: Vector3, lateral: float,
		jumped: bool, crouching: bool, sprinting: bool, in_combat: bool) -> void:
	var cells: Dictionary = heatmap.get(map_key, {})
	var cell := cell_of(position)
	cells[cell] = float(cells.get(cell, 0.0)) + delta
	heatmap[map_key] = cells
	if not in_combat:
		current_strafe_sign = 0
		current_strafe_time = 0.0
		return

	combat_time += delta
	var side := 0
	if absf(lateral) >= STRAFE_SPEED:
		side = 1 if lateral > 0.0 else -1
	if side != 0:
		strafe_bias += (side - strafe_bias) * minf(delta / BIAS_TAU, 1.0)
		if current_strafe_sign != 0 and side != current_strafe_sign:
			# Trocou de lado: guarda quanto tempo ficou no lado anterior.
			strafe_switch_jitter += (absf(current_strafe_time - strafe_switch_time) - strafe_switch_jitter) * 0.15
			strafe_switch_time += (current_strafe_time - strafe_switch_time) * 0.15
			strafe_switches += 1
			current_strafe_time = 0.0
		current_strafe_sign = side
	current_strafe_time += delta

	var ratio_step := minf(delta / RATIO_TAU, 1.0)
	crouch_ratio += ((1.0 if crouching else 0.0) - crouch_ratio) * ratio_step
	sprint_ratio += ((1.0 if sprinting else 0.0) - sprint_ratio) * ratio_step
	# Cada pulo soma 1/RATIO_TAU e o valor decai com o tempo: média de pulos/s.
	jump_rate += ((1.0 / delta if jumped else 0.0) - jump_rate) * ratio_step


func observe_shot(distance: float, hit: bool) -> void:
	var bucket := range_bucket(distance)
	shots[bucket] += 1.0
	if hit:
		hits[bucket] += 1.0
	preferred_distance += (distance - preferred_distance) * 0.05


func observe_reaction(seconds: float) -> void:
	if seconds < 0.08 or seconds > 3.0:
		return
	reaction_samples += 1
	reaction_time += (seconds - reaction_time) * 0.2


## Resultado de um duelo contra um bot de treino (ajusta a dificuldade).
func observe_duel(player_won: bool) -> void:
	if player_won:
		duels_won += 1
		skill = minf(skill + SKILL_UP, SKILL_MAX)
	else:
		duels_lost += 1
		skill = maxf(skill - SKILL_DOWN, SKILL_MIN)


## Começo de partida: o passado pesa menos e o mapa de calor é podado.
func new_match() -> void:
	for i in shots.size():
		shots[i] *= 0.8
		hits[i] *= 0.8
	for map_key: String in heatmap:
		var cells: Dictionary = heatmap[map_key]
		var ranked := cells.keys()
		ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return cells[a] > cells[b])
		var kept := {}
		for i in mini(ranked.size(), MAX_CELLS_PER_MAP):
			kept[ranked[i]] = float(cells[ranked[i]]) * 0.7
		heatmap[map_key] = kept


## Pela média do ritmo dele, o jogador deve trocar de lado logo?
func expects_reversal() -> bool:
	return knows_rhythm() and current_strafe_sign != 0 and current_strafe_time >= strafe_switch_time * 0.8


## Já viu trocas suficientes para confiar no ritmo.
func knows_rhythm() -> bool:
	return strafe_switches >= MIN_SWITCHES


## Troca de lado sempre no mesmo tempo (previsível).
func has_regular_rhythm() -> bool:
	return knows_rhythm() and strafe_switch_jitter < strafe_switch_time * REGULAR_RHYTHM


## Precisão (0 a 1) na faixa; com poucos tiros puxa para 35%.
func accuracy(bucket: int) -> float:
	return (hits[bucket] + 0.35 * 3.0) / (shots[bucket] + 3.0)


func has_accuracy_data(bucket: int) -> bool:
	return shots[bucket] >= MIN_SHOTS_FOR_ACCURACY


## Distância em que o jogador mira pior (onde um bot esperto quer brigar).
## Sem dados, foge da distância preferida dele.
func weakest_range_distance() -> float:
	var worst := -1
	for bucket in shots.size():
		if has_accuracy_data(bucket) and (worst < 0 or accuracy(bucket) < accuracy(worst)):
			worst = bucket
	if worst < 0:
		return RANGE_CENTERS[2] if preferred_distance < RANGE_LIMITS[1] else RANGE_CENTERS[0]
	return RANGE_CENTERS[worst]


## Centros (no chão) das células onde o jogador mais fica neste mapa.
func hot_spots(map_key: String, count: int) -> Array[Vector3]:
	var cells: Dictionary = heatmap.get(map_key, {})
	var ranked := cells.keys()
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return cells[a] > cells[b])
	var spots: Array[Vector3] = []
	for i in mini(count, ranked.size()):
		var cell: Vector2i = ranked[i]
		spots.append(Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE))
	return spots


## Fração do tempo no mapa passada nas 3 células preferidas.
func hot_spot_share(map_key: String) -> float:
	var cells: Dictionary = heatmap.get(map_key, {})
	var values: Array = cells.values()
	if values.is_empty():
		return 0.0
	values.sort()
	values.reverse()
	var total := 0.0
	for value in values:
		total += float(value)
	var top := 0.0
	for i in mini(3, values.size()):
		top += float(values[i])
	return top / total if total > 0.0 else 0.0


static func cell_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))


static func range_bucket(distance: float) -> int:
	for i in RANGE_LIMITS.size():
		if distance < RANGE_LIMITS[i]:
			return i
	return RANGE_LIMITS.size()


# --- Relatório ---------------------------------------------------------------------

## Linhas de números para a tela de hábitos.
func stats_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Combate observado: %s" % _duration_text(combat_time))
	var right := roundi((strafe_bias + 1.0) * 50.0)
	lines.append("Desvio: %d%% para a direita, %d%% para a esquerda" % [right, 100 - right])
	if knows_rhythm():
		lines.append("Troca de lado a cada %s s (varia %s s)" % [_decimal(strafe_switch_time), _decimal(strafe_switch_jitter)])
	else:
		lines.append("Ritmo de troca de lado: ainda poucas trocas observadas")
	lines.append("Pulos: %s por segundo de combate · agachado %d%% · correndo %d%%" % [
		_decimal(jump_rate), roundi(crouch_ratio * 100.0), roundi(sprint_ratio * 100.0)])
	lines.append("Atira, em média, de %d m" % roundi(preferred_distance))
	if reaction_samples > 0:
		lines.append("Tempo de reação: %s s" % _decimal(reaction_time, 2))
	var accuracy_parts := PackedStringArray()
	for bucket in shots.size():
		var value := "%d%%" % roundi(accuracy(bucket) * 100.0) if has_accuracy_data(bucket) else "poucos tiros"
		accuracy_parts.append("%s %s" % [RANGE_NAMES[bucket], value])
	lines.append("Precisão: " + " · ".join(accuracy_parts))
	lines.append("Dificuldade dos bots de treino: %d%% (você venceu %d e perdeu %d duelos)" % [
		roundi(skill * 100.0), duels_won, duels_lost])
	return lines


## Dicas em português sobre os vícios que os bots estão explorando.
func insights(map_key: String = "") -> PackedStringArray:
	var tips := PackedStringArray()
	if combat_time < 15.0:
		tips.append("Jogue mais um pouco no Treino adaptativo para a IA conhecer seu estilo.")
		return tips
	if absf(strafe_bias) > 0.3:
		tips.append("Em combate você desvia mais para a %s (%d%% das vezes). Os Caçadores já miram desse lado: misture as direções." % [
			"direita" if strafe_bias > 0.0 else "esquerda", roundi((absf(strafe_bias) + 1.0) * 50.0)])
	if has_regular_rhythm():
		tips.append("Você troca de lado num ritmo regular (a cada %s s). Os Caçadores esperam a troca e miram onde você vai estar: quebre o ritmo." % _decimal(strafe_switch_time))
	if jump_rate > 0.6:
		tips.append("Você pula bastante no tiroteio (%s por segundo). No ar a trajetória é previsível; pule menos quando o inimigo já está mirando." % _decimal(jump_rate))
	elif jump_rate < 0.05 and crouch_ratio < 0.1:
		tips.append("Você quase não pula nem agacha em combate. Mudar de altura de vez em quando atrapalha a mira inimiga.")
	if crouch_ratio > 0.45:
		tips.append("Você fica agachado %d%% do combate: fica mais lento e fácil de acertar quando está no aberto." % roundi(crouch_ratio * 100.0))
	var best := -1
	var worst := -1
	for bucket in shots.size():
		if not has_accuracy_data(bucket):
			continue
		if best < 0 or accuracy(bucket) > accuracy(best):
			best = bucket
		if worst < 0 or accuracy(bucket) < accuracy(worst):
			worst = bucket
	if best >= 0 and worst >= 0 and best != worst and accuracy(best) - accuracy(worst) > 0.1:
		tips.append("Sua mira é melhor de %s (%d%%) do que de %s (%d%%). Os Caçadores puxam a briga para %s: treine essa distância." % [
			RANGE_NAMES[best], roundi(accuracy(best) * 100.0), RANGE_NAMES[worst],
			roundi(accuracy(worst) * 100.0), RANGE_NAMES[worst]])
	if reaction_samples >= 5 and reaction_time > 0.7:
		tips.append("Você demora %s s para atirar quando um inimigo aparece. Mire nos cantos antes de virar (pré-mira)." % _decimal(reaction_time, 2))
	if not map_key.is_empty() and hot_spot_share(map_key) > 0.5:
		tips.append("Você passa mais da metade do tempo nas mesmas 3 áreas deste mapa. Os Caçadores patrulham lá: mude de posição.")
	if tips.is_empty():
		tips.append("Nenhum vício forte por enquanto: seu movimento está imprevisível. Continue variando.")
	return tips


## Uma linha para a tela de fim do treino.
func summary_line(map_key: String = "") -> String:
	return "Bots de treino em %d%% · %s" % [roundi(skill * 100.0), insights(map_key)[0]]


static func _decimal(value: float, places: int = 1) -> String:
	return (("%." + str(places) + "f") % value).replace(".", ",")


static func _duration_text(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % roundi(seconds)
	return "%d min %02d s" % [int(seconds) / 60, int(seconds) % 60]


# --- Save -------------------------------------------------------------------------

const SAVED_KEYS: Array[String] = [
	"combat_time", "strafe_bias", "strafe_switch_time", "strafe_switches",
	"strafe_switch_jitter", "jump_rate", "crouch_ratio",
	"sprint_ratio", "preferred_distance", "reaction_time", "reaction_samples", "shots",
	"hits", "skill", "duels_won", "duels_lost", "heatmap",
]


func to_dict() -> Dictionary:
	var data := {}
	for key in SAVED_KEYS:
		data[key] = get(key)
	return data


## Lê um save; valores fora do esperado ficam no padrão ou são limitados.
func load_dict(data: Dictionary) -> void:
	combat_time = maxf(float(data.get("combat_time", 0.0)), 0.0)
	strafe_bias = clampf(float(data.get("strafe_bias", 0.0)), -1.0, 1.0)
	strafe_switch_time = clampf(float(data.get("strafe_switch_time", 1.0)), 0.1, 10.0)
	strafe_switches = maxi(int(data.get("strafe_switches", 0)), 0)
	strafe_switch_jitter = clampf(float(data.get("strafe_switch_jitter", 0.5)), 0.0, 10.0)
	jump_rate = clampf(float(data.get("jump_rate", 0.0)), 0.0, 10.0)
	crouch_ratio = clampf(float(data.get("crouch_ratio", 0.0)), 0.0, 1.0)
	sprint_ratio = clampf(float(data.get("sprint_ratio", 0.0)), 0.0, 1.0)
	preferred_distance = clampf(float(data.get("preferred_distance", 14.0)), 1.0, 200.0)
	reaction_time = clampf(float(data.get("reaction_time", 0.6)), 0.05, 3.0)
	reaction_samples = maxi(int(data.get("reaction_samples", 0)), 0)
	skill = clampf(float(data.get("skill", 0.4)), SKILL_MIN, SKILL_MAX)
	duels_won = maxi(int(data.get("duels_won", 0)), 0)
	duels_lost = maxi(int(data.get("duels_lost", 0)), 0)
	for key in ["shots", "hits"]:
		var saved = data.get(key, [])
		var values: Array[float] = [0.0, 0.0, 0.0]
		if saved is Array:
			for i in mini(saved.size(), values.size()):
				values[i] = maxf(float(saved[i]), 0.0)
		set(key, values)
	heatmap = {}
	var saved_heat = data.get("heatmap", {})
	if saved_heat is Dictionary:
		for map_key in saved_heat:
			var cells = saved_heat[map_key]
			if not cells is Dictionary:
				continue
			var clean := {}
			for cell in cells:
				if cell is Vector2i:
					clean[cell] = maxf(float(cells[cell]), 0.0)
			heatmap[str(map_key)] = clean
