extends SceneTree
## Testes unitários das partes sem cena. Rode com:
##   godot --headless --path . --script res://tests/unit_tests.gd
## Sai com código 1 se algum falhar.

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_ray_capsule()
	_test_spread()
	_test_history()
	_test_announcement()
	_test_private_ip()
	_test_rules()
	_test_upgrades()
	_test_loadout()
	_test_levels()
	_test_profile()
	_test_habits_movement()
	_test_habits_combat()
	_test_habits_skill()
	_test_habits_save()
	print("%d verificações, %d falha(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALHOU: " + label)


func _test_ray_capsule() -> void:
	var feet := Vector3(0, 0, -10)
	# Raio reto na altura do peito acerta a 10 m menos o raio da cápsula.
	var d := CombatMath.ray_capsule_distance(Vector3(0, 1.2, 0), Vector3.FORWARD, 100.0, feet, 1.8, 0.4)
	_check(absf(d - 9.6) < 0.01, "cápsula: distância no peito (%f)" % d)
	# Passa 0,5 m ao lado: erra.
	d = CombatMath.ray_capsule_distance(Vector3(0.5, 1.2, 0), Vector3.FORWARD, 100.0, feet, 1.8, 0.4)
	_check(d < 0.0, "cápsula: tiro ao lado erra")
	# Acima da cabeça: erra.
	d = CombatMath.ray_capsule_distance(Vector3(0, 2.3, 0), Vector3.FORWARD, 100.0, feet, 1.8, 0.4)
	_check(d < 0.0, "cápsula: tiro por cima erra")
	# Na cabeça (1,7 m): acerta e conta como headshot com a razão 0,8.
	d = CombatMath.ray_capsule_distance(Vector3(0, 1.7, 0), Vector3.FORWARD, 100.0, feet, 1.8, 0.4)
	_check(d > 0.0 and 1.7 >= 1.8 * 0.8, "cápsula: tiro na cabeça acerta")
	# Parede antes do alvo: max_distance curto não alcança.
	d = CombatMath.ray_capsule_distance(Vector3(0, 1.2, 0), Vector3.FORWARD, 5.0, feet, 1.8, 0.4)
	_check(d < 0.0, "cápsula: limite de distância respeitado")


func _test_spread() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var forward := Vector3.FORWARD
	_check(CombatMath.spread_direction(forward, 0.0, rng) == forward, "dispersão zero mantém a direção")
	var worst := 0.0
	for i in 500:
		var dir := CombatMath.spread_direction(forward, 5.0, rng)
		_check(absf(dir.length() - 1.0) < 0.001, "dispersão normalizada")
		worst = maxf(worst, rad_to_deg(forward.angle_to(dir)))
	_check(worst <= 5.01 and worst > 3.0, "dispersão dentro do cone (%f°)" % worst)


func _test_history() -> void:
	var history := [[1000, Vector3(0, 0, 0)], [1100, Vector3(10, 0, 0)], [1200, Vector3(10, 0, 10)]]
	_check(CombatMath.sample_history(history, 1050, Vector3.ZERO).is_equal_approx(Vector3(5, 0, 0)), "histórico interpola")
	_check(CombatMath.sample_history(history, 900, Vector3.ZERO) == Vector3.ZERO, "histórico antes do início")
	_check(CombatMath.sample_history(history, 5000, Vector3.ZERO) == Vector3(10, 0, 10), "histórico depois do fim")
	_check(CombatMath.sample_history([], 1000, Vector3.ONE) == Vector3.ONE, "histórico vazio usa o padrão")


func _test_announcement() -> void:
	var good := JSON.stringify({"magic": LanDiscovery.MAGIC, "port": 7777, "host": "Ana", "map": "Arena", "players": 3, "version": "1.1.0"})
	var entry := LanDiscovery.parse_announcement(good, "192.168.0.5")
	_check(entry.get("port") == 7777 and entry.get("host") == "Ana" and entry.get("ip") == "192.168.0.5", "anúncio válido")
	_check(LanDiscovery.parse_announcement("lixo", "192.168.0.5").is_empty(), "anúncio inválido ignorado")
	var other := JSON.stringify({"magic": "OUTRO", "port": 7777})
	_check(LanDiscovery.parse_announcement(other, "192.168.0.5").is_empty(), "anúncio de outro jogo ignorado")
	var bad_port := JSON.stringify({"magic": LanDiscovery.MAGIC, "port": 70000})
	_check(LanDiscovery.parse_announcement(bad_port, "192.168.0.5").is_empty(), "porta inválida ignorada")


