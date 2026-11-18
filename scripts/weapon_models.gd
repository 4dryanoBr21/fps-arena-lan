class_name WeaponModels
extends RefCounted
## Modelos low poly das armas, montados com caixas e cilindros. As peças de
## cada arma viram uma malha só (uma superfície por material), criada uma vez
## e compartilhada por todos os jogadores e pelas miniaturas do Arsenal.
## Coordenadas em metros: o cano aponta para -Z, Y para cima e a origem fica
## no punho (onde a mão segura). MUZZLES diz de onde sai o traço do tiro.
## hold_offset() empurra as armas longas para a frente, para a coronha não
## encostar na câmera em primeira pessoa.

enum Mat { DARK, METAL, WOOD, POLYMER, LENS }

const MATERIAL_SPECS := {
	Mat.DARK: [Color(0.16, 0.16, 0.18), 0.6, 0.45],
	Mat.METAL: [Color(0.38, 0.39, 0.43), 0.8, 0.35],
	Mat.WOOD: [Color(0.46, 0.28, 0.14), 0.0, 0.8],
	Mat.POLYMER: [Color(0.24, 0.25, 0.22), 0.0, 0.85],
	Mat.LENS: [Color(0.25, 0.55, 0.85), 0.3, 0.1],
}

## Peças: "box" = tamanho; "cyl" = (raio, comprimento), deitado ao longo de Z;
## "sides" = lados do cilindro (6 = sextavado); "rot" = graus em X, Y, Z.
const PARTS := {
	"knife": [
		{"box": Vector3(0.005, 0.03, 0.15), "at": Vector3(0, 0.01, -0.13), "mat": Mat.METAL},
		{"box": Vector3(0.005, 0.021, 0.021), "at": Vector3(0, 0.0175, -0.205), "rot": Vector3(45, 0, 0), "mat": Mat.METAL},
		{"box": Vector3(0.007, 0.008, 0.13), "at": Vector3(0, 0.022, -0.125), "mat": Mat.DARK},
		{"box": Vector3(0.022, 0.055, 0.012), "at": Vector3(0, 0.005, -0.05), "mat": Mat.DARK},
		{"cyl": Vector2(0.014, 0.1), "sides": 6, "at": Vector3(0, 0.005, 0.005), "mat": Mat.POLYMER},
		{"box": Vector3(0.02, 0.03, 0.014), "at": Vector3(0, 0.005, 0.06), "mat": Mat.DARK},
	],
	"pistol": [
		{"box": Vector3(0.034, 0.04, 0.19), "at": Vector3(0, 0.045, -0.06), "mat": Mat.DARK},
		{"box": Vector3(0.03, 0.026, 0.15), "at": Vector3(0, 0.014, -0.05), "mat": Mat.POLYMER},
		{"box": Vector3(0.03, 0.1, 0.045), "at": Vector3(0, -0.04, 0.012), "rot": Vector3(-14, 0, 0), "mat": Mat.POLYMER},
		{"box": Vector3(0.008, 0.022, 0.045), "at": Vector3(0, -0.008, -0.03), "mat": Mat.POLYMER},
		{"cyl": Vector2(0.007, 0.012), "at": Vector3(0, 0.045, -0.158), "mat": Mat.METAL},
		{"box": Vector3(0.006, 0.01, 0.008), "at": Vector3(0, 0.07, -0.145), "mat": Mat.METAL},
		{"box": Vector3(0.022, 0.01, 0.008), "at": Vector3(0, 0.07, 0.02), "mat": Mat.METAL},
	],
	"revolver": [
		{"cyl": Vector2(0.014, 0.15), "at": Vector3(0, 0.05, -0.125), "mat": Mat.METAL},
		{"box": Vector3(0.012, 0.012, 0.15), "at": Vector3(0, 0.066, -0.125), "mat": Mat.METAL},
		{"cyl": Vector2(0.006, 0.08), "at": Vector3(0, 0.027, -0.09), "mat": Mat.METAL},
		{"cyl": Vector2(0.03, 0.05), "sides": 6, "at": Vector3(0, 0.04, -0.025), "mat": Mat.METAL},
		{"box": Vector3(0.03, 0.055, 0.08), "at": Vector3(0, 0.035, -0.02), "mat": Mat.DARK},
		{"box": Vector3(0.03, 0.1, 0.042), "at": Vector3(0, -0.03, 0.045), "rot": Vector3(-20, 0, 0), "mat": Mat.WOOD},
		{"box": Vector3(0.01, 0.022, 0.016), "at": Vector3(0, 0.07, 0.022), "rot": Vector3(-25, 0, 0), "mat": Mat.DARK},
		{"box": Vector3(0.008, 0.02, 0.04), "at": Vector3(0, -0.005, -0.01), "mat": Mat.DARK},
		{"box": Vector3(0.006, 0.012, 0.008), "at": Vector3(0, 0.078, -0.195), "mat": Mat.METAL},
	],
	"rifle": [
		{"box": Vector3(0.045, 0.06, 0.26), "at": Vector3(0, 0.022, -0.05), "mat": Mat.DARK},
		{"box": Vector3(0.042, 0.08, 0.24), "at": Vector3(0, -0.012, 0.19), "rot": Vector3(8, 0, 0), "mat": Mat.WOOD},
		{"box": Vector3(0.05, 0.05, 0.22), "at": Vector3(0, 0.008, -0.28), "mat": Mat.WOOD},
		{"cyl": Vector2(0.011, 0.2), "at": Vector3(0, 0.026, -0.47), "mat": Mat.DARK},
		{"box": Vector3(0.03, 0.085, 0.05), "at": Vector3(0, -0.05, -0.08), "rot": Vector3(10, 0, 0), "mat": Mat.DARK},
		{"box": Vector3(0.008, 0.022, 0.05), "at": Vector3(0, -0.015, 0.0), "mat": Mat.DARK},
		{"box": Vector3(0.008, 0.032, 0.01), "at": Vector3(0, 0.056, -0.53), "mat": Mat.DARK},
		{"box": Vector3(0.026, 0.016, 0.022), "at": Vector3(0, 0.06, -0.01), "mat": Mat.DARK},
	],
	"smg": [
		{"box": Vector3(0.045, 0.065, 0.24), "at": Vector3(0, 0.022, -0.06), "mat": Mat.DARK},
		{"cyl": Vector2(0.019, 0.1), "sides": 8, "at": Vector3(0, 0.026, -0.23), "mat": Mat.METAL},
		{"cyl": Vector2(0.008, 0.05), "at": Vector3(0, 0.026, -0.3), "mat": Mat.DARK},
		{"box": Vector3(0.026, 0.15, 0.034), "at": Vector3(0, -0.085, -0.1), "rot": Vector3(6, 0, 0), "mat": Mat.DARK},
		{"box": Vector3(0.03, 0.09, 0.04), "at": Vector3(0, -0.045, 0.045), "rot": Vector3(-15, 0, 0), "mat": Mat.POLYMER},
		{"box": Vector3(0.024, 0.07, 0.026), "at": Vector3(0, -0.04, -0.2), "mat": Mat.POLYMER},
		{"box": Vector3(0.007, 0.007, 0.19), "at": Vector3(0.016, 0.02, 0.15), "mat": Mat.METAL},
		{"box": Vector3(0.007, 0.007, 0.19), "at": Vector3(-0.016, 0.02, 0.15), "mat": Mat.METAL},
		{"box": Vector3(0.04, 0.065, 0.012), "at": Vector3(0, 0.0, 0.245), "mat": Mat.METAL},
		{"box": Vector3(0.008, 0.02, 0.01), "at": Vector3(0, 0.063, -0.17), "mat": Mat.DARK},
		{"box": Vector3(0.022, 0.016, 0.014), "at": Vector3(0, 0.063, 0.04), "mat": Mat.DARK},
	],
	"shotgun": [
		{"box": Vector3(0.05, 0.07, 0.2), "at": Vector3(0, 0.02, -0.02), "mat": Mat.DARK},
		{"cyl": Vector2(0.016, 0.42), "at": Vector3(0, 0.042, -0.33), "mat": Mat.METAL},
		{"cyl": Vector2(0.013, 0.34), "at": Vector3(0, 0.004, -0.29), "mat": Mat.DARK},
		{"box": Vector3(0.052, 0.048, 0.14), "at": Vector3(0, 0.004, -0.3), "mat": Mat.WOOD},
		{"box": Vector3(0.046, 0.095, 0.25), "at": Vector3(0, -0.018, 0.2), "rot": Vector3(10, 0, 0), "mat": Mat.WOOD},
		{"box": Vector3(0.008, 0.025, 0.05), "at": Vector3(0, -0.028, 0.03), "mat": Mat.DARK},
		{"box": Vector3(0.008, 0.008, 0.008), "at": Vector3(0, 0.062, -0.53), "mat": Mat.METAL},
	],
	"assault": [
		{"box": Vector3(0.05, 0.075, 0.3), "at": Vector3(0, 0.02, -0.04), "mat": Mat.DARK},
		{"box": Vector3(0.022, 0.016, 0.26), "at": Vector3(0, 0.066, -0.06), "mat": Mat.METAL},
		{"box": Vector3(0.056, 0.056, 0.22), "at": Vector3(0, 0.02, -0.3), "mat": Mat.POLYMER},
		{"cyl": Vector2(0.01, 0.15), "at": Vector3(0, 0.026, -0.48), "mat": Mat.DARK},
		{"cyl": Vector2(0.015, 0.045), "sides": 6, "at": Vector3(0, 0.026, -0.575), "mat": Mat.DARK},
		{"box": Vector3(0.01, 0.055, 0.016), "at": Vector3(0, 0.06, -0.4), "mat": Mat.DARK},
		{"box": Vector3(0.03, 0.08, 0.05), "at": Vector3(0, -0.055, -0.1), "rot": Vector3(10, 0, 0), "mat": Mat.DARK},
		{"box": Vector3(0.03, 0.075, 0.05), "at": Vector3(0, -0.115, -0.083), "rot": Vector3(26, 0, 0), "mat": Mat.DARK},
		{"box": Vector3(0.032, 0.09, 0.042), "at": Vector3(0, -0.05, 0.075), "rot": Vector3(-18, 0, 0), "mat": Mat.POLYMER},
		{"cyl": Vector2(0.016, 0.12), "at": Vector3(0, 0.02, 0.17), "mat": Mat.DARK},
		{"box": Vector3(0.045, 0.075, 0.16), "at": Vector3(0, 0.0, 0.25), "mat": Mat.POLYMER},
	],
	"sniper": [
		{"box": Vector3(0.045, 0.055, 0.26), "at": Vector3(0, 0.02, -0.03), "mat": Mat.DARK},
		{"box": Vector3(0.05, 0.085, 0.27), "at": Vector3(0, -0.022, 0.21), "rot": Vector3(6, 0, 0), "mat": Mat.POLYMER},
		{"box": Vector3(0.05, 0.05, 0.3), "at": Vector3(0, 0.0, -0.31), "mat": Mat.POLYMER},
		{"cyl": Vector2(0.012, 0.32), "at": Vector3(0, 0.026, -0.56), "mat": Mat.DARK},
		{"box": Vector3(0.036, 0.026, 0.055), "at": Vector3(0, 0.026, -0.745), "mat": Mat.METAL},
		{"cyl": Vector2(0.02, 0.28), "at": Vector3(0, 0.087, -0.05), "mat": Mat.DARK},
		{"cyl": Vector2(0.03, 0.06), "at": Vector3(0, 0.087, -0.215), "mat": Mat.DARK},
		{"cyl": Vector2(0.026, 0.05), "at": Vector3(0, 0.087, 0.11), "mat": Mat.DARK},
		{"cyl": Vector2(0.026, 0.004), "at": Vector3(0, 0.087, -0.247), "mat": Mat.LENS},
		{"box": Vector3(0.02, 0.035, 0.02), "at": Vector3(0, 0.058, -0.13), "mat": Mat.METAL},
		{"box": Vector3(0.02, 0.035, 0.02), "at": Vector3(0, 0.058, 0.03), "mat": Mat.METAL},
		{"cyl": Vector2(0.006, 0.055), "at": Vector3(0.03, 0.03, 0.05), "rot": Vector3(0, 90, 0), "mat": Mat.METAL},
		{"box": Vector3(0.016, 0.016, 0.016), "at": Vector3(0.058, 0.03, 0.05), "mat": Mat.METAL},
		{"box": Vector3(0.03, 0.04, 0.06), "at": Vector3(0, -0.03, -0.06), "mat": Mat.DARK},
	],
}

