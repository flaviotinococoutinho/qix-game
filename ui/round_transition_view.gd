class_name QixRoundTransitionView
extends Control
## Overlay de transição dirigido pela Phase/ticks reais da GameSession.

const PANEL_RECT := Rect2(22.0, 58.0, 196.0, 146.0)
const CONTROLS_RECT := Rect2(22.0, 214.0, 196.0, 84.0)
const CONTROL_ROW_Y := 22.0
const CONTROL_ROW_STEP := 12.0
const CONTROL_ROW_HEIGHT := 11.0
const CONTROL_LINES := [
	"SETAS / WASD  MOVER · ESPAÇO / Z  DESENHAR",
	"FECHE NA BORDA PARA CONQUISTAR A ÁREA",
	"TOQUE: STICK + DESENHAR · ESC / P  PAUSA",
	"F2  VISTA 2D / 2.5D · M  SOM",
	"F4  REDUZIR MOVIMENTO",
]
const PROGRESS_WIDTH := 160.0
const DEFAULT_ACCENT := Color("50e3c2")
const DEFAULT_THREAT := Color("ff4d6d")

## Ritmo vertical do painel, em coordenadas locais. Nomeado porque a linha de continuidade
## entrou entre o resultado e a barra: sem a grade explícita, o próximo ajuste volta a ser
## um número solto no meio do `_ready`.
const ROW_PHASE_Y := 11.0
const ROW_TITLE_Y := 29.0
const ROW_SUBTITLE_Y := 54.0
const ROW_RESULT_Y := 82.0
const ROW_CONTINUITY_Y := 95.0
const ROW_PROGRESS_Y := 111.0
const ROW_PROMPT_Y := 118.0
const ROW_INSET_X := 12.0
const ROW_WIDTH := 172.0

## Cadência da passagem, em fração do tempo de transição já decorrido.
##
## A barra de progresso é um relógio — ela conta quanto falta para a sessão avançar sozinha, e
## por isso continua linear: uma barra com aceleração mentiria sobre o tempo restante. O ritmo
## da passagem vive nas linhas, que entram em ordem de leitura em vez de nascerem todas no
## mesmo frame. A linha de continuidade (o que a incursão traz do setor anterior, ou o que
## este setor somou) é a última a entrar **de propósito**: ela é a resposta à pergunta que o
## jogador acabou de fazer ao campo, e entrar por último é o que a torna a batida da passagem.
##
## As frações são do total, não ticks absolutos, porque `intro_ticks` (60) e `clear_ticks`
## (120) diferem por 2×: em ticks fixos a intro terminaria antes de a cadência fechar.
const REVEAL_SUBTITLE := 0.14
const REVEAL_RESULT := 0.30
const REVEAL_CONTINUITY := 0.46
const REVEAL_PROMPT := 0.62

## O acento: pela duração abaixo, contada a partir da entrada da continuidade, a linha é
## escrita em `ACCENT_BEAT_COLOR` e a aresta do painel engrossa. Dois canais em vez de um
## porque 7 px de texto num painel escuro não sustentam sozinhos uma batida — e porque a
## aresta é decorativa: ela pode engrossar sem empurrar nenhuma linha (`ROW_INSET_X` = 12).
const ACCENT_SPAN := 0.18
const ACCENT_BEAT_COLOR := Color("f2ffff")
const EDGE_WIDTH := 3.0
const EDGE_BEAT_WIDTH := 5.0

var _scrim: ColorRect
var _panel: ColorRect
var _edge: ColorRect
var _phase_label: Label
var _title_label: Label
var _subtitle_label: Label
var _result_label: Label
var _continuity_label: Label
var _progress_fill: ColorRect
var _prompt_label: Label
var _controls: ColorRect
var _built: bool = false


