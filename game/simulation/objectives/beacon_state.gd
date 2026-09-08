class_name BeaconState
extends RefCounted
## Identidades fixas de balizas e seu ciclo de vida na rodada. O índice autorado nunca é
## reutilizado: CAPTURED persiste até reset. Nenhuma célula territorial é escrita aqui.

enum State { AVAILABLE, CAPTURED }

const MAX_BEACONS := 16
const FRAME_MARGIN := 8

var count: int = 0
var width: int = 0
var height: int = 0
var positions: PackedInt32Array = PackedInt32Array()
var states: PackedInt32Array = PackedInt32Array()
var captured_fill: PackedInt32Array = PackedInt32Array()
var capture_chain: PackedInt32Array = PackedInt32Array()
var items: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	positions.resize(MAX_BEACONS * 2)
	positions.fill(-1)
	states.resize(MAX_BEACONS)
	captured_fill.resize(MAX_BEACONS)
	capture_chain.resize(MAX_BEACONS)
	items.resize(MAX_BEACONS)


## Rejeição atômica: conteúdo inválido não descarta estado anterior de uma rodada.
func reset(cells: PackedInt32Array, field_width: int, field_height: int) -> bool:
	if not placement_errors(cells, field_width, field_height).is_empty():
		return false
	width = field_width
	height = field_height
	@warning_ignore("integer_division")
	count = cells.size() / 2
	positions.fill(-1)
	for index in cells.size():
		positions[index] = cells[index]
	states.fill(State.AVAILABLE)
	captured_fill.fill(0)
	capture_chain.fill(0)
	items.fill(0)
	return true


static func placement_errors(cells: PackedInt32Array, field_width: int, field_height: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if field_width < 3 or field_height < 3:
		errors.append("field precisa ter moldura e interior")
	if cells.size() % 2 != 0:
		errors.append("beacon_cells precisa ter pares x,y")
		return errors
	if cells.size() > MAX_BEACONS * 2:
		errors.append("no máximo %d balizas" % MAX_BEACONS)
		return errors
	for offset in range(0, cells.size(), 2):
		var x := cells[offset]
		var y := cells[offset + 1]
		if x < FRAME_MARGIN or y < FRAME_MARGIN \
				or x > field_width - FRAME_MARGIN - 1 or y > field_height - FRAME_MARGIN - 1:
			errors.append("baliza em (%d,%d) precisa ficar a 8 células da moldura" % [x, y])
		for previous in range(0, offset, 2):
			if cells[previous] == x and cells[previous + 1] == y:
				errors.append("duas balizas não podem ocupar (%d,%d)" % [x, y])
				break
	return errors


func cell(index: int) -> Vector2i:
	if index < 0 or index >= count:
		return Vector2i(-1, -1)
	return Vector2i(positions[index * 2], positions[index * 2 + 1])


func is_captured(index: int) -> bool:
	return index >= 0 and index < count and states[index] == State.CAPTURED


func captured_count() -> int:
	var total := 0
	for index in count:
		if is_captured(index):
			total += 1
	return total


func canonical_bytes() -> PackedByteArray:
	var values := PackedInt32Array([count, width, height])
	values.append_array(positions)
	values.append_array(states)
	values.append_array(captured_fill)
	values.append_array(capture_chain)
	values.append_array(items)
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s32(index * 4, values[index])
	return bytes
