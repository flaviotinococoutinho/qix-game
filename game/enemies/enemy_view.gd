class_name QixEnemyView
extends Node2D
## Núcleo prismático com fases legíveis por silhueta. Nenhum desenho participa da colisão.

@export var show_body: bool = true

const DEFAULT_BODY := Color("ff4d6d")
const DEFAULT_CORE := Color("ffd166")
const DEFAULT_ACCENT := Color("6ca8b5")
const BossBehaviorControllerScript = preload("res://game/simulation/enemies/boss_behavior_controller.gd")
const BossBehaviorProfileScript = preload("res://game/rules/boss_behavior_profile.gd")

var _body := DEFAULT_BODY
var _core := DEFAULT_CORE
var _accent := DEFAULT_ACCENT
var _phase_step: int = 0
var _behavior_pattern: int = 0
var _surging: bool = false
var _cornered: bool = false
var _facing := Vector2.RIGHT
var _boss_phase: int = 0
var _lifecycle: int = ActorLifecycle.State.ACTIVE
var _stasis: bool = false
var _lifecycle_ticks: int = 0


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	_body = visual.threat_color if visual != null else DEFAULT_BODY
	_core = visual.trail_hot_color if visual != null else DEFAULT_CORE
	_accent = visual.accent_color if visual != null else DEFAULT_ACCENT
	_lifecycle = simulation.boss.lifecycle()
	_lifecycle_ticks = simulation.boss.despawn_ticks_left
	visible = _lifecycle != ActorLifecycle.State.DESPAWNED
	position = Vector2(CoordinateSpace.field_to_screen(simulation.boss_cell()))
	_phase_step = simulation.tick % 60
	_boss_phase = simulation.boss.phase
	_behavior_pattern = simulation.rules.boss_behavior.pattern_for_phase(_boss_phase) if simulation.rules.boss_behavior != null else 0
	_surging = simulation.boss_effective_speed_fp > simulation.rules.boss_speed_fp
	_cornered = simulation.boss.burst_left > 0
	_stasis = simulation.boss.stasis_ticks > 0
	_facing = Vector2(
		float(BossBehaviorControllerScript.DIRECTION_X[simulation.boss_dir_index]),
		float(BossBehaviorControllerScript.DIRECTION_Y[simulation.boss_dir_index]),
	).normalized()
	queue_redraw()


func presentation_colors() -> Dictionary:
	return {"body": _body, "core": _core, "accent": _accent}


