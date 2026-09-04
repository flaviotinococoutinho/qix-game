class_name DeterministicRng
extends RefCounted
## xorshift32 (Marsaglia, deslocamentos 13/17/5). Único ponto de acaso do domínio.
## Seed explícita; estado é um u32 exposto para checksum e replay.

var state: int


func _init(seed_value: int) -> void:
	state = seed_value & 0xFFFFFFFF
	if state == 0:
		state = 0x9E3779B9  # xorshift não pode partir de zero


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x & 0xFFFFFFFF
	return state


## Inteiro em [0, n). Viés de módulo é aceitável para n pequeno (tabelas de direção).
func next_below(n: int) -> int:
	assert(n > 0)
	return next_u32() % n
