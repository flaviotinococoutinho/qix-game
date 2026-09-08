class_name GameInputAdapter
extends RefCounted
## Une teclado/InputMap, gamepad cru e touch em um intent cardinal por tick.
## Estado cru é isolado por device e agregado deterministicamente; o domínio
## recebe somente MoveIntent.
##
## Por que o adaptador tem memória (F1 — entrada e habilidade, spec §10):
##
## - **Latch de toque por tick.** Um press e um release que chegam entre duas amostras eram
##   invisíveis: `Input.is_action_pressed` já estava falso quando o tick amostrava. Agora todo
##   press de ação (tecla ou botão de gamepad via InputMap) e todo flick do touch é anotado com
##   o tick em que chegou e conta como pressionado na amostra seguinte, por TAP_LATCH_TICKS.
## - **SOCD "último pressionado vence".** Cada direção guarda o número de sequência do seu press
##   mais recente. Direções opostas mantidas ao mesmo tempo não se anulam nem seguem ordem
##   fixa: vence a mais recente. Sem sequência registrada (eventos simultâneos, chamadas
##   estáticas antigas) a ordem canônica UP > RIGHT > DOWN > LEFT continua valendo.
## - **Buffer de curva sem estado no domínio.** A direção perpendicular a `pdir` pressionada
##   nos últimos TURN_BUFFER_TICKS e ainda não consumida vira a primária do MoveIntent; a
##   direção mantida (ou solta há ≤ RELEASE_MEMORY_TICKS) vira o `fallback`. O domínio tenta o
##   fallback só quando a primária bloqueia (`PlayerMotion.substep`), e o replay grava as duas
##   intenções no mesmo byte — a decisão mora aqui, a execução mora no domínio, o checksum não
##   ganha estado novo (invariantes 6 e 7).
##
## Tempo aqui é **contagem de ticks** (`begin_tick`, chamado pelo bootstrap antes de `sample`),
## nunca relógio: o adaptador precisa ser reproduzível em teste headless e não pode variar com
## a cadência de quadros. Fontes amostradas (booleans do InputMap, d-pad cru, stick analógico,
## direção do touch) recebem sequência no instante em que a amostra vê a subida; subidas vistas
## na mesma amostra são simultâneas e empatam (a ordem entre devices não é informação).

const ANALOG_PRESS_THRESHOLD := 0.42
const ANALOG_RELEASE_THRESHOLD := 0.28

## Um press visto entre duas amostras conta na amostra seguinte, mesmo já solto.
const TAP_LATCH_TICKS := 1
## Janela em que uma curva pedida continua sendo tentada enquanto a primária bloqueia.
const TURN_BUFFER_TICKS := 6
## Uma direção solta há até este número de ticks ainda serve de fallback para a curva.
const RELEASE_MEMORY_TICKS := 4

const _NO_TICK := -1

## Quanto o eixo secundário precisa vencer o eixo já sustentado para tomar a direção.
##
## A histerese de magnitude acima decide *se* o stick está empurrado; esta decide *para onde*.
## Sem ela, `absf(x) > absf(y)` era reavaliado a cada `InputEventJoypadMotion` — e o hardware
## manda um evento por eixo, não um vetor —, então um stick parado perto de 45° alternava de
## direção com o próprio ruído do potenciômetro.
##
## Neste jogo isso não é um detalhe de conforto: com `draw` apertado, cada troca de direção é um
## canto novo na trilha confirmada. A escada de cantos alonga a trilha, e comprimento de trilha é
## a moeda que `TrailExposure` lê para acelerar o pulso e nomear o aviso no HUD — o jogador
## pagava exposição por um movimento que não fez.
##
## 0.18 medido contra a deflexão: o eixo só troca depois de ~7° fora da diagonal com o stick no
## fim de curso, ~11° a meia deflexão e ~18° logo acima de `ANALOG_PRESS_THRESHOLD`. A trava é
## mais firme onde o gesto é mais vago, que é onde o ruído domina.
const ANALOG_AXIS_SWITCH_MARGIN := 0.18

