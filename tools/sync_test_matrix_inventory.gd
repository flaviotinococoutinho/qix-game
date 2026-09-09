extends SceneTree
## Uso: Godot --headless --path . --script res://tools/sync_test_matrix_inventory.gd [-- --write]
##      [--assertions=N]
##
## Recalcula, a partir da árvore, os números que `docs/TEST_MATRIX.md` é obrigada a declarar, e
## diz exatamente quais linhas divergem. Com `--write`, reescreve essas linhas.
##
## Por que este comando existe. `tests/unit/test_matrix_inventory_test.gd` (a guarda do #69) deriva
## o inventário varrendo diretório e recusa a matriz que não repita esse número — em *todas* as
## linhas `N testes, M asserções, K falhas`. A guarda diz que está errado; ela não diz, em um
## comando, o que escrever nas quatro linhas. Enquanto a contagem é digitada à mão, quem acrescenta
## um teste acerta a sua branch e erra a árvore de destino: cada branch mede a si mesma, e a
## primeira que mescla deixa o número certo — a segunda o deixa falso. É a mesma doença que o
## histórico do loop já curou com um arquivo por execução, aqui na única linha que não pode ser
## partida em várias, porque o seu trabalho é dizer o **agora** da árvore inteira.
##
## O que este comando **não** faz, de propósito:
##
##   * não inventa contagem de asserções. Ela só existe depois de executar a suíte, e por isso só
##     entra com `--assertions=N`, digitada por quem leu a saída do runner. Sem a opção, o número
##     de asserções é preservado como está e apontado como suspeito quando a contagem de testes
##     mudou — dois números do mesmo run não mudam um sem o outro;
##   * não toca no cabeçalho `> **Verificado em**`. Data, commit, ambiente e alcance dizem se
##     alguém realmente rodou a suíte; deduzi-los seria fabricar a evidência que eles atestam.

const MATRIX := "res://docs/TEST_MATRIX.md"

## Espelha `tests/run_tests.gd` e a guarda. Divergir daqui é medir uma suíte que ninguém corre.
const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]
const TEST_SUFFIX := "_test.gd"
const ScriptErrorCapture := preload("res://tests/support/script_error_capture.gd")

const INVENTORY_PATTERN := \
	"^\\*\\*Inventário da suíte \\(derivado, não digitado\\):\\*\\* ([0-9]+) arquivos de teste · ([0-9]+) casos `test_\\*`\\.$"
const SUITE_CLAIM_PATTERN := "([0-9][0-9.]*) testes, ([0-9][0-9.]*) asserções, ([0-9]+) falhas"


func _initialize() -> void:
	var options := parse_options(OS.get_cmdline_user_args())
	if not options.ok:
		printerr(options.error)
		quit(2)
		return
	var swept := discover_suite(PackedStringArray(TEST_DIRS))
	if not swept.ok:
		printerr(swept.error)
		quit(2)
		return
	var files: int = swept["files"]
	var cases: int = swept["cases"]
	print("varredura da árvore: %d arquivos de teste · %d casos `test_*`" % [files, cases])

	var handle := FileAccess.open(MATRIX, FileAccess.READ)
	if handle == null:
		printerr("não abriu " + MATRIX)
		quit(2)
		return
	var source := handle.get_as_text()
	handle.close()
	var plan := plan_sync(source, files, cases, options.assertions)
	if not plan.ok:
		printerr(plan.error)
		quit(2)
		return
	var drift: Array = plan.changes
	if drift.is_empty():
		print("matriz em dia: nenhuma linha diverge da árvore")
		quit(0)
		return

	print("")
	for change in drift:
		print("linha %d" % change["line"])
		print("  -%s" % change["before"])
		print("  +%s" % change["after"])

	if not options.write:
		print("")
		print("%d linha(s) divergem. Reescreva com `-- --write`." % drift.size())
		quit(1)
		return

	var write_error := apply_plan(MATRIX, plan)
	if not write_error.is_empty():
		printerr(write_error)
		quit(2)
		return
	print("")
	print("%d linha(s) reescritas em docs/TEST_MATRIX.md" % drift.size())
	if options.assertions < 0:
		print(
			"atenção: a contagem de asserções foi preservada como estava. Se a suíte mudou, "
			+ "rode-a e repita com --assertions=N."
		)
	print("atualize à mão o cabeçalho `> **Verificado em**`: data, commit, ambiente e alcance.")
	quit(0)


