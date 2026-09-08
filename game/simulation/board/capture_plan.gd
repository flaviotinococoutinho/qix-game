class_name CapturePlan
extends RefCounted
## Descrição imutável de um fechamento válido. Não muta nada; BoardState o aplica uma vez.

## Versão do board no instante do planejamento.
var board_version: int
## Células FREE inalcançáveis por qualquer anchor → viram CLAIMED. Ordem ascendente.
var claimed_indices: PackedInt32Array
## Células TRAIL → viram BOUNDARY. Na ordem da trilha.
var trail_indices: PackedInt32Array
## Delta de ownership real: claimed + trilha consolidada (toda trilha é interior).
var filled_delta: int
## Células FREE alcançáveis que permanecem livres (diagnóstico; não é aplicado).
var free_remaining: int
