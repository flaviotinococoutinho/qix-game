class_name QixDepthStage
extends Node3D
## Palco 2.5D de apresentação. O campo e os sinais continuam no SubViewport 2D;
## os GLBs são proxies sem colisão, sincronizados no mesmo espaço de células.
## HUD/input ficam na janela raiz. F2 oferece vista plana, F4 reduz movimento.

const UNITS_PER_CELL := 1.0 / 80.0
const CAMERA_SIZE := 4.16
const MODEL_DIR := "res://assets/models/lumen/"

@export_range(1, 4) var render_scale: int = 3
@export var reduced_motion: bool = false

var surface_viewport: SubViewport
var surface_root: Node2D
var camera: Camera3D
var pivot: Node3D
var enabled: bool = true
var _canvas_nodes: Array[Node] = []
var _host: Node
var _actors: Dictionary = {}
var _packed_models: Dictionary = {}
var _rim_material: StandardMaterial3D
var _pulse_ticks := 0
var _hit_ticks := 0
var _last_tick := -1
var _sim_id := 0


func mount(host: Node, canvas_nodes: Array[Node]) -> void:
	_host = host
	_canvas_nodes = canvas_nodes
	_build_stage()
	for view in _canvas_nodes:
		view.reparent(surface_root, false)
	if host.board_view != null:
		host.board_view.draw_outer_background = false
		host.board_view.queue_redraw()
		host.board_view.call("_register_performance_monitors")


func _build_stage() -> void:
	surface_viewport = SubViewport.new()
	surface_viewport.name = "TerritorySurface"
	surface_viewport.size = CoordinateSpace.VIEWPORT * render_scale
	surface_viewport.size_2d_override = CoordinateSpace.VIEWPORT
	surface_viewport.size_2d_override_stretch = true
	surface_viewport.transparent_bg = true
	surface_viewport.disable_3d = true
	surface_viewport.gui_disable_input = true
	surface_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(surface_viewport)
	surface_root = Node2D.new()
	surface_root.name = "Canvas"
	surface_viewport.add_child(surface_root)
	pivot = Node3D.new()
	pivot.name = "CartographyTable"
	add_child(pivot)
	var surface := MeshInstance3D.new()
	surface.name = "TerritoryProjection"
	var quad := QuadMesh.new()
	quad.size = Vector2(CoordinateSpace.VIEWPORT) * UNITS_PER_CELL
	surface.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = surface_viewport.get_texture()
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(surface)
	var slab_material := _material(Color("111e29"), 0.55)
	var under_material := _material(Color("050b13"), 0.3)
	_rim_material = _material(Color("4aa8c2"), 0.3)
	_rim_material.emission_enabled = true
	_rim_material.emission = Color("4aa8c2")
	_rim_material.emission_energy_multiplier = 0.35
	var center := screen_to_stage(Vector2(CoordinateSpace.FIELD_ORIGIN) + Vector2(112.5, 141.5))
	_box("Foundation", center + Vector3(0, 0, -0.12), Vector3(2.88, 3.60, 0.20), under_material)
	_box("GraphiteDeck", center + Vector3(0, 0, -0.055), Vector3(2.85, 3.56, 0.10), slab_material)
	for side in [-1, 1]:
		_box("Rail%d" % side, center + Vector3(side*1.432, 0, -0.014), Vector3(0.015, 3.56, 0.025), _rim_material)
		_box("CrossRail%d" % side, center + Vector3(0, side*1.786, -0.014), Vector3(2.87, 0.015, 0.025), _rim_material)
		for i in 6:
			_box("Tick%d_%d" % [side, i], center + Vector3(side*1.445, -1.50 + i*0.60, -0.01), Vector3(0.04, 0.007, 0.025), _rim_material)
	camera = Camera3D.new()
	camera.name = "OrthographicCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.position = Vector3(0, 0, 8)
	camera.near = 0.1
	camera.far = 30.0
	add_child(camera)
	camera.make_current()
	var world := WorldEnvironment.new()
	world.name = "LumenEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("03080f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("93b4c7")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, -25, -20)
	key.light_color = Color("d8f4ff")
	key.light_energy = 1.8
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.8, -1.0, 2)
	rim.light_color = Color("ff8b63")
	rim.light_energy = 1.8
	rim.omni_range = 6
	add_child(rim)
	for model_name in ["surveyor", "core", "walker", "dart", "ember", "beacon"]:
		var path: String = MODEL_DIR + String(model_name) + ".glb"
		if ResourceLoader.exists(path):
			_packed_models[model_name] = load(path) as PackedScene


func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.4
	return material


