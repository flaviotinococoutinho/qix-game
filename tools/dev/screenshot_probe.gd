extends SceneTree
## Sonda visual de desenvolvimento: roda a cena principal com renderer real, injeta uma
## rota de entrada e salva PNGs do viewport. Serve para revisar a apresentação sem editor.
##
## Uso (janela abre brevemente; não funciona em --headless):
##   Godot --path . --script res://tools/dev/screenshot_probe.gd -- \
##       --out=/caminho/prefixo --route=intro,L36,D141:draw,R20,U141:draw --shots=60,240,420
##
## `--route` é uma lista de segmentos: `intro` confirma a intro; `L36` segura LEFT por 36
## ticks; `D141:draw` segura DOWN + draw por 141 ticks; `W30` espera 30 ticks sem entrada.
## `--shots` são os ticks (contados a partir do início da rota) em que salvar um PNG.
## Nada aqui toca o domínio diretamente: a entrada passa por `Input.action_press`, o mesmo
## caminho do teclado, e o bootstrap continua dono do tick.

const BOOTSTRAP_SCENE := "res://app/bootstrap.tscn"

var _out_prefix := "build/dev/shot"
var _segments: Array = []
var _shot_ticks: Array[int] = []
var _tick := 0
var _segment_index := 0
var _segment_ticks_left := 0
var _bootstrap: Node
var _pressed: Array[String] = []
var _started := false
var _settle_frames := 4
var _stretch_override := ""
var _window_scale := 0


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	var packed := load(BOOTSTRAP_SCENE) as PackedScene
	if packed == null:
		printerr("QIX_SHOT_ERROR não carregou " + BOOTSTRAP_SCENE)
		quit(2)
		return
	_bootstrap = packed.instantiate()
	if _stretch_override != "":
		# Permite comparar modos de stretch sem editar project.godot: só apresentação.
		match _stretch_override:
			"canvas_items":
				root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			"viewport":
				root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		if _window_scale > 0:
			root.size = Vector2i(240 * _window_scale, 320 * _window_scale)
	root.add_child(_bootstrap)
	print("QIX_SHOT_START out=%s segments=%d shots=%s" % [_out_prefix, _segments.size(), str(_shot_ticks)])


func _physics_process(_delta: float) -> bool:
	if _bootstrap == null:
		return false
	if _settle_frames > 0:
		_settle_frames -= 1
		return false
	if not _started:
		_started = true
		_begin_segment()
	_apply_segment_input()
	_tick += 1
	if _shot_ticks.has(_tick):
		_save_shot(_tick)
	if _segment_ticks_left > 0:
		_segment_ticks_left -= 1
		if _segment_ticks_left == 0:
			_segment_index += 1
			_begin_segment()
	if _segment_index >= _segments.size() and (_shot_ticks.is_empty() or _tick >= _shot_ticks.max()):
		_release_all()
		print("QIX_SHOT_DONE ticks=%d" % _tick)
		quit(0)
		return true
	return false


func _begin_segment() -> void:
	_release_all()
	if _segment_index >= _segments.size():
		_segment_ticks_left = 0
		return
	var segment: Dictionary = _segments[_segment_index]
	_segment_ticks_left = int(segment.get("ticks", 1))
	if segment.get("confirm", false):
		Input.action_press("ui_accept")
		_pressed.append("ui_accept")


func _apply_segment_input() -> void:
	if _segment_index >= _segments.size():
		return
	var segment: Dictionary = _segments[_segment_index]
	var action: String = segment.get("action", "")
	if action != "" and not _pressed.has(action):
		Input.action_press(action)
		_pressed.append(action)
	if segment.get("draw", false) and not _pressed.has("draw"):
		Input.action_press("draw")
		_pressed.append("draw")
	# A confirmação é um edge: solta no tick seguinte para não repetir.
	if _pressed.has("ui_accept") and _segment_ticks_left < int(segment.get("ticks", 1)):
		Input.action_release("ui_accept")
		_pressed.erase("ui_accept")


func _release_all() -> void:
	for action in _pressed:
		Input.action_release(action)
	_pressed.clear()


func _save_shot(tick: int) -> void:
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		printerr("QIX_SHOT_ERROR viewport sem imagem no tick %d" % tick)
		return
	var path := "%s_%04d.png" % [_out_prefix, tick]
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := image.save_png(path)
	if err != OK:
		printerr("QIX_SHOT_ERROR save_png %s -> %d" % [path, err])
		return
	var state := ""
	if _bootstrap != null and _bootstrap.get("session") != null:
		var session = _bootstrap.get("session")
		state = "phase=%d round=%d permille=%d tick=%d" % [
			session.phase, session.round_index, session.simulation.permille, session.simulation.tick,
		]
	print("QIX_SHOT_SAVED %s %dx%d %s" % [path, image.get_width(), image.get_height(), state])


func _parse_args(args: PackedStringArray) -> void:
	var route := "intro,W120"
	var shots := "30"
	for argument in args:
		if argument.begins_with("--out="):
			_out_prefix = argument.trim_prefix("--out=")
		elif argument.begins_with("--route="):
			route = argument.trim_prefix("--route=")
		elif argument.begins_with("--shots="):
			shots = argument.trim_prefix("--shots=")
		elif argument.begins_with("--stretch="):
			_stretch_override = argument.trim_prefix("--stretch=")
		elif argument.begins_with("--window-scale="):
			_window_scale = argument.trim_prefix("--window-scale=").to_int()
	for token in route.split(",", false):
		var t := token.strip_edges()
		if t == "intro":
			_segments.append({"confirm": true, "ticks": 2})
			continue
		var draw := t.ends_with(":draw")
		if draw:
			t = t.trim_suffix(":draw")
		var letter := t.substr(0, 1).to_upper()
		var count := t.substr(1).to_int()
		var action := ""
		match letter:
			"L": action = "move_left"
			"R": action = "move_right"
			"U": action = "move_up"
			"D": action = "move_down"
			"W": action = ""
			_:
				printerr("QIX_SHOT_ERROR segmento desconhecido: " + token)
				continue
		_segments.append({"action": action, "draw": draw, "ticks": maxi(1, count)})
	for token in shots.split(",", false):
		var value := token.strip_edges().to_int()
		if value > 0:
			_shot_ticks.append(value)
