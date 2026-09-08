class_name GameSimulation
extends RefCounted
## Orquestrador de uma rodada: dono da ordem do tick, da arbitragem e do checksum composto.
## `step(intent)` avança exatamente um tick. Os estados vivem em objetos pequenos
## (`PlayerState`, `BossState`, `MinorActorPools`, `DirectorState`, `ScoreLedger`, `ShieldClock`)
## e as regras em funções estáticas (`PlayerMotion`, `BossMotion`, `WalkerRules`, `DartRules`,
## `EmberRules`, `ThreatDirector`, `FloodFillCaptureResolver`).
##
## Ordem do tick (normativa; ADR-0010/0011):
##  1. avança dissipações dos pools; canonicaliza o intent (trilha ativa força draw; fallback só vale se diferir do primário);
##  2. subpassos do jogador: primário, ou fallback se o primário bloqueou; escreve trilha e
##     testa contato contra Núcleo, vagalumes e dardos armados no estado atual; conta stall;
##  3. fechamento → CapturePlan, TRAIL fica ativa até a arbitragem;
##  4. Núcleo: fase, virada (caça à trilha), reflexões, fúria — todos os subpassos;
##  5. diretor de ameaça: índice, contagens, spawns (nunca no tick de um fechamento);
##  6. atores menores em ordem estável — vagalumes, dardos (corte acende brasa), brasas —
##     cada um testando contato;
##  7. arbitragem: LETHAL_CONTACT_WINS escolhe contato; caso contrário, captura válida vence;
##  8. sem contato, expira efeitos consumidos; aplica o plano atomicamente (TRAIL → BOUNDARY) e faz a varredura
##     pós-captura: atores inválidos apagam, balizas pagam/ativam itens, diretor recarrega;
##  9. escudo, graça pós-reentrada (após TODAS as colisões), razão de fim de rodada;
## 10. lista ordenada de eventos confirmados.
## Inteiros e ponto fixo 8.8 apenas. Nada aqui lê relógio, Input, Tween ou física.

enum Phase { PLAYING, DYING, ROUND_WON, GAME_OVER }
enum DeathReason { BOSS_CONTACT, SHIELD_EXPIRED, WALKER_CONTACT, DART_CONTACT, EMBER_CONTACT }

var rules: GameRules
var round_def: RoundDefinition
var seed_value: int
var round_start_state: RoundStartState

var board: BoardState
var rng: DeterministicRng
var resolver := FloodFillCaptureResolver.new()

var player := PlayerState.new()
var boss := BossState.new()
var pools := MinorActorPools.new()
var director := DirectorState.new()
var ledger := ScoreLedger.new()
var shield := ShieldClock.new()
var beacons := BeaconState.new()
var effects := EffectTimers.new()

var tick: int = 0
var phase: int = Phase.PLAYING
var lives: int
var death_ticks_left: int = 0
## Flag explícita de aceleração preservada no estado/checksum. A campanha ativa a aceleração
## pelo timer autoritativo de VELOCITY; `_player_substeps()` consulta ambos sem duplicar timers.
var speedup_active: bool = false
var round_end_reason: int = GameRules.RoundEndReason.NONE
var deaths_this_round: int = 0

# ---------------------------------------------------------------------------------------------
# Fachada de leitura. Views, HUD e testes leem por aqui; os setters existem para fixtures de
# apresentação e nunca são chamados por quem observa a simulação em jogo.
# ---------------------------------------------------------------------------------------------

var px: int:
	get: return player.px
	set(value): player.px = value
var py: int:
	get: return player.py
	set(value): player.py = value
var pdir: int:
	get: return player.pdir
	set(value): player.pdir = value
var trail: PackedInt32Array:
	get: return player.trail
	set(value): player.trail = value
var trail_active: bool:
	get: return player.trail_active
	set(value): player.trail_active = value
var first_vertex: Vector2i:
	get: return player.first_vertex
	set(value): player.first_vertex = value
