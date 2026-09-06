class_name GameInputAdapter
extends RefCounted
## Une teclado/InputMap, gamepad cru e touch em um intent cardinal por tick.
## Estado cru é isolado por device e agregado deterministicamente; o domínio
## recebe somente MoveIntent.

const ANALOG_PRESS_THRESHOLD := 0.42
const ANALOG_RELEASE_THRESHOLD := 0.28

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


func attach_touch_controls(controls: Object) -> void:
	_touch_controls = controls


## O composition root deve encaminhar `_unhandled_input(event)` para cá.
## Isso completa o InputMap com stick analógico sem gravar estado fora da apresentação.
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
	if not (event is InputEventJoypadButton):
		return
	var button := event as InputEventJoypadButton
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


## Variante pura/injetável para testes e smoke tests exportados.
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
	var all_up := up or _button_pressed(JOY_BUTTON_DPAD_UP) \
		or _analog_direction_pressed(MoveIntent.Dir.UP) or touch_direction == MoveIntent.Dir.UP
	var all_right := right or _button_pressed(JOY_BUTTON_DPAD_RIGHT) \
		or _analog_direction_pressed(MoveIntent.Dir.RIGHT) or touch_direction == MoveIntent.Dir.RIGHT
	var all_down := down or _button_pressed(JOY_BUTTON_DPAD_DOWN) \
		or _analog_direction_pressed(MoveIntent.Dir.DOWN) or touch_direction == MoveIntent.Dir.DOWN
	var all_left := left or _button_pressed(JOY_BUTTON_DPAD_LEFT) \
		or _analog_direction_pressed(MoveIntent.Dir.LEFT) or touch_direction == MoveIntent.Dir.LEFT
	var direction := choose_direction(
		all_up,
		all_right,
		all_down,
		all_left,
		preferred_direction,
	)
	var drawing := draw or _button_pressed(JOY_BUTTON_A) \
		or _button_pressed(JOY_BUTTON_X) or touch_draw
	return MoveIntent.make(direction, drawing)


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


func reset_transient_state() -> void:
	_left_sticks_by_device.clear()
	_analog_directions_by_device.clear()
	_joy_buttons_by_device.clear()
	_confirm_queued_by_device.clear()
	_pause_queued_by_device.clear()


func handle_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_clear_device_state(device)


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
static func choose_direction(
	up: bool,
	right: bool,
	down: bool,
	left: bool,
	preferred_direction: int = MoveIntent.Dir.NONE,
) -> int:
	match preferred_direction:
		MoveIntent.Dir.UP:
			if up:
				return MoveIntent.Dir.UP
		MoveIntent.Dir.RIGHT:
			if right:
				return MoveIntent.Dir.RIGHT
		MoveIntent.Dir.DOWN:
			if down:
				return MoveIntent.Dir.DOWN
		MoveIntent.Dir.LEFT:
			if left:
				return MoveIntent.Dir.LEFT
	if up:
		return MoveIntent.Dir.UP
	if right:
		return MoveIntent.Dir.RIGHT
	if down:
		return MoveIntent.Dir.DOWN
	if left:
		return MoveIntent.Dir.LEFT
	return MoveIntent.Dir.NONE
