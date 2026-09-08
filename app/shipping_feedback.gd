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
	var exposure := exposure_of(session)
	# A travessia do limiar é uma aresta com **um** dono: a memória do tick anterior vive em
	# `haptics`. O hub pergunta antes de a avançar e entrega a mesma resposta aos dois canais,
	# porque o que se ouve e o que se sente descrevem o mesmo instante — duas cópias da
	# memória divergiriam em silêncio no primeiro tick em que só um dos canais sincronizasse.
	var crossed := haptics.would_cross_warning(exposure)
	audio.sync(session, events, paused, crossed)
	haptics.sync(events, exposure, paused)


## A exposição da trilha lida do snapshot já confirmado, para som e háptica saberem o
## instante em que o jogador atravessa o limiar de risco. Leitura pura: o hub observa a
## sessão, nunca a escreve.
static func exposure_of(session: GameSession) -> float:
	if session == null:
		return 0.0
	return TrailExposure.of_simulation(session.simulation)


func set_feedback_enabled(audio_enabled: bool, haptics_enabled: bool) -> void:
	ensure_ready()
	audio.set_enabled(audio_enabled)
	haptics.enabled = haptics_enabled
