class_name QixBootstrap
extends Node
## Composition root e host de tick fixo da campanha autorável.
##
## Latência de entrada (F1, spec §10): `Input.use_accumulated_input = false` para que cada
## evento de tecla/toque chegue individualmente ao adaptador (acumular junta press e release do
## mesmo tick num evento só e perde o toque curto), e `input_devices/buffering/agile_event_flushing`
## no `project.godot` para a fila ser drenada antes de cada tick físico, não só por quadro.
## `GameInputAdapter.begin_tick()` abre cada tick antes da amostra: é o relógio de ticks que
## envelhece latch, buffer de curva e memória de release — nenhum `Time.*` participa.

const FramePacingProbeNode := preload("res://tools/profile/frame_pacing_probe_node.gd")
const FramebufferProbeNode := preload("res://tools/shipping/framebuffer_shader_probe_node.gd")

@export var campaign: CampaignDefinition
@export var show_touch_controls_on_desktop: bool = false
@export var depth_stage_enabled: bool = true
@export var audio_enabled: bool = true

@onready var board_view: QixBoardView = $BoardView
@onready var enemy_view: QixEnemyView = $EnemyView
@onready var player_view: QixPlayerView = $PlayerView
@onready var capture_vfx: QixCaptureVfx = $CaptureVfx
@onready var hud: QixGameHud = $HUD
@onready var round_transition: QixRoundTransitionView = $RoundTransition
@onready var shipping_feedback: QixFeedbackHub = $ShippingFeedback
@onready var touch_controls: QixTouchControls = $TouchControls

var session: GameSession
var paused: bool = false
var _input_adapter := GameInputAdapter.new()
var _shipping_audio_smoke_requested_ticks: int = 0
var _shipping_audio_smoke_completed_ticks: int = 0
var depth_stage: QixDepthStage
var minor_actor_view: QixMinorActorView
var actor_trace: QixActorTraceOverlay

var simulation: GameSimulation:
	get:
		return null if session == null else session.simulation

var replay: ReplayLog:
	get:
		return null if session == null else session.replay