var segment_len: int:
	get: return player.segment_len
	set(value): player.segment_len = value
var trail_px_since_score: int:
	get: return player.trail_px_since_score
	set(value): player.trail_px_since_score = value

var score: int:
	get: return ledger.score
	set(value): ledger.score = value
var permille: int:
	get: return ledger.permille
	set(value): ledger.permille = value
var fills_done: int:
	get: return ledger.fills_done
	set(value): ledger.fills_done = value
var permille_remainder: int:
	get: return ledger.permille_remainder
	set(value): ledger.permille_remainder = value

var shield_ticks: int:
	get: return shield.ticks
	set(value): shield.ticks = value
var shield_critical_sent: bool:
	get: return shield.critical_sent
	set(value): shield.critical_sent = value

var boss_alive: bool:
	get: return boss.alive
	set(value): boss.alive = value
var bx_fp: int:
	get: return boss.x_fp
	set(value): boss.x_fp = value
var by_fp: int:
	get: return boss.y_fp
	set(value): boss.y_fp = value
var bvx_fp: int:
	get: return boss.vx_fp
	set(value): boss.vx_fp = value
var bvy_fp: int:
	get: return boss.vy_fp
	set(value): boss.vy_fp = value
var boss_dir_index: int:
	get: return boss.dir_index
	set(value): boss.dir_index = value
var boss_effective_speed_fp: int:
	get: return boss.effective_speed_fp
	set(value): boss.effective_speed_fp = value


func _init(
	p_rules: GameRules,
	p_round: RoundDefinition,
	p_seed: int,
	p_start_state: RoundStartState = null,
) -> void:
	rules = p_rules
	round_def = p_round
	# O RNG e o formato binário de replay usam exatamente a mesma representação u32.
	seed_value = p_seed & 0xFFFFFFFF
	round_start_state = (
		p_start_state.duplicate_state()
		if p_start_state != null
		else RoundStartState.initial(rules)
	)
	reset_round()


## Reinício limpo: mesmo seed ⇒ mesmo estado inicial ⇒ mesmo checksum.
func reset_round() -> void:
	board = BoardState.new(round_def.field_width, round_def.field_height)
	rng = DeterministicRng.new(seed_value)
	tick = 0
	phase = Phase.PLAYING
	lives = round_start_state.lives
	ledger.reset(round_start_state.score)
	shield.reset(rules)
	death_ticks_left = 0
	speedup_active = false
	round_end_reason = GameRules.RoundEndReason.NONE
	deaths_this_round = 0
	effects.reset()
	var beacons_valid := beacons.reset(round_def.beacon_cells, round_def.field_width, round_def.field_height)
	assert(beacons_valid, "balizas inválidas")
	player.reset(round_def.player_spawn)
	assert(board.get_cell(player.px, player.py) == BoardState.Cell.BOUNDARY, "spawn precisa estar na moldura")
	boss.reset(round_def.boss_start, round_def.boss_dir_index)
	boss.set_velocity(boss.dir_index, BossMotion.speed_for(boss, rules, tick))
	assert(board.get_cell(boss.cell().x, boss.cell().y) == BoardState.Cell.FREE, "chefe nasce em FREE")
	pools.clear()
	director.reset(threat_profile())


func threat_profile() -> ThreatProfile:
	return rules.threat as ThreatProfile


func threat_enabled() -> bool:
	var profile := threat_profile()
	return profile != null and profile.enabled


func item_profile() -> ItemProfile:
	return rules.items as ItemProfile


func items_enabled() -> bool:
	var profile := item_profile()
	return profile != null and profile.enabled


func boss_cell() -> Vector2i:
	return boss.cell()


## Células que o chefe ocupa para contato: centro + cruz (raio 1).
func boss_contact_cells() -> PackedInt32Array:
	return boss.contact_cells(board)


func player_index() -> int:
	return player.index_in(board)


func interior_cells() -> int:
	return board.interior_cell_count()


