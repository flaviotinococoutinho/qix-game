class_name QixEnemyView
extends Node2D
## Chefe-anchor procedural. A cruz translúcida comunica o footprint letal de 1 célula.

const DEFAULT_BODY := Color("ff4d6d")
const DEFAULT_CORE := Color("ffd166")
const DEFAULT_ACCENT := Color("6ca8b5")
const BossBehaviorControllerScript = preload("res://game/enemies/boss_behavior_controller.gd")
const BossBehaviorProfileScript = preload("res://game/enemies/boss_behavior_profile.gd")

var _body := DEFAULT_BODY
var _core := DEFAULT_CORE
var _accent := DEFAULT_ACCENT
var _phase_step: int = 0
var _behavior_pattern: int = 0
var _surging: bool = false
var _facing := Vector2.RIGHT
var _diamond := PackedVector2Array([
	Vector2(0.0, -4.0),
	Vector2(4.0, 0.0),
	Vector2(0.0, 4.0),
	Vector2(-4.0, 0.0),
])


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	if visual != null:
		_body = visual.threat_color
		_core = visual.trail_hot_color
		_accent = visual.accent_color
	visible = simulation.boss_alive
	if not visible:
		return
	var screen := CoordinateSpace.field_to_screen(simulation.boss_cell())
	position = Vector2(screen.x, screen.y)
	_phase_step = simulation.tick % 16
	if simulation.rules.boss_behavior != null:
		_behavior_pattern = int(simulation.rules.boss_behavior.pattern)
	_surging = simulation.boss_effective_speed_fp > simulation.rules.boss_speed_fp
	_facing = Vector2(
		float(BossBehaviorControllerScript.DIRECTION_X[simulation.boss_dir_index]) / 256.0,
		float(BossBehaviorControllerScript.DIRECTION_Y[simulation.boss_dir_index]) / 256.0,
	).normalized()
	queue_redraw()


func presentation_colors() -> Dictionary:
	return {"body": _body, "core": _core, "accent": _accent}


func presentation_state() -> Dictionary:
	return {
		"pattern": _behavior_pattern,
		"surging": _surging,
		"facing": _facing,
	}


func _draw() -> void:
	# Footprint real usado por GameSimulation.boss_contact_cells().
	var footprint := _body
	footprint.a = 0.18 if _phase_step < 8 else 0.3
	draw_rect(Rect2(0.0, 0.0, 1.0, 1.0), footprint)
	draw_rect(Rect2(-1.0, 0.0, 1.0, 1.0), footprint)
	draw_rect(Rect2(1.0, 0.0, 1.0, 1.0), footprint)
	draw_rect(Rect2(0.0, -1.0, 1.0, 1.0), footprint)
	draw_rect(Rect2(0.0, 1.0, 1.0, 1.0), footprint)

	var aura := _accent
	aura.a = 0.42 if _surging else (0.2 if _phase_step < 8 else 0.35)
	var aura_reach := 8.0 if _surging else 6.0
	draw_polyline(PackedVector2Array([
		Vector2(0.0, -aura_reach), Vector2(aura_reach, 0.0), Vector2(0.0, aura_reach),
		Vector2(-aura_reach, 0.0), Vector2(0.0, -aura_reach),
	]), aura, 1.0)
	draw_colored_polygon(_diamond, _body)
	draw_polyline(PackedVector2Array([
		Vector2(0.0, -4.0), Vector2(4.0, 0.0), Vector2(0.0, 4.0),
		Vector2(-4.0, 0.0), Vector2(0.0, -4.0),
	]), _core, 1.0)
	draw_rect(Rect2(-1.0, -1.0, 3.0, 3.0), _core)
	draw_rect(Rect2(0.0, 0.0, 1.0, 1.0), Color.WHITE)

	# A silhueta comunica o contrato de movimento antes que ele ameace a trilha.
	match _behavior_pattern:
		BossBehaviorProfileScript.Pattern.PURSUIT:
			var nose := _facing * (11.0 if _surging else 9.0)
			draw_line(_facing * 4.0, nose, _core, 1.0)
			draw_circle(nose, 1.5, _core, false, 1.0)
		BossBehaviorProfileScript.Pattern.SWEEP:
			draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 16, aura, 1.0)
			draw_line(_facing * 4.0, _facing * 9.0, _core, 1.0)
		_:
			pass

	# Tendrils alternados mantêm energia sem Tween/relógio e seguem o tick observado.
	var reach := 10.0 if _surging else (8.0 if _phase_step < 8 else 7.0)
	draw_line(Vector2(-4.0, 0.0), Vector2(-reach, -2.0), _body)
	draw_line(Vector2(4.0, 0.0), Vector2(reach, 2.0), _body)
	draw_line(Vector2(0.0, -4.0), Vector2(2.0, -reach), _body)
	draw_line(Vector2(0.0, 4.0), Vector2(-2.0, reach), _body)
