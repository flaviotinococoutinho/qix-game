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
var _flash_message: String = ""
var _flash_ticks: int = 0
var _shown_permille: int = -1
var _counter_delay: int = 0
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


## `source` pode ser uma sessão M2 ou a simulação G1, preservando integrações existentes.
func sync(source: Variant, paused: bool, events: Array[GameEvent]) -> void:
	if not _built:
		_ready()
	var simulation := _simulation_from(source)
	if simulation == null:
		return
	_capture_flash(events)
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
	_score_label.text = "S %06d" % simulation.score
	var target := maxi(1, simulation.rules.target_permille)
	@warning_ignore("integer_division")
	var target_percent := target / 10
	_advance_shown_permille(simulation.permille)
	_percent_label.text = "%04.1f/%02d" % [_shown_permille / 10.0, target_percent]
	_vitals_label.text = "L×%d  E%02d" % [simulation.lives, _shield_seconds(simulation)]
	_round_title_label.text = visual.display_name if visual != null else "SETOR ATIVO"
	_status_label.text = _status_text(simulation, session, paused)

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
		return
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


func _simulation_from(source: Variant) -> GameSimulation:
	if source is GameSession:
		return (source as GameSession).simulation
	if source is GameSimulation:
		return source as GameSimulation
	return null


func _shield_seconds(simulation: GameSimulation) -> int:
	return maxi(0, ceili(simulation.shield_ticks / 60.0))


func _capture_flash(events: Array[GameEvent]) -> void:
	for event in events:
		match event.kind:
			GameEvent.Kind.CAPTURED:
				_flash_message = "CAPTURA +%d" % event.data.get("filled_delta", 0)
				_flash_ticks = 75
			GameEvent.Kind.PLAYER_DIED:
				var reason: int = event.data.get("reason", GameSimulation.DeathReason.BOSS_CONTACT)
				if reason == GameSimulation.DeathReason.SHIELD_EXPIRED:
					_flash_message = "ESCUDO ESGOTADO · REENTRADA"
				else:
					_flash_message = "CONTATO! · REENTRADA"
				_flash_ticks = 45
			GameEvent.Kind.SHIELD_CRITICAL:
				_flash_message = "ESCUDO CRÍTICO"
				_flash_ticks = 120


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
			if _flash_ticks > 0:
				return _flash_message
			return "REENTRADA EM CURSO"
	if _flash_ticks > 0:
		return _flash_message
	if simulation.trail_active:
		# A trilha longa já dói no campo (luminância e ritmo do pulso); aqui ela ganha nome, para
		# que o jogador consiga dizer *quando* ficou exposto em vez de só descobrir no impacto.
		if TrailExposure.is_warning(TrailExposure.of_simulation(simulation)):
			return "EXPOSTO · VOLTE À BORDA"
		return "FECHE NA BORDA"
	return "DESENHE · ESPAÇO/Z"


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
	# Entrar na árvore resolve o tema; definir o retângulo depois evita os 23 px padrão.
	label.position = node_position
	label.size = node_size
	return label
