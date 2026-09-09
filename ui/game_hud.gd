class_name QixGameHud
extends Control
## HUD compacto de campanha. Lê GameSession ou GameSimulation e nunca escreve no domínio.

const HUD_COLOR := Color("d9f7ff")
const ACCENT_COLOR := Color("50e3c2")
const WARNING_COLOR := Color("ffd166")
const DANGER_COLOR := Color("ff4d6d")
const BAR_COLOR := Color("050b10ed")
const TRACK_COLOR := Color("17303a")

## Grade do HUD. A aritmética abaixo é verificada por `tests/unit/game_hud_layout_test.gd`:
## margens iguais, blocos sem sobreposição, trilho alinhado ao rótulo que ele anota e texto
## de pior caso cabendo no retângulo. Mudou um número aqui, o teste diz se a banda ainda fecha.
const MARGIN := 3.0
const GUTTER := 4.0
const TOP_BAR_HEIGHT := 19.0
const BOTTOM_BAR_Y := 302.0
const BOTTOM_BAR_HEIGHT := 18.0
const TEXT_HEIGHT := 14.0
const TOP_TEXT_Y := 1.0
const TRACK_Y := 16.0
const TRACK_HEIGHT := 2.0
## 302 + 2 acima + 14 de texto + 2 abaixo = 320: o rodapé respira igual dos dois lados.
const BOTTOM_TEXT_Y := 304.0

## Blocos da banda superior, da esquerda para a direita.
## A percentagem e o escudo são instrumentos: cada um governa a largura do próprio trilho, e
## o trilho do objetivo é o mais largo porque é a leitura primária de "quanto falta".
const ROUND_X := 3.0
const ROUND_WIDTH := 20.0
const SCORE_X := 27.0
const SCORE_WIDTH := 34.0
const OBJECTIVE_X := 65.0
const OBJECTIVE_WIDTH := 86.0
const SHIELD_X := 155.0
const SHIELD_WIDTH := 82.0

## Blocos da banda inferior.
const TITLE_X := 3.0
const TITLE_WIDTH := 91.0
const STATUS_X := 98.0
const STATUS_WIDTH := 139.0

## Hierarquia tipográfica: a percentagem é o único campo promovido.
##
## Dos 22 campos numéricos do HUD do Volfied, o da percentagem é o único que pede a fonte
## alternativa — a de dígitos grandes (`reference/volfied/07-texto-e-fonte.md` §5.1, campo 4,
## `fonte: 1`; a fonte em §2.3). O que se adota aqui é o comportamento, não os tiles: num
## campo de 240×320 o número que responde "quanto falta" precisa pesar mais que a pontuação,
## que é balanço, e que as vitais, que já têm o trilho do escudo a gritar por elas.
const PRIMARY_FONT_SIZE := 9
const SECONDARY_FONT_SIZE := 7

## Escada de denominações do contador de percentagem, adotada de `hud_area_pct_step`
## (`reference/volfied/06-gameplay.md §6.3`): o contador fecha primeiro as dezenas de %, depois
## as unidades, por fim os décimos — por isso uma conquista grande *rola* mais tempo que uma
## pequena sem que a subida fique arrastada.
const COUNTER_DECADE_STEP := 100  ## 10,0 %
const COUNTER_UNIT_STEP := 10     ## 1,0 %
## Atrasos entre passos, em ticks. No original eram 1 frame ou nenhum porque o contador corria
## numa pausa dedicada de fim de ronda; aqui ele corre durante o jogo, então estes são os
## números **deste** jogo: fecham uma conquista típica (~8 %) em ~24 ticks e o campo inteiro em
## menos de um segundo, tempo bastante para a subida ser lida sem disputar a atenção do campo.
const COUNTER_DECADE_DELAY := 3
const COUNTER_UNIT_DELAY := 2
const COUNTER_TENTH_DELAY := 1

