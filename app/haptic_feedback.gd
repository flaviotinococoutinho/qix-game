class_name QixHapticFeedback
extends RefCounted
## Planeja um único pulso por tick e despacha para gamepad/mobile.

@export var enabled := true
@export_range(0.0, 1.0, 0.05) var intensity := 1.0

## Exposição da trilha no tick anterior — o único estado desta classe.
##
## Existe porque atravessar `TrailExposure.WARNING_RATIO` é uma aresta, e uma aresta só se
## reconhece comparando dois ticks. É memória da apresentação sobre snapshots já confirmados,
## não estado de jogo: nada aqui volta para a simulação (invariante 6).
var _previous_exposure := 0.0


## `exposure_crossed` vem de `TrailExposure.crossed_warning`; quem chama `plan` direto e só
## se importa com eventos não precisa passá-lo. A aresta entra como candidata igual às
## outras: se a morte do jogador cai no mesmo tick, é a morte que se sente.
func plan(events: Array[GameEvent], exposure_crossed: bool = false, paused: bool = false) -> Dictionary:
	if not enabled or paused:
		return {}
	var best: Dictionary = _exposure_pulse() if exposure_crossed else {}
	for event in events:
		var candidate := _pulse_for_event(event)
		if candidate.is_empty():
			continue
		if best.is_empty() or int(candidate["priority"]) > int(best["priority"]):
			best = candidate
	if best.is_empty():
		return best
	best["weak"] = snappedf(clampf(float(best["weak"]) * intensity, 0.0, 1.0), 0.001)
	best["strong"] = snappedf(clampf(float(best["strong"]) * intensity, 0.0, 1.0), 0.001)
	best["amplitude"] = snappedf(clampf(float(best["amplitude"]) * intensity, 0.0, 1.0), 0.001)
	return best


## Leitura pura: diz se `exposure` atravessaria o limiar contra a memória deste tick, **sem
## a avançar**.
##
## Existe para que a aresta continue a ter um dono só. O canal sonoro do mesmo limiar precisa
## da mesma resposta, e se cada canal guardasse a sua cópia de `_previous_exposure` bastaria
## um `sync` desemparelhado — um canal desligado, um tick de arranque — para o jogador sentir
## e não ouvir. O hub pergunta aqui antes de chamar `sync`, que é quem avança a memória.
func would_cross_warning(exposure: float) -> bool:
	return TrailExposure.crossed_warning(_previous_exposure, exposure)


## `exposure` é a leitura de `TrailExposure` para o tick que acabou de ser confirmado. O
## default `0.0` preserva o comportamento de quem sincroniza só por eventos.
##
## Pausa interrompe vibração e conserva a memória da exposição; eventos não ficam em fila.
func sync(events: Array[GameEvent], exposure: float = 0.0, paused: bool = false) -> Dictionary:
	if paused:
		for joypad_id in Input.get_connected_joypads():
			Input.stop_joy_vibration(joypad_id)
		return {}
	var crossed := TrailExposure.crossed_warning(_previous_exposure, exposure)
	# Fora do `if enabled` de propósito: com háptica desligada a leitura continua a andar,
	# senão religar num traço já longo dispararia uma aresta que o jogador atravessou faz
	# tempo.
	_previous_exposure = exposure
	var pulse := plan(events, crossed, paused)
	if pulse.is_empty():
		return pulse
	for joypad_id in Input.get_connected_joypads():
		Input.start_joy_vibration(
			joypad_id,
			float(pulse["weak"]),
			float(pulse["strong"]),
			float(pulse["duration_seconds"]),
		)
	Input.vibrate_handheld(int(pulse["duration_ms"]), float(pulse["amplitude"]))
	return pulse


