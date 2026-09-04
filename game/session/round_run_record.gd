class_name RoundRunRecord
extends RefCounted
## Registro imutável por convenção de uma tentativa de rodada já encerrada.

var round_id: StringName
var round_index: int
var completed: bool
var start_state: RoundStartState
var replay: ReplayLog
var final_checksum: PackedByteArray
var final_tick: int
var final_score: int
var final_lives: int
