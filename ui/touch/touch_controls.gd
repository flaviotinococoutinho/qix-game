class_name QixTouchControls
extends Control
## Overlay vetorial multi-touch: stick cardinal, ação/confirmar e pausa.
## Não chama a simulação; expõe apenas estado para GameInputAdapter.
##
## Decisões de sensação do stick (F1 — entrada e habilidade, spec §10):
##
## - **Stick flutuante.** Todo toque ancora onde o dedo pousa, inclusive dentro do anel.
##   Pousar não inicia um passo; arrastar produz direção. O flick preserva gestos entre ticks.
## - **Histerese de setor.** Entra numa cardinal a ≥ STICK_ENGAGE_RADIUS do centro e só volta a
##   NONE abaixo de STICK_RELEASE_RADIUS; troca de cardinal só quando o vetor passa
##   STICK_SECTOR_HYSTERESIS_DEG além da diagonal. Sem isso um polegar parado sobre a diagonal
##   oscila entre duas direções a cada quadro e a trilha vira serrilhado.
## - **Flick.** Um toque mais curto que um tick (press, arrasto e release entre duas amostras)
##   ainda produz direção: a última direção não observada por `direction()` fica guardada e
##   `consume_flick_direction()` a entrega uma vez ao adaptador, que a trata como um toque de
##   tecla latched.

const FALLBACK_SIZE := Vector2(240.0, 320.0)
const STICK_CENTER_FROM_BOTTOM := Vector2(52.0, 54.0)
const STICK_RADIUS := 42.0
## Distância do centro a partir da qual uma cardinal entra (era o dead zone fixo).
const STICK_ENGAGE_RADIUS := 11.0
## Distância abaixo da qual a cardinal ativa volta a NONE.
const STICK_RELEASE_RADIUS := 7.0
## Graus além da diagonal (45°) necessários para trocar de cardinal com uma ativa.
const STICK_SECTOR_HYSTERESIS_DEG := 10.0
## cos(45° + histerese): o vetor fica na cardinal atual enquanto dot(v, eixo) ≥ |v| · este valor.
const STICK_SECTOR_KEEP_COS := cos(deg_to_rad(45.0 + STICK_SECTOR_HYSTERESIS_DEG))
const ACTION_CENTER_FROM_BOTTOM := Vector2(48.0, 54.0)
const ACTION_RADIUS := 39.0

## A zona de ancoragem do stick é bem maior que o anel desenhado — um polegar em retrato não
## acerta um alvo de 42 px. Por isso o anel **segue a âncora**: onde o dedo pousa vira o centro
## (`_stick_origin`), e a direção nasce do deslocamento a partir dali, não da distância até um
## centro fixo. Com centro fixo, a zona toda menos um disco de 11 px produzia direção no próprio
## toque — o primeiro quadro de contato já era um passo que o jogador não pediu, e num jogo de
## gramática Qix sair da moldura sem querer é uma trilha que você não escolheu abrir.
const STICK_ZONE_RIGHT_RATIO := 0.55
const STICK_ZONE_TOP_RATIO := 0.48

## A pausa encosta **por baixo** da banda superior do HUD, derivando a altura dela em vez de
## repetir o número. Antes começava em y=10, dentro dos 19 px do HUD: o preenchimento quase
## opaco cobria 32 dos 82 px do trilho do escudo e o pé dos números vitais. Um instrumento meio
## escondido é pior que um instrumento ausente — o jogador lê um valor e acredita nele sem ver
## que falta pedaço, e o escudo é justamente a leitura de urgência.
##
## O custo assumido no lugar disso é um véu sobre o canto superior direito da moldura. É o
## mesmo trato que o anel do stick e o botão de ação já fazem com o rodapé do campo, e a
## opacidade adotada aqui é a deles: sob 24 % de véu a moldura e um corpo de ameaça continuam
## legíveis, sob 58 % um número não continua.
const PAUSE_SIZE := Vector2(32.0, 24.0)
const PAUSE_RIGHT_INSET := 42.0
const PAUSE_TOP := QixGameHud.TOP_BAR_HEIGHT

## Tintas da sobreposição, promovidas de locais de `_draw()` a constantes: é o que permite a
## `tests/unit/touch_hud_occlusion_test.gd` provar que nenhuma peça do chrome é opaca o
## bastante para esconder o que está debaixo dela.
const VEIL_STICK := Color(0.38, 0.97, 0.82, 0.24)
const VEIL_ACTION := Color(1.0, 0.52, 0.66, 0.28)
const VEIL_PAUSE := Color(0.04, 0.08, 0.14, 0.24)
const CHROME_LINE := Color(0.78, 1.0, 0.96, 0.62)
const KNOB_FILL := Color(0.75, 1.0, 0.95, 0.42)

