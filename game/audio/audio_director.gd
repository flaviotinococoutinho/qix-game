class_name QixAudioDirector
extends Node
## Mix e música procedural observacionais. `sync` nunca escreve em GameSession.

const BUS_MASTER := &"Qix Master"
const BUS_MUSIC := &"Qix Music"
const BUS_SFX := &"Qix SFX"
const SFX_VOICES := 8
const TRAIL_THROTTLE_MSEC := 36
## O cue do limiar de exposição da trilha. Não está em `cue_for_kind` porque não é
## um evento: é uma aresta lida sobre o snapshot já confirmado, e quem a reconhece
## é o hub de feedback, que compara dois ticks. Ver `QixFeedbackHub.sync`.
const EXPOSURE_CUE := &"exposure"

@export_range(0.0, 1.0, 0.01) var master_volume := 0.90
@export_range(0.0, 1.0, 0.01) var music_volume := 0.52
@export_range(0.0, 1.0, 0.01) var sfx_volume := 0.82
@export var enabled := true

var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _voice_cursor := 0
## Prioridade do cue que cada voz segura e o instante em que ela volta a ficar
## livre. Mantemos isto aqui em vez de ler `AudioStreamPlayer.playing` porque o
## runtime headless nunca inicia o playback: a decisão de mix precisa ser a mesma
## nos dois caminhos para ser testável.
var _voice_priorities := PackedInt32Array()
var _voice_free_msec := PackedInt64Array()
var _round_index := -1
var _last_trail_msec := -TRAIL_THROTTLE_MSEC
var _music_cache: Dictionary = {}
var _cue_cache: Dictionary = {}
var _paused := false
## Instante real em que a pausa começou, ou `-1` enquanto o jogo corre. Enquanto
## é válido, o relógio de mix fica congelado nele — ver `mix_now_msec`.
var _pause_started_msec := -1
## Quantas vozes receberam a ordem de suspensão na última pausa. Guardamos a ordem
## dada em vez de reler `AudioStreamPlayer.stream_paused` pela mesma razão que já
## vale para `_voice_priorities`: essa propriedade deriva dos playbacks vivos, e o
## runtime headless nunca os inicia — relê-la devolveria `false` mesmo depois de a
## pausa ter sido aplicada, e o caminho de mix ficaria por testar.
var _paused_voices := 0


func _ready() -> void:
	ensure_ready()
	if enabled and runtime_allows_playback() and _music.stream != null and not _music.playing:
		_music.play()


func _exit_tree() -> void:
	shutdown()


## Solta playback e PCM antes do AudioServer encerrar. Isso evita referências de
## AudioStreamPlaybackWAV sobrevivendo ao teardown de builds e smoke tests.
func shutdown() -> void:
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	_music_cache.clear()
	_cue_cache.clear()
	_round_index = -1
	_release_all_voices()


func ensure_ready() -> void:
	_ensure_buses()
	_ensure_players()
	_apply_mix()


## Headless runners do not have an audible output and Godot currently retains a
## playback object when the process exits with a runtime WAV still playing.
## Keeping synthesis available but never starting the playback makes server/CI
## smokes deterministic and avoids reporting that engine-level exit leak as a
## game resource leak.
static func runtime_allows_playback() -> bool:
	return (
		DisplayServer.get_name().to_lower() != "headless"
		and arguments_allow_playback(
			OS.get_cmdline_user_args(),
			OS.has_feature("shipping_qa"),
		)
	)


## Probes gráficos medem render e encerram a árvore de forma deliberadamente
## curta. Não abrir AudioStreamPlaybackWAV nesse caminho evita atribuir ao jogo
## o leak de teardown do mixer registrado em godotengine/godot#76745, sem
## silenciar a música no runtime normal nem no smoke Android.
static func arguments_allow_playback(
	arguments: PackedStringArray,
	shipping_qa_enabled: bool = false,
) -> bool:
	if not shipping_qa_enabled:
		return true
	for argument in arguments:
		if argument.begins_with("--shipping-probe="):
			return false
	return true


