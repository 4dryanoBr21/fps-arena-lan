extends SceneTree
## Occlusion culling dos mapas: cria um OccluderInstance3D com a geometria
## mesclada do mapa (WorldGeometry). Com ele a engine deixa de desenhar o que
## está atrás das paredes (jogadores, armas, alvos, efeitos, números de dano).
## A própria geometria do mapa é uma malha grande por material e sempre passa
## no teste; o ganho é em tudo que se mexe por trás dela.
## O bake_maps.gd chama build() ao gerar os mapas; para refazer só os oclusores
## dos mapas já gerados:
##   godot --headless --path . --script res://tools/bake_occluders.gd

const MAPS: Array[String] = ["res://scenes/arena.tscn", "res://scenes/deathmatch.tscn"]
const NODE_NAME := "Occluders"


func _initialize() -> void:
	for path in MAPS:
		var root := (load(path) as PackedScene).instantiate() as Node3D
		var triangles := build(root)
		var packed := PackedScene.new()
		packed.pack(root)
		var err := ResourceSaver.save(packed, path)
		print("%s: oclusor com %d triângulos (%s)" % [path, triangles, "ok" if err == OK else "erro %d" % err])
		root.free()
	quit()


## Troca (ou cria) o nó Occluders do mapa. Devolve quantos triângulos ele tem.
static func build(root: Node3D) -> int:
	var old := root.get_node_or_null(NODE_NAME)
	if old != null:
		root.remove_child(old)
		old.free()
	var geometry := root.get_node_or_null("WorldGeometry")
	if geometry == null:
		return 0
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node in geometry.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var xform := _transform_to(root, instance)
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# Malha sem índice (o SurfaceTool do bake não indexa): um triângulo a cada 3 vértices.
			var surface_indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				surface_indices = arrays[Mesh.ARRAY_INDEX]
			var base := vertices.size()
			for v in surface_vertices:
				vertices.append(xform * v)
			if surface_indices.is_empty():
				for i in surface_vertices.size():
					indices.append(base + i)
			else:
				for i in surface_indices:
					indices.append(base + i)
	if indices.is_empty():
		return 0
	var occluder := ArrayOccluder3D.new()
	occluder.set_arrays(vertices, indices)
	var instance := OccluderInstance3D.new()
	instance.name = NODE_NAME
	instance.occluder = occluder
	root.add_child(instance)
	instance.owner = root
	return indices.size() / 3


## Transformação de `node` relativa a `root` sem precisar estar na árvore.
static func _transform_to(root: Node, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