var _touch_controls: Object
var _left_sticks_by_device: Dictionary = {}
var _analog_directions_by_device: Dictionary = {}
var _joy_buttons_by_device: Dictionary = {}
var _confirm_queued_by_device: Dictionary = {}
var _pause_queued_by_device: Dictionary = {}

## Contador de ticks do adaptador (só avança em `begin_tick`) e sequência global de presses.
var _tick: int = 0
var _sequence: int = 0

# Estado por direção, indexado por MoveIntent.Dir (índice 0 = NONE, nunca usado).
var _press_seq := PackedInt64Array([0, 0, 0, 0, 0])
var _press_tick := PackedInt64Array([_NO_TICK, _NO_TICK, _NO_TICK, _NO_TICK, _NO_TICK])
var _release_tick := PackedInt64Array([_NO_TICK, _NO_TICK, _NO_TICK, _NO_TICK, _NO_TICK])
var _consumed_seq := PackedInt64Array([0, 0, 0, 0, 0])
var _press_pending := PackedByteArray([0, 0, 0, 0, 0])
var _prev_pressed := PackedByteArray([0, 0, 0, 0, 0])

var _draw_press_tick: int = _NO_TICK
var _draw_press_pending: bool = false


func attach_touch_controls(controls: Object) -> void:
	_touch_controls = controls


## Início de um tick de simulação. Avança o contador que envelhece latches, buffer de curva e
## memória de release, e drena o flick do touch para que ele também expire como um toque de
## tecla se nenhuma amostra o consumir (pausa, transições).
func begin_tick() -> void:
	_tick += 1
	_drain_touch_flick()