## Interface única para o bootstrap após a simulação emitir eventos.
##
## `exposure_crossed` é a aresta de `TrailExposure.crossed_warning` para este tick, calculada
## pelo hub. O default `false` preserva quem sincroniza só por eventos.
func sync(
	session: GameSession,
	events: Array[GameEvent],
	paused: bool = false,
	exposure_crossed: bool = false,
) -> void:
	ensure_ready()
	if session != null and session.round_index != _round_index:
		play_round_music(session.round_index)
	apply_pause(paused, Time.get_ticks_msec())
	if not enabled:
		return
	var cues := cues_for_events(events)
	for cue_name in cues:
		play_cue(cue_name)
	# Depois dos cues de evento de propósito: eles reservam voz primeiro, e o aviso entra
	# no que sobrar — nunca por cima da notícia do tick.
	if exposure_crossed and exposure_cue_survives(cues):
		play_cue(EXPOSURE_CUE)


## O aviso de exposição só soa se nada mais alto tiver acontecido no mesmo tick.
##
## Ao contrário da háptica — um actuador, um pulso, e por isso uma disputa que `plan` já
## resolve — o mix tem oito vozes: sem esta regra o aviso entraria numa voz livre por cima
## da captura ou da morte. E o problema não é disputa de canal, é que o aviso **perde o
## objeto**: se o laço fechou, a notícia é o território; se o jogador morreu, já não há
## trilha para estar exposta. A regra e o número são os mesmos de
## `QixHapticFeedback._exposure_pulse`, para que ouvir e sentir não discordem sobre qual foi
## o acontecimento do tick.
static func exposure_cue_survives(event_cues: Array[StringName]) -> bool:
	var exposure_priority := QixProceduralAudioLibrary.priority_for(EXPOSURE_CUE)
	for cue_name in event_cues:
		if QixProceduralAudioLibrary.priority_for(cue_name) > exposure_priority:
			return false
	return true


## Congela ou retoma **todo** o feedback sonoro: a música e as oito vozes de SFX.
## Antes disto a pausa parava só a música, e o cue em voo continuava a tocar por
## cima de um campo já congelado — `death` (0,42 s) e `game_over` (0,75 s) são
## longos o bastante para isso ser audível sempre que se pausa ao morrer.
##
## Retomar não é só voltar a tocar. Os prazos em `_voice_free_msec` são absolutos
## contra `Time.get_ticks_msec()`, que não pára na pausa: sem empurrá-los pelo
## tempo pausado, uma pausa de poucos segundos declararia todas as vozes livres
## enquanto elas ainda seguram áudio por tocar, e o primeiro `trail` depois de
## retomar roubaria a voz do `death` — exatamente o corte que `select_voice`
## existe para impedir. O mesmo vale para o estrangulamento de `trail`.
func apply_pause(paused: bool, now_msec: int) -> void:
	if paused and not _paused:
		_pause_started_msec = now_msec
	elif not paused and _paused:
		var elapsed := maxi(now_msec - _pause_started_msec, 0)
		_pause_started_msec = -1
		for index in _voice_free_msec.size():
			_voice_free_msec[index] += elapsed
		_last_trail_msec += elapsed
	_paused = paused
	if _music != null and _music.is_inside_tree():
		_music.stream_paused = paused
	# Sem guarda de `is_inside_tree`: `stream_paused` só percorre os playbacks vivos,
	# portanto é inócuo fora da árvore, e assim a ordem dada é a mesma no runtime e
	# no runner de teste — que corre inteiro dentro de `_initialize()`, antes de a
	# árvore existir.
	var commanded := 0
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stream_paused = paused
			commanded += 1
	_paused_voices = commanded if paused else 0


## Instante que a mixagem considera "agora": o relógio real quando o jogo corre,
## congelado no início da pausa enquanto ela dura. Puro e estático para que a
## aritmética da pausa seja testável sem depender do relógio da máquina.
static func mix_now_msec(real_now_msec: int, pause_started_msec: int) -> int:
	return pause_started_msec if pause_started_msec >= 0 else real_now_msec


