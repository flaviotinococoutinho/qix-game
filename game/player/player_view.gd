class_name QixPlayerView
extends Node2D
## Cartógrafo: silhueta 2D contrastante e sinais compartilhados com o modelo 3D.
## A célula e o ciclo de vida vêm do domínio; nenhuma apresentação altera a colisão.

@export var show_body: bool = true

const DEFAULT_OUTER := Color("f5f7ff")
const DEFAULT_CORE := Color("fff4b0")
const DEFAULT_ACCENT := Color("50e3c2")
## Mesmo padrão de `QixEnemyView.DEFAULT_INK`: a tinta é o chão não reclamado da paleta.
const DEFAULT_INK := Color("071923")

## Meia-extensão da cruz opaca da silhueta e a da cruz de tinta desenhada por baixo dela. A
## diferença é a espessura do contorno — 1 px, a mesma do anel da ameaça (ADR-0011), porque é a
## menor marca que sobrevive à escala de 240×320 sem virar borrão.
## Ver `docs/decisions/ADR-0012-cursor-ink-outline.md`.
const BODY_REACH := 2.0
const INK_REACH := 3.0

## Deslocamento da proa por `MoveIntent.Dir` (NONE, UP, RIGHT, DOWN, LEFT). Campo e tela
## diferem por translação pura (`CoordinateSpace.field_to_screen`), então o eixo do domínio
## vale sem correção: y cresce para baixo nos dois espaços.
const FACING_DX := [0, 0, 1, 0, -1]
const FACING_DY := [0, -1, 0, 1, 0]
## A proa nasce fora da tinta: `INK_REACH + 1`. Antes do contorno era `BODY_REACH + 1`; manter 3,0
## faria a proa começar dentro do próprio contorno e a leitura de direção competiria com a de
## posição. O comprimento de 2 px de #35 é preservado.
const FACING_NEAR := 4.0
const FACING_FAR := 6.0

var _outer := DEFAULT_OUTER
var _core := DEFAULT_CORE
var _accent := DEFAULT_ACCENT
var _ink := DEFAULT_INK
var _facing_dir: int = MoveIntent.Dir.NONE
var _facing := Vector2.UP
var _trail_active: bool = false
var _shield_critical: bool = false
var _pulse_step: int = 0
var _lifecycle: int = ActorLifecycle.State.ACTIVE
var _lifecycle_ticks: int = 0
var _shield_ratio: float = 1.0


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	_outer = visual.boundary_color if visual != null else DEFAULT_OUTER
	_core = visual.trail_hot_color if visual != null else DEFAULT_CORE
	_accent = visual.accent_color if visual != null else DEFAULT_ACCENT
	_ink = visual.free_color if visual != null else DEFAULT_INK
	position = Vector2(CoordinateSpace.field_to_screen(simulation.player.cell()))
	_trail_active = simulation.trail_active
	_facing_dir = simulation.pdir
	_facing = Vector2(FACING_DX[_facing_dir], FACING_DY[_facing_dir])
	if _facing_dir == MoveIntent.Dir.NONE:
		_facing = Vector2.UP
	_shield_critical = simulation.shield_ticks <= simulation.rules.shield_critical_ticks
	_shield_ratio = clampf(float(simulation.shield_ticks) / float(maxi(1, simulation.rules.shield_ticks)), 0.0, 1.0)
	_pulse_step = simulation.tick % 24
	_lifecycle = simulation.player.lifecycle()
	_lifecycle_ticks = simulation.player.lifecycle_ticks
	visible = _lifecycle != ActorLifecycle.State.DESPAWNED
	queue_redraw()


func presentation_colors() -> Dictionary:
	return {"outer": _outer, "core": _core, "accent": _accent, "ink": _ink}


## Os dois retângulos que formam uma cruz de meia-extensão `reach`, na ordem em que `_draw` os
## consome. Existe como função para que o teste afirme a geometria que a tela recebe em vez de
## reconstruí-la a partir de números repetidos.
static func cross_rects(reach: float) -> Array[Rect2]:
	var arm := reach - 1.0
	return [
		Rect2(-reach, -arm, reach * 2.0 + 1.0, arm * 2.0 + 1.0),
		Rect2(-arm, -reach, arm * 2.0 + 1.0, reach * 2.0 + 1.0),
	]


