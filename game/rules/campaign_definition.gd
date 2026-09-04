class_name CampaignDefinition
extends Resource
## Catálogo ordenado. Resources referenciados são tratados como imutáveis no runtime.

@export var campaign_id: StringName
@export var rounds: Array[RoundContent] = []
@export_range(0, 600, 1, "suffix:ticks") var intro_ticks: int = 60
@export_range(0, 600, 1, "suffix:ticks") var clear_ticks: int = 120


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(campaign_id).strip_edges().is_empty():
		errors.append("campaign_id vazio")
	if rounds.is_empty():
		errors.append("rounds vazio")
	if intro_ticks < 0:
		errors.append("intro_ticks negativo")
	if clear_ticks < 0:
		errors.append("clear_ticks negativo")
	var seen := {}
	for index in rounds.size():
		var content := rounds[index]
		if content == null:
			errors.append("rounds[%d] ausente" % index)
			continue
		var id := String(content.round_id)
		if not id.is_empty() and seen.has(id):
			errors.append("round_id duplicado: %s" % id)
		seen[id] = true
		for error in content.validation_errors():
			errors.append("rounds[%d]: %s" % [index, error])
	return errors
