extends SceneTree
## Wrapper CLI para `godot --script`. A implementação reutilizável vive no Node
## carregado também pela cena principal dos pacotes shipping_qa.

const ProbeNode := preload("res://tools/shipping/framebuffer_shader_probe_node.gd")

const SHADER_PATH := ProbeNode.SHADER_PATH
const CAMPAIGN_PATH := ProbeNode.CAMPAIGN_PATH
const VIEWPORT_SIZE := ProbeNode.VIEWPORT_SIZE
const REGION_WIDTH := ProbeNode.REGION_WIDTH
const BACKGROUND := ProbeNode.BACKGROUND
const FREE_COLOR := ProbeNode.FREE_COLOR
const BOUNDARY_COLOR := ProbeNode.BOUNDARY_COLOR
const TRAIL_COLOR := ProbeNode.TRAIL_COLOR
const TRAIL_HOT_COLOR := ProbeNode.TRAIL_HOT_COLOR

var _probe: Node


func _initialize() -> void:
	_probe = ProbeNode.new()
	_probe.name = "ShippingFramebufferProbe"
	root.add_child(_probe)
	_probe.start(OS.get_cmdline_user_args())


static func validate_final_composition(
	rendered: Dictionary,
	source: Dictionary,
	visual: RoundVisualDefinition,
) -> Dictionary:
	return ProbeNode.validate_final_composition(rendered, source, visual)


static func validate_samples(samples: Dictionary, background: Color) -> Dictionary:
	return ProbeNode.validate_samples(samples, background)


static func _composition_error(message: String) -> Dictionary:
	return ProbeNode._composition_error(message)


static func _assert_probe(
	condition: bool,
	message: String,
	failures: PackedStringArray,
	assertions: PackedStringArray,
) -> void:
	ProbeNode._assert_probe(condition, message, failures, assertions)


static func _color_distance(left: Color, right: Color) -> float:
	return ProbeNode._color_distance(left, right)


static func _serializable_samples(samples: Dictionary) -> Dictionary:
	return ProbeNode._serializable_samples(samples)


static func _color_record(color: Color) -> Dictionary:
	return ProbeNode._color_record(color)
