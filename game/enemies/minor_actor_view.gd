class_name QixMinorActorView
extends Node2D
## Elenco menor em uma camada de desenho: snapshots próprios, sem referências ao domínio.
## Os avisos usam a mesma trajetória que as regras. Corpos podem ceder lugar aos modelos 3D.

@export var show_body: bool = true

const INK := Color("020a15")
const WALKER_COLOR := Color("ffb35b")
const DART_COLOR := Color("ff708a")
const EMBER_COLOR := Color("fff0c4")
const TELEGRAPH_CELLS := 6
## Boca do disparo: as células mais próximas do dardo, no brilho que o aviso já tinha.
const MUZZLE_CELLS := 5
## Teto do corredor avisado: o dobro de `dart_min_range` (24), a distância em que o dardo nasce
## do jogador. Nunca esconde o alvo, e impede que seis dardos armados sobre um campo quase todo
## livre custem milissegundos por frame só para desenhar aviso. Um corredor que bate no teto
## perde a ponta de seta: seta significa «é aqui que ele morre», e isso não pode ser inventado.
const TELEGRAPH_MAX_CELLS := 48

var _walkers: Array[Dictionary] = []
var _darts: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _beacons: Array[Dictionary] = []
var _tick: int = 0
var _accent := Color("50e3c2")
var _hot := Color("fff4b0")
var _threat := Color("ff426d")


