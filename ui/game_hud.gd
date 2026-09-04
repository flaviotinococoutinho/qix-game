class_name QixGameHud
extends Control
## HUD compacto de campanha. Lê GameSession ou GameSimulation e nunca escreve no domínio.

const HUD_COLOR := Color("d9f7ff")
const ACCENT_COLOR := Color("50e3c2")
const WARNING_COLOR := Color("ffd166")
const DANGER_COLOR := Color("ff4d6d")
const BAR_COLOR := Color("050b10ed")
const TRACK_COLOR := Color("17303a")
const OBJECTIVE_WIDTH := 50.0
const SHIELD_WIDTH := 86.0

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
var _built: bool = false


func _ready() -> void:
	if _built:
		return
	_built = true
	position = Vector2.ZERO
	size = Vector2(CoordinateSpace.VIEWPORT.x, CoordinateSpace.VIEWPORT.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_bar("TopBar", Vector2.ZERO, Vector2(240.0, 19.0), BAR_COLOR)
	_add_bar("BottomBar", Vector2(0.0, 302.0), Vector2(240.0, 18.0), BAR_COLOR)

	_round_label = _add_label("Round", Vector2(3.0, 1.0), Vector2(34.0, 14.0), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_score_label = _add_label("Score", Vector2(36.0, 1.0), Vector2(61.0, 14.0), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_percent_label = _add_label("Percent", Vector2(98.0, 1.0), Vector2(50.0, 14.0), HORIZONTAL_ALIGNMENT_CENTER, 7)
	_percent_label.add_theme_color_override("font_color", ACCENT_COLOR)
	_vitals_label = _add_label("Vitals", Vector2(150.0, 1.0), Vector2(87.0, 14.0), HORIZONTAL_ALIGNMENT_RIGHT, 7)

	_add_bar("ObjectiveTrack", Vector2(98.0, 16.0), Vector2(OBJECTIVE_WIDTH, 2.0), TRACK_COLOR)
	_objective_fill = _add_bar("ObjectiveFill", Vector2(98.0, 16.0), Vector2.ZERO, ACCENT_COLOR)
	_objective_fill.size.y = 2.0
	_add_bar("ShieldTrack", Vector2(151.0, 16.0), Vector2(SHIELD_WIDTH, 2.0), TRACK_COLOR)
	_shield_fill = _add_bar("ShieldFill", Vector2(151.0, 16.0), Vector2.ZERO, HUD_COLOR)
	_shield_fill.size.y = 2.0

	_round_title_label = _add_label(
		"RoundTitle", Vector2(3.0, 303.0), Vector2(91.0, 14.0), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_round_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label = _add_label(
		"Status", Vector2(96.0, 303.0), Vector2(141.0, 14.0), HORIZONTAL_ALIGNMENT_RIGHT, 7)
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
	_percent_label.text = "%04.1f/%02d" % [simulation.permille / 10.0, target_percent]
	_vitals_label.text = "L×%d  E%02d" % [simulation.lives, _shield_seconds(simulation)]
	_round_title_label.text = visual.display_name if visual != null else "SETOR ATIVO"
	_status_label.text = _status_text(simulation, session, paused)

	var objective_ratio := clampf(float(simulation.permille) / float(target), 0.0, 1.0)
	_objective_fill.size.x = roundf(OBJECTIVE_WIDTH * objective_ratio)
	var shield_ratio := clampf(float(simulation.shield_ticks) / float(maxi(1, simulation.rules.shield_ticks)), 0.0, 1.0)
	_shield_fill.size.x = roundf(SHIELD_WIDTH * shield_ratio)
	_shield_fill.color = DANGER_COLOR if shield_ratio <= 0.17 else (
		WARNING_COLOR if shield_ratio <= 0.34 else (visual.accent_color if visual != null else HUD_COLOR)
	)
	if _flash_ticks > 0:
		_flash_ticks -= 1


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
