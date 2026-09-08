class_name QixActorTraceOverlay
extends Control
## Diagnóstico explícito F3. Oculto por padrão e sem trabalho de snapshot enquanto oculto.

const MAX_ACTORS := 2 + MinorActorPools.MAX_WALKERS + MinorActorPools.MAX_DARTS + MinorActorPools.MAX_EMBERS
const MAX_LINES := MAX_ACTORS + 7
const PANEL_RECT := Rect2(8.0, 27.0, 224.0, 266.0)
const LIFE_NAMES := ["FORA", "AVISO", "ATIVO", "DORME", "SAINDO"]
const KIND_NAMES := ["JOG", "NUC", "VAG", "DAR", "BRA"]
const CAUSE_NAMES := ["-", "ESCADA", "CAMP", "EXPO", "FURIA", "SERIE", "CORTE", "PAROU", "TEMPO"]
const REASON_NAMES := ["-", "NASCE", "SEGUE", "MAO", "CONTRA", "VOLTA", "DORME", "APAGA",
	"ARMA", "DISPARA", "ABSORVE", "CORTA", "CONTATO", "AVANCA", "ESPERA", "SEMTRIL", "EXPIRA"]

var _body: Label


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func sync(session: GameSession, input_adapter: GameInputAdapter = null) -> void:
	if not visible or session == null or session.simulation == null:
		return
	_ensure_panel()
	_body.text = "\n".join(snapshot_lines(session.simulation, input_adapter != null))


## Dados escalares e cópias: nem diagnóstico nem testes recebem arrays mutáveis do domínio.
static func snapshot(simulation: GameSimulation) -> Dictionary:
	var actors: Array[Dictionary] = [
		_record(ActorLifecycle.Kind.PLAYER, simulation.player.actor_id, simulation.player.lifecycle(), 0, 0),
		_record(ActorLifecycle.Kind.BOSS, simulation.boss.actor_id, simulation.boss.lifecycle(), 0, 0),
	]
	var pools := simulation.pools
	for slot in MinorActorPools.MAX_WALKERS:
		if pools.walker_lifecycle(slot) != ActorLifecycle.State.DESPAWNED:
			actors.append(_record(ActorLifecycle.Kind.WALKER, pools.walker_actor_id(slot), pools.walker_lifecycle(slot),
				pools.walker(slot, MinorActorPools.W.CAUSE), pools.walker(slot, MinorActorPools.W.REASON)))
	for slot in MinorActorPools.MAX_DARTS:
		if pools.dart_lifecycle(slot) != ActorLifecycle.State.DESPAWNED:
			actors.append(_record(ActorLifecycle.Kind.DART, pools.dart_actor_id(slot), pools.dart_lifecycle(slot),
				pools.dart(slot, MinorActorPools.D.CAUSE), pools.dart(slot, MinorActorPools.D.REASON)))
	for slot in MinorActorPools.MAX_EMBERS:
		if pools.ember_lifecycle(slot) != ActorLifecycle.State.DESPAWNED:
			actors.append(_record(ActorLifecycle.Kind.EMBER, pools.ember_actor_id(slot), pools.ember_lifecycle(slot),
				pools.ember(slot, MinorActorPools.E.CAUSE), pools.ember(slot, MinorActorPools.E.REASON)))
	return {
		"tick": simulation.tick, "phase": simulation.boss.phase, "pressure": simulation.director.threat_index,
		"grace": simulation.director.respawn_grace_left, "shield": simulation.shield_ticks,
		"stasis": simulation.boss.stasis_ticks, "burst": simulation.boss.burst_left,
		"beacons": simulation.beacons.count, "captured": simulation.beacons.captured_count(),
		"effects": simulation.effects.remaining.duplicate(), "direction": simulation.pdir,
		"actors": actors,
	}


static func snapshot_lines(simulation: GameSimulation, input_connected: bool = false) -> PackedStringArray:
	var data := snapshot(simulation)
	var lines := PackedStringArray([
		"TICK %d · NÚCLEO F%d · PRESSÃO %d/16" % [data.tick, int(data.phase) + 1, int(data.pressure) + 1],
		"ESCUDO %dt · GRAÇA %dt · BALIZAS %d/%d" % [data.shield, data.grace, data.captured, data.beacons],
		"NÚCLEO: ESTASE %dt · FÚRIA %dt" % [data.stasis, data.burst],
		"ITENS(t): IMP %d · EST %d · ESC %d · PUR %d" % [data.effects[1], data.effects[2], data.effects[3], data.effects[4]],
		"ENTRADA %s · DIREÇÃO CONFIRMADA %d" % ["LIGADA" if input_connected else "N/D", data.direction],
		"ID TIPO ESTADO · C: CAUSA · R: DECISÃO",
	])
	for actor: Dictionary in data.actors:
		lines.append("#%d %s %s · C:%s R:%s" % [actor.id, _name(KIND_NAMES, actor.kind),
			_name(LIFE_NAMES, actor.lifecycle), _name(CAUSE_NAMES, actor.cause), _name(REASON_NAMES, actor.reason)])
	return lines


static func _record(kind: int, id: int, lifecycle: int, cause: int, reason: int) -> Dictionary:
	return {"kind": kind, "id": id, "lifecycle": lifecycle, "cause": cause, "reason": reason}


static func _name(names: Array, index: int) -> String:
	return str(names[index]) if index >= 0 and index < names.size() else "?%d" % index


func _ensure_panel() -> void:
	if _body != null:
		return
	position = Vector2.ZERO
	size = Vector2(CoordinateSpace.VIEWPORT)
	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.color = Color("03101af5")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var title := Label.new()
	title.text = "F3 · RASTREIO DOS ATORES"
	title.add_theme_font_size_override("font_size", 7)
	title.add_theme_color_override("font_color", Color("70ebd7"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	title.position = Vector2(8.0, 6.0)
	title.size = Vector2(208.0, 12.0)
	_body = Label.new()
	_body.name = "Snapshot"
	_body.add_theme_font_size_override("font_size", 6)
	_body.add_theme_constant_override("line_spacing", 0)
	_body.add_theme_color_override("font_color", Color("ddf4ff"))
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body.clip_text = true
	panel.add_child(_body)
	_body.position = Vector2(8.0, 23.0)
	_body.size = Vector2(208.0, 237.0)
