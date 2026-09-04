class_name ReplayLog
extends RefCounted
## Registro determinístico: cabeçalho + um intent por tick. Formato canônico binário, LE.
##  "QIXR" | u32 schema | u32 rules_version | u32 seed | 32 B round_hash | 32 B initial_checksum
##  | u32 n | n bytes de intents (MoveIntent.to_byte)
## Compatibilidade de replay: mesma schema + rules_version + round_hash. PRNG fixo (xorshift32).

const MAGIC := "QIXR"
const SCHEMA_VERSION := 1

var rules_version: int = GameRules.RULES_VERSION
var seed_value: int
var round_hash: PackedByteArray
var initial_checksum: PackedByteArray
var intents: PackedByteArray = PackedByteArray()


static func start(sim: GameSimulation) -> ReplayLog:
	var r := ReplayLog.new()
	r.seed_value = sim.seed_value
	r.round_hash = config_hash(sim.rules, sim.round_def)
	r.initial_checksum = sim.state_checksum()
	return r


static func config_hash(rules: GameRules, round_def: RoundDefinition) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(rules.canonical_bytes())
	ctx.update(round_def.canonical_bytes())
	return ctx.finish()


func record(intent: MoveIntent) -> void:
	intents.append(intent.to_byte())


func tick_count() -> int:
	return intents.size()


func intent_at(i: int) -> MoveIntent:
	return MoveIntent.from_byte(intents[i])


func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(MAGIC.to_ascii_buffer())
	var hdr := PackedByteArray()
	hdr.resize(12)
	hdr.encode_u32(0, SCHEMA_VERSION)
	hdr.encode_u32(4, rules_version)
	hdr.encode_u32(8, seed_value & 0xFFFFFFFF)
	out.append_array(hdr)
	out.append_array(round_hash)
	out.append_array(initial_checksum)
	var n := PackedByteArray()
	n.resize(4)
	n.encode_u32(0, intents.size())
	out.append_array(n)
	out.append_array(intents)
	return out


## Devolve null se os bytes não forem um replay válido.
static func from_bytes(b: PackedByteArray) -> ReplayLog:
	if b.size() < 4 + 12 + 64 + 4:
		return null
	if b.slice(0, 4).get_string_from_ascii() != MAGIC:
		return null
	if b.decode_u32(4) != SCHEMA_VERSION:
		return null
	var r := ReplayLog.new()
	r.rules_version = b.decode_u32(8)
	r.seed_value = b.decode_u32(12)
	r.round_hash = b.slice(16, 48)
	r.initial_checksum = b.slice(48, 80)
	var n := b.decode_u32(80)
	if b.size() != 84 + n:
		return null
	r.intents = b.slice(84, 84 + n)
	return r


func checksum() -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(to_bytes())
	return ctx.finish()


## Vazio significa compatível. A checagem ocorre antes de qualquer mutação da simulação.
func compatibility_error(sim: GameSimulation) -> String:
	if rules_version != GameRules.RULES_VERSION:
		return "rules_version incompatível: replay=%d runtime=%d" % [rules_version, GameRules.RULES_VERSION]
	if seed_value != (sim.seed_value & 0xFFFFFFFF):
		return "seed incompatível: replay=%d simulação=%d" % [seed_value, sim.seed_value]
	if round_hash != config_hash(sim.rules, sim.round_def):
		return "rules/round incompatíveis"
	if initial_checksum != sim.state_checksum():
		return "estado inicial incompatível"
	return ""


## Reproduz o log numa simulação nova com o mesmo seed/config e devolve o checksum final.
## Devolve bytes vazios, sem avançar a simulação, quando o contrato não é compatível.
func replay_into(sim: GameSimulation) -> PackedByteArray:
	if compatibility_error(sim) != "":
		return PackedByteArray()
	for i in intents.size():
		sim.step(intent_at(i))
	return sim.state_checksum()
