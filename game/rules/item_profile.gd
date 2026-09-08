class_name ItemProfile
extends Resource
## Vocabulário e economia autoráveis dos itens do Atlas Vivo. O orquestrador decide enabled.
## O ciclo por identidade + preenchimento segue a forma de reference/volfied/06-gameplay.md
## §11; composição, durações, piso e limites abaixo são DESIGN_DECISION deste jogo.

enum Kind { NONE, VELOCITY, STASIS, SHIELD_FREEZE, PURGE }

const PROFILE_VERSION := 1
const ITEM_COUNT := 5
const CYCLE_SIZE := 10
const MAX_BEACONS := 16

@export var enabled: bool = false
@export var capture_cycle: PackedInt32Array = PackedInt32Array([3, 1, 2, 3, 4, 1, 3, 2, 4, 1])
## Indexado por Kind. PURGE dura um tick: seu efeito imediato é aplicado pelo orquestrador.
@export var effect_durations_ticks: PackedInt32Array = PackedInt32Array([0, 360, 180, 360, 1])
## §7.3: cadeia 1 000→64 000; acima do sétimo mantém o teto, evitando crescimento ilimitado.
@export_range(1, 100000, 1) var chain_base_points: int = 1000
@export_range(1, 7, 1) var chain_max_steps: int = 7
## PURGE também restaura o escudo até este piso, nunca reduz uma reserva existente.
@export_range(0, 36000, 1) var shield_floor_ticks: int = 600
## Atlas Vivo §3.3: o bolsão já não cresce após o commit; limite 0 desliga esta condição.
@export_range(0, 1000000, 1) var sealed_free_cell_limit: int = 400


func item_for_capture(index: int, fills_done: int) -> int:
	if index < 0 or index >= MAX_BEACONS or fills_done < 0 or capture_cycle.size() != CYCLE_SIZE:
		return Kind.NONE
	var kind := capture_cycle[(index + fills_done % CYCLE_SIZE) % CYCLE_SIZE]
	return kind if kind >= Kind.NONE and kind < ITEM_COUNT else Kind.NONE


func duration_ticks(kind: int) -> int:
	if kind <= Kind.NONE or kind >= ITEM_COUNT or effect_durations_ticks.size() != ITEM_COUNT:
		return 0
	return clampi(effect_durations_ticks[kind], 0, 36000)


## `chain` começa em 1 e reinicia em cada varredura pós-captura.
func chain_points(chain: int) -> int:
	if chain <= 0:
		return 0
	var exponent := mini(chain - 1, clampi(chain_max_steps, 1, 7) - 1)
	return clampi(chain_base_points, 0, 100000) * (1 << exponent)


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if capture_cycle.size() != CYCLE_SIZE:
		errors.append("capture_cycle precisa ter 10 IDs")
	for kind in capture_cycle:
		if kind < Kind.NONE or kind >= ITEM_COUNT:
			errors.append("capture_cycle contém ID de item desconhecido")
			break
	if effect_durations_ticks.size() != ITEM_COUNT:
		errors.append("effect_durations_ticks precisa ter um contador por Kind")
	else:
		if effect_durations_ticks[Kind.NONE] != 0:
			errors.append("NONE não pode ter duração")
		for kind in range(1, ITEM_COUNT):
			if effect_durations_ticks[kind] < 1 or effect_durations_ticks[kind] > 36000:
				errors.append("duração do item %d precisa estar entre 1 e 36000 ticks" % kind)
	if chain_base_points < 1 or chain_base_points > 100000:
		errors.append("chain_base_points precisa estar entre 1 e 100000")
	if chain_max_steps < 1 or chain_max_steps > 7:
		errors.append("chain_max_steps precisa estar entre 1 e 7")
	if shield_floor_ticks < 0 or shield_floor_ticks > 36000:
		errors.append("shield_floor_ticks precisa estar entre 0 e 36000")
	if sealed_free_cell_limit < 0 or sealed_free_cell_limit > 1000000:
		errors.append("sealed_free_cell_limit precisa estar entre 0 e 1000000")
	return errors


func canonical_bytes() -> PackedByteArray:
	var values := PackedInt32Array([PROFILE_VERSION, 1 if enabled else 0,
		chain_base_points, chain_max_steps, shield_floor_ticks, sealed_free_cell_limit,
		capture_cycle.size()])
	values.append_array(capture_cycle)
	values.append(effect_durations_ticks.size())
	values.append_array(effect_durations_ticks)
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s32(index * 4, values[index])
	return bytes
