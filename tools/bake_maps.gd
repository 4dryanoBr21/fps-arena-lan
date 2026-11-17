extends SceneTree
## Converte os mapas de rascunho (CSG, em scenes/maps_src/) nos mapas do jogo:
## um MeshInstance3D por material com toda a geometria mesclada e um único
## StaticBody3D com caixas de colisão. Edite os mapas em maps_src e rode:
##   godot --headless --path . --script res://tools/bake_maps.gd

const MAPS := {
	"res://scenes/maps_src/arena_csg.tscn": "res://scenes/arena.tscn",
	"res://scenes/maps_src/deathmatch_csg.tscn": "res://scenes/deathmatch.tscn",
}

var _pending: Array = []
var _frames: int = 0


func _initialize() -> void:
	# O CSG só calcula a malha dentro da árvore; espera alguns quadros.
	for source: String in MAPS:
		var root := (load(source) as PackedScene).instantiate() as Node3D
		# Parado: alvos móveis não podem sair do lugar antes de salvar.
		root.process_mode = Node.PROCESS_MODE_DISABLED
		get_root().add_child(root)
		_pending.append([root, MAPS[source]])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	for entry: Array in _pending:
		_bake(entry[0], entry[1])
	return true


func _bake(root: Node3D, target_path: String) -> void:
	var shapes: Array[CSGShape3D] = []
	for node in root.find_children("*", "CSGShape3D", true, false):
		# Só as raízes: filhos de CSG já entram na malha do pai.
		if not (node.get_parent() is CSGShape3D):
			shapes.append(node)

	var tools: Dictionary = {}
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	root.add_child(body)
	body.owner = root
	var geometry := Node3D.new()
	geometry.name = "WorldGeometry"
	root.add_child(geometry)
	geometry.owner = root

	var collision_count := 0
	for csg in shapes:
		var xform := root.global_transform.affine_inverse() * csg.global_transform
		var mesh := csg.bake_static_mesh()
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if not tools.has(material):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[material] = st
				(tools[material] as SurfaceTool).append_from(mesh, surface, xform)
		if csg.use_collision:
			var shape_node := CollisionShape3D.new()
			shape_node.name = "%s_Collision" % csg.name
			if csg is CSGBox3D:
				var box := BoxShape3D.new()
				box.size = (csg as CSGBox3D).size
				shape_node.shape = box
			else:
				shape_node.shape = csg.bake_collision_shape()
			shape_node.transform = xform
			body.add_child(shape_node)
			shape_node.owner = root
			collision_count += 1

	var index := 0
	for material: Material in tools:
		var instance := MeshInstance3D.new()
		instance.name = "Geometry%d" % index
		var st := tools[material] as SurfaceTool
		var merged := st.commit()
		merged.surface_set_material(0, material)
		instance.mesh = merged
		geometry.add_child(instance)
		instance.owner = root
		index += 1

	for csg in shapes:
		csg.get_parent().remove_child(csg)
		csg.free()
	# Grupos vazios (Walls, Cover...) que só tinham CSG.
	for child in root.get_children():
		if child is Node3D and child.get_child_count() == 0 and child.get_class() == "Node3D":
			root.remove_child(child)
			child.free()

	root.process_mode = Node.PROCESS_MODE_INHERIT
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, target_path)
	print("%s: %d blocos CSG -> %d malhas, %d colisões (%s)" % [
		target_path, shapes.size(), index, collision_count, "ok" if err == OK else "erro %d" % err])
