extends Node3D
## Regressões da mira x tiro:
## 1. Celular com entalhe: o HUD encolhe para a área segura, mas a mira (e o
##    flash/arcos de dano) continuam no centro da TELA, que é para onde a
##    câmera aponta. Antes a mira andava junto com o HUD e o tiro parecia ir
##    para o lado dela.
## 2. Terceira pessoa: o tiro sai do olho e vai até o ponto sob a mira.
##    Antes ele seguia a frente da cabeça e passava abaixo da mira de perto.
## 3. Troca de arma pela roda do mouse e a curva seca da aterrissagem.
## Roda como cena (com os autoloads):
##   godot --headless --path . res://tests/aim_test.tscn

## Entalhe simulado (pixels da janela).
const NOTCH_LEFT: float = 120.0
const NOTCH_RIGHT: float = 40.0
## Parede na frente do jogador, perto o bastante para a diferença aparecer.
const WALL_DISTANCE: float = 6.0

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	GameInput.touch = true
	await _test_crosshair_with_notch()
	await _test_third_person_aim()
	_test_scroll_and_landing()
	print("%d verificações, %d falha(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_crosshair_with_notch() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as GameHUD
	layer.add_child(hud)
	await _frames(2)
	var view := hud.get_viewport_rect().size
	hud.apply_safe_rect(Rect2(NOTCH_LEFT, 0.0, view.x - NOTCH_LEFT - NOTCH_RIGHT, view.y), view)
	await _frames(2)

	var screen_center := view * 0.5
	var cross_center := hud.cross.get_global_rect().get_center()
	_check(cross_center.distance_to(screen_center) < 1.0,
		"mira no centro da tela com entalhe (mira %s, tela %s)" % [cross_center, screen_center])
	_check(absf(hud.get_global_rect().position.x - NOTCH_LEFT) < 1.0, "HUD encolhe para a área segura")
	_check(hud.damage_flash.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, view)),
		"flash de dano cobre a tela inteira")
	_check(hud.damage_indicator.get_global_rect().get_center().distance_to(screen_center) < 1.0,
		"arcos de dano em volta do centro da tela")
	layer.queue_free()


func _test_third_person_aim() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	_add_box(Vector3(0, 2, -WALL_DISTANCE), Vector3(40, 6, 1))
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as FPSPlayer
	player.name = "1"
	add_child(player)
	await _physics_frames(20)
	# Espera o teleporte do spawn assentar e olha reto para a parede.
	player.global_position = Vector3(0, 0.1, 0)
	player.rotation.y = 0.0
	player.head.rotation.x = 0.0
	await _physics_frames(10)

	var forward := -player.head.global_basis.z
	FPSPlayer.view_mode = FPSPlayer.ViewMode.FIRST
	await _frames(2)
	_check(player._aim_direction(100.0).is_equal_approx(forward), "primeira pessoa: tiro reto da cabeça")

	FPSPlayer.view_mode = FPSPlayer.ViewMode.BACK
	await _frames(3)
	var cam := player.camera
	var under_crosshair := _ray(cam.global_position, -cam.global_basis.z)
	var eye := player.eye_position()
	var shot_point := _ray(eye, player._aim_direction(100.0))
	var old_point := _ray(eye, forward)
	_check(shot_point.distance_to(under_crosshair) < 0.05,
		"terceira pessoa: tiro acerta o ponto sob a mira (erro %.3f m)" % shot_point.distance_to(under_crosshair))
	_check(old_point.distance_to(under_crosshair) > 0.1,
		"cenário mostra o erro antigo (%.3f m)" % old_point.distance_to(under_crosshair))
	FPSPlayer.view_mode = FPSPlayer.ViewMode.FIRST


func _test_scroll_and_landing() -> void:
	_check(FPSPlayer.scroll_weapon_index(0, 1, 3) == 1, "roda para baixo: próxima arma")
	_check(FPSPlayer.scroll_weapon_index(2, 1, 3) == 0, "roda para baixo na última volta à primeira")
	_check(FPSPlayer.scroll_weapon_index(0, -1, 3) == 2, "roda para cima na primeira vai à última")
	# Aterrissagem seca: chega ao fundo rápido e volta sem passar do zero.
	var hit := WeaponAnimator.LAND_HIT
	_check(is_zero_approx(WeaponAnimator.land_curve(0.0)) and is_zero_approx(WeaponAnimator.land_curve(1.0)),
		"aterrissagem começa e termina no zero")
	_check(is_equal_approx(WeaponAnimator.land_curve(hit), 1.0), "aterrissagem chega ao fundo em LAND_HIT")
	_check(hit * WeaponAnimator.LAND_TIME < 0.05, "fundo da aterrissagem em menos de 50 ms")
	var monotonic := true
	var last := 1.0
	for i in range(1, 20):
		var value := WeaponAnimator.land_curve(hit + (1.0 - hit) * i / 20.0)
		monotonic = monotonic and value <= last and value >= 0.0
		last = value
	_check(monotonic, "aterrissagem volta sem tremer")


func _ray(from: Vector3, direction: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * 100.0)
	for node in get_tree().get_nodes_in_group("players"):
		query.exclude += [(node as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return Vector3.INF if hit.is_empty() else hit["position"]


func _add_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	add_child(body)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FALHOU: " + label)
	else:
		print("ok: " + label)