func _ready() -> void:
	if _built:
		return
	_built = true
	position = Vector2.ZERO
	size = Vector2(CoordinateSpace.VIEWPORT.x, CoordinateSpace.VIEWPORT.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = _bar("Scrim", self, Vector2.ZERO, size, Color("02070bd1"))
	_bar("PanelShadow", self, PANEL_RECT.position + Vector2(3.0, 5.0), PANEL_RECT.size, Color("01040a99"))
	_panel = _bar("Panel", self, PANEL_RECT.position, PANEL_RECT.size, Color("07141af2"))
	_bar("PanelLight", _panel, Vector2.ZERO, Vector2(PANEL_RECT.size.x, 0.6), Color("95d8ef77"))
	_bar("PanelDepth", _panel, Vector2(0.0, PANEL_RECT.size.y - 2.0), Vector2(PANEL_RECT.size.x, 2.0), Color("020b13"))
	_edge = _bar("Edge", _panel, Vector2.ZERO, Vector2(EDGE_WIDTH, PANEL_RECT.size.y), DEFAULT_ACCENT)
	_phase_label = _label("Phase", _panel, Vector2(ROW_INSET_X, ROW_PHASE_Y), Vector2(ROW_WIDTH, 14.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_title_label = _label("Title", _panel, Vector2(ROW_INSET_X, ROW_TITLE_Y), Vector2(ROW_WIDTH, 23.0), 13, HORIZONTAL_ALIGNMENT_LEFT)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_label = _label("Subtitle", _panel, Vector2(ROW_INSET_X, ROW_SUBTITLE_Y), Vector2(ROW_WIDTH, 27.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label = _label("Result", _panel, Vector2(ROW_INSET_X, ROW_RESULT_Y), Vector2(ROW_WIDTH, 12.0), 8, HORIZONTAL_ALIGNMENT_LEFT)
	_continuity_label = _label("Continuity", _panel, Vector2(ROW_INSET_X, ROW_CONTINUITY_Y), Vector2(ROW_WIDTH, 12.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_bar("ProgressTrack", _panel, Vector2(ROW_INSET_X, ROW_PROGRESS_Y), Vector2(PROGRESS_WIDTH, 3.0), Color("1a343d"))
	_progress_fill = _bar("ProgressFill", _panel, Vector2(ROW_INSET_X, ROW_PROGRESS_Y), Vector2(0.0, 3.0), DEFAULT_ACCENT)
	_prompt_label = _label("Prompt", _panel, Vector2(ROW_INSET_X, ROW_PROMPT_Y), Vector2(ROW_WIDTH, 16.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_controls = _bar("Controls", self, CONTROLS_RECT.position, CONTROLS_RECT.size, Color("06121ee8"))
	_bar("ControlsEdge", _controls, Vector2.ZERO, Vector2(1.0, CONTROLS_RECT.size.y), Color("467a91"))
	var controls_title := _label("Legend", _controls, Vector2(10.0, 7.0), Vector2(176.0, 10.0), 6, HORIZONTAL_ALIGNMENT_LEFT)
	controls_title.text = "COMANDOS DO CARTÓGRAFO"
	controls_title.add_theme_color_override("font_color", Color("86b6c8"))
	for index in CONTROL_LINES.size():
		var row := _label("Command%d" % index, _controls,
			Vector2(10.0, CONTROL_ROW_Y + float(index) * CONTROL_ROW_STEP),
			Vector2(178.0, CONTROL_ROW_HEIGHT), 7, HORIZONTAL_ALIGNMENT_LEFT)
		row.text = CONTROL_LINES[index]
		row.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_controls.visible = false
	visible = false


func sync(session: GameSession, paused: bool = false, _events: Array[GameEvent] = []) -> void:
	if not _built:
		_ready()
	if session == null or session.simulation == null:
		visible = false
		return
	var visual := session.current_content().visual
	var accent := visual.accent_color if visual != null else DEFAULT_ACCENT
	var threat := visual.threat_color if visual != null else DEFAULT_THREAT
	_controls.visible = paused or session.phase == GameSession.Phase.ROUND_INTRO
	_edge.color = accent
	_progress_fill.color = accent
	_title_label.add_theme_color_override("font_color", accent)
	_phase_label.add_theme_color_override("font_color", visual.boundary_color if visual != null else Color.WHITE)

	_prompt_label.add_theme_color_override("font_color", Color("d9f7ff"))
	_continuity_label.add_theme_color_override("font_color", accent)

	if paused:
		visible = true
		_phase_label.text = "SISTEMA SUSPENSO"
		_title_label.text = "PAUSA"
		_subtitle_label.text = "A SIMULAÇÃO ESTÁ CONGELADA."
		_result_label.text = "PROGRESSO PRESERVADO"
		_continuity_label.text = _running_totals(session)
		_prompt_label.text = "ESC / P  ·  CONTINUAR"
		_progress_fill.size.x = PROGRESS_WIDTH
		# A pausa não é uma passagem: o painel abre inteiro, sem batida nenhuma.
		_apply_cadence(1.0, accent)
		return

	match session.phase:
		GameSession.Phase.PLAYING:
			visible = false
		GameSession.Phase.ROUND_INTRO:
			visible = true
			_phase_label.text = "SETOR %02d / %02d" % [session.current_round_number(), session.campaign.rounds.size()]
			_title_label.text = visual.display_name if visual != null else "SETOR SEM NOME"
			_subtitle_label.text = visual.subtitle if visual != null and not visual.subtitle.is_empty() else "RESTAURE A CARTOGRAFIA PERDIDA."
			@warning_ignore("integer_division")
			var target_percent := session.simulation.rules.target_permille / 10
			_result_label.text = "OBJETIVO  %02d%%" % target_percent
			_continuity_label.text = _carry_in_line(session)
			_prompt_label.text = "ENTER  ·  INICIAR AGORA"
			var progress := transition_progress(session)
			_set_progress(progress)
			_apply_cadence(progress, accent)
		GameSession.Phase.ROUND_CLEAR:
			visible = true
			_phase_label.text = "ROTA SEGURA  %02d / %02d" % [session.current_round_number(), session.campaign.rounds.size()]
			_title_label.text = "SETOR ESTABILIZADO"
			_subtitle_label.text = "%s · DADOS ORIGINAIS RECUPERADOS" % (
				visual.display_name if visual != null else "SETOR")
			_result_label.text = "%04.1f%% REVELADO" % (session.simulation.permille / 10.0)
			_continuity_label.text = _round_gain_line(session)
			_prompt_label.text = _next_sector_prompt(session)
			# O prompt herda o acento do *próximo* setor: a virada de paleta do arco
			# (ciano → âmbar → lima, `docs/ART_DIRECTION.md`) acontece na passagem, não
			# depois dela. É a ameaça crescente aparecendo antes de ser enfrentada.
			_prompt_label.add_theme_color_override("font_color", _next_accent(session, accent))
			var progress := transition_progress(session)
			_set_progress(progress)
			_apply_cadence(progress, accent)
		GameSession.Phase.GAME_OVER:
			visible = true
			_edge.color = threat
			_title_label.add_theme_color_override("font_color", threat)
			_phase_label.text = "SINAL PERDIDO"
			_title_label.text = "FIM DE JOGO"
			_subtitle_label.text = "A INCURSÃO FOI INTERROMPIDA."
			_result_label.text = "PONTUAÇÃO  %07d" % session.simulation.score
			_continuity_label.text = _sectors_cleared_line(session)
			_continuity_label.add_theme_color_override("font_color", threat)
			_prompt_label.text = "ENTER  ·  REINICIAR CAMPANHA"
			_set_progress(0.0)
			# Fim de jogo e campanha concluída não têm relógio de transição
			# (`transition_ticks_total` = 0): são estados terminais, e um painel que ainda se
			# monta por partes atrasaria a leitura de um resultado que já é definitivo.
			_apply_cadence(1.0, threat)
		GameSession.Phase.CAMPAIGN_COMPLETE:
			visible = true
			_phase_label.text = "TODOS OS SETORES ONLINE"
			_title_label.text = "CAMPANHA CONCLUÍDA"
			_subtitle_label.text = "A CARTOGRAFIA FOI INTEGRALMENTE RESTAURADA."
			_result_label.text = "PONTUAÇÃO FINAL  %07d" % session.simulation.score
			_continuity_label.text = _sectors_cleared_line(session)
			_prompt_label.text = "ENTER  ·  NOVA CAMPANHA"
			_set_progress(1.0)
			_apply_cadence(1.0, accent)


## Linha de continuidade da intro: o que a incursão trouxe do setor anterior. Sem ela, cada
## setor abria como se fosse o primeiro — o carry-in existia no domínio (`RoundStartState`)
## e não existia na tela, contra a barra de qualidade de `docs/ART_DIRECTION.md`.
func _carry_in_line(session: GameSession) -> String:
	var carry := session.simulation.round_start_state
	if session.round_index == 0:
		return "INCURSÃO NOVA  ·  L×%d" % carry.lives
	return "TRAZIDO  S %06d  ·  L×%d" % [carry.score, carry.lives]


## Linha de continuidade do clear: quanto *este* setor somou, não só o total acumulado.
## O ganho é a diferença entre o placar atual e o carry-in da rodada — ambos estado
## confirmado do domínio, lidos, nunca escritos.
func _round_gain_line(session: GameSession) -> String:
	var gained := session.simulation.score - session.simulation.round_start_state.score
	return "+%06d  ·  S %06d  ·  L×%d" % [
		maxi(0, gained),
		session.simulation.score,
		session.simulation.lives,
	]


func _running_totals(session: GameSession) -> String:
	return "S %06d  ·  L×%d" % [session.simulation.score, session.simulation.lives]


func _sectors_cleared_line(session: GameSession) -> String:
	var cleared := 0
	for record in session.records:
		if record.completed:
			cleared += 1
	return "SETORES ESTABILIZADOS  %02d / %02d" % [cleared, session.campaign.rounds.size()]


## O clear aponta para frente nomeando o próximo setor. "PRÓXIMO SETOR" descrevia a mecânica;
## o nome do destino descreve a incursão.
func _next_sector_prompt(session: GameSession) -> String:
	var next_index := session.round_index + 1
	if next_index >= session.campaign.rounds.size():
		return "ENTER  ·  FECHAR A CARTOGRAFIA"
	var next_visual := session.campaign.rounds[next_index].visual
	if next_visual == null or next_visual.display_name.is_empty():
		return "ENTER  ·  PRÓXIMO SETOR"
	return "ENTER  ·  %s" % next_visual.display_name


func _next_accent(session: GameSession, fallback: Color) -> Color:
	var next_index := session.round_index + 1
	if next_index >= session.campaign.rounds.size():
		return fallback
	var next_visual := session.campaign.rounds[next_index].visual
	return next_visual.accent_color if next_visual != null else fallback


## Fração concluída da transição atual, derivada dos dois contadores inteiros da sessão.
## Mora aqui, e não em `GameSession`, porque o domínio não fala em float (invariante 1).
static func transition_progress(session: GameSession) -> float:
	if session.transition_ticks_total <= 0:
		return 1.0
	return clampf(
		1.0 - float(session.transition_ticks_left) / float(session.transition_ticks_total),
		0.0,
		1.0,
	)


## Encena a passagem a partir do progresso **já confirmado** pela sessão. Não mede tempo, não
## guarda contador próprio e não antecipa fase nenhuma: recebe a mesma fração que a barra e
## decide o que já está em cena (invariante 6). Uma transição de duração zero — pausa, fim de
## jogo, campanha concluída — chega aqui com 1.0 e abre o painel inteiro.
func _apply_cadence(progress: float, settled_color: Color) -> void:
	var elapsed := clampf(progress, 0.0, 1.0)
	_subtitle_label.visible = elapsed >= REVEAL_SUBTITLE
	_result_label.visible = elapsed >= REVEAL_RESULT
	_continuity_label.visible = elapsed >= REVEAL_CONTINUITY
	_prompt_label.visible = elapsed >= REVEAL_PROMPT
	_continuity_label.add_theme_color_override(
		"font_color", settled_color.lerp(ACCENT_BEAT_COLOR, _beat(elapsed)))
	_edge.size.x = lerpf(EDGE_WIDTH, EDGE_BEAT_WIDTH, _beat(elapsed))


## Força da batida: 1.0 no frame em que a continuidade entra, 0.0 ao fim de `ACCENT_SPAN`.
## Decai em vez de piscar porque um degrau de um frame é ruído a 60 Hz, não ênfase — a mesma
## razão pela qual o contador de percentagem sobe em degraus com atraso (ADR-0009).
func _beat(elapsed: float) -> float:
	if elapsed < REVEAL_CONTINUITY:
		return 0.0
	return clampf(1.0 - (elapsed - REVEAL_CONTINUITY) / ACCENT_SPAN, 0.0, 1.0)


func _set_progress(value: float) -> void:
	_progress_fill.size.x = roundf(PROGRESS_WIDTH * clampf(value, 0.0, 1.0))


func _bar(
	node_name: String,
	parent: Control,
	node_position: Vector2,
	node_size: Vector2,
	color: Color,
) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = node_name
	bar.position = node_position
	bar.size = node_size
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _label(
	node_name: String,
	parent: Control,
	node_position: Vector2,
	node_size: Vector2,
	font_size: int,
	alignment: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("d9f7ff"))
	parent.add_child(label)
	# Resolver o tema antes do retângulo evita manter os 23 px mínimos da fonte padrão.
	label.position = node_position
	label.size = node_size
	return label
