class_name QixCaptureVfx
extends Node2D
## Feedback visual efêmero. Consome eventos confirmados e não participa do estado/replay.

const CAPTURE_DURATION_TICKS := 28
const CLEAR_DURATION_TICKS := 90
const HIT_DURATION_TICKS := 20

var capture_ticks_left: int = 0
var clear_ticks_left: int = 0
var hit_ticks_left: int = 0
var last_filled_delta: int = 0
var last_permille: int = 0
var _accent := Color("50e3c2")
var _hot := Color("fff4b0")
var _threat := Color("ff4d6d")
var _field_size := Vector2(225.0, 283.0)


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
	}


func _draw() -> void:
	var field := field_rect()
	if capture_ticks_left > 0:
		var capture_t := 1.0 - float(capture_ticks_left) / float(CAPTURE_DURATION_TICKS)
		var edge_color := _accent
		edge_color.a = (1.0 - capture_t) * 0.85
		draw_rect(field.grow(-1.0 - floorf(capture_t * 3.0)), edge_color, false, 1.0)
		var sweep_color := _hot
		sweep_color.a = (1.0 - capture_t) * 0.72
		var sweep_y := field.position.y + floorf(field.size.y * capture_t)
		draw_line(
			Vector2(field.position.x + 1.0, sweep_y),
			Vector2(field.end.x - 1.0, sweep_y),
			sweep_color,
			1.0,
		)
		# Marcas discretas dão peso à captura sem criar partículas/nós por célula.
		@warning_ignore("integer_division")
		var marker_count := mini(12, maxi(4, last_filled_delta / 64))
		for marker in marker_count:
			var marker_x := field.position.x + 5.0 + float((marker * 37 + last_filled_delta) % 214)
			var marker_y := field.position.y + 5.0 + float((marker * 71 + last_permille) % 272)
			draw_line(Vector2(marker_x - 2.0, marker_y), Vector2(marker_x + 2.0, marker_y), sweep_color)
			draw_line(Vector2(marker_x, marker_y - 2.0), Vector2(marker_x, marker_y + 2.0), sweep_color)
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
