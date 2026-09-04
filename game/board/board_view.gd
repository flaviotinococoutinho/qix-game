class_name QixBoardView
extends Node2D
## Projeção visual read-only do BoardState.
##
## A grade autoritativa já é um PackedByteArray com um byte por célula. A view usa esses
## bytes diretamente como uma Image R8 e mantém a mesma ImageTexture entre versões do board.
## Assim, o caminho quente não percorre 63.675 pixels em GDScript nem aloca uma textura por tick.

const BOARD_SHADER := preload("res://game/board/board_reveal.gdshader")

const BACKGROUND_COLOR := Color("050b13")
const DEFAULT_FREE_COLOR := Color("071923")
const DEFAULT_BOUNDARY_COLOR := Color("46f5c5")
const DEFAULT_TRAIL_COLOR := Color("ffd166")
const DEFAULT_TRAIL_HOT_COLOR := Color("fff4b0")
const PROFILE_SAMPLE_CAPACITY := 240

const MONITOR_LAST := &"Qix Board/refresh_usec"
const MONITOR_P95 := &"Qix Board/refresh_p95_usec"
const MONITOR_UPLOADS := &"Qix Board/refresh_count"

var _mask_image: Image
var _mask_texture: ImageTexture
var _reveal_sprite: Sprite2D
var _reveal_material: ShaderMaterial
var _fallback_background: ImageTexture
var _fallback_size := Vector2i.ZERO
var _board_instance_id: int = 0
var _board_version: int = -1
var _last_trail_exposure: float = 0.0

var _refresh_count: int = 0
var _skipped_count: int = 0
var _texture_create_count: int = 0
var _bytes_uploaded: int = 0
var _last_pixels: int = 0
var _last_usec: int = 0
var _max_usec: int = 0
var _total_usec: int = 0
var _profile_samples := PackedInt64Array()
var _profile_write_index: int = 0
var _profile_sample_count: int = 0
var _registered_monitors := PackedStringArray()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_presentation()
	_register_performance_monitors()
	queue_redraw()


func _exit_tree() -> void:
	for monitor_name in _registered_monitors:
		Performance.remove_custom_monitor(StringName(monitor_name))
	_registered_monitors.clear()


## Atualiza somente quando a identidade ou versão do board muda. `visual` é opcional para manter
## compatibilidade com hosts antigos; quando fornecido, troca apenas material/background, nunca a
## simulação nem a máscara autoritativa.
func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	_ensure_presentation()
	_apply_visual(visual, simulation.board.width, simulation.board.height)
	_reveal_material.set_shader_parameter("presentation_tick", float(simulation.tick))
	# Leitura de risco: a trilha confirmada esquenta e acelera conforme se afasta da moldura.
	_last_trail_exposure = TrailExposure.of_simulation(simulation)
	_reveal_material.set_shader_parameter("trail_exposure", _last_trail_exposure)

	var board_id := simulation.board.get_instance_id()
	if board_id == _board_instance_id and simulation.board.version == _board_version:
		_skipped_count += 1
		return
	_board_instance_id = board_id
	_board_version = simulation.board.version
	_refresh_mask(simulation.board)


func _ensure_presentation() -> void:
	if is_instance_valid(_reveal_sprite):
		return
	# O filho é criado em runtime; `find_child` evita declarar um NodePath autorado inexistente.
	_reveal_sprite = find_child("BoardReveal", false, false) as Sprite2D
	if _reveal_sprite == null:
		_reveal_sprite = Sprite2D.new()
		_reveal_sprite.name = "BoardReveal"
		add_child(_reveal_sprite)
	_reveal_sprite.centered = false
	_reveal_sprite.position = Vector2(CoordinateSpace.FIELD_ORIGIN)
	_reveal_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_reveal_material = ShaderMaterial.new()
	_reveal_material.shader = BOARD_SHADER
	_reveal_sprite.material = _reveal_material
	_set_visual_colors(null)


func _apply_visual(visual: RoundVisualDefinition, width: int, height: int) -> void:
	if visual != null:
		_set_visual_colors(visual)
		if visual.background != null \
			and visual.background.get_width() == width \
			and visual.background.get_height() == height:
			_reveal_sprite.texture = visual.background
			return
		# Uma rodada mal autorada nunca deve herdar silenciosamente a arte da rodada anterior.
		_reveal_sprite.texture = _fallback_texture(width, height)
		return
	if _reveal_sprite.texture == null \
		or _reveal_sprite.texture.get_width() != width \
		or _reveal_sprite.texture.get_height() != height:
		_reveal_sprite.texture = _fallback_texture(width, height)


func _set_visual_colors(visual: RoundVisualDefinition) -> void:
	var free_color := DEFAULT_FREE_COLOR if visual == null else visual.free_color
	var boundary_color := DEFAULT_BOUNDARY_COLOR if visual == null else visual.boundary_color
	var trail_color := DEFAULT_TRAIL_COLOR if visual == null else visual.trail_color
	var trail_hot_color := DEFAULT_TRAIL_HOT_COLOR if visual == null else visual.trail_hot_color
	_reveal_material.set_shader_parameter("free_color", free_color)
	_reveal_material.set_shader_parameter("boundary_color", boundary_color)
	_reveal_material.set_shader_parameter("trail_color", trail_color)
	_reveal_material.set_shader_parameter("trail_hot_color", trail_hot_color)