@export var touch_enabled: bool = true:
	set(value):
		touch_enabled = value
		if not value:
			clear_state()
		queue_redraw()

var _roles: Dictionary = {}
var _stick_touch: int = -1
var _stick_origin := Vector2.ZERO
var _stick_position := Vector2.ZERO
var _draw_touches: Dictionary = {}
var _direction: int = MoveIntent.Dir.NONE
var _direction_observed: bool = true
var _flick_direction: int = MoveIntent.Dir.NONE
var _confirm_queued: bool = false
var _pause_queued: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


## Público para QA headless com InputEventScreenTouch/Drag sintéticos.
func handle_event(event: InputEvent) -> bool:
	if not touch_enabled:
		return false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			return _press(touch.index, touch.position)
		return _release(touch.index)
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if int(_roles.get(drag.index, -1)) == 1:
			_stick_position = drag.position
			_update_direction()
			queue_redraw()
			return true
	return false


## Direção mantida pelo stick. Chamar aqui marca a direção atual como observada: um release
## que vier depois já não gera flick, porque o adaptador já a viu.
func direction() -> int:
	_direction_observed = true
	return _direction


## Entrega uma única vez a direção de um flick (stick solto antes de qualquer `direction()`).
func consume_flick_direction() -> int:
	var result := _flick_direction
	_flick_direction = MoveIntent.Dir.NONE
	return result


func is_drawing() -> bool:
	return not _draw_touches.is_empty()


func consume_confirm() -> bool:
	var result := _confirm_queued
	_confirm_queued = false
	return result


func consume_pause() -> bool:
	var result := _pause_queued
	_pause_queued = false
	return result


func clear_state() -> void:
	_roles.clear()
	_draw_touches.clear()
	_stick_touch = -1
	_stick_origin = _default_stick_center()
	_stick_position = _default_stick_center()
	_direction = MoveIntent.Dir.NONE
	_direction_observed = true
	_flick_direction = MoveIntent.Dir.NONE
	_confirm_queued = false
	_pause_queued = false
	queue_redraw()


func presentation_state() -> Dictionary:
	return {
		"direction": _direction,
		"drawing": is_drawing(),
		"stick_touch": _stick_touch,
		"stick_center": _stick_center(),
		"flick_pending": _flick_direction,
		"stick_origin": _stick_center(),
		"active_touches": _roles.size(),
	}


func _press(index: int, position: Vector2) -> bool:
	if _pause_rect().has_point(position):
		_roles[index] = 3
		_pause_queued = true
		queue_redraw()
		return true
	if position.distance_to(_action_center()) <= ACTION_RADIUS * 1.35:
		_roles[index] = 2
		_draw_touches[index] = true
		_confirm_queued = true
		queue_redraw()
		return true
	var layout := _layout_size()
	if position.x <= layout.x * STICK_ZONE_RIGHT_RATIO and position.y >= layout.y * STICK_ZONE_TOP_RATIO:
		if _stick_touch < 0:
			_stick_touch = index
			_stick_origin = position
			_stick_position = position
			_roles[index] = 1
			# Deslocamento zero: pousar o dedo nunca é um passo. Só o arrasto pede direção.
			_flick_direction = MoveIntent.Dir.NONE
			_direction = MoveIntent.Dir.NONE
			_direction_observed = true
			_update_direction()
			queue_redraw()
			return true
	return false


func _release(index: int) -> bool:
	if not _roles.has(index):
		return false
	var role := int(_roles[index])
	_roles.erase(index)
	if role == 1 and _stick_touch == index:
		if _direction != MoveIntent.Dir.NONE and not _direction_observed:
			_flick_direction = _direction
		_stick_touch = -1
		_stick_origin = _default_stick_center()
		_stick_position = _default_stick_center()
		_direction = MoveIntent.Dir.NONE
		_direction_observed = true
	elif role == 2:
		_draw_touches.erase(index)
	queue_redraw()
	return true


## Histerese em duas camadas: magnitude (entrar/sair) e setor (trocar de cardinal).
func _update_direction() -> void:
	var delta := _stick_position - _stick_center()
	var distance := delta.length()
	var previous := _direction
	if previous == MoveIntent.Dir.NONE:
		if distance >= STICK_ENGAGE_RADIUS:
			_direction = _nearest_cardinal(delta)
	elif distance < STICK_RELEASE_RADIUS:
		_direction = MoveIntent.Dir.NONE
	elif not _within_sector(delta, distance, previous):
		_direction = _nearest_cardinal(delta)
	if _direction != previous and _direction != MoveIntent.Dir.NONE:
		_direction_observed = false