## Atores menores podem matar? Não durante a graça pós-reentrada (o Núcleo continua letal).
func minor_lethal_allowed() -> bool:
	return threat_enabled() and director.respawn_grace_left <= 0


# ---------------------------------------------------------------------------------------------
# tick
# ---------------------------------------------------------------------------------------------

func step(raw_intent: MoveIntent) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	if phase == Phase.ROUND_WON or phase == Phase.GAME_OVER:
		pools.advance_removals()
		boss.advance_removal()
		tick += 1
		return events  # rodada concluída: só dissipações já confirmadas avançam
	if phase == Phase.DYING:
		death_ticks_left -= 1
		player.lifecycle_ticks = maxi(0, death_ticks_left)
		if death_ticks_left <= 0:
			_respawn(events)
		tick += 1
		return events

	pools.advance_removals()
	var shield_frozen_this_tick := items_enabled() and effects.active(ItemProfile.Kind.SHIELD_FREEZE)
	# 1. canonicalizar (trilha ativa força draw; fallback igual ao primário não é fallback)
	var intent := MoveIntent.make(
		raw_intent.direction, raw_intent.drawing or player.trail_active, raw_intent.fallback
	)
	if not MoveIntent.is_valid_dir(intent.direction):
		intent.direction = MoveIntent.Dir.NONE
	if not MoveIntent.is_valid_dir(intent.fallback) or intent.fallback == intent.direction:
		intent.fallback = MoveIntent.Dir.NONE
	var fallback_intent := MoveIntent.make(intent.fallback, intent.drawing)

	# 2/3. jogador
	var lethal := false
	var lethal_reason := DeathReason.BOSS_CONTACT
	var plan: RefCounted = null
	var start_cell := player.cell()
	var substeps := _player_substeps()
	for _s in substeps:
		var result := PlayerMotion.substep(player, board, rules, intent, ledger, events)
		if result == PlayerMotion.StepResult.BLOCKED and intent.fallback != MoveIntent.Dir.NONE:
			# Buffer de curva: a curva pedida ainda não é legal, então a direção segurada continua.
			result = PlayerMotion.substep(player, board, rules, fallback_intent, ledger, events)
		if BossMotion.touches_player(boss, board, player):
			lethal = true
		if not lethal:
			var minor_reason := _player_touches_minor()
			if minor_reason >= 0:
				lethal = true
				lethal_reason = minor_reason
		if result == PlayerMotion.StepResult.CLOSED:
			plan = resolver.resolve(board, player.trail, _anchor_indices())
			break  # fill armado → o jogador para (§4.3)
	if player.cell() == start_cell:
		player.stall_ticks += 1
	else:
		player.stall_ticks = 0

	# 4. Núcleo: todos os subpassos, testando cada célula varrida
	if boss.alive and BossMotion.update(
		boss, board, rules, tick, ledger.permille, player, rng, director, events
	):
		lethal = true
		lethal_reason = DeathReason.BOSS_CONTACT

	# 5. diretor de ameaça (nunca nasce nada no tick de um fechamento)
	ThreatDirector.update(self, plan != null, events)

	# 6. atores menores
	var minor_contact := _minor_actors_update(events, plan == null)
	if minor_contact >= 0 and not lethal:
		lethal = true
		lethal_reason = minor_contact

	# 7. arbitragem: somente uma captura válida pode superar contato no mesmo tick.
	if lethal and plan is CapturePlan:
		if rules.lethal_contact_wins:
			plan = null
		else:
			lethal = false
	if lethal:
		# Movimento já consumiu os efeitos deste tick, mesmo quando termina em morte.
		_advance_effects(events)
		_die(lethal_reason, events)
		tick += 1
		return events

	# 8. Efeitos duram ticks completos de movimento/contato. Pickups deste commit
	# começam a contar no próximo tick; o escudo conserva o estado lido no início.
	_advance_effects(events)
	# aplicar plano
	if plan != null:
		if plan is CapturePlan:
			_commit_capture(plan as CapturePlan, events)
		else:
			var err := plan as CaptureError
			events.append(GameEvent.make(GameEvent.Kind.CAPTURE_REJECTED,
				{"code": err.code, "message": err.message}))
			_undo_trail(events)  # política da simulação: rejeição desfaz a trilha sem morte

	# 9. escudo
	if phase == Phase.PLAYING:
		var paused := (rules.shield_pauses_during_trail and player.trail_active) \
			or shield_frozen_this_tick or (items_enabled() and effects.active(ItemProfile.Kind.SHIELD_FREEZE))
		match shield.advance(rules, paused):
			ShieldClock.Outcome.CRITICAL:
				events.append(GameEvent.make(GameEvent.Kind.SHIELD_CRITICAL))
			ShieldClock.Outcome.EXPIRED:
				_die(DeathReason.SHIELD_EXPIRED, events)

	_advance_respawn_grace()
	tick += 1
	return events