func play_round_music(round_index: int) -> void:
	ensure_ready()
	_round_index = round_index
	if not _music_cache.has(round_index):
		_music_cache[round_index] = QixProceduralAudioLibrary.music_for_round(round_index)
	_music.stream = _music_cache[round_index]
	if enabled and runtime_allows_playback() and _music.is_inside_tree():
		_music.play()


func play_cue(cue_name: StringName) -> void:
	if not enabled:
		return
	ensure_ready()
	var now := mix_now_msec(Time.get_ticks_msec(), _pause_started_msec)
	if cue_name == &"trail":
		if now - _last_trail_msec < TRAIL_THROTTLE_MSEC:
			return
		_last_trail_msec = now
	# O cue é sintetizado e cacheado antes da decisão de mix: mesmo um pedido
	# recusado deve exercitar o pipeline de síntese, que é o que o smoke valida.
	if not _cue_cache.has(cue_name):
		_cue_cache[cue_name] = QixProceduralAudioLibrary.cue(cue_name)
	var priority := QixProceduralAudioLibrary.priority_for(cue_name)
	var index := select_voice(voice_priorities_at(now), priority, _voice_cursor)
	if index < 0:
		return  # todas as vozes seguram algo tão ou mais importante: não corta
	_voice_cursor = (index + 1) % _voices.size()
	_voice_priorities[index] = priority
	_voice_free_msec[index] = now + QixProceduralAudioLibrary.duration_msec(cue_name)
	var voice := _voices[index]
	voice.stream = _cue_cache[cue_name]
	# Headless ainda constrói o cue para validar o pipeline e o cache; só não
	# inicia o hardware playback, que é o caminho afetado pelo leak de teardown.
	if runtime_allows_playback() and voice.is_inside_tree():
		voice.play()


## Prioridade que cada voz ainda segura neste instante, ou `PRIORITY_IDLE` para as
## que já terminaram. É o snapshot que `select_voice` consome.
func voice_priorities_now() -> PackedInt32Array:
	return voice_priorities_at(mix_now_msec(Time.get_ticks_msec(), _pause_started_msec))


## Igual a `voice_priorities_now`, mas com o instante injetado — é por aqui que o
## teste exercita a aritmética da pausa sem depender do relógio da máquina.
func voice_priorities_at(now: int) -> PackedInt32Array:
	var snapshot := PackedInt32Array()
	snapshot.resize(_voices.size())
	for index in _voices.size():
		var busy: bool = index < _voice_free_msec.size() and _voice_free_msec[index] > now
		snapshot[index] = (
			_voice_priorities[index] if busy else QixProceduralAudioLibrary.PRIORITY_IDLE
		)
	return snapshot


## Escolhe a voz que vai tocar `incoming_priority`, ou `-1` se o pedido deve ser
## recusado. `busy_priorities[i]` é a prioridade que a voz `i` ainda segura (ou
## `PRIORITY_IDLE` se está livre) e `cursor` é a próxima voz do rodízio, que mantém
## cues consecutivos espalhados em vez de empilhados na mesma voz.
##
## A regra vem do despacho de canal do Volfied (`reference/volfied/05-som.md` §5.4):
## um pedido só entra num canal ocupado quando é **mais importante** que o que lá
## soa; senão é recusado, e o que já soa termina inteiro. O Volfied codifica isso
## como "menor valor = mais importante"; aqui a escala é a de `QixHapticFeedback`
## (maior valor = mais importante), porque é a que este jogo já usa para ordenar os
## mesmos eventos. O que importa para a experiência é a consequência: a morte do
## jogador nunca mais é cortada ao meio pelo início de uma trilha.
static func select_voice(
	busy_priorities: PackedInt32Array,
	incoming_priority: int,
	cursor: int,
) -> int:
	var count := busy_priorities.size()
	if count == 0:
		return -1
	var victim := -1
	var victim_priority := incoming_priority
	for offset in count:
		var index: int = posmod(cursor + offset, count)
		var holding := busy_priorities[index]
		if holding == QixProceduralAudioLibrary.PRIORITY_IDLE:
			return index
		if holding < victim_priority:
			victim = index
			victim_priority = holding
	return victim