static func _nearest_cardinal(delta: Vector2) -> int:
	if absf(delta.x) > absf(delta.y):
		return MoveIntent.Dir.RIGHT if delta.x > 0.0 else MoveIntent.Dir.LEFT
	return MoveIntent.Dir.DOWN if delta.y > 0.0 else MoveIntent.Dir.UP


## O vetor continua dentro do setor alargado da cardinal `dir` (45° + histerese)?
static func _within_sector(delta: Vector2, distance: float, dir: int) -> bool:
	if distance <= 0.0:
		return false
	return delta.dot(_axis_of(dir)) >= distance * STICK_SECTOR_KEEP_COS


static func _axis_of(dir: int) -> Vector2:
	match dir:
		MoveIntent.Dir.UP:
			return Vector2.UP
		MoveIntent.Dir.RIGHT:
			return Vector2.RIGHT
		MoveIntent.Dir.DOWN:
			return Vector2.DOWN
		MoveIntent.Dir.LEFT:
			return Vector2.LEFT
	return Vector2.ZERO


func _layout_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	return FALLBACK_SIZE


## Centro efetivo do stick: o ponto do toque enquanto ele flutua, o padrão no resto do tempo.
func _stick_center() -> Vector2:
	if _stick_touch >= 0:
		return _stick_origin
	return _default_stick_center()


func _default_stick_center() -> Vector2:
	var layout := _layout_size()
	return Vector2(STICK_CENTER_FROM_BOTTOM.x, layout.y - STICK_CENTER_FROM_BOTTOM.y)


func _action_center() -> Vector2:
	var layout := _layout_size()
	return Vector2(layout.x - ACTION_CENTER_FROM_BOTTOM.x, layout.y - ACTION_CENTER_FROM_BOTTOM.y)


func _pause_rect() -> Rect2:
	var layout := _layout_size()
	return Rect2(Vector2(layout.x - PAUSE_RIGHT_INSET, PAUSE_TOP), PAUSE_SIZE)


## Caixas do que a sobreposição realmente desenha, com o veu de cada uma. `_draw()` e a guarda
## de oclusão leem esta mesma função: uma peça nova de chrome nasce medida contra o HUD, sem
## depender de alguém lembrar de a listar num teste.
##
## O anel do stick é dado pelo centro **efetivo**, não pelo de descanso: enquanto o dedo está
## na zona, o anel viaja com ele e é essa a caixa que esconde campo.
func chrome_rects() -> Dictionary:
	var stick := _stick_center()
	var action := _action_center()
	return {
		"stick": {
			"rect": Rect2(stick - Vector2.ONE * STICK_RADIUS, Vector2.ONE * STICK_RADIUS * 2.0),
			"veil": VEIL_STICK,
		},
		"action": {
			"rect": Rect2(action - Vector2.ONE * ACTION_RADIUS, Vector2.ONE * ACTION_RADIUS * 2.0),
			"veil": VEIL_ACTION,
		},
		"pause": {"rect": _pause_rect(), "veil": VEIL_PAUSE},
	}


func _draw() -> void:
	if not touch_enabled:
		return
	var chrome := chrome_rects()
	var center := _stick_center()
	draw_circle(center, STICK_RADIUS, chrome["stick"]["veil"])
	draw_arc(center, STICK_RADIUS, 0.0, TAU, 48, CHROME_LINE, 1.25, true)
	var knob := _stick_position if _stick_touch >= 0 else center
	var delta := knob - center
	if delta.length() > STICK_RADIUS - 8.0:
		knob = center + delta.normalized() * (STICK_RADIUS - 8.0)
	draw_circle(knob, 13.0, KNOB_FILL)
	draw_circle(_action_center(), ACTION_RADIUS, chrome["action"]["veil"])
	draw_arc(_action_center(), ACTION_RADIUS, 0.0, TAU, 48, CHROME_LINE, 1.5, true)
	draw_string(ThemeDB.fallback_font, _action_center() + Vector2(-12.0, 5.0), "DRAW", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, CHROME_LINE)
	var pause: Rect2 = chrome["pause"]["rect"]
	draw_rect(pause, chrome["pause"]["veil"], true)
	draw_rect(pause, CHROME_LINE, false, 1.0)
	draw_line(pause.position + Vector2(12.0, 7.0), pause.position + Vector2(12.0, 17.0), CHROME_LINE, 2.0)
	draw_line(pause.position + Vector2(20.0, 7.0), pause.position + Vector2(20.0, 17.0), CHROME_LINE, 2.0)
