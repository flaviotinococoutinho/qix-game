class_name QixPlayerView
extends Node2D
## Cursor procedural de alta legibilidade; observa somente GameSimulation.

const DEFAULT_OUTER := Color("f5f7ff")
const DEFAULT_CORE := Color("fff4b0")
const DEFAULT_ACCENT := Color("50e3c2")

## Deslocamento da proa por `MoveIntent.Dir` (NONE, UP, RIGHT, DOWN, LEFT). Campo e tela
## diferem por translação pura (`CoordinateSpace.field_to_screen`), então o eixo do domínio
## vale sem correção: y cresce para baixo nos dois espaços.
const FACING_DX := [0, 0, 1, 0, -1]
const FACING_DY := [0, -1, 0, 1, 0]
const FACING_NEAR := 3.0
const FACING_FAR := 5.0

var _outer := DEFAULT_OUTER
var _core := DEFAULT_CORE
var _accent := DEFAULT_ACCENT
var _facing: int = MoveIntent.Dir.NONE
var _trail_active: bool = false
var _shield_critical: bool = false
var _pulse_step: int = 0


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	if visual != null:
		_outer = visual.boundary_color
		_core = visual.trail_hot_color
		_accent = visual.accent_color
	var screen := CoordinateSpace.field_to_screen(Vector2i(simulation.px, simulation.py))
	position = Vector2(screen.x, screen.y)
	_trail_active = simulation.trail_active
	_facing = simulation.pdir
	_shield_critical = simulation.shield_ticks <= simulation.rules.shield_critical_ticks
	_pulse_step = simulation.tick % 12
	if simulation.phase == GameSimulation.Phase.GAME_OVER:
		visible = false
	elif simulation.phase == GameSimulation.Phase.DYING:
		@warning_ignore("integer_division")
		visible = (simulation.death_ticks_left / 4) % 2 == 0
	else:
		visible = true
	queue_redraw()


func presentation_colors() -> Dictionary:
	return {"outer": _outer, "core": _core, "accent": _accent}


## Segmento da proa em espaço local, ou vazio quando não há trilha a apontar. É a mesma
## fonte que `_draw` consome: o que o teste afirma é o que a tela recebe.
func facing_indicator() -> PackedVector2Array:
	if not _trail_active or _facing == MoveIntent.Dir.NONE:
		return PackedVector2Array()
	var axis := Vector2(FACING_DX[_facing], FACING_DY[_facing])
	return PackedVector2Array([axis * FACING_NEAR, axis * FACING_FAR])


func _draw() -> void:
	var halo := _accent
	halo.a = 0.32 if _trail_active else 0.16
	var halo_radius := 4.0 if _pulse_step < 6 else 5.0
	draw_rect(Rect2(-halo_radius, -halo_radius, halo_radius * 2.0 + 1.0, halo_radius * 2.0 + 1.0), halo, false, 1.0)

	# Silhueta 5×5 com centro inequívoco no pixel/célula autoritativo.
	draw_rect(Rect2(-2.0, -1.0, 5.0, 3.0), _outer)
	draw_rect(Rect2(-1.0, -2.0, 3.0, 5.0), _outer)
	draw_rect(Rect2(-1.0, -1.0, 3.0, 3.0), _accent)
	draw_rect(Rect2(0.0, 0.0, 1.0, 1.0), _core)

	var prow := facing_indicator()
	if not prow.is_empty():
		var direction_color := _core
		direction_color.a = 0.9
		draw_line(prow[0], prow[1], direction_color, 1.0)
	if _shield_critical:
		var alert := Color("ff4d6d")
		alert.a = 1.0 if _pulse_step < 6 else 0.38
		draw_line(Vector2(-5.0, -5.0), Vector2(-2.0, -5.0), alert)
		draw_line(Vector2(-5.0, -5.0), Vector2(-5.0, -2.0), alert)
		draw_line(Vector2(5.0, -5.0), Vector2(2.0, -5.0), alert)
		draw_line(Vector2(5.0, -5.0), Vector2(5.0, -2.0), alert)
