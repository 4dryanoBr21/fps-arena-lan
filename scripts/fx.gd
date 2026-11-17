extends Node
## Autoload "Fx": traços e impactos de tiro reaproveitados de pools fixos.
## Malhas e materiais são criados uma vez só; cada disparo apenas reposiciona
## um nó e anima a transparência (nada de material novo nem shader compilando
## no meio da partida).

const TRACER_POOL: int = 32
const IMPACT_POOL: int = 24
const TRACER_TIME: float = 0.12
const IMPACT_TIME: float = 0.25

var _tracers: Array[MeshInstance3D] = []
var _impacts: Array[MeshInstance3D] = []
var _tweens: Dictionary = {}
var _next_tracer: int = 0
var _next_impact: int = 0


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
		_impacts.append(_make_instance(impact_mesh))


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


func _make_instance(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node
