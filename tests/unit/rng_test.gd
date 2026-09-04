extends TestCase
## Vetores dourados calculados por um oráculo Python independente (xorshift32 13/17/5).

const GOLD_SEED1 := [270369,67634689,2647435461,307599695,2398689233,745495504]
const GOLD_SEED42 := [11355432,2836018348,476557059,3648046016]


func test_golden_seed_1() -> void:
	var r := DeterministicRng.new(1)
	for k in GOLD_SEED1.size():
		eq(r.next_u32(), GOLD_SEED1[k], "seed 1, valor %d" % k)


func test_golden_seed_42() -> void:
	var r := DeterministicRng.new(42)
	for k in GOLD_SEED42.size():
		eq(r.next_u32(), GOLD_SEED42[k], "seed 42, valor %d" % k)


func test_same_seed_same_sequence() -> void:
	var a := DeterministicRng.new(12345)
	var b := DeterministicRng.new(12345)
	for _k in 100:
		eq(a.next_u32(), b.next_u32(), "sequências divergem")


func test_zero_seed_is_remapped() -> void:
	var r := DeterministicRng.new(0)
	ne(r.state, 0, "estado zero travaria o xorshift")
	ne(r.next_u32(), 0)


func test_next_below_in_range() -> void:
	var r := DeterministicRng.new(7)
	for _k in 1000:
		var v := r.next_below(16)
		ok(v >= 0 and v < 16, "fora de [0,16): %d" % v)
