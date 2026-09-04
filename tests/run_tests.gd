extends SceneTree
## Runner headless determinístico. Uso:
##   Godot --headless --path . --script res://tests/run_tests.gd [-- filtro]
## Descobre res://tests/{unit,integration}/*_test.gd, instancia cada script (extends TestCase)
## e chama todo método `test_*` em ordem alfabética. Sai com 1 se algo falhar.

const DIRS := ["res://tests/unit", "res://tests/integration"]
const ScriptErrorCapture := preload("res://tests/support/script_error_capture.gd")

var _script_error_capture
var _capture_registered := false


func _initialize() -> void:
	_register_script_error_capture()
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var total := 0
	var failures := 0
	var assertions := 0
	var started := Time.get_ticks_usec()
	for dir in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f in files:
			if not f.ends_with("_test.gd"):
				continue
			var script: GDScript = load(dir + "/" + f)
			if script == null or not script.can_instantiate():
				printerr("ERRO: não carregou " + f)
				failures += 1
				continue
			var inst = script.new()
			if not (inst is TestCase):
				printerr("ERRO: %s não estende TestCase" % f)
				failures += 1
				continue
			var names: Array[String] = []
			for m in inst.get_method_list():
				if m.name.begins_with("test_"):
					names.append(m.name)
			names.sort()
			for name in names:
				if filter != "" and not (f + "::" + name).contains(filter):
					continue
				total += 1
				inst.reset()
				_script_error_capture.begin_capture()
				inst.call(name)
				var script_errors: PackedStringArray = _script_error_capture.end_capture()
				if not script_errors.is_empty():
					inst.fail(
						"teste abortado por SCRIPT ERROR:\n      "
						+ "\n      ".join(script_errors),
					)
				if inst.assertions == 0:
					inst.fail("teste terminou sem asserções; possível erro de runtime antes da validação")
				assertions += inst.assertions
				if inst.failed:
					failures += 1
					print("FAIL  %s::%s\n%s" % [f, name, inst.messages])
				else:
					print("ok    %s::%s" % [f, name])
	var ms := (Time.get_ticks_usec() - started) / 1000
	print("\n%d testes, %d asserções, %d falhas, %d ms" % [total, assertions, failures, ms])
	_unregister_script_error_capture()
	quit(1 if failures > 0 or total == 0 else 0)


func _finalize() -> void:
	_unregister_script_error_capture()


func _register_script_error_capture() -> void:
	if _capture_registered:
		return
	_script_error_capture = ScriptErrorCapture.new()
	OS.add_logger(_script_error_capture)
	_capture_registered = true


func _unregister_script_error_capture() -> void:
	if not _capture_registered:
		return
	OS.remove_logger(_script_error_capture)
	_capture_registered = false
	_script_error_capture = null