## O composition root deve encaminhar `_unhandled_input(event)` para cá.
## Isso completa o InputMap com stick analógico sem gravar estado fora da apresentação.
## Teclas e botões de gamepad passam por aqui só para registrar **bordas** (sequência, latch);
## o estado mantido continua vindo de `Input.is_action_pressed`, que vê todo evento mesmo que
## um Control o consuma antes de chegar a `_unhandled_input`.
func handle_event(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var stick: Vector2 = _left_sticks_by_device.get(motion.device, Vector2.ZERO)
		if motion.axis == JOY_AXIS_LEFT_X:
			stick.x = motion.axis_value
		elif motion.axis == JOY_AXIS_LEFT_Y:
			stick.y = motion.axis_value
		else:
			return
		_left_sticks_by_device[motion.device] = stick
		_update_analog_direction(motion.device)
		return
	if event is InputEventKey:
		_register_action_edges(event)
		return
	if not (event is InputEventJoypadButton):
		return
	var button := event as InputEventJoypadButton
	_register_action_edges(button)
	var device_buttons: Dictionary = _joy_buttons_by_device.get(button.device, {})
	if button.pressed:
		device_buttons[button.button_index] = true
	else:
		device_buttons.erase(button.button_index)
	if device_buttons.is_empty():
		_joy_buttons_by_device.erase(button.device)
	else:
		_joy_buttons_by_device[button.device] = device_buttons
	if not button.pressed:
		return
	if button.button_index == JOY_BUTTON_A:
		_confirm_queued_by_device[button.device] = true
	elif button.button_index == JOY_BUTTON_START:
		_pause_queued_by_device[button.device] = true


func sample(preferred_direction: int = MoveIntent.Dir.NONE) -> MoveIntent:
	return sample_from_state(
		preferred_direction,
		Input.is_action_pressed("move_up"),
		Input.is_action_pressed("move_right"),
		Input.is_action_pressed("move_down"),
		Input.is_action_pressed("move_left"),
		Input.is_action_pressed("draw"),
	)


## Variante pura/injetável para testes e smoke tests exportados. Compõe tudo: booleans do
## InputMap, d-pad e stick crus, touch (direção mantida e flick), latches, sequências, buffer
## de curva e fallback. `preferred_direction` é o `pdir` da simulação no tick anterior.
func sample_from_state(
	preferred_direction: int,
	up: bool,
	right: bool,
	down: bool,
	left: bool,
	draw: bool,
) -> MoveIntent:
	var touch_direction := MoveIntent.Dir.NONE
	var touch_draw := false
	if is_instance_valid(_touch_controls):
		if _touch_controls.has_method("direction"):
			touch_direction = int(_touch_controls.call("direction"))
		if _touch_controls.has_method("is_drawing"):
			touch_draw = bool(_touch_controls.call("is_drawing"))
		_drain_touch_flick()

	var polled := PackedByteArray([0, 0, 0, 0, 0])
	polled[MoveIntent.Dir.UP] = 1 if up or _button_pressed(JOY_BUTTON_DPAD_UP) \
		or _analog_direction_pressed(MoveIntent.Dir.UP) or touch_direction == MoveIntent.Dir.UP else 0
	polled[MoveIntent.Dir.RIGHT] = 1 if right or _button_pressed(JOY_BUTTON_DPAD_RIGHT) \
		or _analog_direction_pressed(MoveIntent.Dir.RIGHT) or touch_direction == MoveIntent.Dir.RIGHT else 0
	polled[MoveIntent.Dir.DOWN] = 1 if down or _button_pressed(JOY_BUTTON_DPAD_DOWN) \
		or _analog_direction_pressed(MoveIntent.Dir.DOWN) or touch_direction == MoveIntent.Dir.DOWN else 0
	polled[MoveIntent.Dir.LEFT] = 1 if left or _button_pressed(JOY_BUTTON_DPAD_LEFT) \
		or _analog_direction_pressed(MoveIntent.Dir.LEFT) or touch_direction == MoveIntent.Dir.LEFT else 0

	# Estado efetivo por direção: fonte amostrada OU latch de um press visto entre amostras.
	# Subidas sem evento registrado ganham sequência agora; subidas na mesma amostra empatam.
	var pressed := PackedByteArray([0, 0, 0, 0, 0])
	var simultaneous_seq := 0
	for dir in range(MoveIntent.Dir.UP, MoveIntent.Dir.LEFT + 1):
		var latched := _press_pending[dir] == 1 \
			and _tick - _press_tick[dir] <= TAP_LATCH_TICKS
		var now := polled[dir] == 1 or latched
		if now and _prev_pressed[dir] == 0 and _press_pending[dir] == 0:
			if simultaneous_seq == 0:
				_sequence += 1
				simultaneous_seq = _sequence
			_press_seq[dir] = simultaneous_seq
			_press_tick[dir] = _tick
		elif not now and _prev_pressed[dir] == 1:
			_release_tick[dir] = _tick
		pressed[dir] = 1 if now else 0
		_prev_pressed[dir] = pressed[dir]
		_press_pending[dir] = 0

	# A curva pedida foi executada: `pdir` passou a ser ela. Consome o press para o buffer não
	# a pedir de novo quando o fallback devolver o jogador à direção anterior.
	if MoveIntent.is_valid_dir(preferred_direction) and preferred_direction != MoveIntent.Dir.NONE:
		_consumed_seq[preferred_direction] = _press_seq[preferred_direction]

	var socd_winner := choose_direction_with_sequence(
		pressed[MoveIntent.Dir.UP] == 1,
		pressed[MoveIntent.Dir.RIGHT] == 1,
		pressed[MoveIntent.Dir.DOWN] == 1,
		pressed[MoveIntent.Dir.LEFT] == 1,
		preferred_direction,
		_press_seq[MoveIntent.Dir.UP],
		_press_seq[MoveIntent.Dir.RIGHT],
		_press_seq[MoveIntent.Dir.DOWN],
		_press_seq[MoveIntent.Dir.LEFT],
	)
	var buffered := _buffered_turn(preferred_direction)
	var primary := buffered if buffered != MoveIntent.Dir.NONE else socd_winner
	var fallback := _fallback_for(primary, pressed, buffered != MoveIntent.Dir.NONE)

	var draw_latched := _draw_press_pending and _tick - _draw_press_tick <= TAP_LATCH_TICKS
	_draw_press_pending = false
	var drawing := draw or _button_pressed(JOY_BUTTON_A) \
		or _button_pressed(JOY_BUTTON_X) or touch_draw or draw_latched
	return MoveIntent.make(primary, drawing, fallback)


## Consolida o edge do InputMap com os canais crus/touch e sempre drena todos.
## O mesmo botão físico pode aparecer nos dois primeiros canais no mesmo tick.
func consume_confirm(input_map_just_pressed: bool = false) -> bool:
	var queued := not _confirm_queued_by_device.is_empty() or input_map_just_pressed
	_confirm_queued_by_device.clear()
	if is_instance_valid(_touch_controls) and _touch_controls.has_method("consume_confirm"):
		queued = bool(_touch_controls.call("consume_confirm")) or queued
	return queued


func consume_pause(input_map_just_pressed: bool = false) -> bool:
	var queued := not _pause_queued_by_device.is_empty() or input_map_just_pressed
	_pause_queued_by_device.clear()
	if is_instance_valid(_touch_controls) and _touch_controls.has_method("consume_pause"):
		queued = bool(_touch_controls.call("consume_pause")) or queued
	return queued


## Restart e perda de foco: nada de stick, botão, latch, buffer ou memória de release
## atravessa a fronteira. O contador de ticks e a sequência global continuam monotônicos.
func reset_transient_state() -> void:
	_left_sticks_by_device.clear()
	_analog_directions_by_device.clear()
	_joy_buttons_by_device.clear()
	_confirm_queued_by_device.clear()
	_pause_queued_by_device.clear()
	for dir in range(_press_seq.size()):
		_press_seq[dir] = 0
		_press_tick[dir] = _NO_TICK
		_release_tick[dir] = _NO_TICK
		_consumed_seq[dir] = 0
		_press_pending[dir] = 0
		_prev_pressed[dir] = 0
	_draw_press_tick = _NO_TICK
	_draw_press_pending = false


func handle_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_clear_device_state(device)


## Registra a borda de press/release das ações de movimento e `draw` vindas do InputMap.
## Echo de tecla não é press (`is_action_pressed` já o descarta). Ações ausentes do mapa são
## ignoradas para que um projeto com InputMap parcial não gere erro por evento.
func _register_action_edges(event: InputEvent) -> void:
	for dir in range(MoveIntent.Dir.UP, MoveIntent.Dir.LEFT + 1):
		var action := _action_for(dir)
		if not InputMap.has_action(action):
			continue
		if event.is_action_pressed(action):
			_register_press(dir)
	if InputMap.has_action(&"draw") and event.is_action_pressed(&"draw"):
		_draw_press_tick = _tick
		_draw_press_pending = true


func _register_press(dir: int) -> void:
	_sequence += 1
	_press_seq[dir] = _sequence
	_press_tick[dir] = _tick
	_press_pending[dir] = 1


## Flick do touch: press e release dentro do mesmo tick viram um press latched aqui, com a
## mesma vida útil de um toque de tecla.
func _drain_touch_flick() -> void:
	if not is_instance_valid(_touch_controls) or not _touch_controls.has_method("consume_flick_direction"):
		return
	var flick := int(_touch_controls.call("consume_flick_direction"))
	if MoveIntent.is_valid_dir(flick) and flick != MoveIntent.Dir.NONE:
		_register_press(flick)


## Direção perpendicular a `preferred_direction` pressionada há ≤ TURN_BUFFER_TICKS, mais
## recente que o press da própria `preferred_direction` e ainda não consumida. A regra "mais
## recente que a preferida" evita que um press antigo sequestre a primária depois que o
## jogador já escolheu (e executou) outra direção.
func _buffered_turn(preferred_direction: int) -> int:
	if not MoveIntent.is_valid_dir(preferred_direction) or preferred_direction == MoveIntent.Dir.NONE:
		return MoveIntent.Dir.NONE
	var preferred_seq := _press_seq[preferred_direction]
	var best := MoveIntent.Dir.NONE
	var best_seq := 0
	for dir in _perpendiculars_of(preferred_direction):
		var seq := _press_seq[dir]
		if seq <= 0 or seq <= _consumed_seq[dir] or seq <= preferred_seq:
			continue
		if _tick - _press_tick[dir] > TURN_BUFFER_TICKS:
			continue
		if seq > best_seq:
			best_seq = seq
			best = dir
	return best


## Fallback: a direção mantida mais recente diferente da primária; com buffer ativo, também
## uma direção solta há ≤ RELEASE_MEMORY_TICKS (o dedo que saiu de RIGHT para pedir UP ainda
## quer deslizar por RIGHT até a curva ser legal). Nunca igual à primária.
func _fallback_for(primary: int, pressed: PackedByteArray, buffer_active: bool) -> int:
	var best := MoveIntent.Dir.NONE
	var best_seq := 0
	for dir in range(MoveIntent.Dir.UP, MoveIntent.Dir.LEFT + 1):
		if dir == primary or pressed[dir] == 0:
			continue
		if _press_seq[dir] > best_seq:
			best_seq = _press_seq[dir]
			best = dir
	if best != MoveIntent.Dir.NONE or not buffer_active:
		return best
	var best_release := _NO_TICK
	for dir in range(MoveIntent.Dir.UP, MoveIntent.Dir.LEFT + 1):
		if dir == primary or pressed[dir] == 1 or _release_tick[dir] == _NO_TICK:
			continue
		if _tick - _release_tick[dir] > RELEASE_MEMORY_TICKS:
			continue
		if _release_tick[dir] > best_release \
			or (_release_tick[dir] == best_release and _press_seq[dir] > best_seq):
			best_release = _release_tick[dir]
			best_seq = _press_seq[dir]
			best = dir
	return best


func _button_pressed(button_index: int) -> bool:
	for value in _joy_buttons_by_device.values():
		var device_buttons: Dictionary = value
		if bool(device_buttons.get(button_index, false)):
			return true
	return false


func _analog_direction_pressed(direction: int) -> bool:
	for value in _analog_directions_by_device.values():
		if int(value) == direction:
			return true
	return false


func _update_analog_direction(device: int) -> void:
	var stick: Vector2 = _left_sticks_by_device.get(device, Vector2.ZERO)
	var current_direction := int(
		_analog_directions_by_device.get(device, MoveIntent.Dir.NONE),
	)
	var magnitude := stick.length()
	var threshold := ANALOG_RELEASE_THRESHOLD \
		if current_direction != MoveIntent.Dir.NONE else ANALOG_PRESS_THRESHOLD
	if magnitude < threshold:
		_analog_directions_by_device.erase(device)
		return
	_analog_directions_by_device[device] = resolve_analog_direction(stick, current_direction)


func _clear_device_state(device: int) -> void:
	_left_sticks_by_device.erase(device)
	_analog_directions_by_device.erase(device)
	_joy_buttons_by_device.erase(device)
	_confirm_queued_by_device.erase(device)
	_pause_queued_by_device.erase(device)


static func _action_for(dir: int) -> StringName:
	match dir:
		MoveIntent.Dir.UP:
			return &"move_up"
		MoveIntent.Dir.RIGHT:
			return &"move_right"
		MoveIntent.Dir.DOWN:
			return &"move_down"
		MoveIntent.Dir.LEFT:
			return &"move_left"
	return &""


static func _opposite_of(dir: int) -> int:
	match dir:
		MoveIntent.Dir.UP:
			return MoveIntent.Dir.DOWN
		MoveIntent.Dir.DOWN:
			return MoveIntent.Dir.UP
		MoveIntent.Dir.RIGHT:
			return MoveIntent.Dir.LEFT
		MoveIntent.Dir.LEFT:
			return MoveIntent.Dir.RIGHT
	return MoveIntent.Dir.NONE


static func _perpendiculars_of(dir: int) -> PackedInt32Array:
	if dir == MoveIntent.Dir.UP or dir == MoveIntent.Dir.DOWN:
		return PackedInt32Array([MoveIntent.Dir.RIGHT, MoveIntent.Dir.LEFT])
	if dir == MoveIntent.Dir.RIGHT or dir == MoveIntent.Dir.LEFT:
		return PackedInt32Array([MoveIntent.Dir.UP, MoveIntent.Dir.DOWN])
	return PackedInt32Array()

## Eixo dominante do stick, com trava no eixo já sustentado.
##
## É o análogo analógico do que `choose_direction` faz para o digital: sob ambiguidade, quem
## está valendo continua valendo. Sem direção sustentada o desempate é o antigo — `|x| > |y|`,
## empate exato vai para o vertical —, então o primeiro toque de um stick não muda de
## comportamento. Trocar de **sentido** dentro do mesmo eixo escapa da trava por construção: a
## margem compara módulos, e `RIGHT`→`LEFT` não altera qual eixo domina.
static func resolve_analog_direction(stick: Vector2, current_direction: int) -> int:
	var horizontal := absf(stick.x) > absf(stick.y)
	if _is_horizontal(current_direction):
		horizontal = absf(stick.y) <= absf(stick.x) + ANALOG_AXIS_SWITCH_MARGIN
	elif _is_vertical(current_direction):
		horizontal = absf(stick.x) > absf(stick.y) + ANALOG_AXIS_SWITCH_MARGIN
	if horizontal:
		return MoveIntent.Dir.RIGHT if stick.x > 0.0 else MoveIntent.Dir.LEFT
	return MoveIntent.Dir.DOWN if stick.y > 0.0 else MoveIntent.Dir.UP


static func _is_horizontal(direction: int) -> bool:
	return direction == MoveIntent.Dir.RIGHT or direction == MoveIntent.Dir.LEFT


static func _is_vertical(direction: int) -> bool:
	return direction == MoveIntent.Dir.UP or direction == MoveIntent.Dir.DOWN


## Mantém a direção atual em diagonais/sobreposição; sem preferência usa ordem canônica.
## Forma sem sequência: equivale a todos os presses terem chegado ao mesmo tempo.
static func choose_direction(
	up: bool,
	right: bool,
	down: bool,
	left: bool,
	preferred_direction: int = MoveIntent.Dir.NONE,
) -> int:
	return choose_direction_with_sequence(
		up, right, down, left, preferred_direction, 0, 0, 0, 0,
	)


## SOCD "último pressionado vence": a preferida (pdir) continua enquanto estiver pressionada e
## a sua oposta não tiver um press **mais recente**; fora isso vence a maior sequência entre as
## pressionadas, com empate decidido pela ordem canônica UP > RIGHT > DOWN > LEFT.
static func choose_direction_with_sequence(
	up: bool,
	right: bool,
	down: bool,
	left: bool,
	preferred_direction: int,
	up_seq: int,
	right_seq: int,
	down_seq: int,
	left_seq: int,
) -> int:
	var pressed := [false, up, right, down, left]
	var sequences := [0, up_seq, right_seq, down_seq, left_seq]
	if preferred_direction >= MoveIntent.Dir.UP and preferred_direction <= MoveIntent.Dir.LEFT \
		and bool(pressed[preferred_direction]):
		var opposite := _opposite_of(preferred_direction)
		var reversed: bool = bool(pressed[opposite]) \
			and int(sequences[opposite]) > int(sequences[preferred_direction])
		if not reversed:
			return preferred_direction
	var best := MoveIntent.Dir.NONE
	var best_seq := -1
	for dir in range(MoveIntent.Dir.UP, MoveIntent.Dir.LEFT + 1):
		if bool(pressed[dir]) and int(sequences[dir]) > best_seq:
			best = dir
			best_seq = int(sequences[dir])
	return best
