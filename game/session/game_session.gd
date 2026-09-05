class_name GameSession
extends RefCounted
## Máquina determinística de campanha. Uma GameSimulation e um ReplayLog por rodada.
##
## Contrato de `records`: uma rodada só é arquivada pela via PLAYING → vitória/derrota
## (`_archive_current_round`). Forçar `phase` num teste não arquiva nada. Quem conta rodadas
## concluídas conta `records` com `completed == true`.
## Progresso da transição é (total − restantes) / total: a conversão para float é da view
## (`QixRoundTransitionView.transition_progress`), porque o domínio só fala em inteiros.

enum Phase { ROUND_INTRO, PLAYING, ROUND_CLEAR, GAME_OVER, CAMPAIGN_COMPLETE }

var campaign: CampaignDefinition
var phase: int = Phase.ROUND_INTRO
var round_index: int = 0
var transition_ticks_left: int = 0
var transition_ticks_total: int = 0
var simulation: GameSimulation
var replay: ReplayLog
var records: Array[RoundRunRecord] = []
var _current_archived: bool = false


func _init(definition: CampaignDefinition) -> void:
	assert(definition != null, "CampaignDefinition obrigatória")
	assert(definition.validation_errors().is_empty(), "CampaignDefinition inválida: %s" % str(definition.validation_errors()))
	campaign = definition
	_start_current_round(RoundStartState.initial(current_content().rules))


func current_content() -> RoundContent:
	return campaign.rounds[round_index]


func current_round_number() -> int:
	return round_index + 1


func is_gameplay_active() -> bool:
	return phase == Phase.PLAYING


## Avança exatamente um tick da sessão. Intents só entram no replay durante PLAYING.
func step(intent: MoveIntent, confirm: bool = false) -> Array[GameEvent]:
	var events: Array[GameEvent] = []
	match phase:
		Phase.ROUND_INTRO:
			_tick_intro(confirm, events)
		Phase.PLAYING:
			replay.record(intent)
			events.append_array(simulation.step(intent))
			if simulation.phase == GameSimulation.Phase.ROUND_WON:
				_archive_current_round(true)
				_enter_phase(Phase.ROUND_CLEAR, campaign.clear_ticks)
				events.append(GameEvent.make(GameEvent.Kind.ROUND_CLEAR_STARTED, {
					"round_index": round_index,
					"round_id": current_content().round_id,
					"score": simulation.score,
				}))
			elif simulation.phase == GameSimulation.Phase.GAME_OVER:
				_archive_current_round(false)
				_enter_phase(Phase.GAME_OVER, 0)
		Phase.ROUND_CLEAR:
			_tick_clear(confirm, events)
		Phase.GAME_OVER, Phase.CAMPAIGN_COMPLETE:
			pass
	return events


func restart_campaign() -> void:
	records.clear()
	round_index = 0
	_start_current_round(RoundStartState.initial(current_content().rules))


func _tick_intro(confirm: bool, events: Array[GameEvent]) -> void:
	if confirm:
		transition_ticks_left = 0
	else:
		transition_ticks_left -= 1
	if transition_ticks_left <= 0:
		_enter_phase(Phase.PLAYING, 0)
		events.append(GameEvent.make(GameEvent.Kind.ROUND_STARTED, {
			"round_index": round_index,
			"round_id": current_content().round_id,
		}))


func _tick_clear(confirm: bool, events: Array[GameEvent]) -> void:
	if confirm:
		transition_ticks_left = 0
	else:
		transition_ticks_left -= 1
	if transition_ticks_left > 0:
		return
	if round_index + 1 >= campaign.rounds.size():
		_enter_phase(Phase.CAMPAIGN_COMPLETE, 0)
		events.append(GameEvent.make(GameEvent.Kind.CAMPAIGN_COMPLETE, {
			"score": simulation.score,
			"rounds": campaign.rounds.size(),
		}))
		return
	var carry := RoundStartState.carry_from(simulation)
	round_index += 1
	_start_current_round(carry)
	events.append(GameEvent.make(GameEvent.Kind.ROUND_INTRO_STARTED, {
		"round_index": round_index,
		"round_id": current_content().round_id,
	}))


func _start_current_round(start_state: RoundStartState) -> void:
	var content := current_content()
	simulation = GameSimulation.new(
		content.rules,
		content.round_definition,
		content.seed_value,
		start_state,
	)
	replay = ReplayLog.start(simulation)
	_current_archived = false
	if campaign.intro_ticks > 0:
		_enter_phase(Phase.ROUND_INTRO, campaign.intro_ticks)
	else:
		_enter_phase(Phase.PLAYING, 0)


func _archive_current_round(completed: bool) -> void:
	if _current_archived:
		return
	var record := RoundRunRecord.new()
	record.round_id = current_content().round_id
	record.round_index = round_index
	record.completed = completed
	record.start_state = simulation.round_start_state.duplicate_state()
	record.replay = replay
	record.final_checksum = simulation.state_checksum()
	record.final_tick = simulation.tick
	record.final_score = simulation.score
	record.final_lives = simulation.lives
	records.append(record)
	_current_archived = true


func _enter_phase(next_phase: int, duration_ticks: int) -> void:
	phase = next_phase
	transition_ticks_left = maxi(0, duration_ticks)
	transition_ticks_total = maxi(0, duration_ticks)