func _ready() -> void:
	assert(campaign != null, "CampaignDefinition precisa estar ligada à cena")
	assert(campaign.validation_errors().is_empty(), "CampaignDefinition inválida: %s" % str(campaign.validation_errors()))
	Input.use_accumulated_input = false
	var touch_active := OS.has_feature("mobile") or show_touch_controls_on_desktop
	touch_controls.touch_enabled = touch_active
	touch_controls.visible = touch_active
	_input_adapter.attach_touch_controls(touch_controls)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	minor_actor_view = QixMinorActorView.new()
	minor_actor_view.name = "MinorActorView"
	minor_actor_view.z_index = 12
	add_child(minor_actor_view)
	depth_stage = QixDepthStage.new()
	depth_stage.name = "DepthStage"
	add_child(depth_stage)
	depth_stage.mount(self, [board_view, enemy_view, minor_actor_view, player_view, capture_vfx])
	depth_stage.set_enabled(depth_stage_enabled)
	shipping_feedback.set_feedback_enabled(audio_enabled, true)
	actor_trace = QixActorTraceOverlay.new()
	actor_trace.name = "ActorTrace"
	actor_trace.z_index = 60
	add_child(actor_trace)
	_start_campaign()
	_start_exported_shipping_audio_smoke()
	_start_exported_shipping_probe()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			actor_trace.visible = not actor_trace.visible
			actor_trace.sync(session, _input_adapter)
			return
		if event.physical_keycode == KEY_F2:
			depth_stage.set_enabled(not depth_stage.enabled)
			_sync_views([])
			return
		if event.physical_keycode == KEY_F4:
			depth_stage.reduced_motion = not depth_stage.reduced_motion
			_sync_views([])
			return
		if event.physical_keycode == KEY_M:
			audio_enabled = not audio_enabled
			shipping_feedback.set_feedback_enabled(audio_enabled, true)
			return
	_input_adapter.handle_event(event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_input_adapter.reset_transient_state()
		if is_instance_valid(touch_controls):
			touch_controls.clear_state()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_input_adapter.handle_joy_connection_changed(device, connected)


func _physics_process(_delta: float) -> void:
	_input_adapter.begin_tick()
	_process_input_tick(
		Input.is_action_just_pressed("pause"),
		Input.is_action_just_pressed("ui_accept"),
	)
	if _record_shipping_audio_smoke_physics_tick():
		print(
			"QIX_SHIPPING_AUDIO_SMOKE_COMPLETE requested_ticks=%d completed_ticks=%d physics_ticks_per_second=%d"
			% [
				_shipping_audio_smoke_requested_ticks,
				_shipping_audio_smoke_completed_ticks,
				Engine.physics_ticks_per_second,
			],
		)
		get_tree().quit(0)


## Snapshot injetável para provar a arbitragem InputMap/evento cru entre ticks.
func _process_input_tick(
	input_map_pause_just_pressed: bool,
	input_map_confirm_just_pressed: bool,
) -> void:
	# Os dois latches são drenados no mesmo tick, sempre. Sair cedo pelo ramo da pausa
	# sem drenar o confirmar deixava-o pendurado para o tick seguinte, onde ele valia
	# por um pedido feito noutro ecrã: carregar em A e em START na mesma janela de
	# frame no fim de jogo pausava e, um tick depois, reiniciava a campanha.
	var pause_requested := _input_adapter.consume_pause(
		input_map_pause_just_pressed,
	)
	var confirm_requested := _input_adapter.consume_confirm(
		input_map_confirm_just_pressed,
	)
	if pause_requested:
		paused = not paused
		_sync_views([])
		return
	if session.phase == GameSession.Phase.GAME_OVER \
		or session.phase == GameSession.Phase.CAMPAIGN_COMPLETE:
		if confirm_requested:
			_start_campaign()
		return
	if paused:
		return
	var intent := MoveIntent.none()
	if session.is_gameplay_active():
		intent = _input_adapter.sample(session.simulation.pdir)
	var events := session.step(intent, confirm_requested)
	_sync_views(events)


func _start_campaign() -> void:
	session = GameSession.new(campaign)
	paused = false
	_input_adapter.reset_transient_state()
	touch_controls.clear_state()
	_sync_views([])


func _sync_views(events: Array[GameEvent]) -> void:
	var content := session.current_content()
	board_view.sync(session.simulation, content.visual)
	enemy_view.sync(session.simulation, content.visual)
	minor_actor_view.sync(session.simulation, content.visual)
	player_view.sync(session.simulation, content.visual)
	capture_vfx.sync(session, events)
	hud.sync(session, paused, events)
	round_transition.sync(session, paused, events)
	shipping_feedback.sync(session, events, paused)
	var terminal_alpha := terminal_actor_alpha(session)
	enemy_view.modulate.a = terminal_alpha
	minor_actor_view.modulate.a = terminal_alpha
	depth_stage.sync(session.simulation, content.visual, events, terminal_alpha)
	actor_trace.sync(session, _input_adapter)


static func terminal_actor_alpha(source: GameSession) -> float:
	if source.phase == GameSession.Phase.CAMPAIGN_COMPLETE:
		return 0.0
	if source.phase == GameSession.Phase.ROUND_CLEAR:
		var elapsed := source.transition_ticks_total - source.transition_ticks_left
		return clampf(1.0 - float(elapsed)/24.0, 0.0, 1.0)
	return 1.0


func _start_exported_shipping_audio_smoke() -> void:
	var requested_ticks := shipping_audio_smoke_ticks(
		OS.get_cmdline_user_args(),
		OS.has_feature("shipping_qa"),
	)
	if requested_ticks < 0:
		printerr(
			"QIX_SHIPPING_AUDIO_SMOKE_ERROR --shipping-audio-smoke-ticks exige um único inteiro positivo",
		)
		get_tree().quit(2)
		return
	if requested_ticks == 0:
		return
	_shipping_audio_smoke_requested_ticks = requested_ticks
	_shipping_audio_smoke_completed_ticks = 0
	print(
		"QIX_SHIPPING_AUDIO_SMOKE_START requested_ticks=%d physics_ticks_per_second=%d"
		% [requested_ticks, Engine.physics_ticks_per_second],
	)


func _record_shipping_audio_smoke_physics_tick() -> bool:
	if _shipping_audio_smoke_requested_ticks <= 0 \
			or _shipping_audio_smoke_completed_ticks >= _shipping_audio_smoke_requested_ticks:
		return false
	_shipping_audio_smoke_completed_ticks += 1
	return _shipping_audio_smoke_completed_ticks == _shipping_audio_smoke_requested_ticks


func _start_exported_shipping_probe() -> void:
	# Official export templates do not reliably honor `--script` against their
	# embedded PCK. Shipping-QA builds therefore dispatch a bounded probe from the
	# real main scene using user arguments after `--`.
	if not OS.has_feature("shipping_qa"):
		return
	var arguments := OS.get_cmdline_user_args()
	var probe_name := shipping_probe_name(arguments)
	match probe_name:
		"":
			return
		"frame-pacing":
			var frame_probe = FramePacingProbeNode.new()
			frame_probe.name = "ShippingFramePacingProbe"
			add_child(frame_probe)
			frame_probe.start(self, arguments)
		"framebuffer":
			var framebuffer_probe = FramebufferProbeNode.new()
			framebuffer_probe.name = "ShippingFramebufferProbe"
			add_child(framebuffer_probe)
			framebuffer_probe.start(arguments, self)
		_:
			printerr("QIX_SHIPPING_PROBE_ERROR probe desconhecido: " + probe_name)
			get_tree().quit(2)


static func shipping_probe_name(arguments: PackedStringArray) -> String:
	for argument in arguments:
		if argument.begins_with("--shipping-probe="):
			return argument.trim_prefix("--shipping-probe=").strip_edges()
	return ""


static func shipping_audio_smoke_ticks(
	arguments: PackedStringArray,
	shipping_qa_enabled: bool,
) -> int:
	if not shipping_qa_enabled:
		return 0
	var found := false
	var parsed_ticks := 0
	for argument in arguments:
		if not argument.begins_with("--shipping-audio-smoke-ticks="):
			continue
		if found:
			return -1
		found = true
		var raw_ticks := argument.trim_prefix("--shipping-audio-smoke-ticks=").strip_edges()
		if not raw_ticks.is_valid_int():
			return -1
		parsed_ticks = raw_ticks.to_int()
		if parsed_ticks <= 0:
			return -1
	return parsed_ticks if found else 0