func _test_private_ip() -> void:
	for address: String in ["192.168.1.20", "10.0.0.7", "172.16.4.1", "172.31.255.1"]:
		_check(LanDiscovery.is_private_ipv4(address), "IP privado: " + address)
	for address: String in ["8.8.8.8", "172.32.0.1", "127.0.0.1", "fe80::1"]:
		_check(not LanDiscovery.is_private_ipv4(address), "IP não privado: " + address)


func _test_rules() -> void:
	var rules := load("res://data/game_rules.tres") as GameRules
	_check(rules != null and rules.weapons.size() >= 4, "catálogo com várias armas")
	var ids := {}
	for item: ShopItem in rules.weapons + rules.equipment:
		_check(not item.id.is_empty() and not ids.has(item.id), "id único: " + item.display_name)
		ids[item.id] = true
		_check(item.price >= 0 and item.unlock_level >= 1, "preço e nível válidos: " + item.display_name)
	for weapon in rules.weapons:
		_check(weapon.magazine > 0 and weapon.fire_cooldown > 0.0 and weapon.pellets >= 1, "arma válida: " + weapon.display_name)
		_check(weapon.sound in _sfx_names(), "som existe: " + weapon.display_name)
	for id in [rules.default_primary, rules.default_secondary]:
		var weapon := rules.weapon_by_id(id)
		_check(weapon != null and weapon.is_free(), "arma inicial gratuita: " + id)
	_check(rules.weapon_by_id(rules.default_primary).slot == WeaponData.Slot.PRIMARY, "inicial principal na vaga certa")
	_check(rules.weapon_by_id(rules.default_secondary).slot == WeaponData.Slot.SECONDARY, "inicial secundária na vaga certa")
	_check(rules.sprint_speed > rules.walk_speed and rules.walk_speed > rules.crouch_speed, "velocidades em ordem")


## Nomes que o autoload Sfx carrega (aqui não há autoloads).
func _sfx_names() -> Array:
	return Array(load("res://scripts/sfx.gd").ALL)


func _test_upgrades() -> void:
	var rules := load("res://data/game_rules.tres") as GameRules
	var rifle := rules.weapon_by_id("rifle")
	var base := rifle.upgraded(0, rules)
	_check(base.magazine == rifle.magazine and base.tier == 0 and base != rifle, "melhoria 0 é cópia igual")
	var best := rifle.upgraded(99, rules)
	_check(best.tier == rules.max_upgrade_tier, "melhoria limitada ao máximo")
	_check(best.magazine > rifle.magazine and best.reload_time < rifle.reload_time and best.recoil < rifle.recoil, "melhoria ajuda")
	_check(best.body_damage == rifle.body_damage, "melhoria não mexe no dano")
	_check(rifle.magazine == 12, "original intacto depois de melhorar")


func _test_loadout() -> void:
	var rules := load("res://data/game_rules.tres") as GameRules
	var clean := rules.sanitize_loadout({})
	_check(clean["primary"] == rules.default_primary and clean["secondary"] == rules.default_secondary and clean["equipment"] == "", "equipamento vazio vira padrão")
	clean = rules.sanitize_loadout({"primary": "pistol", "secondary": "sniper", "equipment": "nada", "primary_tier": 50, "secondary_tier": -3})
	_check(clean["primary"] == rules.default_primary and clean["secondary"] == rules.default_secondary, "arma na vaga errada volta ao padrão")
	_check(clean["equipment"] == "" and clean["primary_tier"] == rules.max_upgrade_tier and clean["secondary_tier"] == 0, "equipamento e melhorias conferidos")
	clean = rules.sanitize_loadout({"primary": "sniper", "secondary": "revolver", "equipment": "heavy_vest", "primary_tier": 2})
	_check(clean["primary"] == "sniper" and clean["secondary"] == "revolver" and clean["equipment"] == "heavy_vest" and clean["primary_tier"] == 2, "equipamento válido passa")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 30:
		var bot := rules.random_loadout(rng)
		_check(rules.sanitize_loadout(bot) == bot, "equipamento de bot é válido")


