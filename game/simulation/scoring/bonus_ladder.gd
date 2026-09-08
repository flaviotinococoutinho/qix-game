class_name BonusLadder
extends Resource
## Economia de fim de rodada autorável, calculada sem mutar pontuação ou estado.
## Escada de reference/volfied/06-gameplay.md §12.6, escala ×0,1 escolhida no Atlas Vivo §5.
## Multiplicadores e bônus sem morte são DESIGN_DECISION; enabled é arbitrado pela simulação.

const PROFILE_VERSION := 1

@export var enabled: bool = false
@export var thresholds_permille: PackedInt32Array = PackedInt32Array([
	800, 810, 820, 830, 840, 850, 860, 870, 880, 890, 900,
	910, 920, 930, 940, 950, 960, 970, 980, 990, 991, 992, 993, 994, 995, 996, 997, 998, 999,
])
@export var points: PackedInt32Array = PackedInt32Array([
	1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000,
	2200, 2400, 2600, 2800, 3000, 3500, 4000, 5000, 10000, 11000, 12000,
	13000, 14000, 15000, 20000, 25000, 30000, 50000,
])
@export_range(1, 100, 1) var sealed_multiplier: int = 10
@export_range(1, 100, 1) var single_fill_multiplier: int = 100
@export_range(0, 1000, 1) var no_death_bonus_permille: int = 250


func base_points(permille: int) -> int:
	if points.size() != thresholds_permille.size():
		return 0
	var bounded_permille := clampi(permille, 0, 1000)
	for index in range(thresholds_permille.size() - 1, -1, -1):
		if bounded_permille >= thresholds_permille[index]:
			return maxi(0, points[index])
	return 0


func award(permille: int, reason: int, no_death: bool) -> int:
	var multiplier := 1
	match reason:
		GameRules.RoundEndReason.TARGET:
			pass
		GameRules.RoundEndReason.SEALED:
			multiplier = sealed_multiplier
		GameRules.RoundEndReason.SINGLE_FILL:
			multiplier = single_fill_multiplier
		_:
			return 0
	# Uma vitória confirmada em alvo autorado abaixo do primeiro limiar (ou por selamento)
	# ainda recebe a base da escada. Consultar área sem vitória continua devolvendo zero.
	var base := base_points(permille)
	if base == 0 and not points.is_empty() and points.size() == thresholds_permille.size():
		base = maxi(0, points[0])
	var total := base * multiplier
	if no_death:
		@warning_ignore("integer_division")
		total += total * no_death_bonus_permille / 1000
	return total


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if thresholds_permille.is_empty() or thresholds_permille.size() > 1001:
		errors.append("a escada precisa ter entre 1 e 1001 degraus")
	if thresholds_permille.size() != points.size():
		errors.append("cada limiar de bônus precisa ter um valor de pontos")
	var previous := -1
	for threshold in thresholds_permille:
		if threshold < 0 or threshold > 1000 or threshold <= previous:
			errors.append("limiares precisam ser crescentes, únicos e entre 0 e 1000")
			break
		previous = threshold
	previous = -1
	for value in points:
		if value < 0 or value > 1000000 or value < previous:
			errors.append("pontos precisam ser não decrescentes, entre 0 e 1000000")
			break
		previous = value
	if sealed_multiplier < 1 or sealed_multiplier > 100:
		errors.append("sealed_multiplier precisa estar entre 1 e 100")
	if single_fill_multiplier < 1 or single_fill_multiplier > 100:
		errors.append("single_fill_multiplier precisa estar entre 1 e 100")
	if no_death_bonus_permille < 0 or no_death_bonus_permille > 1000:
		errors.append("no_death_bonus_permille precisa estar entre 0 e 1000")
	return errors


func canonical_bytes() -> PackedByteArray:
	var values := PackedInt32Array([PROFILE_VERSION, 1 if enabled else 0,
		sealed_multiplier, single_fill_multiplier, no_death_bonus_permille,
		thresholds_permille.size()])
	values.append_array(thresholds_permille)
	values.append(points.size())
	values.append_array(points)
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s32(index * 4, values[index])
	return bytes
