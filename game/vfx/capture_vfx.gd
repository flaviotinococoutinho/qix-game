class_name QixCaptureVfx
extends Node2D
## Feedback visual efêmero. Consome eventos confirmados e não participa do estado/replay.

const CAPTURE_DURATION_TICKS := 28
const CLEAR_DURATION_TICKS := 90
const HIT_DURATION_TICKS := 20

## Menor lado, em px, do foco da captura. Uma trilha reta tem 1 px de espessura: sem um piso, a
## floritura nasceria dentro de uma fenda e ninguém a veria.
const MIN_FOCUS_SIDE := 24.0
## Meia-largura da cruz de cada marca. As marcas nascem afastadas desta distância da borda do
## foco, para que a cruz inteira caiba dentro do campo.
const MARKER_RADIUS := 2.0

var capture_ticks_left: int = 0
var clear_ticks_left: int = 0
var hit_ticks_left: int = 0
var last_filled_delta: int = 0
var last_permille: int = 0
## Recorte de tela onde a floritura da última captura acontece: a extensão da trilha que fechou a
## região, com piso e recortada ao campo. Vazio antes da primeira captura.
var focus_rect := Rect2()
var _accent := Color("50e3c2")
var _hot := Color("fff4b0")
var _threat := Color("ff4d6d")
var _field_size := Vector2(225.0, 283.0)
var _trail_min := Vector2i.ZERO
var _trail_max := Vector2i.ZERO
var _trail_seen: int = 0
var _has_trail_extent := false


func sync(source: Variant, events: Array[GameEvent]) -> void:
	_apply_visual(_visual_from(source))
	var simulation := _simulation_from(source)
	if simulation != null:
		_field_size = Vector2(simulation.board.width, simulation.board.height)
	var captured_now := false
	var cleared_now := false
	var hit_now := false
	for event in events:
		match event.kind:
			GameEvent.Kind.CAPTURED:
				last_filled_delta = event.data.get("filled_delta", 0)
				last_permille = event.data.get("permille", 0)
				capture_ticks_left = CAPTURE_DURATION_TICKS
				captured_now = true
				# Antes de `_track_trail`: no tick da captura o domínio já zerou `trail`, e a
				# extensão que interessa é a acumulada nos ticks anteriores.
				focus_rect = _focus_from_trail_extent()
			GameEvent.Kind.ROUND_CLEAR_STARTED, GameEvent.Kind.CAMPAIGN_COMPLETE:
				clear_ticks_left = CLEAR_DURATION_TICKS
				cleared_now = true
			GameEvent.Kind.PLAYER_DIED:
				hit_ticks_left = HIT_DURATION_TICKS
				hit_now = true
	if not captured_now:
		capture_ticks_left = maxi(0, capture_ticks_left - 1)
	if not cleared_now:
		clear_ticks_left = maxi(0, clear_ticks_left - 1)
	if not hit_now:
		hit_ticks_left = maxi(0, hit_ticks_left - 1)
	if simulation != null:
		_track_trail(simulation)
	visible = capture_ticks_left > 0 or clear_ticks_left > 0 or hit_ticks_left > 0
	if visible:
		queue_redraw()


func presentation_state() -> Dictionary:
	return {
		"capture_ticks_left": capture_ticks_left,
		"clear_ticks_left": clear_ticks_left,
		"hit_ticks_left": hit_ticks_left,
		"last_filled_delta": last_filled_delta,
		"last_permille": last_permille,
		"focus_rect": focus_rect,
	}


## Acompanha a extensão da trilha corrente lendo só os índices ainda não consumidos: O(células
## novas por tick), sem cópia do board. Leitura pura — a trilha é estado confirmado do domínio.
func _track_trail(simulation: GameSimulation) -> void:
	var trail := simulation.trail
	if trail.size() < _trail_seen:
		# Consolidada pela captura ou desfeita pela rejeição/morte: o próximo traço recomeça.
		_trail_seen = 0
		_has_trail_extent = false
	var width := simulation.board.width
	for i in range(_trail_seen, trail.size()):
		@warning_ignore("integer_division")
		var y := trail[i] / width
		var cell := Vector2i(trail[i] - y * width, y)
		if _has_trail_extent:
			_trail_min = _trail_min.min(cell)
			_trail_max = _trail_max.max(cell)
		else:
			_trail_min = cell
			_trail_max = cell
			_has_trail_extent = true
	_trail_seen = trail.size()