func presentation_state() -> Dictionary:
	return {
		"pattern": _behavior_pattern, "surging": _surging, "facing": _facing,
		"phase": _boss_phase, "lifecycle": _lifecycle, "cornered": _cornered, "stasis": _stasis,
		"lifecycle_ticks": _lifecycle_ticks, "position": position, "id": ActorLifecycle.BOSS_ID,
	}


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(float(_phase_step) * TAU / 30.0)
	var reach := 7.0 + float(_boss_phase)
	var body := _body if not _stasis else _accent
	if _lifecycle == ActorLifecycle.State.DYING:
		for index in 8:
			var direction := Vector2.from_angle(float(index) * TAU / 8.0)
			draw_line(direction * 4.0, direction * (8.0 + pulse * 2.0), _core, 0.8, true)
		return
	if not show_body:
		_draw_tactical_only(reach)
		return
	draw_set_transform(Vector2(1.8, 4.2), 0.0, Vector2(1.0, 0.46))
	draw_circle(Vector2.ZERO, reach + 1.0, Color(0.0, 0.005, 0.02, 0.7), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	var aura := body
	aura.a = 0.08 + pulse * 0.04
	draw_circle(Vector2.ZERO, reach + 3.0, aura, true, -1.0, true)
	# Desenho orbital aberto comunica volume sem fingir uma área letal circular.
	var orbit_color := _accent
	orbit_color.a = 0.45
	draw_set_transform(Vector2(0.0, 1.0), -0.3, Vector2(1.0, 0.48))
	draw_arc(Vector2.ZERO, reach + 2.0, 0.15, PI - 0.2, 20, orbit_color, 0.65, true)
	draw_arc(Vector2.ZERO, reach + 2.0, PI + 0.15, TAU - 0.2, 20, orbit_color, 0.65, true)
	draw_set_transform(Vector2.ZERO)
	# Cada fase adiciona um par de lâminas, além de mudar o padrão autorado.
	var blade_count := 4 + _boss_phase * 2
	for index in blade_count:
		var angle := float(index) * TAU / float(blade_count) - PI * 0.25
		var direction := Vector2.from_angle(angle)
		var tangent := direction.orthogonal()
		var tip := direction * (reach + (1.0 if _surging else 0.0))
		var blade := PackedVector2Array([
			direction * 3.0 - tangent, tip - tangent * 0.5,
			tip + direction * 1.0, direction * 3.8 + tangent * 1.5,
		])
		draw_colored_polygon(blade, body.darkened(0.3))
		draw_polyline(_closed(blade), Color("020913"), 1.0, true)
		draw_line(direction * 3.7, tip, body.lightened(0.15), 0.6, true)
	var hull := PackedVector2Array([
		Vector2(0.0, -5.0), Vector2(4.5, -1.0), Vector2(3.1, 3.0),
		Vector2(0.0, 5.0), Vector2(-3.1, 3.0), Vector2(-4.5, -1.0),
	])
	draw_colored_polygon(hull, body.darkened(0.55))
	draw_polyline(_closed(hull), Color("020913"), 1.5, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -5.0), Vector2(4.5, -1.0), Vector2(0.0, 1.8), Vector2(-4.5, -1.0),
	]), body)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.5, -1.0), Vector2(0.0, 1.8), Vector2(0.0, 5.0), Vector2(-3.1, 3.0),
	]), body.darkened(0.25))
	draw_line(Vector2(-3.6, -1.3), Vector2(0.0, -4.4), body.lightened(0.7), 0.7, true)
	draw_circle(Vector2.ZERO, 2.4, Color("030913"), true, -1.0, true)
	draw_circle(Vector2.ZERO, 1.6, _core, true, -1.0, true)
	# A cruz de cinco células é o footprint real do Núcleo, iluminada no centro.
	for offset: Vector2 in [Vector2.ZERO, Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_rect(Rect2(offset - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), Color.WHITE)
	match _behavior_pattern:
		BossBehaviorProfileScript.Pattern.PURSUIT:
			var tangent := _facing.orthogonal()
			var nose := _facing * (reach + 4.0)
			draw_polyline(PackedVector2Array([
				nose - _facing * 2.0 - tangent * 1.3, nose,
				nose - _facing * 2.0 + tangent * 1.3,
			]), _core, 0.85, true)
		BossBehaviorProfileScript.Pattern.SWEEP:
			draw_arc(Vector2.ZERO, reach + 3.0, _facing.angle() - 0.75, _facing.angle() + 0.75, 12, _core, 0.75, true)
	if _cornered:
		# Fúria só aparece enquanto o contador autoritativo está ativo.
		var warning := _core
		warning.a = 0.5 + pulse * 0.5
		draw_arc(Vector2.ZERO, reach + 4.5, 0.0, TAU, 40, warning, 0.8, true)
	if _stasis:
		draw_arc(Vector2.ZERO, reach + 2.0, 0.0, TAU, 32, _accent, 1.0, true)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result


func _draw_tactical_only(reach: float) -> void:
	for offset: Vector2 in [Vector2.ZERO, Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_rect(Rect2(offset - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), _core)
	if _behavior_pattern == BossBehaviorProfileScript.Pattern.PURSUIT:
		var tangent := _facing.orthogonal()
		var nose := _facing * (reach + 4.0)
		draw_polyline(PackedVector2Array([
			nose - _facing * 2.0 - tangent * 1.3, nose,
			nose - _facing * 2.0 + tangent * 1.3,
		]), _core, 0.85, true)
	elif _behavior_pattern == BossBehaviorProfileScript.Pattern.SWEEP:
		draw_arc(Vector2.ZERO, reach + 3.0, _facing.angle() - 0.75, _facing.angle() + 0.75, 12, _core, 0.75, true)
	if _cornered:
		draw_arc(Vector2.ZERO, reach + 4.5, 0.0, TAU, 40, _core, 0.8, true)
	if _stasis:
		draw_arc(Vector2.ZERO, reach + 2.0, 0.0, TAU, 32, _accent, 1.0, true)
