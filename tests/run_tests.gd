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
	var json_path := ""
	var args := OS.get_cmdline_user_args()
	var arg_index := 0
	while arg_index < args.size():
		if args[arg_index] == "--json":
			arg_index += 1
			if arg_index >= args.size() or args[arg_index].begins_with("--"):
				printerr("--json exige um caminho de saída")
				quit(2)
				return
			json_path = args[arg_index]
		elif args[arg_index].begins_with("--json="):
			json_path = args[arg_index].trim_prefix("--json=")
		elif args[arg_index].begins_with("--") or filter != "":
			printerr("Argumento inesperado: " + args[arg_index])
			quit(2)
			return
		else:
			filter = args[arg_index]
		arg_index += 1
	var total := 0
	var failures := 0
	var assertions := 0
	var discovery_errors := 0
	var test_results: Array[Dictionary] = []
	var started := Time.get_ticks_usec()
	for dir in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f in files:
			if not f.ends_with("_test.gd"):
				continue
			# Dependências podem falhar no parser e ainda deixar o script externo instanciável.
			# Capturar só inst.call(test) dava exit 0 apesar de SCRIPT ERROR durante descoberta.
			_script_error_capture.begin_capture()
			var script: GDScript = load(dir + "/" + f)
			var load_errors: PackedStringArray = _script_error_capture.end_capture()
			if not load_errors.is_empty():
				printerr("ERRO ao compilar %s:\n%s" % [f, "\n".join(load_errors)])
				failures += 1
				discovery_errors += 1
				continue
			if script == null or not script.can_instantiate():
				printerr("ERRO: não carregou " + f)
				failures += 1
				discovery_errors += 1
				continue
			_script_error_capture.begin_capture()
			var inst = script.new()
			var init_errors: PackedStringArray = _script_error_capture.end_capture()
			if not init_errors.is_empty():
				printerr("ERRO ao instanciar %s:\n%s" % [f, "\n".join(init_errors)])
				failures += 1
				discovery_errors += 1
				continue
			if not (inst is TestCase):
				printerr("ERRO: %s não estende TestCase" % f)
				failures += 1
				discovery_errors += 1
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
				test_results.append({"file": dir + "/" + f, "name": name,
					"assertions": inst.assertions, "failed": inst.failed,
					"messages": inst.messages})
				if inst.failed:
					failures += 1
					print("FAIL  %s::%s\n%s" % [f, name, inst.messages])
				else:
					print("ok    %s::%s" % [f, name])
	var ms := (Time.get_ticks_usec() - started) / 1000
	print("\n%d testes, %d asserções, %d falhas, %d ms" % [total, assertions, failures, ms])
	var exit_code := 1 if failures > 0 or total == 0 else 0
	if not json_path.is_empty():
		var output := FileAccess.open(json_path, FileAccess.WRITE)
		if output == null:
			printerr("Não foi possível escrever resultado JSON: " + json_path)
			exit_code = 2
		else:
			output.store_string(JSON.stringify({"schema_version": 1,
				"total": total, "assertions": assertions, "failures": failures,
				"discovery_errors": discovery_errors, "duration_ms": ms,
				"exit_code": exit_code, "filter": filter, "tests": test_results}, "\t") + "\n")
	_unregister_script_error_capture()
	quit(exit_code)


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
