extends TestCase

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"


class BootstrapWithoutViews:
	extends QixBootstrap

	func _sync_views(_events: Array[GameEvent]) -> void:
		pass


## `_start_campaign` real depende de `$TouchControls`, que não existe num bootstrap
## construído sem cena. Contar a chamada prova a mesma coisa sem montar a árvore.
class BootstrapCountingRestarts:
	extends BootstrapWithoutViews

	var restarts: int = 0

	func _start_campaign() -> void:
		restarts += 1


func test_start_from_input_map_and_raw_gamepad_toggles_pause_only_once() -> void:
	Input.action_release(&"pause")
	var bootstrap := _ready_bootstrap()
	if bootstrap == null:
		return

	var start_down := InputEventJoypadButton.new()
	start_down.button_index = JOY_BUTTON_START
	start_down.pressed = true
	bootstrap._unhandled_input(start_down)
	bootstrap._process_input_tick(true, false)
	eq(bootstrap.paused, true, "Start deve pausar no primeiro tick")

	bootstrap._process_input_tick(false, false)
	eq(
		bootstrap.paused,
		true,
		"o edge cru duplicado pelo InputMap não pode despausar no tick seguinte",
	)
	_dispose_bootstrap(bootstrap)


func test_a_from_input_map_and_raw_gamepad_confirms_only_one_transition() -> void:
	Input.action_release(&"ui_accept")
	var bootstrap := _ready_bootstrap()
	if bootstrap == null:
		return
	bootstrap.session.phase = GameSession.Phase.ROUND_CLEAR
	bootstrap.session.transition_ticks_left = 120
	bootstrap.session.transition_ticks_total = 120

	var confirm_down := InputEventJoypadButton.new()
	confirm_down.button_index = JOY_BUTTON_A
	confirm_down.pressed = true
	bootstrap._unhandled_input(confirm_down)
	bootstrap._process_input_tick(false, true)
	eq(bootstrap.session.round_index, 1, "A deve avançar para a rodada seguinte")
	eq(
		bootstrap.session.phase,
		GameSession.Phase.ROUND_INTRO,
		"o primeiro edge confirma apenas o encerramento da rodada",
	)

	bootstrap._process_input_tick(false, false)
	eq(
		bootstrap.session.phase,
		GameSession.Phase.ROUND_INTRO,
		"o edge cru duplicado não pode também pular a intro no tick seguinte",
	)
	_dispose_bootstrap(bootstrap)


func test_pause_edge_does_not_leave_a_confirm_latched_for_the_next_tick() -> void:
	Input.action_release(&"pause")
	Input.action_release(&"ui_accept")
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "a campanha real precisa carregar")
	if campaign == null:
		return
	var bootstrap := BootstrapCountingRestarts.new()
	bootstrap.campaign = campaign
	bootstrap.session = GameSession.new(campaign)
	bootstrap.session.phase = GameSession.Phase.GAME_OVER

	# O ecrã de fim de jogo é o único onde confirmar reinicia a campanha. O jogador
	# que carrega em A e em START na mesma janela de frame pediu uma pausa — não uma
	# corrida nova.
	var confirm_down := InputEventJoypadButton.new()
	confirm_down.button_index = JOY_BUTTON_A
	confirm_down.pressed = true
	bootstrap._unhandled_input(confirm_down)
	var start_down := InputEventJoypadButton.new()
	start_down.button_index = JOY_BUTTON_START
	start_down.pressed = true
	bootstrap._unhandled_input(start_down)

	bootstrap._process_input_tick(false, false)
	eq(bootstrap.paused, true, "o edge de pausa vence o tick")
	eq(bootstrap.restarts, 0, "pausar não reinicia a campanha")

	bootstrap._process_input_tick(false, false)
	eq(
		bootstrap.restarts,
		0,
		"o confirmar enfileirado no tick da pausa não pode reiniciar a campanha no tick seguinte",
	)
	_dispose_bootstrap(bootstrap)


func _ready_bootstrap() -> QixBootstrap:
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	ok(campaign != null, "a campanha real precisa carregar")
	if campaign == null:
		return null
	var bootstrap := BootstrapWithoutViews.new()
	bootstrap.campaign = campaign
	bootstrap.session = GameSession.new(campaign)
	return bootstrap


func _dispose_bootstrap(bootstrap: QixBootstrap) -> void:
	Input.action_release(&"pause")
	Input.action_release(&"ui_accept")
	if is_instance_valid(bootstrap):
		bootstrap.free()