## O toque do instante em que a trilha deixa de ser um compromisso e vira uma aposta.
##
## O canal visual desse limiar já existe — o pulso da trilha acelera e clareia, e o HUD
## nomeia o estado. Só que no tick em que isso acontece o olho do jogador está no chefe e nas
## duas células à frente do cursor, não na trilha atrás dele. A háptica é o único canal que
## não disputa a atenção do olhar: ela chega mesmo quando ninguém está olhando para ela.
##
## Deliberadamente **fraco e curto** — 70 ms, mais suave que o `shield`, que é o relógio de
## uma ameaça imposta. Aqui a exposição foi escolhida pelo jogador: o jogo confirma a aposta,
## não repreende. Em *Lumen Cartography* é o papel que estica sob o traço longo, não um alarme.
##
## Prioridade 35: acima do `respawn` (30), abaixo do `capture` (40). Se o laço fecha no mesmo
## tick em que o limiar é cruzado, a notícia é o território conquistado — o aviso perdeu o
## objeto. E o limiar nunca disputa com a morte, que zera a trilha de qualquer maneira.
func _exposure_pulse() -> Dictionary:
	return _pulse(&"exposure", 35, 0.30, 0.10, 70, 0.28)


func _pulse_for_event(event: GameEvent) -> Dictionary:
	match event.kind:
		GameEvent.Kind.CAPTURED:
			var scale := clampf(float(event.data.get("filled_delta", 0)) / 2000.0, 0.0, 0.25)
			return _pulse(&"capture", 40, 0.35 + scale, 0.22 + scale, 90, 0.42)
		GameEvent.Kind.CAPTURE_REJECTED:
			return _pulse(&"reject", 45, 0.25, 0.42, 110, 0.38)
		GameEvent.Kind.SHIELD_CRITICAL:
			return _pulse(&"shield", 92, 0.50, 0.12, 120, 0.42)
		GameEvent.Kind.PLAYER_DIED:
			return _pulse(&"death", 100, 0.72, 1.00, 380, 0.90)
		GameEvent.Kind.PLAYER_RESPAWNED:
			return _pulse(&"respawn", 30, 0.22, 0.18, 80, 0.25)
		GameEvent.Kind.ROUND_WON, GameEvent.Kind.ROUND_CLEAR_STARTED:
			return _pulse(&"round_won", 80, 0.70, 0.80, 240, 0.78)
		GameEvent.Kind.GAME_OVER:
			return _pulse(&"game_over", 95, 0.52, 0.92, 460, 0.82)
		GameEvent.Kind.CAMPAIGN_COMPLETE:
			return _pulse(&"campaign_complete", 90, 0.82, 0.78, 520, 0.86)
	# O despacho por evento preserva o silêncio de ameaça em queda e da expiração instantânea
	# de Expurgo. Som e pulso recebem a mesma prioridade da receita autorada.
	var cue_name := QixAudioDirector.cue_for_event(event)
	var priority := QixProceduralAudioLibrary.priority_for(cue_name)
	match cue_name:
		&"trail_cut":
			return _pulse(cue_name, priority, 0.42, 0.65, 95, 0.58)
		&"ember", &"boss_cornered":
			return _pulse(cue_name, priority, 0.50, 0.48, 140, 0.52)
		&"boss_phase", &"overtime":
			return _pulse(cue_name, priority, 0.48, 0.36, 180, 0.50)
		&"dart_arm", &"walker_spawn":
			return _pulse(cue_name, priority, 0.18, 0.08, 35, 0.18)
		&"threat", &"item_end":
			return _pulse(cue_name, priority, 0.25, 0.14, 65, 0.24)
		&"beacon":
			return _pulse(cue_name, priority, 0.32, 0.24, 65, 0.32)
		&"velocity", &"stasis", &"shield_freeze":
			return _pulse(cue_name, priority, 0.36, 0.20, 110, 0.35)
		&"purge":
			return _pulse(cue_name, priority, 0.40, 0.58, 125, 0.50)
		&"sealed":
			return _pulse(cue_name, priority, 0.65, 0.72, 230, 0.72)
	return {}


func _pulse(
	kind: StringName,
	priority: int,
	weak: float,
	strong: float,
	duration_ms: int,
	amplitude: float,
) -> Dictionary:
	return {
		"kind": kind,
		"priority": priority,
		"weak": weak,
		"strong": strong,
		"duration_ms": duration_ms,
		"duration_seconds": float(duration_ms) / 1000.0,
		"amplitude": amplitude,
	}
