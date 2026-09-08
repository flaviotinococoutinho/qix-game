class_name EffectTimers
extends RefCounted
## Contadores de efeitos, independentes de relógio e de apresentação.
## O orquestrador avança contadores após consumir os efeitos deste tick e antes de aplicar
## itens recém-capturados. A ordem de expiração é a ordem estável de ItemProfile.Kind.

var remaining: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])


func reset() -> void:
	remaining.fill(0)


func active(kind: int) -> bool:
	return kind > ItemProfile.Kind.NONE and kind < ItemProfile.ITEM_COUNT and remaining[kind] > 0


## Reaplicar renova até a duração autorada, sem somar nem abreviar um efeito mais longo.
## true significa aplicação válida; o orquestrador emite ITEM_STARTED também na renovação.
func activate(kind: int, profile: ItemProfile) -> bool:
	if profile == null or kind <= ItemProfile.Kind.NONE or kind >= ItemProfile.ITEM_COUNT:
		return false
	var duration := profile.duration_ticks(kind)
	if duration <= 0:
		return false
	remaining[kind] = maxi(remaining[kind], duration)
	return true


func advance() -> PackedInt32Array:
	var expired := PackedInt32Array()
	for kind in range(1, ItemProfile.ITEM_COUNT):
		if remaining[kind] <= 0:
			continue
		remaining[kind] -= 1
		if remaining[kind] == 0:
			expired.append(kind)
	return expired


func canonical_bytes() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(remaining.size() * 4)
	for index in remaining.size():
		bytes.encode_s32(index * 4, remaining[index])
	return bytes