var _round_label: Label
var _score_label: Label
var _percent_label: Label
var _vitals_label: Label
var _round_title_label: Label
var _status_label: Label
var _objective_fill: ColorRect
var _shield_fill: ColorRect
var _phase_segments: Array[ColorRect] = []
var _threat_segments: Array[ColorRect] = []
var _threat_index: int = 0
var _boss_phase: int = 0
var _actor_count: int = 0
var _beacon_count: int = 0
var _beacons_captured: int = 0
var _effect_ticks := PackedInt32Array()
var _flash_message: String = ""
var _flash_ticks: int = 0
var _flash_is_alert: bool = false
var _flash_kind: int = -1
var _flash_actor_id: int = -1
var _flash_simulation: GameSimulation
## Causa da última morte **observada**, ou `-1` enquanto nenhuma foi. Não é um flash com prazo
## próprio: quem lhe dá duração é a fase DYING do domínio. Ver `_status_text`.
var _death_reason: int = -1
var _shown_permille: int = -1
var _counter_delay: int = 0
var _shown_score: int = -1
var _climbing: bool = false
var _climb_from_permille: int = 0
var _climb_from_score: int = 0
var _built: bool = false


func _ready() -> void:
	if _built:
		return
	_built = true
	position = Vector2.ZERO
	size = Vector2(CoordinateSpace.VIEWPORT.x, CoordinateSpace.VIEWPORT.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_bar("TopBar", Vector2.ZERO, Vector2(CoordinateSpace.VIEWPORT.x, TOP_BAR_HEIGHT), BAR_COLOR)
	_add_bar(
		"BottomBar",
		Vector2(0.0, BOTTOM_BAR_Y),
		Vector2(CoordinateSpace.VIEWPORT.x, BOTTOM_BAR_HEIGHT),
		BAR_COLOR)

	_round_label = _add_label(
		"Round", Vector2(ROUND_X, TOP_TEXT_Y), Vector2(ROUND_WIDTH, TEXT_HEIGHT),
		HORIZONTAL_ALIGNMENT_LEFT, SECONDARY_FONT_SIZE)
	_score_label = _add_label(
		"Score", Vector2(SCORE_X, TOP_TEXT_Y), Vector2(SCORE_WIDTH, TEXT_HEIGHT),
		HORIZONTAL_ALIGNMENT_LEFT, SECONDARY_FONT_SIZE)
	_percent_label = _add_label(
		"Percent", Vector2(OBJECTIVE_X, TOP_TEXT_Y), Vector2(OBJECTIVE_WIDTH, TEXT_HEIGHT),
		HORIZONTAL_ALIGNMENT_CENTER, PRIMARY_FONT_SIZE)
	_percent_label.add_theme_color_override("font_color", ACCENT_COLOR)
	_vitals_label = _add_label(
		"Vitals", Vector2(SHIELD_X, TOP_TEXT_Y), Vector2(SHIELD_WIDTH, TEXT_HEIGHT),
		HORIZONTAL_ALIGNMENT_RIGHT, SECONDARY_FONT_SIZE)

	_add_bar(
		"ObjectiveTrack", Vector2(OBJECTIVE_X, TRACK_Y),
		Vector2(OBJECTIVE_WIDTH, TRACK_HEIGHT), TRACK_COLOR)
	_objective_fill = _add_bar(
		"ObjectiveFill", Vector2(OBJECTIVE_X, TRACK_Y), Vector2.ZERO, ACCENT_COLOR)
	_objective_fill.size.y = TRACK_HEIGHT
	_add_bar(
		"ShieldTrack", Vector2(SHIELD_X, TRACK_Y),
		Vector2(SHIELD_WIDTH, TRACK_HEIGHT), TRACK_COLOR)
	_shield_fill = _add_bar(
		"ShieldFill", Vector2(SHIELD_X, TRACK_Y), Vector2.ZERO, HUD_COLOR)
	_shield_fill.size.y = TRACK_HEIGHT

	_round_title_label = _add_label(
		"RoundTitle", Vector2(TITLE_X, BOTTOM_TEXT_Y), Vector2(TITLE_WIDTH, TEXT_HEIGHT),
		HORIZONTAL_ALIGNMENT_LEFT, SECONDARY_FONT_SIZE)
	_round_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label = _add_label(
		"Status", Vector2(STATUS_X, BOTTOM_TEXT_Y), Vector2(STATUS_WIDTH, TEXT_HEIGHT),
		HORIZONTAL_ALIGNMENT_RIGHT, SECONDARY_FONT_SIZE)
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# A área livre sob setor/score comporta instrumentos discretos de fase e pressão.
	# Permanecem na banda superior: nenhum pixel adicional cobre o campo.
	for index in 3:
		_phase_segments.append(_add_bar(
			"BossPhase%d" % index, Vector2(ROUND_X + float(index) * 7.0, TRACK_Y),
			Vector2(5.0, TRACK_HEIGHT), TRACK_COLOR))
	var pressure_step := SCORE_WIDTH / float(ThreatProfile.LADDER_SIZE)
	for index in ThreatProfile.LADDER_SIZE:
		_threat_segments.append(_add_bar(
			"ThreatLevel%d" % index, Vector2(SCORE_X + float(index) * pressure_step, TRACK_Y),
			Vector2(pressure_step - 0.6, TRACK_HEIGHT), TRACK_COLOR))


## `source` pode ser uma sessão M2 ou a simulação G1, preservando integrações existentes.
func sync(source: Variant, paused: bool, events: Array[GameEvent]) -> void:
	if not _built:
		_ready()
	var simulation := _simulation_from(source)
	if simulation == null:
		return
	_capture_flash(events, simulation)
	var session := source as GameSession if source is GameSession else null
	var visual: RoundVisualDefinition = null
	var round_number := 1
	var round_count := 1
	if session != null:
		round_number = session.current_round_number()
		round_count = session.campaign.rounds.size()
		visual = session.current_content().visual
	_apply_visual(visual)

	_round_label.text = "R %d/%d" % [round_number, round_count]
	var target := maxi(1, simulation.rules.target_permille)
	@warning_ignore("integer_division")
	var target_percent := target / 10
	# A ordem importa: o contador de área abre a subida e fixa os âncoras que a pontuação segue.
	_advance_shown_permille(simulation.permille)
	_advance_shown_score(simulation.score, simulation.permille)
	_score_label.text = "S %06d" % _shown_score
	_percent_label.text = "%04.1f/%02d" % [_shown_permille / 10.0, target_percent]
	_vitals_label.text = "L×%d  E%02d" % [simulation.lives, _shield_seconds(simulation)]
	if simulation.items_enabled() and simulation.beacons.count > 0:
		_vitals_label.text += "  B%d/%d" % [simulation.beacons.captured_count(), simulation.beacons.count]
	_round_title_label.text = visual.display_name if visual != null else "SETOR ATIVO"
	_status_label.text = _status_text(simulation, session, paused)
	_sync_threat_instruments(simulation, visual)

	var objective_ratio := clampf(float(_shown_permille) / float(target), 0.0, 1.0)
	_objective_fill.size.x = roundf(OBJECTIVE_WIDTH * objective_ratio)
	var shield_ratio := clampf(float(simulation.shield_ticks) / float(maxi(1, simulation.rules.shield_ticks)), 0.0, 1.0)
	_shield_fill.size.x = roundf(SHIELD_WIDTH * shield_ratio)
	_shield_fill.color = DANGER_COLOR if shield_ratio <= 0.17 else (
		WARNING_COLOR if shield_ratio <= 0.34 else (visual.accent_color if visual != null else HUD_COLOR)
	)
	if _flash_ticks > 0:
		_flash_ticks -= 1


## Aproxima o valor mostrado da percentagem **já confirmada** pelo domínio, um degrau por tick.
## Só a subida é encenada: a primeira leitura e qualquer regressão (rodada nova, reinício)
## assentam de imediato, porque um contador a descer devagar mostraria território que o jogador
## já não tem. O contador nunca ultrapassa nem antecipa o domínio — ele atrasa (invariante 6).
func _advance_shown_permille(target: int) -> void:
	if _shown_permille < 0 or target <= _shown_permille:
		_shown_permille = target
		_counter_delay = 0
		_climbing = false
		return
	if not _climbing:
		# Começa aqui uma subida. Os âncoras congelam o par (área, pontuação) de onde os dois
		# números partem, para que percorram o mesmo caminho e pousem no mesmo tick.
		_climbing = true
		_climb_from_permille = _shown_permille
		_climb_from_score = _shown_score
	if _counter_delay > 0:
		_counter_delay -= 1
		return
	var gap := target - _shown_permille
	if gap >= COUNTER_DECADE_STEP:
		_shown_permille += COUNTER_DECADE_STEP
		_counter_delay = COUNTER_DECADE_DELAY
	elif gap >= COUNTER_UNIT_STEP:
		_shown_permille += COUNTER_UNIT_STEP
		_counter_delay = COUNTER_UNIT_DELAY
	else:
		_shown_permille += 1
		_counter_delay = COUNTER_TENTH_DELAY


## Encena a pontuação **pelo caminho da área**: a cada tick o número mostrado fecha a mesma fração
## do seu intervalo que o contador de percentagem já fechou, e por isso os dois pousam no valor
## confirmado no mesmo tick. É o comportamento de `hud_area_pct_step`
## (`reference/volfied/06-gameplay.md §6.3`), onde cada degrau do contador *paga* pontos e é isso
## que faz o número da banda superior pulsar junto com a área — traduzido para aqui, onde a
## pontuação é do domínio e chega inteira num tick: o HUD não decide quantos pontos a conquista
## vale, só escreve o valor já confirmado no mesmo ritmo em que pinta o mapa que o pagou.
##
## Fora de uma subida de área a pontuação assenta de imediato. O gotejo da trilha
## (`rules.trail_score_points` a cada `trail_score_every_px`) é de poucos pontos e contínuo:
## encená-lo seria ruído a competir com a única subida que significa alguma coisa.
func _advance_shown_score(target_score: int, target_permille: int) -> void:
	var span := target_permille - _climb_from_permille
	if _shown_score < 0 or target_score <= _shown_score or not _climbing or span <= 0:
		_shown_score = target_score
		return
	var closed := _shown_permille - _climb_from_permille
	@warning_ignore("integer_division")
	var staged := _climb_from_score + (target_score - _climb_from_score) * closed / span
	# Uma segunda captura no meio da subida alarga o intervalo de área e faria a fração recuar.
	# O contador de área nunca desce (ADR-0009) e a pontuação também não pode: um número a descer
	# diria ao jogador que ele perdeu pontos que acabou de ganhar.
	_shown_score = maxi(_shown_score, staged)


func _simulation_from(source: Variant) -> GameSimulation:
	if source is GameSession:
		return (source as GameSession).simulation
	if source is GameSimulation:
		return source as GameSimulation
	return null


func _shield_seconds(simulation: GameSimulation) -> int:
	return maxi(0, ceili(simulation.shield_ticks / 60.0))


func _capture_flash(events: Array[GameEvent], simulation: GameSimulation) -> void:
	# O snapshot já contém o tick inteiro: resolver o aviso antes de arbitrar o ganho
	# também cobre CAPTURED vindo antes de EMBER_EXTINGUISHED/DART_ABSORBED no mesmo lote.
	if _flash_is_alert and (_flash_simulation != simulation \
			or _alert_resolved(simulation, _flash_kind, _flash_actor_id)):
		_clear_flash()
	for event in events:
		match event.kind:
			GameEvent.Kind.CAPTURED:
				_set_flash("CAPTURA +%d" % event.data.get("filled_delta", 0), 75, false)
			GameEvent.Kind.PLAYER_DIED:
				_death_reason = event.data.get("reason", GameSimulation.DeathReason.BOSS_CONTACT)
				# A morte não entra na fila de flashes: ela tem fase própria no domínio e a linha
				# de estado passa a ser dela até à reentrada. Zerar o prazo pendente impede que um
				# "CAPTURA +n" ou um "ESCUDO CRÍTICO" anterior reapareça do outro lado da morte,
				# anunciando um estado que o jogador já não tem.
				_clear_flash()
			GameEvent.Kind.PLAYER_RESPAWNED:
				# A causa deixa de existir no mesmo tick em que o jogador recupera o controlo.
				_death_reason = -1
			GameEvent.Kind.SHIELD_CRITICAL:
				_set_alert(event, simulation, "ESCUDO CRÍTICO", 120)
			GameEvent.Kind.DART_ARMED:
				_set_alert(event, simulation, "DARDO ARMADO · DESVIE", 30)
			GameEvent.Kind.TRAIL_CUT:
				_set_alert(event, simulation, "TRILHA CORTADA · CONTINUE!", 75)
			GameEvent.Kind.EMBER_IGNITED:
				_set_alert(event, simulation, "BRASA NA TRILHA · AVANCE", 60)
			GameEvent.Kind.WALKER_EXTINGUISHED:
				_set_flash("VAGALUME CONTIDO +%d" % event.data.get("points", 0), 60, false)
			GameEvent.Kind.BOSS_PHASE_CHANGED:
				_set_alert(event, simulation, "NÚCLEO · FASE %d" % (int(event.data.get("phase", 0)) + 1), 100)
			GameEvent.Kind.BOSS_CORNERED:
				_set_alert(event, simulation, "NÚCLEO EM FÚRIA", 75)
			GameEvent.Kind.OVERTIME_STARTED:
				_set_alert(event, simulation, "PRESSÃO MÁXIMA · AVANCE", 100)
			GameEvent.Kind.BEACON_CAPTURED:
				_set_flash(
					"BALIZA ×%d  +%d" % [event.data.get("chain", 1), event.data.get("points", 0)],
					90,
					false,
				)
			GameEvent.Kind.ITEM_STARTED:
				_set_flash("%s ATIVO" % _item_name(int(event.data.get("item", 0))), 75, false)
			GameEvent.Kind.BOSS_SEALED:
				_set_flash("NÚCLEO SELADO", 100, false)


## Escreve a linha de flash respeitando a hierarquia de `docs/ART_DIRECTION.md` §Hierarquia 4:
## «o alerta de perigo conserva prioridade sobre recompensas».
##
## O slot é único e era do último a escrever, sem olhar a quem. Isso invertia a hierarquia no
## caso mais comum do jogo: as balizas ficam no chão livre, que é onde os dardos armam. Meio
## segundo depois de "DARDO ARMADO · DESVIE" (30 ticks) o jogador colhe a baliza que estava a
## perseguir, e "BALIZA ×2  +240" ocupa a linha por 90 ticks — pontos por cima do único aviso
## sobre o qual ainda dava para agir, e três vezes mais tempo do que o aviso teria durado.
##
## A regra: um alerta toma a linha sempre, inclusive de outro alerta — a ameaça mais nova é a
## que ainda pede decisão. Uma recompensa só entra com a linha livre de alerta; caso contrário
## é descartada, não enfileirada. Descartar é honesto porque o ganho não depende desta linha:
## ele já está a ser pago, degrau a degrau, no contador de pontuação (ADR-0009), e a baliza
## conta em `B n/m` na linha de vitais. O aviso não tem segunda casa.
##
## Continua apresentação pura: lê eventos já confirmados e não devolve nada ao domínio
## (invariante 6). Trocar a hierarquia não pode mexer em checksum (invariante 8).
func _set_flash(message: String, ticks: int, is_alert: bool) -> void:
	if not is_alert and _flash_ticks > 0 and _flash_is_alert:
		return
	_flash_message = message
	_flash_ticks = ticks
	_flash_is_alert = is_alert
	_flash_kind = -1
	_flash_actor_id = -1
	_flash_simulation = null


func _clear_flash() -> void:
	_flash_message = ""
	_flash_ticks = 0
	_flash_is_alert = false
	_flash_kind = -1
	_flash_actor_id = -1
	_flash_simulation = null


func _set_alert(event: GameEvent, simulation: GameSimulation, message: String, ticks: int) -> void:
	var actor_id := -1
	if event.kind == GameEvent.Kind.DART_ARMED:
		var slot := int(event.data.get("slot", -1))
		if slot >= 0 and slot < MinorActorPools.MAX_DARTS:
			actor_id = simulation.pools.dart_actor_id(slot)
	# Um aviso pode nascer e ser resolvido no mesmo tick; não o ressuscitar pelo evento antigo.
	if _alert_resolved(simulation, event.kind, actor_id):
		return
	_set_flash(message, ticks, true)
	_flash_kind = event.kind
	_flash_actor_id = actor_id
	_flash_simulation = simulation


## Cada aviso conserva a própria causa: absorver outro dardo não resolve este, e extinguir
## uma brasa não cura o escudo. IDs também distinguem a reutilização de um slot do mesmo ator.
func _alert_resolved(simulation: GameSimulation, kind: int, actor_id: int) -> bool:
	match kind:
		GameEvent.Kind.DART_ARMED:
			for slot in MinorActorPools.MAX_DARTS:
				if simulation.pools.dart_alive(slot) and simulation.pools.dart_actor_id(slot) == actor_id:
					return false
			return true
		GameEvent.Kind.EMBER_IGNITED:
			return not simulation.trail_active or simulation.pools.alive_embers() == 0
		GameEvent.Kind.TRAIL_CUT:
			return not simulation.trail_active
		GameEvent.Kind.SHIELD_CRITICAL:
			return simulation.shield_ticks > simulation.rules.shield_critical_ticks
	return false


func _status_text(simulation: GameSimulation, session: GameSession, paused: bool) -> String:
	if paused:
		return "PAUSA · ESC/P continua"
	if session != null:
		match session.phase:
			GameSession.Phase.ROUND_INTRO:
				return "CALIBRANDO SETOR"
			GameSession.Phase.ROUND_CLEAR:
				return "ÁREA SEGURA"
			GameSession.Phase.CAMPAIGN_COMPLETE:
				return "CAMPANHA CONCLUÍDA"
			GameSession.Phase.GAME_OVER:
				return "FIM DE JOGO"
	match simulation.phase:
		GameSimulation.Phase.ROUND_WON:
			return "ÁREA SEGURA · ENTER"
		GameSimulation.Phase.GAME_OVER:
			return "FIM DE JOGO · ENTER"
		GameSimulation.Phase.DYING:
			# A causa da morte dura exatamente a fase que o domínio abriu para ela
			# (`rules.death_ticks`), não um prazo próprio do HUD. Antes eram 45 ticks fixos: com o
			# `death_ticks` padrão (60) a causa sumia nos últimos 15 quadros da sequência, e com
			# qualquer `death_ticks` abaixo de 45 ela sobrevivia à reentrada e cobria a linha do
			# jogo vivo. Contato e escudo esgotado são erros diferentes e pedem correções
			# diferentes: o nome do erro tem de durar o tempo em que o jogador está a olhar para
			# ele, e acabar quando ele volta a ter o controlo.
			# Defendido por `tests/unit/death_status_duration_test.gd`.
			if _death_reason == GameSimulation.DeathReason.SHIELD_EXPIRED:
				return "ESCUDO ESGOTADO · REENTRADA"
			if _death_reason >= 0:
				return "CONTATO! · REENTRADA"
			# Ninguém observou o evento — a fase foi vista já a decorrer. O HUD não inventa uma
			# causa que não lhe foi confirmada (invariante 6).
			return "REENTRADA EM CURSO"
	if _flash_ticks > 0:
		return _flash_message
	if simulation.trail_active:
		# A trilha longa já dói no campo (luminância e ritmo do pulso); aqui ela ganha nome, para
		# que o jogador consiga dizer *quando* ficou exposto em vez de só descobrir no impacto.
		if TrailExposure.is_warning(TrailExposure.of_simulation(simulation)):
			return "EXPOSTO · VOLTE À BORDA"
		return "FECHE NA BORDA"
	if simulation.items_enabled():
		var effects := _effect_status(simulation)
		if not effects.is_empty():
			return effects
	if simulation.threat_enabled():
		if simulation.director.calm_ticks > 0:
			return "TRÉGUA · TRACE A PRÓXIMA ROTA"
		return "FASE %d · PRESSÃO %d" % [simulation.boss.phase + 1, simulation.director.threat_index + 1]
	return "DESENHE · ESPAÇO/Z"


func _sync_threat_instruments(simulation: GameSimulation, visual: RoundVisualDefinition) -> void:
	_threat_index = simulation.director.threat_index
	_boss_phase = simulation.boss.phase
	_actor_count = simulation.pools.alive_total()
	_beacon_count = simulation.beacons.count
	_beacons_captured = simulation.beacons.captured_count()
	_effect_ticks = simulation.effects.remaining.duplicate()
	var accent := visual.accent_color if visual != null else ACCENT_COLOR
	for index in _phase_segments.size():
		_phase_segments[index].visible = simulation.threat_enabled()
		_phase_segments[index].color = accent if index <= _boss_phase else TRACK_COLOR
	for index in _threat_segments.size():
		_threat_segments[index].visible = simulation.threat_enabled()
		_threat_segments[index].color = (
			DANGER_COLOR if _threat_index >= 3 else WARNING_COLOR
		) if index <= _threat_index else TRACK_COLOR
	_status_label.add_theme_color_override("font_color", (
		DANGER_COLOR if simulation.trail_active and simulation.pools.alive_embers() > 0
		else HUD_COLOR
	))


func presentation_state() -> Dictionary:
	return {
		"phase": _boss_phase, "pressure": _threat_index, "minor_actors": _actor_count,
		"beacons": _beacon_count, "beacons_captured": _beacons_captured, "effects": _effect_ticks.duplicate(),
	}


func _effect_status(simulation: GameSimulation) -> String:
	var labels := PackedStringArray()
	for kind in [ItemProfile.Kind.VELOCITY, ItemProfile.Kind.STASIS, ItemProfile.Kind.SHIELD_FREEZE]:
		if simulation.effects.active(kind):
			labels.append("%s %ds" % [_item_name(kind), ceili(simulation.effects.remaining[kind] / 60.0)])
	return " · ".join(labels)


func _item_name(kind: int) -> String:
	match kind:
		ItemProfile.Kind.VELOCITY: return "IMPULSO"
		ItemProfile.Kind.STASIS: return "ESTASE"
		ItemProfile.Kind.SHIELD_FREEZE: return "ESCUDO"
		ItemProfile.Kind.PURGE: return "PURGA"
	return "ITEM"


func _apply_visual(visual: RoundVisualDefinition) -> void:
	var accent := visual.accent_color if visual != null else ACCENT_COLOR
	var boundary := visual.boundary_color if visual != null else HUD_COLOR
	_percent_label.add_theme_color_override("font_color", accent)
	_round_label.add_theme_color_override("font_color", boundary)
	_round_title_label.add_theme_color_override("font_color", accent)
	_objective_fill.color = accent


func _add_bar(node_name: String, node_position: Vector2, node_size: Vector2, color: Color) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = node_name
	bar.position = node_position
	bar.size = node_size
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar


func _add_label(
	node_name: String,
	node_position: Vector2,
	node_size: Vector2,
	alignment: HorizontalAlignment,
	font_size: int,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", HUD_COLOR)
	add_child(label)
	# O retângulo é definido **depois** de entrar na árvore porque `size` é clampado para cima
	# pelo mínimo do `Label`, e esse mínimo só vale o da fonte pedida com o tema já resolvido.
	# Numa árvore que já processa — o caso do jogo — isso vale já no `add_child`, e a linha
	# assenta em `TEXT_HEIGHT`. Construído antes do primeiro frame (só o runner de testes faz
	# isso), o mínimo ainda é o do tema padrão, 23 px, e a altura pedida é ignorada; o `size`
	# fica preso nos 23 px mesmo depois de o mínimo relaxar, porque Godot nunca re-encolhe.
	# Medido em 2026-09-06 por `tools/verify_hud_row_geometry.gd`, que é quem defende isto.
	label.position = node_position
	label.size = node_size
	return label