func _test_levels() -> void:
	_check(PlayerProfile.level_for_xp(0) == 1, "começa no nível 1")
	_check(PlayerProfile.level_for_xp(199) == 1 and PlayerProfile.level_for_xp(200) == 2, "nível 2 com 200 XP")
	_check(PlayerProfile.level_for_xp(600) == 3, "nível 3 com 600 XP")
	_check(PlayerProfile.level_for_xp(10000000) == PlayerProfile.MAX_LEVEL, "nível máximo")
	for level in range(1, PlayerProfile.MAX_LEVEL):
		_check(PlayerProfile.xp_for_level(level + 1) > PlayerProfile.xp_for_level(level), "curva de XP cresce")


func _test_profile() -> void:
	var rules := load("res://data/game_rules.tres") as GameRules
	var smg := rules.weapon_by_id("smg")
	var vest := rules.equipment_by_id("light_vest")
	var profile := PlayerProfile.new()
	_check(profile.owns(rules.weapon_by_id("rifle")) and not profile.owns(smg), "começa só com as gratuitas")
	_check(not profile.buy(smg) and profile.buy_block_reason(smg).begins_with("Nível"), "nível baixo bloqueia compra")

	_check(profile.add_reward(0, 200) == 1, "subiu um nível")
	_check(not profile.buy(smg) and profile.buy_block_reason(smg).begins_with("Faltam"), "sem moedas bloqueia compra")
	profile.add_reward(1000, 0)
	_check(profile.buy(smg) and profile.coins == 100 and profile.owns(smg), "compra desconta e guarda")
	_check(not profile.buy(smg), "não compra duas vezes")
	_check(profile.equip(smg) and profile.primary == "smg", "equipa arma comprada na vaga principal")
	_check(not profile.equip(rules.weapon_by_id("sniper")), "não equipa o que não comprou")

	_check(not profile.upgrade(smg), "melhoria sem moedas falha")
	profile.add_reward(5000, 0)
	var coins_before := profile.coins
	_check(profile.upgrade(smg) and profile.upgrade_tier("smg") == 1, "melhoria sobe um nível")
	_check(profile.coins == coins_before - rules.upgrade_prices[0], "melhoria desconta o preço")
	while profile.upgrade(smg):
		pass
	_check(profile.upgrade_tier("smg") == rules.max_upgrade_tier and profile.upgrade_price("smg") == -1, "melhoria para no máximo")

	profile.add_reward(0, 1000)
	_check(profile.buy(vest) and profile.equip(vest) and profile.equipment == "light_vest", "compra e equipa colete")
	_check(profile.equip(vest) and profile.equipment == "", "equipar de novo tira o colete")
	profile.equip(vest)

	var net := profile.network_loadout()
	_check(net["primary"] == "smg" and net["primary_tier"] == rules.max_upgrade_tier and net["equipment"] == "light_vest", "equipamento enviado à rede")

	var copy := PlayerProfile.new()
	copy.load_dict(profile.to_dict())
	_check(copy.coins == profile.coins and copy.xp == profile.xp and copy.primary == "smg" and copy.equipment == "light_vest", "save e leitura batem")
	_check(copy.upgrade_tier("smg") == rules.max_upgrade_tier, "melhorias salvas")

	var cheat := PlayerProfile.new()
	cheat.load_dict({"coins": -50, "primary": "sniper", "equipment": "heavy_vest", "owned": ["inexistente"], "upgrades": {"rifle": 99}})
	_check(cheat.coins == 0 and cheat.primary == rules.default_primary and cheat.equipment == "", "save sem compra volta ao padrão")
	_check(cheat.owned.is_empty() and cheat.upgrade_tier("rifle") == rules.max_upgrade_tier, "save com lixo é limpo")


## Simula `seconds` de combate desviando para `side` e trocando a cada `switch_every` s.
func _strafe(habits: PlayerHabits, seconds: float, side: float, switch_every: float, map_key: String = "m") -> void:
	var t := 0.0
	var current := side
	var since := 0.0
	while t < seconds:
		habits.observe_tick(0.1, map_key, Vector3(10, 0, 10), current * 5.0, false, false, false, true)
		t += 0.1
		since += 0.1
		if switch_every > 0.0 and since >= switch_every - 0.001:
			current = -current
			since = 0.0


