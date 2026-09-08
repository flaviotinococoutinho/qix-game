class_name BeaconRules
extends RefCounted
## A varredura segue o commit territorial (§7.3 da referência), nunca um traço pendente.


## Devolve pontos confirmados para ScoreLedger; nenhum score é escrito fora desse ledger.
## Eventos seguem índices autorados. O orquestrador aplica seus itens só depois desta varredura,
## portanto um PURGE não altera a ordem ou a recompensa das outras balizas deste fechamento.
static func capture_claimed(state: BeaconState, board: BoardState, fills_done: int,
		profile: ItemProfile, events: Array[GameEvent]) -> int:
	if state == null or board == null or profile == null or fills_done < 1:
		return 0
	if state.width != board.width or state.height != board.height:
		return 0
	var chain := 0
	var points_total := 0
	for index in state.count:
		if state.is_captured(index):
			continue
		var position := state.cell(index)
		if board.get_cell(position.x, position.y) != BoardState.Cell.CLAIMED:
			continue
		chain += 1
		var points := profile.chain_points(chain)
		var item := profile.item_for_capture(index, fills_done)
		state.states[index] = BeaconState.State.CAPTURED
		state.captured_fill[index] = fills_done
		state.capture_chain[index] = chain
		state.items[index] = item
		points_total += points
		events.append(GameEvent.make(GameEvent.Kind.BEACON_CAPTURED, {
			"index": index, "x": position.x, "y": position.y,
			"chain": chain, "points": points, "item": item,
		}))
	return points_total