## Um valor explícito inválido não pode virar silenciosamente "preservar asserções".
static func parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {"ok": true, "error": "", "write": false, "assertions": -1}
	for option in arguments:
		if option == "--write" and not result.write:
			result.write = true
		elif option.begins_with("--assertions=") and result.assertions < 0:
			var raw := option.trim_prefix("--assertions=")
			var digits := RegEx.create_from_string("^[1-9][0-9]*$")
			# Verificar o limite antes de to_int evita emitir um erro do engine no próprio CLI.
			if digits.search(raw) == null or raw.length() > 19 or (
				raw.length() == 19 and raw.casecmp_to("9223372036854775807") > 0
			):
				return {"ok": false, "error": "--assertions exige inteiro positivo sem separadores: " + option}
			result.assertions = raw.to_int()
		else:
			return {"ok": false, "error": "opção desconhecida ou duplicada: " + option}
	return result


## Resultado explícito separa contrato inválido de um plano válido sem mudanças. O texto nunca
## é normalizado: até as quebras finais são preservadas. As afirmações de suíte se repetem por
## desenho; só o marcador de inventário é único (mesmo contrato da guarda, com cardinalidade).
static func plan_sync(source: String, files: int, cases: int, assertions: int = -1) -> Dictionary:
	var result := {"ok": false, "error": "", "original": source, "text": source, "changes": []}
	if files <= 0 or cases <= 0:
		result.error = "inventário inválido: a descoberta precisa encontrar arquivos e casos test_*"
		return result
	if assertions != -1 and assertions <= 0:
		result.error = "asserções precisam ser positivas ou desconhecidas (-1)"
		return result
	var lines := source.split("\n")
	var inventory := RegEx.create_from_string(INVENTORY_PATTERN)
	var claim := RegEx.create_from_string(SUITE_CLAIM_PATTERN)
	var markers := 0
	var valid_markers := 0
	var claims := 0
	var previous_assertions := -1
	for line in lines:
		if line.contains("**Inventário da suíte"):
			markers += 1
		if inventory.search(line) != null:
			valid_markers += 1
		for found in claim.search_all(line):
			claims += 1
			var raw_count := String(found.get_string(2)).replace(".", "")
			if raw_count.length() > 19 or (
				raw_count.length() == 19 and raw_count.casecmp_to("9223372036854775807") > 0
			):
				result.error = "afirmação com asserções fora do limite de int64"
				return result
			var count := raw_count.to_int()
			if assertions < 0 and previous_assertions >= 0 and previous_assertions != count:
				result.error = "afirmações com asserções conflitantes; execute a suíte e informe --assertions=N"
				return result
			previous_assertions = count
	if markers != 1 or valid_markers != 1:
		result.error = "matriz exige exatamente um marcador de inventário no formato canônico"
		return result
	if claims < 2:
		result.error = "matriz exige ao menos duas afirmações completas: N testes, M asserções, K falhas"
		return result
	var changes := _plan(lines, files, cases, assertions)
	for change in changes:
		lines[change.line - 1] = change.after
	result.ok = true
	result.text = "\n".join(lines)
	result.changes = changes
	return result


## As linhas a reescrever, já com o texto final. Nada é aplicado aqui: o mesmo plano serve para
## relatar (sem `--write`) e para gravar, e assim o relatório não pode divergir do que se grava.
static func _plan(lines: PackedStringArray, files: int, cases: int, assertions: int) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var inventory := RegEx.create_from_string(INVENTORY_PATTERN)
	var claim := RegEx.create_from_string(SUITE_CLAIM_PATTERN)
	var expected_inventory := (
		"**Inventário da suíte (derivado, não digitado):** %d arquivos de teste · %d casos `test_*`."
		% [files, cases]
	)
	for index in lines.size():
		var line := lines[index]
		if inventory.search(line) != null:
			if line != expected_inventory:
				changes.append(
					{"line": index + 1, "before": line, "after": expected_inventory}
				)
			continue
		var rewritten := _rewrite_claims(line, claim, cases, assertions)
		if rewritten != line:
			changes.append({"line": index + 1, "before": line, "after": rewritten})
	return changes


## Substitui os números dentro de cada `N testes, M asserções, K falhas` da linha. As ocorrências
## são percorridas de trás para frente para que as posições das anteriores continuem válidas.
static func _rewrite_claims(line: String, claim: RegEx, cases: int, assertions: int) -> String:
	var found := claim.search_all(line)
	var rewritten := line
	for index in range(found.size() - 1, -1, -1):
		var match_found := found[index]
		if assertions >= 0:
			rewritten = _splice(
				rewritten,
				match_found.get_start(2),
				match_found.get_end(2),
				_format_like(assertions, match_found.get_string(2)),
			)
		rewritten = _splice(
			rewritten,
			match_found.get_start(1),
			match_found.get_end(1),
			_format_like(cases, match_found.get_string(1)),
		)
	return rewritten


