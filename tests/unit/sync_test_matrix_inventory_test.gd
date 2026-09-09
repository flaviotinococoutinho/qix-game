extends TestCase
## Regressões do comando: uma matriz sem contrato ou uma descoberta quebrada não é um no-op verde.

const InventorySync := preload("res://tools/sync_test_matrix_inventory.gd")
const INVENTORY := "**Inventário da suíte (derivado, não digitado):** 2 arquivos de teste · 3 casos `test_*`."
const VALID := "> **Verificado em** 2026-09-09, ambiente de fixture.\n" + INVENTORY + "\nResultado: **3 testes, 1.234 asserções, 0 falhas**.\n| suíte | 3 testes, 1234 asserções, 0 falhas |\n\n"


func test_missing_inventory_marker_fails_without_changing_text() -> void:
	var source := VALID.replace(INVENTORY + "\n", "")
	var result: Dictionary = InventorySync.plan_sync(source, 2, 3)
	ok(not result.ok)
	ok(String(result.error).contains("inventário"))
	eq(result.text, source)
	eq(result.changes, [])


func test_duplicate_or_malformed_inventory_marker_fails_closed() -> void:
	for source in [VALID + INVENTORY + "\n", VALID.replace("2 arquivos", "dois arquivos"), VALID + "**Inventário da suíte:** incompleto\n"]:
		var result: Dictionary = InventorySync.plan_sync(source, 2, 3)
		ok(not result.ok)
		eq(result.text, source)
		eq(result.changes, [])
	for raw in ["9223372036854775808", "9.223.372.036.854.775.808", "99999999999999999999"]:
		var source := VALID.replace("1.234 asserções", raw + " asserções")
		var result: Dictionary = InventorySync.plan_sync(source, 2, 3, 1234)
		ok(not result.ok)
		ok(String(result.error).contains("int64"))
		eq(result.text, source)
		eq(result.changes, [])


func test_missing_suite_claims_cannot_be_reported_as_in_sync() -> void:
	for source in [INVENTORY + "\n", INVENTORY + "\n3 testes, 1234 asserções, 0 falhas\n"]:
		var result: Dictionary = InventorySync.plan_sync(source, 2, 3)
		ok(not result.ok)
		ok(String(result.error).contains("afirmações"))
		eq(result.text, source)


func test_valid_noop_preserves_all_bytes_including_trailing_blank_lines() -> void:
	var result: Dictionary = InventorySync.plan_sync(VALID, 2, 3)
	ok(result.ok, str(result.error))
	eq(result.changes, [])
	eq(result.text, VALID)


func test_drift_rewrites_counts_but_preserves_provenance_and_assertion_style() -> void:
	var result: Dictionary = InventorySync.plan_sync(VALID, 4, 7, 2345)
	ok(result.ok, str(result.error))
	eq(result.changes.size(), 3)
	eq(result.text, "> **Verificado em** 2026-09-09, ambiente de fixture.\n**Inventário da suíte (derivado, não digitado):** 4 arquivos de teste · 7 casos `test_*`.\nResultado: **7 testes, 2.345 asserções, 0 falhas**.\n| suíte | 7 testes, 2345 asserções, 0 falhas |\n\n")
	eq(result.original, VALID)


func test_unknown_assertions_are_preserved_and_conflicting_counts_need_measurement() -> void:
	var result: Dictionary = InventorySync.plan_sync(VALID, 2, 7)
	ok(result.ok, str(result.error))
	ok(String(result.text).contains("7 testes, 1.234 asserções"))
	ok(String(result.text).contains("7 testes, 1234 asserções"))
	var conflicting := VALID.replace("1234 asserções", "999 asserções")
	var refused: Dictionary = InventorySync.plan_sync(conflicting, 2, 3)
	ok(not refused.ok)
	eq(refused.text, conflicting)
	ok(InventorySync.plan_sync(conflicting, 2, 3, 1234).ok)


func test_zero_cases_or_files_never_produce_a_valid_plan() -> void:
	for counts in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 3), Vector2i(-1, 3)]:
		var result: Dictionary = InventorySync.plan_sync(VALID, counts.x, counts.y)
		ok(not result.ok)
		eq(result.text, VALID)


func test_assertion_option_requires_one_positive_integer() -> void:
	for argument in ["--assertions=", "--assertions=-1", "--assertions=0", "--assertions=1.234", "--assertions=abc", "--assertions=99999999999999999999"]:
		ok(not InventorySync.parse_options(PackedStringArray([argument])).ok, argument)
	ok(not InventorySync.parse_options(PackedStringArray(["--assertions=12", "--assertions=13"])).ok)
	var valid: Dictionary = InventorySync.parse_options(PackedStringArray(["--write", "--assertions=1234"]))
	ok(valid.ok)
	eq(valid.assertions, 1234)
	ok(valid.write)
	eq(InventorySync.parse_options(PackedStringArray()).assertions, -1)


func test_discovery_counts_methods_without_executing_reset_or_tests() -> void:
	var root := _fixture_root("methods")
	var script_path := root + "/fixture_test.gd"
	_write(script_path, "extends TestCase\nfunc reset() -> void:\n\tassert(false, \"discovery must not reset\")\nfunc test_first() -> void:\n\tassert(false, \"discovery must not run cases\")\nfunc test_second() -> void:\n\tassert(false, \"discovery must not run cases\")\n")
	var result: Dictionary = InventorySync.discover_suite(PackedStringArray([root]))
	ok(result.ok, str(result.error))
	eq(result.files, 1)
	eq(result.cases, 2)
	_remove_fixture(root, [script_path])