## Segmento da proa em espaço local, ou vazio quando não há trilha a apontar. É a mesma
## fonte que `_draw` consome: o que o teste afirma é o que a tela recebe.
func facing_indicator() -> PackedVector2Array:
	if not _trail_active or _facing_dir == MoveIntent.Dir.NONE:
		return PackedVector2Array()
	return PackedVector2Array([_facing * FACING_NEAR, _facing * FACING_FAR])


func presentation_state() -> Dictionary:
	return {
		"lifecycle": _lifecycle, "lifecycle_ticks": _lifecycle_ticks,
		"facing": _facing, "drawing": _trail_active, "shield_ratio": _shield_ratio,
		"position": position, "id": ActorLifecycle.PLAYER_ID,
	}


func _draw() -> void:
	if _lifecycle == ActorLifecycle.State.DESPAWNED:
		return
	var pulse := 0.5 + 0.5 * sin(float(_pulse_step) * TAU / 24.0)
	if _lifecycle == ActorLifecycle.State.DYING:
		_draw_dissolving(pulse)
		return
	if show_body:
		_draw_body()
	else:
		# O GLB ocupa a silhueta; este ponto mantém a célula autoritativa legível.
		draw_circle(Vector2.ZERO, 0.6, _core, true, -1.0, true)
	_draw_indicators(pulse)


func _draw_body() -> void:
	var halo := _accent
	halo.a = 0.32 if _trail_active else 0.16
	# `INK_REACH + 2` e `+ 3`: o halo mantém a folga de 1 px que tinha contra a silhueta antes de o
	# contorno existir. Colado à tinta, ele lê-se como parte do cursor, não como respiração.
	var halo_radius := 5.0 if _pulse_step < 12 else 6.0
	draw_rect(Rect2(-halo_radius, -halo_radius, halo_radius * 2.0 + 1.0, halo_radius * 2.0 + 1.0), halo, false, 1.0)

	# Contorno de tinta de 1 px por baixo da silhueta. Sobre `BOUNDARY` — onde as três camadas
	# opacas medem 1,00–1,11:1 e nenhuma paleta conserta isso — é ele que separa o cursor do chão,
	# por luminância em vez de matiz. Sobre `FREE` ele é o próprio chão e desaparece, que é o
	# desejado: ali a silhueta já passa com folga. Mesmo mecanismo do anel da ameaça (ADR-0011).
	for rect in cross_rects(INK_REACH):
		draw_rect(rect, _ink)

	# Silhueta 5×5 com centro inequívoco no pixel/célula autoritativo.
	for rect in cross_rects(BODY_REACH):
		draw_rect(rect, _outer)
	draw_rect(Rect2(-1.0, -1.0, 3.0, 3.0), _accent)
	draw_rect(Rect2(0.0, 0.0, 1.0, 1.0), _core)


func _draw_indicators(pulse: float) -> void:
	var prow := facing_indicator()
	if not prow.is_empty():
		var direction_color := _core
		direction_color.a = 0.9
		draw_line(prow[0], prow[1], direction_color, 1.0)
	if _shield_critical:
		var alert := Color("ff4d6d")
		alert.a = 0.55 + pulse * 0.45
		draw_line(Vector2(-5.0, -5.0), Vector2(-2.0, -5.0), alert)
		draw_line(Vector2(-5.0, -5.0), Vector2(-5.0, -2.0), alert)
		draw_line(Vector2(5.0, -5.0), Vector2(2.0, -5.0), alert)
		draw_line(Vector2(5.0, -5.0), Vector2(5.0, -2.0), alert)

	if _lifecycle == ActorLifecycle.State.WARMUP:
		draw_arc(Vector2.ZERO, 6.7, -PI * 0.7, PI * 0.7, 20, _outer, 0.7, true)
		draw_arc(Vector2.ZERO, 6.7, PI * 0.3, PI * 1.7, 20, _accent, 0.7, true)


func _draw_dissolving(pulse: float) -> void:
	var color := _core
	color.a = 0.35 + pulse * 0.4
	var radius := 4.0 + float(_lifecycle_ticks % 12) * 0.3
	for index in 6:
		var direction := Vector2.from_angle(float(index) * TAU / 6.0)
		draw_line(direction * radius, direction * (radius + 1.8), color, 0.9, true)
	draw_circle(Vector2.ZERO, 0.7, _core, true, -1.0, true)
