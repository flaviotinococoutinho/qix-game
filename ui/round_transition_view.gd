class_name QixRoundTransitionView
extends Control
## Overlay de transição dirigido pela Phase/ticks reais da GameSession.

const PANEL_RECT := Rect2(22.0, 87.0, 196.0, 146.0)
const PROGRESS_WIDTH := 160.0
const DEFAULT_ACCENT := Color("50e3c2")
const DEFAULT_THREAT := Color("ff4d6d")

var _scrim: ColorRect
var _panel: ColorRect
var _edge: ColorRect
var _phase_label: Label
var _title_label: Label
var _subtitle_label: Label
var _result_label: Label
var _progress_fill: ColorRect
var _prompt_label: Label
var _built: bool = false


func _ready() -> void:
	if _built:
		return
	_built = true
	position = Vector2.ZERO
	size = Vector2(CoordinateSpace.VIEWPORT.x, CoordinateSpace.VIEWPORT.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = _bar("Scrim", self, Vector2.ZERO, size, Color("02070bd1"))
	_panel = _bar("Panel", self, PANEL_RECT.position, PANEL_RECT.size, Color("07141af2"))
	_edge = _bar("Edge", _panel, Vector2.ZERO, Vector2(3.0, PANEL_RECT.size.y), DEFAULT_ACCENT)
	_phase_label = _label("Phase", _panel, Vector2(12.0, 11.0), Vector2(172.0, 14.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_title_label = _label("Title", _panel, Vector2(12.0, 29.0), Vector2(172.0, 23.0), 13, HORIZONTAL_ALIGNMENT_LEFT)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_label = _label("Subtitle", _panel, Vector2(12.0, 54.0), Vector2(172.0, 27.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label = _label("Result", _panel, Vector2(12.0, 84.0), Vector2(172.0, 14.0), 8, HORIZONTAL_ALIGNMENT_LEFT)
	_bar("ProgressTrack", _panel, Vector2(12.0, 104.0), Vector2(PROGRESS_WIDTH, 3.0), Color("1a343d"))
	_progress_fill = _bar("ProgressFill", _panel, Vector2(12.0, 104.0), Vector2(0.0, 3.0), DEFAULT_ACCENT)
	_prompt_label = _label("Prompt", _panel, Vector2(12.0, 116.0), Vector2(172.0, 18.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
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
	_edge.color = accent
	_progress_fill.color = accent
	_title_label.add_theme_color_override("font_color", accent)
	_phase_label.add_theme_color_override("font_color", visual.boundary_color if visual != null else Color.WHITE)

	if paused:
		visible = true
		_phase_label.text = "SISTEMA SUSPENSO"
		_title_label.text = "PAUSA"
		_subtitle_label.text = "A SIMULAÇÃO ESTÁ CONGELADA."
		_result_label.text = "PROGRESSO PRESERVADO"
		_prompt_label.text = "ESC / P  ·  CONTINUAR"
		_progress_fill.size.x = PROGRESS_WIDTH
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
			_prompt_label.text = "ENTER  ·  INICIAR AGORA"
			_set_progress(session.transition_progress())
		GameSession.Phase.ROUND_CLEAR:
			visible = true
			_phase_label.text = "ROTA SEGURA  %02d / %02d" % [session.current_round_number(), session.campaign.rounds.size()]
			_title_label.text = "SETOR ESTABILIZADO"
			_subtitle_label.text = "%s · DADOS ORIGINAIS RECUPERADOS" % (
				visual.display_name if visual != null else "SETOR")
			_result_label.text = "%04.1f%% REVELADO" % (session.simulation.permille / 10.0)
			_prompt_label.text = "ENTER  ·  PRÓXIMO SETOR"
			_set_progress(session.transition_progress())
		GameSession.Phase.GAME_OVER:
			visible = true
			_edge.color = threat
			_title_label.add_theme_color_override("font_color", threat)
			_phase_label.text = "SINAL PERDIDO"
			_title_label.text = "FIM DE JOGO"
			_subtitle_label.text = "A INCURSÃO FOI INTERROMPIDA."
			_result_label.text = "PONTUAÇÃO  %07d" % session.simulation.score
			_prompt_label.text = "ENTER  ·  REINICIAR CAMPANHA"
			_set_progress(0.0)
		GameSession.Phase.CAMPAIGN_COMPLETE:
			visible = true
			_phase_label.text = "TODOS OS SETORES ONLINE"
			_title_label.text = "CAMPANHA CONCLUÍDA"
			_subtitle_label.text = "A CARTOGRAFIA FOI INTEGRALMENTE RESTAURADA."
			_result_label.text = "PONTUAÇÃO FINAL  %07d" % session.simulation.score
			_prompt_label.text = "ENTER  ·  NOVA CAMPANHA"
			_set_progress(1.0)


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
	label.position = node_position
	label.size = node_size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("d9f7ff"))
	parent.add_child(label)
	return label