func _advance_respawn_grace() -> void:
	if phase != Phase.PLAYING:
		return
	if director.respawn_grace_left > 0:
		director.respawn_grace_left -= 1
	player.lifecycle_ticks = director.respawn_grace_left
	player.lifecycle_state = ActorLifecycle.State.WARMUP if player.lifecycle_ticks > 0 else ActorLifecycle.State.ACTIVE


func _player_substeps() -> int:
	if not speedup_active and not (items_enabled() and effects.active(ItemProfile.Kind.VELOCITY)):
		return rules.substeps_normal
	if player.trail_active and player.segment_len < rules.new_segment_slow_px:
		return rules.substeps_normal
	return rules.substeps_speedup


func _anchor_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if boss.alive and round_def.boss_protects_territory:
		var c := boss.cell()
		out.append(board.index_of(c.x, c.y))
	return out


# --- atores menores ---------------------------------------------------------------------------

## O jogador andou para cima de um ator armado? Devolve a razão de morte ou -1.
func _player_touches_minor() -> int:
	if not minor_lethal_allowed():
		return -1
	var cell := player.cell()
	for slot in MinorActorPools.MAX_WALKERS:
		if pools.walker_alive(slot) and pools.walker_lifecycle(slot) == ActorLifecycle.State.ACTIVE \
			and pools.walker_cell(slot) == cell and WalkerRules.is_live_boundary(board, cell.x, cell.y):
			pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.HIT_PLAYER)
			return DeathReason.WALKER_CONTACT
	for slot in MinorActorPools.MAX_DARTS:
		if pools.dart_alive(slot) and pools.dart_lifecycle(slot) == ActorLifecycle.State.ACTIVE \
			and board.get_cell(cell.x, cell.y) == BoardState.Cell.TRAIL:
			var dart_cell := pools.dart_cell(slot)
			if absi(dart_cell.x - cell.x) <= 1 and absi(dart_cell.y - cell.y) <= 1:
				pools.set_dart(slot, MinorActorPools.D.REASON, MinorActorPools.Reason.HIT_PLAYER)
				return DeathReason.DART_CONTACT
	return -1