static func _splice(text: String, start: int, end: int, replacement: String) -> String:
	return text.substr(0, start) + replacement + text.substr(end)


## A matriz escreve milhares ora com ponto (`11.837`), ora sem. Preservar o estilo da ocorrência
## evita que sincronizar o número vire, de quebra, uma mudança de formatação no diff.
static func _format_like(value: int, sample: String) -> String:
	if not sample.contains("."):
		return str(value)
	var digits := str(value)
	var grouped := ""
	var counted := 0
	for index in range(digits.length() - 1, -1, -1):
		grouped = digits[index] + grouped
		counted += 1
		if counted % 3 == 0 and index > 0:
			grouped = "." + grouped
	return grouped


## Captura carga/dependências e _init como o runner. Não chama reset, setUp nem casos de teste.
## O logger sempre sai após a varredura, inclusive quando uma etapa devolve erro.
static func discover_suite(directories: PackedStringArray) -> Dictionary:
	var capture = ScriptErrorCapture.new()
	OS.add_logger(capture)
	var result := _sweep_suite(directories, capture)
	OS.remove_logger(capture)
	return result


static func _sweep_suite(directories: PackedStringArray, capture: ScriptErrorCapture) -> Dictionary:
	var files := 0
	var cases := 0
	for dir in directories:
		if not DirAccess.dir_exists_absolute(dir):
			return {"ok": false, "error": "diretório de teste ausente: " + dir}
		var entries := Array(DirAccess.get_files_at(dir))
		entries.sort()
		for entry in entries:
			var name := String(entry)
			if not name.ends_with(TEST_SUFFIX):
				continue
			var path := dir + "/" + name
			capture.begin_capture()
			var script: GDScript = load(path)
			var load_errors: PackedStringArray = capture.end_capture()
			if not load_errors.is_empty():
				return {"ok": false, "error": "erro ao carregar %s:\n%s" % [path, "\n".join(load_errors)]}
			if script == null or not script.can_instantiate():
				return {"ok": false, "error": "não carregou " + path + " — o runner falharia igual"}
			capture.begin_capture()
			var instance: Variant = script.new()
			var init_errors: PackedStringArray = capture.end_capture()
			if not init_errors.is_empty():
				return {"ok": false, "error": "erro ao instanciar %s:\n%s" % [path, "\n".join(init_errors)]}
			if not (instance is TestCase):
				return {"ok": false, "error": path + " não estende TestCase"}
			files += 1
			for method in (instance as TestCase).get_method_list():
				if String(method.name).begins_with("test_"):
					cases += 1
	if files == 0 or cases == 0:
		return {"ok": false, "error": "a varredura não encontrou arquivos com casos test_* — o runner recusaria zero casos"}
	return {"ok": true, "error": "", "files": files, "cases": cases}


## Publica por rename de um temporário vizinho só depois de validar a gravação e conferir
## novamente a origem. Uma falha deixa a matriz anterior inteira; não é um lock entre editores.
static func apply_plan(path: String, plan: Dictionary) -> String:
	if not plan.get("ok", false):
		return "plano inválido: nenhuma escrita foi aplicada"
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != plan.original:
		return "a matriz mudou após o planejamento: execute o comando novamente"
	if plan.changes.is_empty():
		return ""
	var temporary := path + ".sync-%d.tmp" % OS.get_process_id()
	if FileAccess.file_exists(temporary):
		return "temporário já existe: " + temporary
	var handle := FileAccess.open(temporary, FileAccess.WRITE)
	if handle == null:
		return "não abriu temporário para escrita: " + temporary
	handle.store_string(plan.text)
	handle.flush()
	var write_error := handle.get_error()
	handle.close()
	if write_error != OK or FileAccess.get_file_as_string(temporary) != plan.text:
		DirAccess.remove_absolute(temporary)
		return "falha ao gravar temporário: a matriz foi preservada"
	if FileAccess.get_file_as_string(path) != plan.original:
		DirAccess.remove_absolute(temporary)
		return "a matriz mudou durante a gravação: nenhuma substituição foi aplicada"
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return "não substituiu a matriz: " + error_string(rename_error)
	return ""
