class_name QixPlayerView
extends Node2D
## Cartógrafo facetado. O pivô continua na célula letal; volume, sombra e halo são só desenho.

@export var show_body: bool = true

const DEFAULT_OUTER := Color("f5f7ff")
const DEFAULT_CORE := Color("fff4b0")
const DEFAULT_ACCENT := Color("50e3c2")
const INK := Color("020a16")

var _outer := DEFAULT_OUTER
var _core := DEFAULT_CORE
var _accent := DEFAULT_ACCENT
var _trail_active: bool = false
var _shield_critical: bool = false
var _pulse_step: int = 0
var _lifecycle: int = ActorLifecycle.State.ACTIVE
var _lifecycle_ticks: int = 0
var _facing := Vector2.UP
var _shield_ratio: float = 1.0


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	_outer = visual.boundary_color if visual != null else DEFAULT_OUTER
	_core = visual.trail_hot_color if visual != null else DEFAULT_CORE
	_accent = visual.accent_color if visual != null else DEFAULT_ACCENT
	position = Vector2(CoordinateSpace.field_to_screen(simulation.player.cell()))
	_trail_active = simulation.trail_active
	_shield_critical = simulation.shield_ticks <= simulation.rules.shield_critical_ticks
	_shield_ratio = clampf(float(simulation.shield_ticks) / float(maxi(1, simulation.rules.shield_ticks)), 0.0, 1.0)
	_pulse_step = simulation.tick % 24
	_lifecycle = simulation.player.lifecycle()
	_lifecycle_ticks = simulation.player.lifecycle_ticks
	match simulation.pdir:
		MoveIntent.Dir.UP: _facing = Vector2.UP
		MoveIntent.Dir.RIGHT: _facing = Vector2.RIGHT
		MoveIntent.Dir.DOWN: _facing = Vector2.DOWN
		MoveIntent.Dir.LEFT: _facing = Vector2.LEFT
		_: _facing = Vector2.UP
	visible = _lifecycle != ActorLifecycle.State.DESPAWNED
	queue_redraw()


func presentation_colors() -> Dictionary:
	return {"outer": _outer, "core": _core, "accent": _accent}


func presentation_state() -> Dictionary:
	return {
		"lifecycle": _lifecycle, "lifecycle_ticks": _lifecycle_ticks,
		"facing": _facing, "drawing": _trail_active, "shield_ratio": _shield_ratio,
		"position": position, "id": ActorLifecycle.PLAYER_ID,
	}


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(float(_pulse_step) * TAU / 24.0)
	if _lifecycle == ActorLifecycle.State.DYING:
		_draw_dissolving(pulse)
		return
	if not show_body:
		draw_circle(Vector2.ZERO, 0.6, _core, true, -1.0, true)
		if _trail_active:
			draw_line(-_facing * 3.0, -_facing * 5.0, _core, 0.8, true)
		if _shield_critical or _lifecycle == ActorLifecycle.State.WARMUP:
			var warning := Color("ff657b") if _shield_critical else _outer
			draw_arc(Vector2.ZERO, 6.7, -PI * 0.7, PI * 0.7, 20, warning, 0.7, true)
			draw_arc(Vector2.ZERO, 6.7, PI * 0.3, PI * 1.7, 20, warning, 0.7, true)
		return
	# A sombra e a saia ficam abaixo do núcleo, preservando o ponto exato da colisão.
	draw_set_transform(Vector2(0.8, 2.6), 0.0, Vector2(1.0, 0.48))
	draw_circle(Vector2.ZERO, 4.3, Color(0.0, 0.015, 0.03, 0.7), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	var halo := _accent
	halo.a = 0.14 + pulse * 0.08 if _trail_active else 0.09
	draw_circle(Vector2.ZERO, 5.2 + pulse * 0.4, halo, true, -1.0, true)
	var hull := PackedVector2Array([
		Vector2(0.0, -3.8), Vector2(3.0, -0.8), Vector2(2.1, 2.4),
		Vector2(0.0, 3.3), Vector2(-2.1, 2.4), Vector2(-3.0, -0.8),
	])
	draw_colored_polygon(hull, INK)
	draw_polyline(_closed(hull), Color("09121f"), 1.9, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -3.2), Vector2(2.5, -0.6), Vector2(0.0, 1.3), Vector2(-2.5, -0.6),
	]), _outer)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2.5, -0.6), Vector2(0.0, 1.3), Vector2(0.0, 2.8), Vector2(-1.8, 2.0),
	]), _accent.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 1.3), Vector2(2.5, -0.6), Vector2(1.8, 2.0), Vector2(0.0, 2.8),
	]), _accent.darkened(0.62))
	draw_circle(Vector2.ZERO, 1.35, INK, true, -1.0, true)
	draw_circle(Vector2.ZERO, 0.8, _core, true, -1.0, true)
	draw_line(Vector2(-1.8, -1.0), Vector2(0.0, -2.8), Color.WHITE, 0.55, true)
	# A seta é orientação corrente, sem prever uma curva que ainda não foi aceita.
	var nose := _facing * 5.6
	var tangent := _facing.orthogonal()
	draw_polyline(PackedVector2Array([
		nose - _facing * 1.4 - tangent * 1.2, nose,
		nose - _facing * 1.4 + tangent * 1.2,
	]), _core if _trail_active else _outer, 0.8, true)
	if _trail_active:
		draw_line(-_facing * 3.2, -_facing * (5.0 + pulse), _core, 1.1, true)
	if _lifecycle == ActorLifecycle.State.WARMUP:
		draw_arc(Vector2.ZERO, 6.7, -PI * 0.7, PI * 0.7, 20, _outer, 0.7, true)
		draw_arc(Vector2.ZERO, 6.7, PI * 0.3, PI * 1.7, 20, _accent, 0.7, true)
	if _shield_critical:
		var alert := Color("ff657b")
		alert.a = 0.55 + pulse * 0.45
		for side: float in [-1.0, 1.0]:
			draw_polyline(PackedVector2Array([
				Vector2(side * 4.0, -5.0), Vector2(side * 6.0, -5.0), Vector2(side * 6.0, -2.0),
			]), alert, 0.8, true)


func _draw_dissolving(pulse: float) -> void:
	var color := _core
	color.a = 0.35 + pulse * 0.4
	var radius := 4.0 + float(_lifecycle_ticks % 12) * 0.3
	for index in 6:
		var direction := Vector2.from_angle(float(index) * TAU / 6.0)
		draw_line(direction * radius, direction * (radius + 1.8), color, 0.9, true)
	draw_circle(Vector2.ZERO, 0.7, _core, true, -1.0, true)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