## Um tick de cada ator menor, em ordem de slot. Devolve a razão de morte ou -1.
func _minor_actors_update(events: Array[GameEvent], allow_spawn: bool = true) -> int:
	if not threat_enabled():
		return -1
	var profile := threat_profile()
	var lethal_allowed := minor_lethal_allowed()
	var lethal := -1
	var walker_speed: int = profile.ladder_walker_speed_fp[director.threat_index]
	for slot in MinorActorPools.MAX_WALKERS:
		if not pools.walker_alive(slot):
			continue
		var outcome := WalkerRules.update(pools, slot, board, walker_speed, profile.walker_dormant_ticks, profile.actor_despawn_ticks)
		if outcome == WalkerRules.StepOutcome.EXTINGUISHED:
			var cell := pools.walker_cell(slot)
			ledger.add(profile.walker_trap_points, events)
			events.append(GameEvent.make(GameEvent.Kind.WALKER_EXTINGUISHED, {
				"slot": slot, "x": cell.x, "y": cell.y, "points": profile.walker_trap_points}))
			continue
		if lethal < 0 and lethal_allowed and pools.walker_lifecycle(slot) == ActorLifecycle.State.ACTIVE \
			and pools.walker_cell(slot) == player.cell():
			pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.HIT_PLAYER)
			lethal = DeathReason.WALKER_CONTACT
	var cut_index: Array[int] = []
	for slot in MinorActorPools.MAX_DARTS:
		if not pools.dart_alive(slot):
			continue
		cut_index.clear()
		var outcome := DartRules.update(pools, slot, board, player, lethal_allowed, cut_index, profile.actor_despawn_ticks)
		match outcome:
			DartRules.Outcome.FIRED:
				events.append(GameEvent.make(GameEvent.Kind.DART_FIRED, {"slot": slot}))
			DartRules.Outcome.ABSORBED, DartRules.Outcome.EXPIRED:
				var cell := pools.dart_cell(slot)
				events.append(GameEvent.make(GameEvent.Kind.DART_ABSORBED, {
					"slot": slot, "x": cell.x, "y": cell.y}))
			DartRules.Outcome.CUT:
				var cell := pools.dart_cell(slot)
				var index: int = cut_index[0] if not cut_index.is_empty() else 0
				events.append(GameEvent.make(GameEvent.Kind.TRAIL_CUT, {
					"slot": slot, "trail_index": index, "x": cell.x, "y": cell.y}))
				var ember_slot := pools.free_ember_slot()
				if ember_slot >= 0 and allow_spawn:
					EmberRules.ignite(pools, ember_slot, index, MinorActorPools.Cause.CUT, profile.ember_warmup_ticks)
					events.append(GameEvent.make(GameEvent.Kind.EMBER_IGNITED, {
						"slot": ember_slot, "trail_index": index, "cause": MinorActorPools.Cause.CUT}))
			DartRules.Outcome.CONTACT:
				if lethal < 0:
					lethal = DeathReason.DART_CONTACT
	for slot in MinorActorPools.MAX_EMBERS:
		if not pools.ember_alive(slot):
			continue
		var outcome := EmberRules.update(pools, slot, player, profile.ember_speed_fp, profile.actor_despawn_ticks)
		if outcome == EmberRules.Outcome.CONTACT and lethal < 0 and lethal_allowed:
			lethal = DeathReason.EMBER_CONTACT
	return lethal


# --- captura ----------------------------------------------------------------------------------

func _commit_capture(plan: CapturePlan, events: Array[GameEvent]) -> void:
	var before := board.owned_interior
	if not board.apply_capture_plan(plan):
		events.append(GameEvent.make(GameEvent.Kind.CAPTURE_REJECTED,
			{"code": -1, "message": "board recusou o plano (versão %d ≠ %d)" % [plan.board_version, board.version]}))
		_undo_trail(events)
		return
	assert(board.owned_interior - before == plan.filled_delta)
	PlayerMotion.consolidate_trail(player)
	var old_permille := ledger.record_fill(board, rules, plan.filled_delta)
	events.append(GameEvent.make(GameEvent.Kind.CAPTURED, {
		"claimed": plan.claimed_indices.size(), "trail": plan.trail_indices.size(),
		"filled_delta": plan.filled_delta, "permille": ledger.permille}))
	if ledger.permille != old_permille:
		events.append(GameEvent.make(GameEvent.Kind.PERCENT_CHANGED, {"permille": ledger.permille}))
		ledger.add((ledger.permille - old_permille) * rules.area_points_per_permille, events)
	# Varredura pós-captura (§7.3: "logo a seguir a cada preenchimento, não continuamente").
	var extinguished := EmberRules.extinguish_all(pools, _actor_despawn_ticks())
	if extinguished > 0:
		events.append(GameEvent.make(GameEvent.Kind.EMBER_EXTINGUISHED, {"count": extinguished}))
	for slot in DartRules.absorb_grounded(pools, board, _actor_despawn_ticks()):
		var cell := pools.dart_cell(slot)
		events.append(GameEvent.make(GameEvent.Kind.DART_ABSORBED, {"slot": slot, "x": cell.x, "y": cell.y}))
	for slot in MinorActorPools.MAX_WALKERS:
		if pools.walker_alive(slot):
			var cell := pools.walker_cell(slot)
			if not WalkerRules.is_live_boundary(board, cell.x, cell.y):
				pools.set_walker(slot, MinorActorPools.W.STATE, ActorLifecycle.State.DORMANT)
				pools.set_walker(slot, MinorActorPools.W.REASON, MinorActorPools.Reason.DORMANT)
	ThreatDirector.on_capture(self, ledger.permille - old_permille, events)
	_capture_beacons(events)
	var free_remaining := board.interior_cell_count() - board.owned_interior
	var profile := item_profile()
	if items_enabled() and boss.alive and profile.sealed_free_cell_limit > 0 \
		and free_remaining <= profile.sealed_free_cell_limit:
		events.append(GameEvent.make(GameEvent.Kind.BOSS_SEALED, {"free_remaining": free_remaining}))
		_complete_round(GameRules.RoundEndReason.SEALED, events)
	elif ledger.permille >= rules.target_permille:
		_complete_round(GameRules.RoundEndReason.SINGLE_FILL if ledger.fills_done == 1
			else GameRules.RoundEndReason.TARGET, events)


