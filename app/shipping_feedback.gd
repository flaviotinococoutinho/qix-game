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
	haptics.sync(events, paused)


func set_feedback_enabled(audio_enabled: bool, haptics_enabled: bool) -> void:
	ensure_ready()
	audio.set_enabled(audio_enabled)
	haptics.enabled = haptics_enabled
