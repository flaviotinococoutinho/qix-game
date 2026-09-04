class_name RoundDefinition
extends Resource
## Geometria e conteúdo de uma rodada. Coordenadas em espaço de campo (célula (0,0) =
## canto superior esquerdo da moldura). Ver CoordinateSpace para a conversão histórica.

const DEFINITION_VERSION := 1

@export var field_width: int = 225      ## §4.4: 283 no eixo de 320 vira altura; 225 no eixo de 256 vira largura
@export var field_height: int = 283
@export var player_spawn: Vector2i = Vector2i(112, 0)   ## §4.1: (19,127) no board → topo, meio
@export var boss_start: Vector2i = Vector2i(112, 141)   ## centro do interior
@export var boss_dir_index: int = 3                     ## índice inicial na tabela de 16 direções
## Política de anchor: no primeiro corte, só o chefe protege território (§5.5).
@export var boss_protects_territory: bool = true


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if field_width < 3 or field_height < 3:
		errors.append("field precisa ter moldura e interior")
		return errors
	var player_in_bounds := player_spawn.x >= 0 and player_spawn.y >= 0 \
		and player_spawn.x < field_width and player_spawn.y < field_height
	var player_on_frame := player_in_bounds and (
		player_spawn.x == 0 or player_spawn.y == 0
		or player_spawn.x == field_width - 1 or player_spawn.y == field_height - 1
	)
	if not player_on_frame:
		errors.append("player_spawn precisa estar na moldura")
	var boss_interior := boss_start.x > 0 and boss_start.y > 0 \
		and boss_start.x < field_width - 1 and boss_start.y < field_height - 1
	if not boss_interior:
		errors.append("boss_start precisa estar no interior")
	if boss_dir_index < 0 or boss_dir_index > 15:
		errors.append("boss_dir_index precisa estar entre 0 e 15")
	return errors


func canonical_bytes() -> PackedByteArray:
	var vals := [DEFINITION_VERSION, field_width, field_height, player_spawn.x, player_spawn.y,
		boss_start.x, boss_start.y, boss_dir_index, 1 if boss_protects_territory else 0]
	var out := PackedByteArray()
	out.resize(vals.size() * 4)
	for k in vals.size():
		out.encode_s32(k * 4, vals[k])
	return out