func _complete_round(reason: int, events: Array[GameEvent]) -> void:
	phase = Phase.ROUND_WON
	round_end_reason = reason
	boss.begin_dying(_actor_despawn_ticks())
	var bonus := rules.completion_bonus
	var ladder := rules.bonus_ladder as BonusLadder
	if ladder != null and ladder.enabled:
		bonus = ladder.award(ledger.permille, reason, deaths_this_round == 0)
	ledger.add(bonus, events)
	events.append(GameEvent.make(GameEvent.Kind.ROUND_WON, {
		"permille": ledger.permille, "score": ledger.score, "reason": reason, "bonus": bonus}))


func _capture_beacons(events: Array[GameEvent]) -> void:
	if not items_enabled():
		return
	var first_event := events.size()
	var points := BeaconRules.capture_claimed(beacons, board, ledger.fills_done, item_profile(), events)
	var last_beacon_event := events.size()
	ledger.add(points, events)
	for index in range(first_event, last_beacon_event):
		if events[index].kind == GameEvent.Kind.BEACON_CAPTURED:
			_activate_item(int(events[index].data.item), events)


func _activate_item(kind: int, events: Array[GameEvent]) -> void:
	var profile := item_profile()
	if not items_enabled() or not effects.activate(kind, profile):
		return
	if kind == ItemProfile.Kind.STASIS:
		boss.stasis_ticks = effects.remaining[kind]
	if kind == ItemProfile.Kind.PURGE:
		for slot in MinorActorPools.MAX_WALKERS:
			if pools.walker_alive(slot):
				var cell := pools.walker_cell(slot)
				pools.retire_walker(slot, MinorActorPools.Reason.EXTINGUISHED, _actor_despawn_ticks())
				events.append(GameEvent.make(GameEvent.Kind.WALKER_EXTINGUISHED, {
					"slot": slot, "x": cell.x, "y": cell.y, "points": 0}))
		for slot in MinorActorPools.MAX_DARTS:
			if pools.dart_alive(slot):
				var cell := pools.dart_cell(slot)
				pools.retire_dart(slot, MinorActorPools.Reason.ABSORBED, _actor_despawn_ticks())
				events.append(GameEvent.make(GameEvent.Kind.DART_ABSORBED, {"slot": slot, "x": cell.x, "y": cell.y}))
		var extinguished := EmberRules.extinguish_all(pools, _actor_despawn_ticks())
		if extinguished > 0:
			events.append(GameEvent.make(GameEvent.Kind.EMBER_EXTINGUISHED, {"count": extinguished}))
		shield.ticks = maxi(shield.ticks, profile.shield_floor_ticks)
		if shield.ticks > rules.shield_critical_ticks:
			shield.critical_sent = false
	events.append(GameEvent.make(GameEvent.Kind.ITEM_STARTED, {"item": kind, "ticks": effects.remaining[kind]}))


