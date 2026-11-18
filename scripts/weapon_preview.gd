class_name WeaponPreview
extends RefCounted
## Miniatura 3D de uma arma: de lado, cano para a direita, num mundo 3D só
## dela. Renderiza uma única vez (UPDATE_ONCE) e depois é imagem parada.
## Usada no Arsenal e na hotbar.


## `min_width` (m): largura mínima enquadrada; com ela as armas curtas
## aparecem menores, dando noção de tamanho.
static func create(weapon_id: String, size: Vector2i, min_width: float = 0.0) -> Control:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = size
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(viewport)

	var mesh := WeaponModels.mesh(weapon_id)
	var model := MeshInstance3D.new()
	model.mesh = mesh
	# -90° em Y: o cano (-Z) vai para a direita e o lado direito fica para a câmera.
	model.rotation_degrees.y = -90.0
	viewport.add_child(model)
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	viewport.add_child(light)

	var box := mesh.get_aabb()
	var center := box.get_center()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(box.size.z * 1.12, min_width)
	camera.position = Vector3(-center.z, center.y, center.x + 1.0)
	viewport.add_child(camera)
	return container
