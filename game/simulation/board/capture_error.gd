class_name CaptureError
extends RefCounted
## Diagnóstico de desenvolvimento devolvido pelo resolver quando o fechamento é inválido.

enum Code {
	EMPTY_TRAIL,
	TRAIL_OUT_OF_BOUNDS,
	TRAIL_NOT_INTERIOR,
	TRAIL_CELL_NOT_TRAIL,
	TRAIL_NOT_CONTIGUOUS,
	TRAIL_SELF_CROSS,
	TRAIL_START_NOT_ON_BOUNDARY,
	TRAIL_END_NOT_ON_BOUNDARY,
	NO_ANCHOR,
	ANCHOR_OUT_OF_BOUNDS,
	ANCHOR_NOT_FREE,
}

var code: int
var message: String


func _init(p_code: int, p_message: String) -> void:
	code = p_code
	message = p_message