func _test_habits_movement() -> void:
	var habits := PlayerHabits.new()
	_check(habits.confidence() == 0.0, "hábitos: começa sem confiança")
	_strafe(habits, 40.0, 1.0, 0.0)
	_check(habits.strafe_bias > 0.9, "hábitos: aprende que desvia para a direita (%f)" % habits.strafe_bias)
	_check(habits.confidence() > 0.6 and habits.confidence() < 0.7, "hábitos: confiança cresce com o combate")

	var rhythm := PlayerHabits.new()
	_strafe(rhythm, 60.0, 1.0, 0.8)
	_check(absf(rhythm.strafe_switch_time - 0.8) < 0.15, "hábitos: aprende o ritmo de troca (%f)" % rhythm.strafe_switch_time)
	_check(absf(rhythm.strafe_bias) < 0.3, "hábitos: desvio alternado fica sem lado")
	# Logo depois de trocar não espera troca; perto do ritmo espera.
	rhythm.current_strafe_time = 0.1
	_check(not rhythm.expects_reversal(), "hábitos: não prevê troca logo após trocar")
	rhythm.current_strafe_time = 0.75
	_check(rhythm.expects_reversal(), "hábitos: prevê troca no ritmo do jogador")

	_check(rhythm.knows_rhythm() and rhythm.has_regular_rhythm(), "hábitos: ritmo constante é regular")

	var fresh := PlayerHabits.new()
	fresh.current_strafe_sign = 1
	fresh.current_strafe_time = 5.0
	_check(not fresh.expects_reversal(), "hábitos: sem trocas vistas não prevê troca")
	var one_side := PlayerHabits.new()
	_strafe(one_side, 60.0, 1.0, 0.0)
	for tip in one_side.insights():
		_check(not "ritmo" in tip, "hábitos: sem trocas não inventa dica de ritmo")

	# Ritmo irregular: alterna trechos de 0,3 s e 1,5 s.
	var irregular := PlayerHabits.new()
	var side := 1.0
	for i in 40:
		var length := 0.3 if i % 2 == 0 else 1.5
		var t := 0.0
		while t < length - 0.001:
			irregular.observe_tick(0.1, "m", Vector3.ZERO, side * 5.0, false, false, false, true)
			t += 0.1
		side = -side
	_check(irregular.knows_rhythm() and not irregular.has_regular_rhythm(), "hábitos: ritmo variado não é regular (%f ± %f)" % [irregular.strafe_switch_time, irregular.strafe_switch_jitter])

	var jumper := PlayerHabits.new()
	for i in 300:
		jumper.observe_tick(0.1, "m", Vector3.ZERO, 0.0, i % 10 == 0, i % 2 == 0, false, true)
	_check(absf(jumper.jump_rate - 1.0) < 0.35, "hábitos: um pulo por segundo (%f)" % jumper.jump_rate)
	_check(absf(jumper.crouch_ratio - 0.5) < 0.1, "hábitos: agachado metade do tempo (%f)" % jumper.crouch_ratio)

	var calm := PlayerHabits.new()
	calm.observe_tick(5.0, "m", Vector3.ZERO, 6.0, false, false, false, false)
	_check(calm.combat_time == 0.0 and calm.strafe_bias == 0.0, "hábitos: fora de combate não conta movimento")
	_check(not calm.heatmap.get("m", {}).is_empty(), "hábitos: fora de combate marca o mapa de calor")