func test_discovery_with_test_files_but_zero_cases_fails() -> void:
	var root := _fixture_root("empty")
	var script_path := root + "/empty_test.gd"
	_write(script_path, "extends TestCase\nfunc helper() -> void:\n\tpass\n")
	var result: Dictionary = InventorySync.discover_suite(PackedStringArray([root]))
	ok(not result.ok)
	ok(String(result.error).contains("caso"))
	_remove_fixture(root, [script_path])


func test_discovery_rejects_dependency_and_initializer_errors_in_isolated_process() -> void:
	# O processo filho mantém os SCRIPT ERROR esperados fora da captura da suíte principal.
	var root := _fixture_root("errors")
	var dependency_dir := root + "/dependency"
	var initializer_dir := root + "/initializer"
	DirAccess.make_dir_recursive_absolute(dependency_dir)
	DirAccess.make_dir_recursive_absolute(initializer_dir)
	var dependency := dependency_dir + "/broken.gd"
	var outer := dependency_dir + "/outer_test.gd"
	var initializer := initializer_dir + "/init_test.gd"
	var helper := root + "/probe.gd"
	_write(dependency, "extends RefCounted\nfunc invalid(:\n")
	_write(outer, "extends TestCase\nconst Broken = preload(%s)\nfunc test_case() -> void:\n\tpass\n" % JSON.stringify(dependency))
	_write(initializer, "extends TestCase\nfunc _init() -> void:\n\tvar missing: Variant = null\n\tmissing.no_such_method()\nfunc test_case() -> void:\n\tpass\n")
	_write(helper, "extends SceneTree\nconst Sync = preload(\"res://tools/sync_test_matrix_inventory.gd\")\nfunc _initialize() -> void:\n\tvar first = Sync.discover_suite(PackedStringArray([%s]))\n\tvar second = Sync.discover_suite(PackedStringArray([%s]))\n\tprint(\"SYNC_PROBE=\" + JSON.stringify([first, second]))\n\tquit(0)\n" % [JSON.stringify(dependency_dir), JSON.stringify(initializer_dir)])
	var process := _run_probe(helper)
	eq(process.code, 0, "helper deve terminar normalmente após recusar as duas descobertas")
	var receipt: Array = []
	for line in String(process.output).split("\n"):
		if line.begins_with("SYNC_PROBE="):
			var parsed: Variant = JSON.parse_string(line.trim_prefix("SYNC_PROBE="))
			if parsed is Array:
				receipt = parsed
	eq(receipt.size(), 2, "helper deve emitir seu recibo mesmo com falhas esperadas")
	if receipt.size() == 2:
		ok(not receipt[0].ok)
		ok(String(receipt[0].error).contains("carregar"))
		ok(not receipt[1].ok)
		ok(String(receipt[1].error).contains("instanciar"))
	_remove_fixture(dependency_dir, [dependency, outer])
	_remove_fixture(initializer_dir, [initializer])
	_remove_fixture(root, [helper])


func _run_probe(helper: String) -> Dictionary:
	var process := OS.execute_with_pipe(OS.get_executable_path(), PackedStringArray([
		"--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"),
		"--script", ProjectSettings.globalize_path(helper),
	]), false)
	if process.is_empty():
		return {"code": -1, "output": "não criou helper"}
	var stdout_pipe: FileAccess = process.stdio
	var stderr_pipe: FileAccess = process.stderr
	var output := PackedByteArray()
	var errors := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 15000
	while OS.is_process_running(process.pid) and Time.get_ticks_msec() < deadline:
		output.append_array(stdout_pipe.get_buffer(4096))
		errors.append_array(stderr_pipe.get_buffer(4096))
		OS.delay_msec(10)
	var timed_out := OS.is_process_running(process.pid)
	if timed_out:
		OS.kill(process.pid)
	# As pipes são não bloqueantes; consumir o trecho final não espera EOF indefinidamente.
	for _chunk in 64:
		var last_output := stdout_pipe.get_buffer(4096)
		var last_errors := stderr_pipe.get_buffer(4096)
		output.append_array(last_output)
		errors.append_array(last_errors)
		if last_output.is_empty() and last_errors.is_empty():
			break
	stdout_pipe.close()
	stderr_pipe.close()
	return {"code": -2 if timed_out else OS.get_process_exit_code(process.pid), "output": output.get_string_from_utf8(), "stderr": errors.get_string_from_utf8()}


func test_write_preserves_file_when_plan_is_invalid_or_source_changed() -> void:
	var root := _fixture_root("write")
	var path := root + "/matrix.md"
	_write(path, VALID)
	var invalid: Dictionary = InventorySync.plan_sync("sem inventário", 2, 3)
	ok(not InventorySync.apply_plan(path, invalid).is_empty())
	eq(FileAccess.get_file_as_string(path), VALID)
	var plan: Dictionary = InventorySync.plan_sync(VALID, 4, 7)
	_write(path, VALID + "edição concorrente\n")
	ok(not InventorySync.apply_plan(path, plan).is_empty())
	eq(FileAccess.get_file_as_string(path), VALID + "edição concorrente\n")
	_write(path, VALID)
	eq(InventorySync.apply_plan(path, plan), "")
	eq(FileAccess.get_file_as_string(path), plan.text)
	_remove_fixture(root, [path])


func _fixture_root(suffix: String) -> String:
	var root := "user://sync_inventory_%d_%s" % [OS.get_process_id(), suffix]
	eq(DirAccess.make_dir_recursive_absolute(root), OK)
	return root


func _write(path: String, source: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	ok(file != null, "fixture precisa abrir: " + path)
	if file != null:
		file.store_string(source)
		file.close()


func _remove_fixture(root: String, paths: Array) -> void:
	for path in paths:
		eq(DirAccess.remove_absolute(path), OK)
	eq(DirAccess.remove_absolute(root), OK)
