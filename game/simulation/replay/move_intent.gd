class_name MoveIntent
extends RefCounted
## Valor único produzido por todos os dispositivos. O domínio recebe isto, nunca consulta Input.

enum Dir { NONE = 0, UP = 1, RIGHT = 2, DOWN = 3, LEFT = 4 }

var direction: int = Dir.NONE
var drawing: bool = false


static func make(dir: int, draw: bool) -> MoveIntent:
	var m := MoveIntent.new()
	m.direction = dir
	m.drawing = draw
	return m


static func none() -> MoveIntent:
	return MoveIntent.new()


## Codificação de replay: bits 0..2 = direção, bit 3 = draw.
func to_byte() -> int:
	return (direction & 0x7) | (0x8 if drawing else 0)


static func from_byte(b: int) -> MoveIntent:
	var d := b & 0x7
	if d > Dir.LEFT:
		d = Dir.NONE
	return make(d, (b & 0x8) != 0)