func _box(label: String, pos: Vector3, dimensions: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	pivot.add_child(instance)


static func screen_to_stage(screen: Vector2, height: float = 0.0) -> Vector3:
	return Vector3((screen.x - 120.0)*UNITS_PER_CELL, (160.0 - screen.y)*UNITS_PER_CELL, height)


func set_enabled(value: bool) -> void:
	if enabled == value or surface_root == null:
		return
	enabled = value
	visible = enabled
	surface_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	for view in _canvas_nodes:
		view.reparent(surface_root if enabled else _host, false)
	_host.board_view.draw_outer_background = not enabled
	_host.board_view.queue_redraw()
	_host.board_view.call("_register_performance_monitors")
	_update_body_flags()


func _update_body_flags() -> void:
	_host.player_view.show_body = not enabled or not _packed_models.has("surveyor")
	_host.enemy_view.show_body = not enabled or not _packed_models.has("core")
	_host.minor_actor_view.show_body = not enabled or not (
		_packed_models.has("walker") and _packed_models.has("dart")
		and _packed_models.has("ember") and _packed_models.has("beacon"))


func sync(simulation: GameSimulation, visual: RoundVisualDefinition, events: Array[GameEvent], terminal_alpha: float = 1.0) -> void:
	if surface_root == null:
		return
	_update_body_flags()
	if _sim_id != simulation.get_instance_id():
		_sim_id = simulation.get_instance_id()
		_last_tick = -1
		_hit_ticks = 0
		_pulse_ticks = 0
	if simulation.tick != _last_tick:
		_hit_ticks = maxi(0, _hit_ticks-1)
		_pulse_ticks = maxi(0, _pulse_ticks-1)
		_last_tick = simulation.tick
	for event in events:
		if event.kind == GameEvent.Kind.CAPTURED:
			_pulse_ticks = 18
		elif event.kind == GameEvent.Kind.PLAYER_DIED:
			_hit_ticks = 16
	var clock := float(simulation.tick)
	var tilt := 0.0 if reduced_motion else sin(clock * 0.009) * 0.3
	pivot.rotation_degrees = Vector3(-6.0 + tilt, 3.5, 0)
	pivot.position = Vector3.ZERO
	if not reduced_motion:
		pivot.position.x = sin(clock*2.3) * float(_hit_ticks) * 0.0009
	camera.size = CAMERA_SIZE - (float(_pulse_ticks) * 0.0008 if not reduced_motion else 0.0)
	if visual != null:
		_rim_material.albedo_color = visual.accent_color
		_rim_material.emission = visual.accent_color
	for node in _actors.values():
		node.visible = false
	if not enabled:
		return
	var player_snapshot: Dictionary = _host.player_view.presentation_state()
	var player_pos: Vector2 = player_snapshot.position
	var player := _proxy("player", "surveyor", player_pos, float(visual.player_model_scale_milli)/1000.0 if visual != null else 0.043, simulation.player.lifecycle(), simulation.tick)
	if player != null:
		var facing: Vector2 = player_snapshot.facing
		player.rotation.z = -atan2(facing.x, -facing.y)
		if not reduced_motion:
			player.rotation.y = sin(clock*0.07)*0.10
		else:
			player.rotation.y = 0.0
	var boss_snapshot: Dictionary = _host.enemy_view.presentation_state()
	var boss_pos: Vector2 = boss_snapshot.position
	var core := _proxy("boss", "core", boss_pos, float(visual.boss_model_scale_milli)/1000.0 if visual != null else 0.082, simulation.boss.lifecycle(), simulation.tick)
	if core != null:
		core.rotation.z = 0.0 if reduced_motion else clock * (0.008 + float(simulation.boss.phase)*0.004)
	var minors: Dictionary = _host.minor_actor_view.presentation_state()
	for plural in ["walkers", "darts", "embers"]:
		var singular: String = String(plural).trim_suffix("s")
		var model_scale: float = float(visual.get(singular + "_model_scale_milli"))/1000.0 if visual != null else 0.035
		for state in minors.get(plural, []):
			var actor := _proxy("%s%d" % [plural, int(state.slot)], singular, state.position, model_scale, state.lifecycle, simulation.tick)
			if actor != null and state.has("direction"):
				var direction: Vector2 = state.direction
				actor.rotation.z = -atan2(direction.x, -direction.y)
	for beacon in minors.get("beacons", []):
		var model := _proxy("beacon%d" % int(beacon.slot), "beacon", beacon.position, float(visual.beacon_model_scale_milli)/1000.0 if visual != null else 0.047, ActorLifecycle.State.ACTIVE, simulation.tick)
		if model != null:
			model.scale *= 0.6 if beacon.captured else 1.0
			model.rotation.z = PI*0.25
	# A sessão congela o checksum ao arquivar a rodada. A dissipação depois da vitória é
	# exclusivamente apresentação, dirigida pelos ticks da transição e nunca pelo domínio.
	for key in _actors:
		if key != "player":
			var model: Node3D = _actors[key]
			model.scale *= terminal_alpha
			model.visible = model.visible and terminal_alpha > 0.0


func _proxy(key: String, model_name: String, screen: Vector2, model_scale: float, lifecycle: int, clock: int) -> Node3D:
	if not _packed_models.has(model_name):
		return null
	if not _actors.has(key):
		var instance := (_packed_models[model_name] as PackedScene).instantiate() as Node3D
		instance.name = "Actor_" + key
		pivot.add_child(instance)
		_actors[key] = instance
	var actor: Node3D = _actors[key]
	actor.visible = lifecycle != ActorLifecycle.State.DESPAWNED
	var warmup := lifecycle == ActorLifecycle.State.WARMUP
	var dying := lifecycle == ActorLifecycle.State.DYING
	var size_factor := 0.65 if warmup else (0.4 if dying else 1.0)
	actor.scale = Vector3.ONE * model_scale * size_factor
	actor.position = screen_to_stage(screen, 0.012)
	if warmup and not reduced_motion:
		actor.scale *= 0.85 + 0.15*sin(float(clock)*0.30)
	return actor


func presentation_state() -> Dictionary:
	return {"enabled": enabled, "reduced_motion": reduced_motion,
		"render_scale": render_scale, "loaded_models": _packed_models.size(),
		"actor_proxies": _actors.size(), "pulse_ticks": _pulse_ticks, "hit_ticks": _hit_ticks}
