class_name QixHapticFeedback
extends RefCounted
## Planeja um único pulso por tick e despacha para gamepad/mobile.

@export var enabled := true
@export_range(0.0, 1.0, 0.05) var intensity := 1.0


func plan(events: Array[GameEvent], paused: bool = false) -> Dictionary:
	if not enabled or paused:
		return {}
	var best: Dictionary = {}
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


func sync(events: Array[GameEvent], paused: bool = false) -> Dictionary:
	if paused:
		for joypad_id in Input.get_connected_joypads():
			Input.stop_joy_vibration(joypad_id)
		return {}
	var pulse := plan(events, paused)
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
