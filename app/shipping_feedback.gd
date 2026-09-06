class_name QixFeedbackHub
extends Node
## Facade de composição: uma chamada `sync` conecta áudio e hápticos à sessão.

var audio: QixAudioDirector
var haptics := QixHapticFeedback.new()


func _ready() -> void:
	ensure_ready()


func ensure_ready() -> void:
	if not is_instance_valid(audio):
		audio = QixAudioDirector.new()
		audio.name = "AudioDirector"
		add_child(audio)
	audio.ensure_ready()


func sync(session: GameSession, events: Array[GameEvent], paused: bool = false) -> void:
	ensure_ready()
	audio.sync(session, events, paused)
	haptics.sync(events, exposure_of(session))


## A exposição da trilha lida do snapshot já confirmado, para a háptica saber o instante em
## que o jogador atravessa o limiar de risco. Leitura pura: o hub observa a sessão, nunca a
## escreve.
##
## O cue sonoro do mesmo limiar ainda não existe — `QixProceduralAudioLibrary` está em
## reautoração de envelopes (ver `docs/LOOP_LEDGER.md`), e um cue novo autorado agora nasceria
## com a forma antiga.
static func exposure_of(session: GameSession) -> float:
	if session == null:
		return 0.0
	return TrailExposure.of_simulation(session.simulation)


func set_feedback_enabled(audio_enabled: bool, haptics_enabled: bool) -> void:
	ensure_ready()
	audio.set_enabled(audio_enabled)
	haptics.enabled = haptics_enabled
