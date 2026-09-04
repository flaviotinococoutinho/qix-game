class_name RoundContent
extends Resource
## Unidade autorável de campanha: gameplay determinístico + seed + apresentação independente.

@export var round_id: StringName
@export var rules: GameRules
@export var round_definition: RoundDefinition
@export var seed_value: int = 1
@export var visual: RoundVisualDefinition


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(round_id).strip_edges().is_empty():
		errors.append("round_id vazio")
	if rules == null:
		errors.append("rules ausente")
	else:
		_append_prefixed(errors, rules.validation_errors(), "rules")
	if round_definition == null:
		errors.append("round_definition ausente")
	else:
		_append_prefixed(errors, round_definition.validation_errors(), "round_definition")
	if seed_value < 1 or seed_value > 0xFFFFFFFF:
		errors.append("seed_value precisa estar no intervalo u32 não zero (1..4294967295)")
	if visual == null:
		errors.append("visual ausente")
	elif round_definition != null:
		_append_prefixed(errors, visual.validation_errors(
			round_definition.field_width,
			round_definition.field_height,
		), "visual")
	return errors


static func _append_prefixed(
	target: PackedStringArray,
	source: PackedStringArray,
	prefix: String,
) -> void:
	for error in source:
		target.append("%s: %s" % [prefix, error])
