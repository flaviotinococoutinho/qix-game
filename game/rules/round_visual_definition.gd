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


func validation_errors(field_width: int, field_height: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if display_name.strip_edges().is_empty():
		errors.append("visual.display_name vazio")
	if background == null:
		errors.append("visual.background ausente")
	elif background.get_width() != field_width or background.get_height() != field_height:
		errors.append("visual.background precisa ter %dx%d; recebido %dx%d" % [
			field_width, field_height, background.get_width(), background.get_height(),
		])
	return errors
