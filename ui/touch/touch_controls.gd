class_name QixTouchControls
extends Control
## Overlay vetorial multi-touch: stick cardinal, ação/confirmar e pausa.
## Não chama a simulação; expõe apenas estado para GameInputAdapter.

const FALLBACK_SIZE := Vector2(240.0, 320.0)
const STICK_CENTER_FROM_BOTTOM := Vector2(52.0, 54.0)
const STICK_RADIUS := 42.0
const STICK_DEAD_ZONE := 11.0
const ACTION_CENTER_FROM_BOTTOM := Vector2(48.0, 54.0)
const ACTION_RADIUS := 39.0

@export var touch_enabled: bool = true:
	set(value):
		touch_enabled = value
		if not value:
			clear_state()
		queue_redraw()

var _roles: Dictionary = {}
var _stick_touch: int = -1
var _stick_position := Vector2.ZERO
var _draw_touches: Dictionary = {}
var _direction: int = MoveIntent.Dir.NONE
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


func direction() -> int:
	return _direction


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
	_stick_position = _stick_center()
	_direction = MoveIntent.Dir.NONE
	_confirm_queued = false
	_pause_queued = false
	queue_redraw()


func presentation_state() -> Dictionary:
	return {
		"direction": _direction,
		"drawing": is_drawing(),
		"stick_touch": _stick_touch,
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
	if position.x <= _layout_size().x * 0.55 and position.y >= _layout_size().y * 0.48:
		if _stick_touch < 0:
			_stick_touch = index
			_stick_position = position
			_roles[index] = 1
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
		_stick_touch = -1
		_stick_position = _stick_center()
		_direction = MoveIntent.Dir.NONE
	elif role == 2:
		_draw_touches.erase(index)
	queue_redraw()
	return true


func _update_direction() -> void:
	var delta := _stick_position - _stick_center()
	if delta.length() < STICK_DEAD_ZONE:
		_direction = MoveIntent.Dir.NONE
	elif absf(delta.x) > absf(delta.y):
		_direction = MoveIntent.Dir.RIGHT if delta.x > 0.0 else MoveIntent.Dir.LEFT
	else:
		_direction = MoveIntent.Dir.DOWN if delta.y > 0.0 else MoveIntent.Dir.UP


func _layout_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	return FALLBACK_SIZE


func _stick_center() -> Vector2:
	var layout := _layout_size()
	return Vector2(STICK_CENTER_FROM_BOTTOM.x, layout.y - STICK_CENTER_FROM_BOTTOM.y)


func _action_center() -> Vector2:
	var layout := _layout_size()
	return Vector2(layout.x - ACTION_CENTER_FROM_BOTTOM.x, layout.y - ACTION_CENTER_FROM_BOTTOM.y)


func _pause_rect() -> Rect2:
	var layout := _layout_size()
	return Rect2(layout.x - 42.0, 10.0, 32.0, 24.0)


func _draw() -> void:
	if not touch_enabled:
		return
	var cyan := Color(0.38, 0.97, 0.82, 0.24)
	var hot := Color(1.0, 0.52, 0.66, 0.28)
	var line := Color(0.78, 1.0, 0.96, 0.62)
	draw_circle(_stick_center(), STICK_RADIUS, cyan)
	draw_arc(_stick_center(), STICK_RADIUS, 0.0, TAU, 48, line, 1.25, true)
	var knob := _stick_position if _stick_touch >= 0 else _stick_center()
	var delta := knob - _stick_center()
	if delta.length() > STICK_RADIUS - 8.0:
		knob = _stick_center() + delta.normalized() * (STICK_RADIUS - 8.0)
	draw_circle(knob, 13.0, Color(0.75, 1.0, 0.95, 0.42))
	draw_circle(_action_center(), ACTION_RADIUS, hot)
	draw_arc(_action_center(), ACTION_RADIUS, 0.0, TAU, 48, line, 1.5, true)
	draw_string(ThemeDB.fallback_font, _action_center() + Vector2(-12.0, 5.0), "DRAW", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, line)
	var pause := _pause_rect()
	draw_rect(pause, Color(0.04, 0.08, 0.14, 0.58), true)
	draw_rect(pause, line, false, 1.0)
	draw_line(pause.position + Vector2(12.0, 7.0), pause.position + Vector2(12.0, 17.0), line, 2.0)
	draw_line(pause.position + Vector2(20.0, 7.0), pause.position + Vector2(20.0, 17.0), line, 2.0)
