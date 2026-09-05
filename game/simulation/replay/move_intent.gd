class_name MoveIntent
extends RefCounted
## Valor único produzido por todos os dispositivos. O domínio recebe isto, nunca consulta Input.
##
## `fallback` é a segunda intenção do jogador: a direção que ele ainda segura (ou soltou há
## instantes) enquanto pede uma curva. O domínio só a tenta quando a direção primária devolve
## `PlayerMotion.StepResult.BLOCKED` — é o buffer de curva sem estado no checksum: a decisão
## fica no adaptador, a execução no domínio, e o replay grava as duas intenções.

enum Dir { NONE = 0, UP = 1, RIGHT = 2, DOWN = 3, LEFT = 4 }

var direction: int = Dir.NONE
var drawing: bool = false
var fallback: int = Dir.NONE


static func make(dir: int, draw: bool, fallback_dir: int = Dir.NONE) -> MoveIntent:
	var m := MoveIntent.new()
	m.direction = dir
	m.drawing = draw
	m.fallback = fallback_dir
	return m


static func none() -> MoveIntent:
	return MoveIntent.new()


## Codificação de replay: bits 0..2 = direção, bit 3 = draw, bits 4..6 = fallback, bit 7 = 0.
## Logs gravados antes do fallback existir têm os bits 4..6 zerados e decodificam idêntico.
func to_byte() -> int:
	return (direction & 0x7) | (0x8 if drawing else 0) | ((fallback & 0x7) << 4)


static func from_byte(b: int) -> MoveIntent:
	var d := b & 0x7
	if d > Dir.LEFT:
		d = Dir.NONE
	var f := (b >> 4) & 0x7
	if f > Dir.LEFT:
		f = Dir.NONE
	return make(d, (b & 0x8) != 0, f)


static func is_valid_dir(dir: int) -> bool:
	return dir >= Dir.NONE and dir <= Dir.LEFT