func _fallback_texture(width: int, height: int) -> ImageTexture:
	var requested := Vector2i(width, height)
	if _fallback_background != null and _fallback_size == requested:
		return _fallback_background
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color("17324a"))
	_fallback_background = ImageTexture.create_from_image(image)
	_fallback_size = requested
	return _fallback_background


func _refresh_mask(board: BoardState) -> void:
	var started_usec := Time.get_ticks_usec()
	var geometry_changed := (
		_mask_image == null
		or _mask_image.get_width() != board.width
		or _mask_image.get_height() != board.height
	)
	if geometry_changed:
		_mask_image = Image.create_from_data(
			board.width,
			board.height,
			false,
			Image.FORMAT_R8,
			board.cells,
		)
		_mask_texture = ImageTexture.create_from_image(_mask_image)
		_texture_create_count += 1
		_reveal_material.set_shader_parameter("state_mask", _mask_texture)
	else:
		# BoardState.cells já é exatamente o layout R8 esperado; set_data faz a única cópia CPU.
		_mask_image.set_data(
			board.width,
			board.height,
			false,
			Image.FORMAT_R8,
			board.cells,
		)
		_mask_texture.update(_mask_image)

	_refresh_count += 1
	_bytes_uploaded += board.cells.size()
	_last_pixels = board.cells.size()
	_record_profile_sample(Time.get_ticks_usec() - started_usec)


func _record_profile_sample(elapsed_usec: int) -> void:
	if _profile_samples.is_empty():
		_profile_samples.resize(PROFILE_SAMPLE_CAPACITY)
	_profile_samples[_profile_write_index] = elapsed_usec
	_profile_write_index = (_profile_write_index + 1) % PROFILE_SAMPLE_CAPACITY
	_profile_sample_count = mini(_profile_sample_count + 1, PROFILE_SAMPLE_CAPACITY)
	_last_usec = elapsed_usec
	_max_usec = maxi(_max_usec, elapsed_usec)
	_total_usec += elapsed_usec


## Estatísticas são calculadas sob demanda; a coleta no caminho quente é O(1), sem alocação após
## o primeiro sample. Tempos são telemetria de apresentação e nunca retroalimentam gameplay.
func metrics_snapshot() -> Dictionary:
	var values: Array[int] = []
	values.resize(_profile_sample_count)
	for i in _profile_sample_count:
		values[i] = _profile_samples[i]
	values.sort()
	return {
		"refresh_count": _refresh_count,
		"skipped_count": _skipped_count,
		"texture_create_count": _texture_create_count,
		"sample_count": _profile_sample_count,
		"sample_capacity": PROFILE_SAMPLE_CAPACITY,
		"pixels_per_refresh": _last_pixels,
		"bytes_uploaded": _bytes_uploaded,
		"last_usec": _last_usec,
		"mean_usec": _total_usec / float(_refresh_count) if _refresh_count > 0 else 0.0,
		"p50_usec": _percentile(values, 50),
		"p95_usec": _percentile(values, 95),
		"max_usec": _max_usec,
	}


func reset_metrics() -> void:
	_refresh_count = 0
	_skipped_count = 0
	_texture_create_count = 0
	_bytes_uploaded = 0
	_last_pixels = 0
	_last_usec = 0
	_max_usec = 0
	_total_usec = 0
	_profile_write_index = 0
	_profile_sample_count = 0
	_profile_samples = PackedInt64Array()


func mask_format() -> int:
	return -1 if _mask_image == null else _mask_image.get_format()


func mask_size() -> Vector2i:
	if _mask_image == null:
		return Vector2i.ZERO
	return Vector2i(_mask_image.get_width(), _mask_image.get_height())


func mask_bytes() -> PackedByteArray:
	return PackedByteArray() if _mask_image == null else _mask_image.get_data()


func mask_texture_instance_id() -> int:
	return 0 if _mask_texture == null else _mask_texture.get_instance_id()


func reveal_sprite() -> Sprite2D:
	return _reveal_sprite


## Última exposição de trilha projetada no shader. Telemetria de apresentação, nunca gameplay.
func last_trail_exposure() -> float:
	return _last_trail_exposure


static func cell_reveals_background(cell: int) -> bool:
	return cell == BoardState.Cell.CLAIMED


static func _percentile(sorted_values: Array[int], percentile: int) -> int:
	if sorted_values.is_empty():
		return 0
	@warning_ignore("integer_division")
	var index := mini((percentile * sorted_values.size() + 99) / 100 - 1, sorted_values.size() - 1)
	return sorted_values[maxi(index, 0)]


func _register_performance_monitors() -> void:
	if not is_inside_tree():
		return
	_add_monitor_if_available(MONITOR_LAST, func() -> int: return _last_usec)
	_add_monitor_if_available(MONITOR_P95, func() -> int: return metrics_snapshot().p95_usec)
	_add_monitor_if_available(MONITOR_UPLOADS, func() -> int: return _refresh_count)


func _add_monitor_if_available(monitor_name: StringName, callable: Callable) -> void:
	if monitor_name in Performance.get_custom_monitor_names():
		return
	Performance.add_custom_monitor(monitor_name, callable)
	_registered_monitors.append(String(monitor_name))


func _draw() -> void:
	# O fundo externo fica neste CanvasItem; o shader afeta somente o Sprite2D filho.
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(CoordinateSpace.VIEWPORT)),
		BACKGROUND_COLOR,
	)