func set_mix(master: float, music: float, sfx: float) -> void:
	master_volume = clampf(master, 0.0, 1.0)
	music_volume = clampf(music, 0.0, 1.0)
	sfx_volume = clampf(sfx, 0.0, 1.0)
	_apply_mix()


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		if _music != null:
			_music.stop()
		for voice in _voices:
			voice.stop()
		_release_all_voices()
	elif runtime_allows_playback() and _music != null and _music.stream != null and _music.is_inside_tree():
		_music.play()


func presentation_state() -> Dictionary:
	return {
		"round_index": _round_index,
		"music_loaded": _music != null and _music.stream != null,
		"music_paused": _paused,
		"mix_clock_frozen": _pause_started_msec >= 0,
		"voice_count": _voices.size(),
		"cached_music": _music_cache.size(),
		"cached_cues": _cue_cache.size(),
		"busy_voices": _busy_voice_count(),
		"paused_voices": _paused_voices,
	}


func _busy_voice_count() -> int:
	var busy := 0
	for priority in voice_priorities_now():
		if priority != QixProceduralAudioLibrary.PRIORITY_IDLE:
			busy += 1
	return busy


func _release_all_voices() -> void:
	_voice_priorities.fill(QixProceduralAudioLibrary.PRIORITY_IDLE)
	_voice_free_msec.fill(0)
	_voice_cursor = 0


static func cues_for_events(events: Array[GameEvent]) -> Array[StringName]:
	var cues: Array[StringName] = []
	for event in events:
		var cue_name := cue_for_kind(event.kind)
		if cue_name != &"" and not cues.has(cue_name):
			cues.append(cue_name)
	return cues


static func cue_for_kind(kind: int) -> StringName:
	match kind:
		GameEvent.Kind.TRAIL_STARTED:
			return &"trail"
		GameEvent.Kind.CAPTURED:
			return &"capture"
		GameEvent.Kind.CAPTURE_REJECTED:
			return &"reject"
		GameEvent.Kind.PLAYER_DIED:
			return &"death"
		GameEvent.Kind.PLAYER_RESPAWNED:
			return &"respawn"
		GameEvent.Kind.SHIELD_CRITICAL:
			return &"shield"
		GameEvent.Kind.ROUND_STARTED:
			return &"round_start"
		GameEvent.Kind.ROUND_CLEAR_STARTED, GameEvent.Kind.ROUND_WON:
			return &"round_clear"
		GameEvent.Kind.GAME_OVER:
			return &"game_over"
		GameEvent.Kind.CAMPAIGN_COMPLETE:
			return &"campaign_complete"
	return &""


func _ensure_players() -> void:
	if not is_instance_valid(_music):
		_music = AudioStreamPlayer.new()
		_music.name = "Music"
		_music.bus = BUS_MUSIC
		add_child(_music)
	while _voices.size() < SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Sfx%02d" % _voices.size()
		voice.bus = BUS_SFX
		add_child(voice)
		_voices.append(voice)
	if _voice_priorities.size() != _voices.size():
		_voice_priorities.resize(_voices.size())
		_voice_free_msec.resize(_voices.size())
		_release_all_voices()


func _ensure_buses() -> void:
	_ensure_bus(BUS_MASTER, &"Master")
	_ensure_bus(BUS_MUSIC, BUS_MASTER)
	_ensure_bus(BUS_SFX, BUS_MASTER)
	var master_index := AudioServer.get_bus_index(BUS_MASTER)
	if master_index >= 0 and AudioServer.get_bus_effect_count(master_index) == 0:
		AudioServer.add_bus_effect(master_index, AudioEffectLimiter.new())


func _ensure_bus(bus_name: StringName, send_to: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, send_to)


func _apply_mix() -> void:
	_set_bus_linear(BUS_MASTER, master_volume)
	_set_bus_linear(BUS_MUSIC, music_volume)
	_set_bus_linear(BUS_SFX, sfx_volume)


func _set_bus_linear(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
