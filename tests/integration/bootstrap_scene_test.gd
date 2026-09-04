extends TestCase

const MAIN_SCENE := "res://app/bootstrap.tscn"


func test_main_scene_contract_exists_and_instantiates() -> void:
	if not ResourceLoader.exists(MAIN_SCENE):
		ok(false, "a cena principal declarada em project.godot precisa existir")
		return
	var packed := load(MAIN_SCENE) as PackedScene
	ok(packed != null, "bootstrap.tscn precisa carregar como PackedScene")
	if packed == null:
		return
	var root := packed.instantiate()
	ok(root != null, "bootstrap.tscn precisa instanciar")
	if root == null:
		return
	eq(root.name, "Bootstrap")
	ok(root.get_node_or_null("BoardView") != null, "BoardView ausente")
	ok(root.get_node_or_null("EnemyView") != null, "EnemyView ausente")
	ok(root.get_node_or_null("PlayerView") != null, "PlayerView ausente")
	ok(root.get_node_or_null("HUD") != null, "HUD ausente")
	root.free()


func test_main_scene_wires_authorable_campaign_and_transition_layers() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	ok(packed != null, "bootstrap.tscn precisa carregar como PackedScene")
	if packed == null:
		return
	var root := packed.instantiate()
	ok(root.get("campaign") is CampaignDefinition, "campanha autorável precisa estar ligada à cena")
	ok(root.get_node_or_null("CaptureVfx") != null, "CaptureVfx ausente")
	ok(root.get_node_or_null("RoundTransition") != null, "RoundTransition ausente")
	root.free()


func test_shipping_feedback_and_touch_controls_are_wired_at_the_composition_root() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	ok(packed != null, "bootstrap.tscn precisa carregar como PackedScene")
	if packed == null:
		return
	var root := packed.instantiate()
	var feedback := root.get_node_or_null("ShippingFeedback")
	var touch := root.get_node_or_null("TouchControls")
	ok(feedback is QixFeedbackHub, "áudio e hápticos precisam estar ligados à cena")
	ok(touch is QixTouchControls, "overlay touch vetorial precisa estar ligado à cena")
	if touch is Control:
		eq((touch as Control).anchors_preset, Control.PRESET_FULL_RECT)
		eq((touch as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	root.free()


func test_shipping_probe_dispatch_is_explicit_and_never_steals_normal_startup() -> void:
	eq(QixBootstrap.shipping_probe_name(PackedStringArray()), "")
	eq(
		QixBootstrap.shipping_probe_name(
			PackedStringArray(["--foo=bar", "--shipping-probe=frame-pacing"]),
		),
		"frame-pacing",
	)
	eq(
		QixBootstrap.shipping_probe_name(
			PackedStringArray(["--shipping-probe=framebuffer"]),
		),
		"framebuffer",
	)


func test_shipping_audio_smoke_request_is_feature_gated_and_strictly_positive() -> void:
	var request := PackedStringArray(["--shipping-audio-smoke-ticks=900"])
	eq(
		QixBootstrap.shipping_audio_smoke_ticks(request, false),
		0,
		"argumento reservado não pode alterar uma build sem a feature shipping_qa",
	)
	eq(QixBootstrap.shipping_audio_smoke_ticks(request, true), 900)
	eq(QixBootstrap.shipping_audio_smoke_ticks(PackedStringArray(), true), 0)
	eq(
		QixBootstrap.shipping_audio_smoke_ticks(
			PackedStringArray(["--shipping-audio-smoke-ticks=0"]),
			true,
		),
		-1,
		"zero não representa um smoke executável",
	)
	eq(
		QixBootstrap.shipping_audio_smoke_ticks(
			PackedStringArray(["--shipping-audio-smoke-ticks=abc"]),
			true,
		),
		-1,
		"valor inválido precisa provocar uma falha explícita",
	)
	eq(
		QixBootstrap.shipping_audio_smoke_ticks(
			PackedStringArray([
				"--shipping-audio-smoke-ticks=900",
				"--shipping-audio-smoke-ticks=900",
			]),
			true,
		),
		-1,
		"duas solicitações tornam a evidência ambígua",
	)


func test_shipping_audio_smoke_counter_completes_on_exact_physics_tick_once() -> void:
	var bootstrap := QixBootstrap.new()
	bootstrap.set("_shipping_audio_smoke_requested_ticks", 3)
	for tick in range(1, 3):
		ok(not bootstrap.call("_record_shipping_audio_smoke_physics_tick"), "tick %d ainda não conclui" % tick)
	eq(bootstrap.get("_shipping_audio_smoke_completed_ticks"), 2)
	ok(bootstrap.call("_record_shipping_audio_smoke_physics_tick"), "o terceiro callback físico conclui")
	eq(bootstrap.get("_shipping_audio_smoke_completed_ticks"), 3)
	ok(not bootstrap.call("_record_shipping_audio_smoke_physics_tick"), "conclusão não pode ser emitida duas vezes")
	eq(bootstrap.get("_shipping_audio_smoke_completed_ticks"), 3)
	bootstrap.free()


func test_fixed_tick_rate_is_explicit_in_project_configuration() -> void:
	var config := ConfigFile.new()
	eq(config.load("res://project.godot"), OK, "project.godot precisa ser legível")
	ok(
		config.has_section_key("physics", "common/physics_ticks_per_second"),
		"o tick autoritativo não deve depender silenciosamente do default da engine",
	)
	eq(config.get_value("physics", "common/physics_ticks_per_second", -1), 60)