## Até onde a parte de trás da arma pode chegar (Z local, metros).
const MAX_BACK: float = 0.2

## Pose própria na mão (somada ao hold_offset): a faca fica mais perto da
## câmera, com a lâmina inclinada para cima e para dentro.
const HOLD_POSES := {
	"knife": {"at": Vector3(-0.04, 0.03, 0.2), "rot": Vector3(25, 20, -35)},
}

const MUZZLES := {
	"knife": Vector3(0, 0.012, -0.215),
	"pistol": Vector3(0, 0.045, -0.165),
	"revolver": Vector3(0, 0.05, -0.2),
	"rifle": Vector3(0, 0.026, -0.57),
	"smg": Vector3(0, 0.026, -0.325),
	"shotgun": Vector3(0, 0.042, -0.54),
	"assault": Vector3(0, 0.026, -0.6),
	"sniper": Vector3(0, 0.026, -0.775),
}

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


static func has_model(id: String) -> bool:
	return PARTS.has(id)


## Malha da arma (criada na primeira vez e reaproveitada).
static func mesh(id: String) -> ArrayMesh:
	if not _meshes.has(id):
		_meshes[id] = _build(PARTS.get(id, PARTS["rifle"]))
	return _meshes[id]


## Boca do cano (ou ponta da lâmina) já na pose da mão: posição para o
## Marker3D do cano, filho do nó da arma.
static func muzzle(id: String) -> Vector3:
	return hold_transform(id) * MUZZLES.get(id, MUZZLES["rifle"])


