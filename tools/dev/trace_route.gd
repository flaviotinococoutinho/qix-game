extends SceneTree
## Traço de eventos de uma rota autorada num setor de produção. Imprime, tick a tick, tudo o
## que o domínio confirmou (menos SCORE_CHANGED) e o estado dos atores no instante de cada
## morte. É a ferramenta de rastreabilidade headless: diz *qual* gatilho matou.
##
## Uso:
##   Godot --headless --path . --script res://tools/dev/trace_route.gd -- --round=2 \
##       --route=L16,D141:draw,R40,U141:draw,D70,L40:draw [--all]
## Segmentos como em screenshot_probe: L/R/U/D + ticks, sufixo `:draw`; `W` espera.

const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"


func _initialize() -> void:
	var round_index := 0
	var route := ""
	var show_all := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--round="):
			round_index = argument.trim_prefix("--round=").to_int()
		elif argument.begins_with("--route="):
			route = argument.trim_prefix("--route=")
		elif argument == "--all":
			show_all = true
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	var content := campaign.rounds[round_index]
	var simulation := GameSimulation.new(content.rules, content.round_definition, content.seed_value)
	print("QIX_TRACE round=%s seed=%d threat_enabled=%s" % [
		content.round_id, content.seed_value, simulation.threat_enabled()])
	for segment in _parse(route):
		for _t in int(segment["ticks"]):
			var intent := MoveIntent.make(segment["dir"], segment["draw"])
			var events := simulation.step(intent)
			for event in events:
				if event.kind == GameEvent.Kind.SCORE_CHANGED and not show_all:
					continue
				print("t=%04d %s %s" % [simulation.tick - 1, _kind_name(event.kind), JSON.stringify(event.data)])
				if event.kind == GameEvent.Kind.PLAYER_DIED:
					_dump_actors(simulation)
			if simulation.phase == GameSimulation.Phase.GAME_OVER:
				break
	print("QIX_TRACE_END tick=%d phase=%d permille=%d score=%d lives=%d fills=%d threat_index=%d" % [
		simulation.tick, simulation.phase, simulation.permille, simulation.score, simulation.lives,
		simulation.fills_done, simulation.director.threat_index])
	quit(0)


func _dump_actors(simulation: GameSimulation) -> void:
	var pools := simulation.pools
	print("   jogador=%s trilha=%d chefe=%s fase=%d" % [
		str(simulation.player.cell()), simulation.trail.size(), str(simulation.boss_cell()),
		simulation.boss.phase])
	for slot in MinorActorPools.MAX_WALKERS:
		if pools.walker_alive(slot):
			print("   vagalume[%d] %s dir=%d warmup=%d reason=%d" % [slot, str(pools.walker_cell(slot)),
				pools.walker(slot, MinorActorPools.W.DIR), pools.walker(slot, MinorActorPools.W.WARMUP),
				pools.walker(slot, MinorActorPools.W.REASON)])
	for slot in MinorActorPools.MAX_DARTS:
		if pools.dart_alive(slot):
			print("   dardo[%d] %s dir_index=%d warmup=%d reason=%d" % [slot, str(pools.dart_cell(slot)),
				pools.dart(slot, MinorActorPools.D.DIR_INDEX), pools.dart(slot, MinorActorPools.D.WARMUP),
				pools.dart(slot, MinorActorPools.D.REASON)])
	for slot in MinorActorPools.MAX_EMBERS:
		if pools.ember_alive(slot):
			print("   brasa[%d] index=%d reason=%d" % [slot, pools.ember(slot, MinorActorPools.E.TRAIL_INDEX),
				pools.ember(slot, MinorActorPools.E.REASON)])


func _kind_name(kind: int) -> String:
	for name in GameEvent.Kind.keys():
		if GameEvent.Kind[name] == kind:
			return name
	return str(kind)


func _parse(route: String) -> Array:
	var out := []
	for token in route.split(",", false):
		var t := token.strip_edges()
		var draw := t.ends_with(":draw")
		if draw:
			t = t.trim_suffix(":draw")
		var dir := MoveIntent.Dir.NONE
		match t.substr(0, 1).to_upper():
			"L": dir = MoveIntent.Dir.LEFT
			"R": dir = MoveIntent.Dir.RIGHT
			"U": dir = MoveIntent.Dir.UP
			"D": dir = MoveIntent.Dir.DOWN
		out.append({"dir": dir, "draw": draw, "ticks": maxi(1, t.substr(1).to_int())})
	return out
