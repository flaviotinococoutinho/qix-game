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
	_append_role_collisions(errors)
	return errors


## Os seis papéis são desenhados uns **contra** os outros — nenhum deles aparece sozinho:
##
## - `free_color` × `boundary_color` × `trail_color`: os três estados de célula que
##   `game/board/board_reveal.gdshader` decide no mesmo `fragment()`, lado a lado no campo.
## - `trail_color` × `trail_hot_color`: o shader faz `mix(trail_color, trail_hot_color, heat)`.
##   Autorados iguais, a mistura é constante e o canal de risco da exposição — o pulso que
##   acelera e clareia conforme a trilha se afasta da moldura — não desenha nada. A feature
##   continua correndo; ela simplesmente deixa de ser visível.
## - `threat_color`: corpo do chefe em `QixEnemyView`, sobreposto aos três estados de célula.
## - `trail_hot_color` e `accent_color`: núcleo e halo do cursor em `QixPlayerView` (cujo contorno
##   é `boundary_color`) e do chefe em `QixEnemyView`.
##
## Dois papéis com a mesma cor não são uma paleta ousada: são uma leitura a menos. E é uma perda
## que **nenhuma** medição de contraste acusa como problema de contraste — razão 1,00 não é um par
## fraco, é a ausência de par. Por isso o piso mora aqui, na autoração, e não em
## `tools/palette_contrast.gd`: a transação de conteúdo (ADR-0008) recusa antes de escrever.
const DISTINCT_ROLES: Array[String] = [
	"free_color",
	"boundary_color",
	"trail_color",
	"trail_hot_color",
	"threat_color",
	"accent_color",
]


## Compara as cores como o framebuffer as guarda, em RGBA8. Autorar `0.5019` e `0.5020` produz o
## mesmo pixel em 8 bits; uma comparação de `Color` diria que os dois papéis estão separados e o
## jogador veria uma cor só.
func _append_role_collisions(errors: PackedStringArray) -> void:
	var roles := [
		free_color,
		boundary_color,
		trail_color,
		trail_hot_color,
		threat_color,
		accent_color,
	]
	for index in roles.size():
		var left := roles[index] as Color
		for other in range(index + 1, roles.size()):
			var right := roles[other] as Color
			if left.to_rgba32() != right.to_rgba32():
				continue
			errors.append("visual.%s e visual.%s são a mesma cor (#%s): dois papéis, uma leitura" % [
				DISTINCT_ROLES[index],
				DISTINCT_ROLES[other],
				left.to_html(),
			])