func _advance_effects(events: Array[GameEvent]) -> void:
	if not items_enabled():
		return
	for kind in effects.advance():
		events.append(GameEvent.make(GameEvent.Kind.ITEM_ENDED, {"item": kind}))



func _actor_despawn_ticks() -> int:
	var profile := threat_profile()
	return profile.actor_despawn_ticks if profile != null else 0


func _undo_trail(events: Array[GameEvent]) -> void:
	PlayerMotion.undo_trail(player, board)
	var extinguished := EmberRules.extinguish_all(pools, _actor_despawn_ticks())
	if extinguished > 0:
		events.append(GameEvent.make(GameEvent.Kind.EMBER_EXTINGUISHED, {"count": extinguished}))


# --- morte ------------------------------------------------------------------------------------

func _die(reason: int, events: Array[GameEvent]) -> void:
	var had_trail := player.trail_active
	_undo_trail(events)  # §4.6: desfaz a trilha até o primeiro vértice; nenhum resíduo TRAIL
	if not had_trail:
		player.first_vertex = player.cell()
	lives -= 1
	deaths_this_round += 1
	phase = Phase.DYING
	death_ticks_left = rules.death_ticks
	player.lifecycle_state = ActorLifecycle.State.DYING
	player.lifecycle_ticks = death_ticks_left
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_DIED, {"reason": reason, "lives": lives}))


func _respawn(events: Array[GameEvent]) -> void:
	if lives <= 0:
		phase = Phase.GAME_OVER
		player.lifecycle_state = ActorLifecycle.State.DESPAWNED
		player.lifecycle_ticks = 0
		events.append(GameEvent.make(GameEvent.Kind.GAME_OVER))
		return
	player.px = player.first_vertex.x
	player.py = player.first_vertex.y
	player.pdir = MoveIntent.Dir.NONE
	player.stall_ticks = 0
	shield.reset(rules)
	var profile := threat_profile()
	director.respawn_grace_left = profile.respawn_grace_ticks if profile != null and profile.enabled else 0
	player.lifecycle_ticks = director.respawn_grace_left
	player.lifecycle_state = ActorLifecycle.State.WARMUP if player.lifecycle_ticks > 0 else ActorLifecycle.State.ACTIVE
	phase = Phase.PLAYING
	events.append(GameEvent.make(GameEvent.Kind.PLAYER_RESPAWNED, {"x": player.px, "y": player.py}))


# --- checksum ---------------------------------------------------------------------------------

## SHA-256 de todo o estado em bytes canônicos, ordem fixa. Nunca JSON/Dictionary/hash().
## A ordem abaixo é contrato: mudar exige bump de `GameRules.RULES_VERSION` e dourados novos.
func state_checksum() -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(board.canonical_bytes())
	var vals: Array[int] = [tick, phase, lives, death_ticks_left, 1 if speedup_active else 0, round_end_reason, deaths_this_round]
	vals.append_array(ledger.canonical_values())
	vals.append_array(shield.canonical_values())
	vals.append_array(player.canonical_values())
	vals.append_array(boss.canonical_values())
	vals.append_array(director.canonical_values())
	vals.append_array([rng.state, player.trail.size()])
	var b := PackedByteArray()
	b.resize(vals.size() * 4)
	for k in vals.size():
		b.encode_s32(k * 4, vals[k])
	ctx.update(b)
	if player.trail.size() > 0:
		ctx.update(player.trail.to_byte_array())
	ctx.update(pools.canonical_bytes())
	ctx.update(beacons.canonical_bytes())
	ctx.update(effects.canonical_bytes())
	return ctx.finish()