## Sem trilha observada (primeiro tick, sessão recém-criada), degrada para o campo inteiro — que
## é o comportamento antigo, não um recorte errado.
func _focus_from_trail_extent() -> Rect2:
	var field := field_rect()
	if not _has_trail_extent:
		return field
	var span := Vector2(_trail_max - _trail_min) + Vector2.ONE
	var rect := Rect2(Vector2(CoordinateSpace.field_to_screen(_trail_min)), span)
	var grow := (Vector2(MIN_FOCUS_SIDE, MIN_FOCUS_SIDE) - rect.size).maxf(0.0) * 0.5
	return rect.grow_individual(grow.x, grow.y, grow.x, grow.y).intersection(field)


## Centros das marcas discretas que dão peso à captura sem criar partículas/nós por célula.
## Público para que o teste headless possa afirmar onde elas caem: não há tela para olhar.
func marker_positions() -> PackedVector2Array:
	var focus := focus_rect if focus_rect.has_area() else field_rect()
	var area := focus.grow(-MARKER_RADIUS)
	if area.size.x < 1.0 or area.size.y < 1.0:
		area = focus
	var span_x := maxi(1, int(area.size.x))
	var span_y := maxi(1, int(area.size.y))
	@warning_ignore("integer_division")
	var marker_count := mini(12, maxi(4, last_filled_delta / 64))
	var centers := PackedVector2Array()
	for marker in marker_count:
		centers.append(Vector2(
			area.position.x + float((marker * 37 + last_filled_delta) % span_x),
			area.position.y + float((marker * 71 + last_permille) % span_y),
		))
	return centers


func _draw() -> void:
	var field := field_rect()
	if capture_ticks_left > 0:
		var capture_t := 1.0 - float(capture_ticks_left) / float(CAPTURE_DURATION_TICKS)
		var edge_color := _accent
		edge_color.a = (1.0 - capture_t) * 0.85
		draw_rect(field.grow(-1.0 - floorf(capture_t * 3.0)), edge_color, false, 1.0)
		# A moldura pisca no campo inteiro (o território mudou), mas a varredura e as marcas
		# acontecem sobre o traço que fechou a região: é ali que a mão do jogador acabou de estar.
		var focus := focus_rect if focus_rect.has_area() else field
		var sweep_color := _hot
		sweep_color.a = (1.0 - capture_t) * 0.72
		var sweep_y := focus.position.y + floorf(focus.size.y * capture_t)
		draw_line(
			Vector2(focus.position.x, sweep_y),
			Vector2(focus.end.x, sweep_y),
			sweep_color,
			1.0,
		)
		for center in marker_positions():
			draw_line(center - Vector2(MARKER_RADIUS, 0.0), center + Vector2(MARKER_RADIUS, 0.0), sweep_color)
			draw_line(center - Vector2(0.0, MARKER_RADIUS), center + Vector2(0.0, MARKER_RADIUS), sweep_color)
	if clear_ticks_left > 0:
		var clear_t := 1.0 - float(clear_ticks_left) / float(CLEAR_DURATION_TICKS)
		var clear_color := _hot
		clear_color.a = (1.0 - clear_t) * 0.6
		var inset := floorf(clear_t * 8.0)
		draw_rect(field.grow(-inset), clear_color, false, 2.0)
	if hit_ticks_left > 0:
		var hit_color := _threat
		hit_color.a = float(hit_ticks_left) / float(HIT_DURATION_TICKS) * 0.35
		draw_rect(field, hit_color, true)


func _visual_from(source: Variant) -> RoundVisualDefinition:
	if source is GameSession:
		return (source as GameSession).current_content().visual
	return null


func _simulation_from(source: Variant) -> GameSimulation:
	if source is GameSession:
		return (source as GameSession).simulation
	if source is GameSimulation:
		return source as GameSimulation
	return null


func field_rect() -> Rect2:
	return Rect2(Vector2(CoordinateSpace.FIELD_ORIGIN), _field_size)


func _apply_visual(visual: RoundVisualDefinition) -> void:
	if visual == null:
		return
	_accent = visual.accent_color
	_hot = visual.trail_hot_color
	_threat = visual.threat_color