func sync(simulation: GameSimulation, visual: RoundVisualDefinition = null) -> void:
	_tick = simulation.tick
	_accent = visual.accent_color if visual != null else Color("50e3c2")
	_hot = visual.trail_hot_color if visual != null else Color("fff4b0")
	_threat = visual.threat_color if visual != null else Color("ff426d")
	_walkers.clear()
	_darts.clear()
	_embers.clear()
	_beacons.clear()
	if simulation.items_enabled():
		for index in simulation.beacons.count:
			var captured := simulation.beacons.is_captured(index)
			_beacons.append({
				"slot": index, "id": index, "captured": captured,
				"state": simulation.beacons.states[index],
				"lifecycle": ActorLifecycle.State.DORMANT if captured else ActorLifecycle.State.ACTIVE,
				"position": Vector2(CoordinateSpace.field_to_screen(simulation.beacons.cell(index))),
			})
	var pools := simulation.pools
	for slot in MinorActorPools.MAX_WALKERS:
		var lifecycle := pools.walker_lifecycle(slot)
		if lifecycle == ActorLifecycle.State.DESPAWNED:
			continue
		var path := PackedVector2Array()
		if lifecycle != ActorLifecycle.State.DYING and lifecycle != ActorLifecycle.State.DORMANT:
			for index in WalkerRules.peek_path(pools, slot, simulation.board, TELEGRAPH_CELLS):
				path.append(_screen(simulation.board, index))
		var dir := pools.walker(slot, MinorActorPools.W.DIR)
		_walkers.append({
			"slot": slot, "id": pools.walker_actor_id(slot), "lifecycle": lifecycle,
			"position": Vector2(CoordinateSpace.field_to_screen(pools.walker_cell(slot))),
			"direction": Vector2(BoardState.NEIGHBOR_DX[dir], BoardState.NEIGHBOR_DY[dir]),
			"path": path, "warmup": pools.walker(slot, MinorActorPools.W.WARMUP),
			"state_ticks": pools.walker(slot, MinorActorPools.W.STATE_TICKS),
			"cause": pools.walker(slot, MinorActorPools.W.CAUSE),
			"reason": pools.walker(slot, MinorActorPools.W.REASON),
		})
	for slot in MinorActorPools.MAX_DARTS:
		var lifecycle := pools.dart_lifecycle(slot)
		if lifecycle == ActorLifecycle.State.DESPAWNED:
			continue
		var dir := pools.dart(slot, MinorActorPools.D.DIR_INDEX)
		var direction := Vector2(DartRules.DIRECTION_X[dir], DartRules.DIRECTION_Y[dir]).normalized()
		var center := Vector2(CoordinateSpace.field_to_screen(pools.dart_cell(slot)))
		var path := PackedVector2Array()
		if lifecycle == ActorLifecycle.State.WARMUP:
			for index in DartRules.peek_path(pools, slot, simulation.board, TELEGRAPH_MAX_CELLS):
				path.append(_screen(simulation.board, index))
		_darts.append({
			"slot": slot, "id": pools.dart_actor_id(slot), "lifecycle": lifecycle,
			"position": center, "direction": direction, "path": path,
			"warmup": pools.dart(slot, MinorActorPools.D.WARMUP),
			"state_ticks": pools.dart(slot, MinorActorPools.D.STATE_TICKS),
			"cause": pools.dart(slot, MinorActorPools.D.CAUSE),
			"reason": pools.dart(slot, MinorActorPools.D.REASON),
		})
	for slot in MinorActorPools.MAX_EMBERS:
		var lifecycle := pools.ember_lifecycle(slot)
		if lifecycle == ActorLifecycle.State.DESPAWNED:
			continue
		# A célula terminal fica retida no pool até o fim da dissolução confirmada.
		var cell_index := EmberRules.cell_index(pools, slot, simulation.player)
		if cell_index < 0:
			continue
		var trail_index := pools.ember(slot, MinorActorPools.E.TRAIL_INDEX)
		var center := _screen(simulation.board, cell_index)
		var scorched := PackedVector2Array()
		var direction := Vector2.ZERO
		if not simulation.trail.is_empty():
			trail_index = clampi(trail_index, 0, simulation.trail.size() - 1)
			for index in range(maxi(0, trail_index - 8), trail_index + 1):
				scorched.append(_screen(simulation.board, simulation.trail[index]))
			var next_index := mini(trail_index + 1, simulation.trail.size() - 1)
			direction = (_screen(simulation.board, simulation.trail[next_index]) - center).normalized()
		_embers.append({
			"slot": slot, "id": pools.ember_actor_id(slot), "lifecycle": lifecycle,
			"position": center, "direction": direction, "scorched": scorched,
			"trail_index": trail_index,
			"state_ticks": pools.ember(slot, MinorActorPools.E.STATE_TICKS),
			"cause": pools.ember(slot, MinorActorPools.E.CAUSE),
			"reason": pools.ember(slot, MinorActorPools.E.REASON),
		})
	visible = not _walkers.is_empty() or not _darts.is_empty() or not _embers.is_empty() or not _beacons.is_empty()
	queue_redraw()


## Cópia profunda: diagnóstico e proxies 3D não conseguem editar o snapshot desenhado.
func presentation_state() -> Dictionary:
	return {
		"walkers": _walkers.duplicate(true), "darts": _darts.duplicate(true),
		"embers": _embers.duplicate(true), "beacons": _beacons.duplicate(true),
	}


func _screen(board: BoardState, index: int) -> Vector2:
	@warning_ignore("integer_division")
	var cell := Vector2i(index % board.width, index / board.width)
	return Vector2(CoordinateSpace.field_to_screen(cell))


func _draw() -> void:
	for actor in _beacons:
		_draw_beacon(actor)
	for actor in _walkers:
		_draw_walker(actor)
	for actor in _darts:
		_draw_dart(actor)
	for actor in _embers:
		_draw_ember(actor)


