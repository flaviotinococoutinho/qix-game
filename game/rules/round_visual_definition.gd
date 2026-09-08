class_name RoundVisualDefinition
extends Resource
## Somente apresentação. Nunca entra no hash ou nas regras determinísticas da rodada.

@export var display_name: String = "SETOR SEM NOME"
@export_multiline var subtitle: String = ""
@export var background: Texture2D
@export var free_color: Color = Color("071923")
@export var boundary_color: Color = Color("46f5c5")
@export var trail_color: Color = Color("ffd166")
@export var trail_hot_color: Color = Color("fff4b0")
@export var threat_color: Color = Color("ff426d")
@export var accent_color: Color = Color("6ca8b5")

@export_group("Escala dos modelos 2.5D")
## Tamanho de apresentação independente do ponto de contato da grade; nunca entra em replay.
@export_range(10, 200, 1) var player_model_scale_milli: int = 43
@export_range(10, 200, 1) var boss_model_scale_milli: int = 82
@export_range(10, 200, 1) var walker_model_scale_milli: int = 41
@export_range(10, 200, 1) var dart_model_scale_milli: int = 33
@export_range(10, 200, 1) var ember_model_scale_milli: int = 33
@export_range(10, 200, 1) var beacon_model_scale_milli: int = 47


func validation_errors(field_width: int, field_height: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if display_name.strip_edges().is_empty():
		errors.append("visual.display_name vazio")
	for property in ["player_model_scale_milli", "boss_model_scale_milli", "walker_model_scale_milli", "dart_model_scale_milli", "ember_model_scale_milli", "beacon_model_scale_milli"]:
		var value: int = get(property)
		if value < 10 or value > 200:
			errors.append("visual.%s precisa estar entre 10 e 200 milésimos" % property)
	if background == null:
		errors.append("visual.background ausente")
	elif background.get_width() != field_width or background.get_height() != field_height:
		errors.append("visual.background precisa ter %dx%d; recebido %dx%d" % [
			field_width, field_height, background.get_width(), background.get_height(),
		])
	return errors
