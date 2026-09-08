class_name RoundDefinition
extends Resource
## Geometria e conteúdo de uma rodada. Coordenadas em espaço de campo (célula (0,0) =
## canto superior esquerdo da moldura). Ver CoordinateSpace para a conversão histórica.
##
## v2 acrescenta o portão dos vagalumes (`walker_spawn`, uma célula da moldura) e as balizas
## (`beacon_cells`, pares x,y no interior, §5.8/§12.3 do Volfied).

const DEFINITION_VERSION := 2
const MAX_BEACONS := 16

@export var field_width: int = 225      ## §4.4: 283 no eixo de 320 vira altura; 225 no eixo de 256 vira largura
@export var field_height: int = 283
@export var player_spawn: Vector2i = Vector2i(112, 0)   ## §4.1: (19,127) no board → topo, meio
@export var boss_start: Vector2i = Vector2i(112, 141)   ## centro do interior
@export var boss_dir_index: int = 3                     ## índice inicial na tabela de 16 direções
## Política de anchor: no primeiro corte, só o chefe protege território (§5.5).
@export var boss_protects_territory: bool = true
## Portão dos vagalumes: uma célula da moldura. (-1, -1) = automático, meio da base.
@export var walker_spawn: Vector2i = Vector2i(-1, -1)
## Balizas: pares (x, y) achatados, no interior e a ≥ 8 células da moldura.
@export var beacon_cells: PackedInt32Array = PackedInt32Array()


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if field_width < 3 or field_height < 3:
		errors.append("field precisa ter moldura e interior")
		return errors
	if not _on_frame(player_spawn):
		errors.append("player_spawn precisa estar na moldura")
	if not _interior(boss_start):
		errors.append("boss_start precisa estar no interior")
	if boss_dir_index < 0 or boss_dir_index > 15:
		errors.append("boss_dir_index precisa estar entre 0 e 15")
	if walker_spawn != Vector2i(-1, -1) and not _on_frame(walker_spawn):
		errors.append("walker_spawn precisa estar na moldura ou ser (-1, -1)")
	errors.append_array(BeaconState.placement_errors(beacon_cells, field_width, field_height))
	for index in range(0, beacon_cells.size() - 1, 2):
		if Vector2i(beacon_cells[index], beacon_cells[index + 1]) == boss_start:
			errors.append("baliza não pode nascer sobre o chefe")
	return errors


## Portão efetivo dos vagalumes: o autorado, ou o meio da base.
func walker_gate() -> Vector2i:
	if walker_spawn == Vector2i(-1, -1):
		@warning_ignore("integer_division")
		return Vector2i(field_width / 2, field_height - 1)
	return walker_spawn


func beacon_count() -> int:
	@warning_ignore("integer_division")
	return beacon_cells.size() / 2


func beacon_cell(index: int) -> Vector2i:
	return Vector2i(beacon_cells[index * 2], beacon_cells[index * 2 + 1])


func _on_frame(cell: Vector2i) -> bool:
	var in_bounds := cell.x >= 0 and cell.y >= 0 and cell.x < field_width and cell.y < field_height
	return in_bounds and (
		cell.x == 0 or cell.y == 0 or cell.x == field_width - 1 or cell.y == field_height - 1
	)


func _interior(cell: Vector2i) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < field_width - 1 and cell.y < field_height - 1


func canonical_bytes() -> PackedByteArray:
	var vals: Array[int] = [DEFINITION_VERSION, field_width, field_height, player_spawn.x, player_spawn.y,
		boss_start.x, boss_start.y, boss_dir_index, 1 if boss_protects_territory else 0,
		walker_spawn.x, walker_spawn.y, beacon_cells.size()]
	vals.append_array(Array(beacon_cells))
	var out := PackedByteArray()
	out.resize(vals.size() * 4)
	for k in vals.size():
		out.encode_s32(k * 4, vals[k])
	return out