func _draw_walker(actor: Dictionary) -> void:
	var center: Vector2 = actor.position
	var lifecycle: int = actor.lifecycle
	var pulse := 0.5 + 0.5 * sin(float(_tick + int(actor.slot) * 7) * TAU / 24.0)
	if lifecycle == ActorLifecycle.State.DYING:
		_draw_release(center, WALKER_COLOR, int(actor.state_ticks))
		return
	var path: PackedVector2Array = actor.path
	for index in path.size():
		var color := WALKER_COLOR
		color.a = 0.65 - float(index) * 0.075
		draw_circle(path[index], 0.65, INK, true, -1.0, true)
		draw_circle(path[index], 0.35, color, true, -1.0, true)
	if lifecycle == ActorLifecycle.State.WARMUP:
		_draw_brackets(center, 4.5 + pulse * 0.5, WALKER_COLOR)
	elif lifecycle == ActorLifecycle.State.DORMANT:
		draw_arc(center, 4.0, 0.0, TAU, 20, _accent, 0.6, true)
		draw_line(center + Vector2(-1.0, -0.7), center + Vector2(-1.0, 0.7), _accent, 0.6, true)
		draw_line(center + Vector2(1.0, -0.7), center + Vector2(1.0, 0.7), _accent, 0.6, true)
	var color := WALKER_COLOR if lifecycle != ActorLifecycle.State.DORMANT else _accent.darkened(0.45)
	if show_body:
		_shadow(center, 3.1)
		var direction: Vector2 = actor.direction
		var tangent := direction.orthogonal()
		var wing := 2.6 + pulse * 0.5
		for sign_value: float in [-1.0, 1.0]:
			var points := PackedVector2Array([
				center - direction * 1.7, center + tangent * wing * sign_value,
				center + direction * 1.2 + tangent * 1.5 * sign_value,
			])
			draw_colored_polygon(points, color.darkened(0.28))
			draw_polyline(_closed(points), INK, 0.75, true)
		draw_circle(center, 1.4, INK, true, -1.0, true)
		draw_circle(center - Vector2(0.0, 0.5), 1.0, color, true, -1.0, true)
	draw_circle(center, 0.48, _hot, true, -1.0, true)


func _draw_dart(actor: Dictionary) -> void:
	var center: Vector2 = actor.position
	var direction: Vector2 = actor.direction
	var lifecycle: int = actor.lifecycle
	if lifecycle == ActorLifecycle.State.DYING:
		_draw_release(center, _threat, int(actor.state_ticks))
		return
	var tangent := direction.orthogonal()
	if lifecycle == ActorLifecycle.State.WARMUP:
		# O aviso é o corredor real até a célula que vai absorver o dardo, e não um raio de
		# comprimento arbitrário: quem está na reta precisa ver que ela chega até ele.
		var path: PackedVector2Array = actor.path
		if path.size() > 0:
			var corridor := PackedVector2Array([center])
			corridor.append_array(path)
			draw_polyline(corridor, INK, 2.0, true)
			# Corredor inteiro discreto; a boca do disparo conserva a leitura forte de antes.
			var far := DART_COLOR
			far.a = 0.55
			draw_polyline(corridor, far, 0.75, true)
			var muzzle := corridor.slice(0, mini(corridor.size(), MUZZLE_CELLS + 1))
			if muzzle.size() > 1:
				draw_polyline(muzzle, DART_COLOR, 0.75, true)
			if path.size() < TELEGRAPH_MAX_CELLS:
				# Corredor inteiro: a seta marca a célula que absorve ou corta o dardo.
				var end: Vector2 = path[path.size() - 1]
				draw_polyline(PackedVector2Array([
					end - direction * 1.3 - tangent, end, end - direction * 1.3 + tangent,
				]), _hot, 0.6, true)
		_draw_brackets(center, 3.5, DART_COLOR)
	else:
		draw_line(center - direction * 4.5, center, Color("541c36"), 1.6, true)
		draw_line(center - direction * 2.5, center, DART_COLOR, 0.65, true)
	if show_body:
		var shape := PackedVector2Array([
			center + direction * 2.8, center - direction * 1.5 + tangent * 1.2,
			center - direction * 0.5, center - direction * 1.5 - tangent * 1.2,
		])
		draw_colored_polygon(shape, DART_COLOR)
		draw_polyline(_closed(shape), INK, 0.8, true)
		draw_line(center, center + direction * 2.0, _hot, 0.65, true)
	else:
		draw_circle(center, 0.45, _hot, true, -1.0, true)