func _test_habits_combat() -> void:
	var habits := PlayerHabits.new()
	var fallback := habits.weakest_range_distance()
	_check(fallback == PlayerHabits.RANGE_CENTERS[2], "hábitos: sem dados, briga longe de quem atira de perto/médio")
	for i in 20:
		habits.observe_shot(4.0, i % 4 != 0)
		habits.observe_shot(30.0, i % 5 == 0)
	_check(habits.accuracy(0) > 0.6 and habits.accuracy(2) < 0.3, "hábitos: precisão por faixa")
	_check(habits.weakest_range_distance() == PlayerHabits.RANGE_CENTERS[2], "hábitos: Caçador briga onde a mira é pior")
	_check(PlayerHabits.range_bucket(3.0) == 0 and PlayerHabits.range_bucket(10.0) == 1 and PlayerHabits.range_bucket(50.0) == 2, "hábitos: faixas de distância")

	for i in 30:
		habits.observe_reaction(0.9)
	_check(absf(habits.reaction_time - 0.9) < 0.05, "hábitos: tempo de reação")
	habits.observe_reaction(10.0)
	_check(absf(habits.reaction_time - 0.9) < 0.05, "hábitos: reação absurda ignorada")

	var map_habits := PlayerHabits.new()
	for i in 100:
		map_habits.observe_tick(0.1, "a", Vector3(21, 0, -3), 0.0, false, false, false, false)
	map_habits.observe_tick(0.1, "a", Vector3(-30, 0, 30), 0.0, false, false, false, false)
	var spots := map_habits.hot_spots("a", 1)
	_check(spots.size() == 1 and PlayerHabits.cell_of(spots[0]) == PlayerHabits.cell_of(Vector3(21, 0, -3)), "hábitos: lugar preferido do mapa")
	_check(map_habits.hot_spots("outro", 3).is_empty(), "hábitos: mapa de calor separado por mapa")
	_check(map_habits.hot_spot_share("a") > 0.95, "hábitos: concentração no mapa")


func _test_habits_skill() -> void:
	var habits := PlayerHabits.new()
	var start := habits.skill
	habits.observe_duel(true)
	_check(habits.skill > start, "dificuldade sobe quando o jogador vence")
	for i in 100:
		habits.observe_duel(true)
	_check(habits.skill == PlayerHabits.SKILL_MAX, "dificuldade tem teto")
	for i in 100:
		habits.observe_duel(false)
	_check(habits.skill == PlayerHabits.SKILL_MIN, "dificuldade tem piso")
	# Equilíbrio: vencendo 55% dos duelos a dificuldade fica parada.
	var balanced := PlayerHabits.new()
	balanced.skill = 0.5
	for i in 200:
		balanced.observe_duel(i % 20 < 11)
	_check(absf(balanced.skill - 0.5) < 0.15, "dificuldade estável com ~55%% de vitórias (%f)" % balanced.skill)


func _test_habits_save() -> void:
	var habits := PlayerHabits.new()
	_check(habits.insights().size() == 1, "hábitos: sem dados, uma dica de jogar mais")
	_strafe(habits, 60.0, -1.0, 0.0, "mapa")
	for i in 20:
		habits.observe_shot(5.0, true)
		habits.observe_shot(25.0, false)
	habits.observe_duel(false)
	var tips := habits.insights("mapa")
	_check(tips.size() >= 2, "hábitos: gera dicas (%d)" % tips.size())
	_check("esquerda" in tips[0], "hábitos: primeira dica fala do lado do desvio")
	_check(habits.stats_lines().size() >= 6, "hábitos: linhas de números")
	_check(not habits.summary_line("mapa").is_empty(), "hábitos: resumo de fim de treino")

	var copy := PlayerHabits.new()
	copy.load_dict(habits.to_dict())
	_check(is_equal_approx(copy.strafe_bias, habits.strafe_bias) and copy.shots == habits.shots and copy.duels_lost == 1, "hábitos: save e leitura batem")
	_check(copy.hot_spots("mapa", 1) == habits.hot_spots("mapa", 1), "hábitos: mapa de calor salvo")
	var rhythm := PlayerHabits.new()
	_strafe(rhythm, 30.0, 1.0, 0.8)
	var rhythm_copy := PlayerHabits.new()
	rhythm_copy.load_dict(rhythm.to_dict())
	_check(rhythm_copy.strafe_switches == rhythm.strafe_switches and is_equal_approx(rhythm_copy.strafe_switch_jitter, rhythm.strafe_switch_jitter), "hábitos: ritmo salvo")

	var junk := PlayerHabits.new()
	junk.load_dict({"strafe_bias": 9.0, "skill": -4.0, "shots": "x", "heatmap": {"m": {"lixo": 3}}, "reaction_time": 99.0})
	_check(junk.strafe_bias == 1.0 and junk.skill == PlayerHabits.SKILL_MIN and junk.shots == [0.0, 0.0, 0.0], "hábitos: save com lixo é limitado")
	_check(junk.heatmap.get("m", {}).is_empty() and junk.reaction_time == 3.0, "hábitos: células e reação inválidas descartadas")

	habits.new_match()
	_check(habits.shots[0] < 20.0, "hábitos: partida nova pesa menos o passado")