## Onde o modelo fica dentro do nó da arma: hold_offset + pose própria.
static func hold_transform(id: String) -> Transform3D:
	var pose: Dictionary = HOLD_POSES.get(id, {})
	var rot: Vector3 = pose.get("rot", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	return Transform3D(basis, hold_offset(id) + pose.get("at", Vector3.ZERO))


## Deslocamento do modelo: só para a frente, e só se passar de MAX_BACK.
static func hold_offset(id: String) -> Vector3:
	var back := mesh(id).get_aabb().end.z
	return Vector3(0.0, 0.0, minf(MAX_BACK - back, 0.0))


static func material(kind: Mat) -> StandardMaterial3D:
	if not _materials.has(kind):
		var spec: Array = MATERIAL_SPECS[kind]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[0]
		mat.metallic = spec[1]
		mat.roughness = spec[2]
		_materials[kind] = mat
	return _materials[kind]


static func _build(parts: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for part: Dictionary in parts:
		var kind: Mat = part["mat"]
		if not tools.has(kind):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[kind] = tool
		(tools[kind] as SurfaceTool).append_from(_primitive(part), 0, _transform(part))
	var result := ArrayMesh.new()
	# Ordem fixa dos materiais: a mesma arma sai sempre igual.
	for kind in MATERIAL_SPECS:
		if tools.has(kind):
			(tools[kind] as SurfaceTool).commit(result)
			result.surface_set_material(result.get_surface_count() - 1, material(kind))
	return result


static func _primitive(part: Dictionary) -> PrimitiveMesh:
	if part.has("box"):
		var box := BoxMesh.new()
		box.size = part["box"]
		return box
	var cylinder := CylinderMesh.new()
	var spec: Vector2 = part["cyl"]
	cylinder.top_radius = spec.x
	cylinder.bottom_radius = spec.x
	cylinder.height = spec.y
	cylinder.radial_segments = int(part.get("sides", 8))
	cylinder.rings = 0
	return cylinder


static func _transform(part: Dictionary) -> Transform3D:
	var rot: Vector3 = part.get("rot", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	if part.has("cyl"):
		# Cilindro nasce em pé (eixo Y); deita ao longo do cano (Z).
		basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(basis, part["at"])