func _draw_ember(actor: Dictionary) -> void:
	var center: Vector2 = actor.position
	if int(actor.lifecycle) == ActorLifecycle.State.DYING:
		_draw_release(center, EMBER_COLOR, int(actor.state_ticks))
		return
	var scorched: PackedVector2Array = actor.scorched
	if scorched.size() > 1:
		draw_polyline(scorched, Color("311a29"), 1.1, true)
		# O pavio apagado acompanha só células já percorridas pela brasa confirmada.
		for point in scorched:
			draw_circle(point, 0.25, Color("cf673d"), true, -1.0, true)
	var pulse := 0.5 + 0.5 * sin(float(_tick + int(actor.slot) * 5) * TAU / 12.0)
	if int(actor.lifecycle) == ActorLifecycle.State.WARMUP:
		_draw_brackets(center, 3.5 + pulse * 0.5, EMBER_COLOR)
	if show_body:
		draw_circle(center, 3.0 + pulse, Color(1.0, 0.32, 0.12, 0.15), true, -1.0, true)
		var flame := PackedVector2Array([
			center + Vector2(0.0, -3.0 - pulse), center + Vector2(1.8, 0.0),
			center + Vector2(0.0, 1.5), center + Vector2(-1.8, 0.0),
		])
		draw_colored_polygon(flame, Color("ff853f"))
		draw_polyline(_closed(flame), INK, 0.8, true)
	draw_circle(center, 0.8, EMBER_COLOR, true, -1.0, true)


func _draw_beacon(actor: Dictionary) -> void:
	var center: Vector2 = actor.position
	var captured: bool = actor.captured
	var color := _accent if captured else _hot
	draw_arc(center, 4.0, 0.0, TAU, 24, INK, 1.8, true)
	if captured:
		draw_arc(center, 4.0, 0.0, TAU, 24, color, 0.65, true)
		draw_polyline(PackedVector2Array([
			center + Vector2(-1.7, 0.0), center + Vector2(-0.4, 1.2), center + Vector2(1.8, -1.2),
		]), color, 0.7, true)
	else:
		# O anel interrompido vira contínuo somente quando a captura é confirmada.
		for index in 4:
			var angle := float(index) * PI * 0.5
			draw_arc(center, 4.0, angle + 0.14, angle + PI * 0.5 - 0.14, 6, color, 0.7, true)
		if show_body:
			_shadow(center, 2.2)
			var crystal := PackedVector2Array([
				center + Vector2(0.0, -2.5), center + Vector2(1.5, 0.0),
				center + Vector2(0.0, 1.5), center + Vector2(-1.5, 0.0),
			])
			draw_colored_polygon(crystal, color.darkened(0.3))
			draw_line(center + Vector2(0.0, -2.5), center + Vector2(-1.5, 0.0), color, 0.65, true)
		draw_circle(center, 0.4, color, true, -1.0, true)


func _shadow(center: Vector2, radius: float) -> void:
	draw_set_transform(center + Vector2(0.8, 2.0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius, Color(0.0, 0.01, 0.03, 0.7), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_brackets(center: Vector2, radius: float, color: Color) -> void:
	for sign_value: float in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([
			center + Vector2(sign_value * (radius - 1.2), -radius),
			center + Vector2(sign_value * radius, -radius),
			center + Vector2(sign_value * radius, -radius + 1.2),
		]), color, 0.7, true)


func _draw_release(center: Vector2, color: Color, ticks: int) -> void:
	var radius := 2.0 + float(12 - clampi(ticks, 0, 12)) * 0.22
	var faded := color
	faded.a = clampf(float(ticks) / 12.0, 0.1, 1.0)
	for index in 4:
		var direction := Vector2.from_angle(PI * 0.25 + float(index) * PI * 0.5)
		draw_line(center + direction * radius, center + direction * (radius + 1.0), faded, 0.6, true)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
