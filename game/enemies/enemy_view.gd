class_name QixEnemyView
extends Node2D
## Chefe-anchor procedural. A cruz translúcida comunica o footprint letal de 1 célula, e um anel
## de tinta de 1 px separa a silhueta de qualquer chão sem depender de matiz (ADR-0011).

const DEFAULT_BODY := Color("ff4d6d")
const DEFAULT_CORE := Color("ffd166")
const DEFAULT_ACCENT := Color("6ca8b5")
## Mesmo padrão de `RoundVisualDefinition.free_color`: a tinta é o chão não reclamado da paleta.
const DEFAULT_INK := Color("071923")
const BossBehaviorControllerScript = preload("res://game/enemies/boss_behavior_controller.gd")
const BossBehaviorProfileScript = preload("res://game/enemies/boss_behavior_profile.gd")

## Raio do losango preenchido com `threat_color`.
const BODY_RADIUS := 4.0
## Raio do contorno de tinta. A diferença para `BODY_RADIUS` é a espessura do anel — 1 px, a
## menor marca que o campo 240×320 consegue sustentar. Ver ADR-0011.
const RIM_RADIUS := 5.0

var _body := DEFAULT_BODY
var _core := DEFAULT_CORE
var _accent := DEFAULT_ACCENT
var _ink := DEFAULT_INK
var _phase_step: int = 0
var _behavior_pattern: int = 0
var _surging: bool = false
var _facing := Vector2.RIGHT
var _diamond := diamond(BODY_RADIUS)
var _rim := diamond(RIM_RADIUS)


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	if visual != null:
		_body = visual.threat_color
		_core = visual.trail_hot_color
		_accent = visual.accent_color
		_ink = visual.free_color
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


## Losango de raio `radius`, no sentido horário a partir do topo. Pura: o teste de silhueta usa a
## mesma função que `_draw`, então a geometria medida é a geometria desenhada.
static func diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -radius),
		Vector2(radius, 0.0),
		Vector2(0.0, radius),
		Vector2(-radius, 0.0),
	])


func presentation_colors() -> Dictionary:
	return {"body": _body, "core": _core, "accent": _accent, "ink": _ink}


## Ponto em que um raio na direção `direction` cruza o losango de raio `radius`.
##
## O anel é um losango, não um círculo: a distância do centro à sua borda vale `radius` sobre os
## eixos e `radius/√2` nas diagonais. Multiplicar uma direção normalizada por `RIM_RADIUS`, como
## se o anel fosse circular, acerta só nas quatro direções axiais — e o chefe anda em dezasseis
## (`BossBehaviorController.DIRECTION_X`). Nas outras doze a marca nascia até 1,46 px fora do
## contorno, mais do que a espessura de 1 px do próprio anel: deixava de ser a proa da silhueta e
## virava um ponto solto ao lado dela, no rumo em que o jogador mais precisa de ler a ameaça.
##
## Pura e estática: o teste de âncora usa a mesma função que `_draw`, então a geometria medida é
## a geometria desenhada — o mesmo contrato de `diamond()`.
static func rim_point(direction: Vector2, radius: float) -> Vector2:
	var span := absf(direction.x) + absf(direction.y)
	if span <= 0.0:
		return Vector2.ZERO
	return direction * (radius / span)


## Geometria da silhueta, para quem precisa provar que o anel de tinta envolve o corpo sem que
## nada da apresentação precise renderizar um frame. `mark_origin` é onde a proa de PURSUIT e a
## haste de SWEEP encostam no anel para o rumo observado no último `sync`.
func silhouette_geometry() -> Dictionary:
	return {"body": _diamond, "rim": _rim, "mark_origin": rim_point(_facing, RIM_RADIUS)}


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
	# Tendrils alternados mantêm energia sem Tween/relógio e seguem o tick observado. Vêm antes do
	# anel de tinta: assim eles emergem de trás da silhueta em vez de furá-la em quatro pontos.
	var reach := 10.0 if _surging else (8.0 if _phase_step < 8 else 7.0)
	draw_line(Vector2(-BODY_RADIUS, 0.0), Vector2(-reach, -2.0), _body)
	draw_line(Vector2(BODY_RADIUS, 0.0), Vector2(reach, 2.0), _body)
	draw_line(Vector2(0.0, -BODY_RADIUS), Vector2(2.0, -reach), _body)
	draw_line(Vector2(0.0, BODY_RADIUS), Vector2(-2.0, reach), _body)

	# Anel de tinta: o único canal da ameaça que não depende de matiz. `threat_color` fica a
	# 1,27:1 de `BOUNDARY` e a 1,82:1 de `TRAIL` na pior dicromacia, então o corpo sozinho não
	# separa a ameaça do chão em que ela anda. A tinta é o `free_color` da rodada — o mais escuro
	# da paleta — e mede ≥ 8,9:1 contra a borda e ≥ 11,2:1 contra a trilha. Ver ADR-0011.
	draw_colored_polygon(_rim, _ink)
	draw_colored_polygon(_diamond, _body)
	draw_polyline(PackedVector2Array([
		Vector2(0.0, -BODY_RADIUS), Vector2(BODY_RADIUS, 0.0), Vector2(0.0, BODY_RADIUS),
		Vector2(-BODY_RADIUS, 0.0), Vector2(0.0, -BODY_RADIUS),
	]), _core, 1.0)
	draw_rect(Rect2(-1.0, -1.0, 3.0, 3.0), _core)
	draw_rect(Rect2(0.0, 0.0, 1.0, 1.0), Color.WHITE)

	# A silhueta comunica o contrato de movimento antes que ele ameace a trilha. As marcas nascem
	# na borda do anel, não na do corpo, para não abrir o contorno na direção do movimento — e a
	# borda do anel é `rim_point`, não `RIM_RADIUS`, porque o anel é losango (ver a função).
	var mark_origin := rim_point(_facing, RIM_RADIUS)
	match _behavior_pattern:
		BossBehaviorProfileScript.Pattern.PURSUIT:
			var nose := _facing * (11.0 if _surging else 9.0)
			draw_line(mark_origin, nose, _core, 1.0)
			draw_circle(nose, 1.5, _core, false, 1.0)
		BossBehaviorProfileScript.Pattern.SWEEP:
			draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 16, aura, 1.0)
			draw_line(mark_origin, _facing * 9.0, _core, 1.0)
		_:
			pass
