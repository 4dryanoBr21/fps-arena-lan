extends Node
## Autoload "Fx": traços, impactos, clarões de tiro e números de dano
## reaproveitados de pools fixos.
## Malhas e materiais são criados uma vez só; cada disparo apenas reposiciona
## um nó e anima a transparência (nada de material novo nem shader compilando
## no meio da partida).

const TRACER_POOL: int = 32
const IMPACT_POOL: int = 24
const FLASH_POOL: int = 12
const FLASH_TIME: float = 0.05
## Tamanho do clarão (m) por unidade de força do recuo da arma.
const FLASH_SIZE: float = 0.2
## Números de dano: quanto sobem, quanto duram e as cores (corpo, cabeça, abate).
const NUMBER_POOL: int = 16
const NUMBER_RISE: float = 0.9
const NUMBER_TIME: float = 0.8
const NUMBER_COLOR := Color(1.0, 1.0, 1.0)
const NUMBER_HEADSHOT_COLOR := Color(1.0, 0.85, 0.25)
const NUMBER_KILL_COLOR := Color(1.0, 0.3, 0.25)
const TRACER_TIME: float = 0.12
const IMPACT_TIME: float = 0.25
const IMPACT_VISIBLE_RANGE: float = 80.0

var _tracers: Array[MeshInstance3D] = []
var _impacts: Array[MeshInstance3D] = []
var _flashes: Array[MeshInstance3D] = []
var _numbers: Array[Label3D] = []
var _tweens: Dictionary = {}
var _next_tracer: int = 0
var _next_impact: int = 0
var _next_flash: int = 0
var _next_number: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.025, 0.025, 1.0)
	tracer_mesh.material = _make_material(Color(1.0, 0.9, 0.35, 0.9))
	var impact_mesh := SphereMesh.new()
	impact_mesh.radius = 0.08
	impact_mesh.height = 0.16
	impact_mesh.radial_segments = 12
	impact_mesh.rings = 6
	impact_mesh.material = _make_material(Color(1.0, 0.55, 0.1, 1.0))
	for i in TRACER_POOL:
		_tracers.append(_make_instance(tracer_mesh))
	for i in IMPACT_POOL:
		var impact_node := _make_instance(impact_mesh)
		# Faísca de 16 cm a mais de 80 m ocupa menos de um pixel.
		impact_node.visibility_range_end = IMPACT_VISIBLE_RANGE
		_impacts.append(impact_node)
	var flash_mesh := QuadMesh.new()
	flash_mesh.material = _make_flash_material()
	for i in FLASH_POOL:
		_flashes.append(_make_instance(flash_mesh))
	for i in NUMBER_POOL:
		_numbers.append(_make_number())


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var node := _tracers[_next_tracer]
	_next_tracer = (_next_tracer + 1) % _tracers.size()
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	node.look_at_from_position((from + to) * 0.5, to, up)
	node.scale = Vector3(1.0, 1.0, length)
	_play(node, TRACER_TIME, 1.0)


func impact(point: Vector3) -> void:
	var node := _impacts[_next_impact]
	_next_impact = (_next_impact + 1) % _impacts.size()
	node.global_position = point
	node.scale = Vector3.ONE
	_play(node, IMPACT_TIME, 2.5)


## Clarão na boca do cano; `strength` é a força do recuo da arma.
func muzzle_flash(point: Vector3, strength: float) -> void:
	var node := _flashes[_next_flash]
	_next_flash = (_next_flash + 1) % _flashes.size()
	node.global_position = point
	var size := FLASH_SIZE * clampf(strength, 0.6, 2.4) * _rng.randf_range(0.85, 1.15)
	node.scale = Vector3.ONE * size
	_play(node, FLASH_TIME, size * 1.4)


## Número de dano sobre a cabeça do inimigo: salta, sobe e some. Cabeça em
## amarelo, abate em vermelho. Aparece por cima de tudo, até de parede.
func damage_number(point: Vector3, amount: int, headshot: bool, killed: bool) -> void:
	var label := _numbers[_next_number]
	_next_number = (_next_number + 1) % _numbers.size()
	var previous: Tween = _tweens.get(label)
	if previous != null:
		previous.kill()
	# Espalha um pouco para números seguidos não ficarem um em cima do outro.
	var start := point + Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.1, 0.15), _rng.randf_range(-0.35, 0.35))
	label.global_position = start
	label.text = str(amount)
	label.modulate = NUMBER_KILL_COLOR if killed else NUMBER_HEADSHOT_COLOR if headshot else NUMBER_COLOR
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	var big := 1.35 if headshot or killed else 1.0
	label.scale = Vector3.ONE * big * 1.6
	label.visible = true
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE * big, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position", start + Vector3.UP * NUMBER_RISE, NUMBER_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, NUMBER_TIME * 0.4).set_delay(NUMBER_TIME * 0.6)
	tween.tween_property(label, "outline_modulate:a", 0.0, NUMBER_TIME * 0.4).set_delay(NUMBER_TIME * 0.6)
	tween.chain().tween_callback(label.hide)
	_tweens[label] = tween


func _play(node: MeshInstance3D, duration: float, end_scale: float) -> void:
	var previous: Tween = _tweens.get(node)
	if previous != null:
		previous.kill()
	node.transparency = 0.0
	node.visible = true
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "transparency", 1.0, duration)
	if end_scale != 1.0:
		tween.tween_property(node, "scale", Vector3.ONE * end_scale, duration)
	tween.chain().tween_callback(node.hide)
	_tweens[node] = tween


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	return mat


## Brilho redondo e suave, sempre virado para a câmera, somando luz.
func _make_flash_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	gradient.set_color(1, Color(1.0, 0.55, 0.1, 0.0))
	gradient.add_point(0.35, Color(1.0, 0.75, 0.3, 0.8))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Sem isto o billboard ignora a escala do nó e o clarão sai com 1 m.
	mat.billboard_keep_scale = true
	mat.albedo_texture = texture
	return mat


func _make_number() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# Tamanho fixo na tela, como no Fortnite (perto ou longe, mesmo tamanho).
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 44
	label.outline_size = 12
	label.render_priority = 10
	label.outline_render_priority = 9
	label.visible = false
	add_child(label)
	return label


func _make_instance(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node
