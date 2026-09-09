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

const INVENTORY_PATTERN := \
	"^\\*\\*Inventário da suíte \\(derivado, não digitado\\):\\*\\* ([0-9]+) arquivos de teste · ([0-9]+) casos"
const SUITE_CLAIM_PATTERN := "([0-9][0-9.]*) testes, ([0-9][0-9.]*) asserções, ([0-9]+) falhas"


func _initialize() -> void:
	var write := false
	var assertions := -1
	for argument in OS.get_cmdline_user_args():
		var option := String(argument)
		if option == "--write":
			write = true
		elif option.begins_with("--assertions="):
			assertions = int(option.split("=")[1])
		else:
			printerr("opção desconhecida: " + option)
			quit(2)
			return

	var swept := _sweep_suite()
	if swept.is_empty():
		quit(2)
		return
	var files: int = swept["files"]
	var cases: int = swept["cases"]
	print("varredura da árvore: %d arquivos de teste · %d casos `test_*`" % [files, cases])

	var lines := _matrix_lines()
	if lines.is_empty():
		quit(2)
		return

	var drift := _plan(lines, files, cases, assertions)
	if drift.is_empty():
		print("matriz em dia: nenhuma linha diverge da árvore")
		quit(0)
		return

	print("")
	for change in drift:
		print("linha %d" % change["line"])
		print("  -%s" % change["before"])
		print("  +%s" % change["after"])

	if not write:
		print("")
		print("%d linha(s) divergem. Reescreva com `-- --write`." % drift.size())
		quit(1)
		return

	for change in drift:
		lines[change["line"] - 1] = change["after"]
	if not _save(lines):
		quit(2)
		return
	print("")
	print("%d linha(s) reescritas em docs/TEST_MATRIX.md" % drift.size())
	if assertions < 0:
		print(
			"atenção: a contagem de asserções foi preservada como estava. Se a suíte mudou, "
			+ "rode-a e repita com --assertions=N."
		)
	print("atualize à mão o cabeçalho `> **Verificado em**`: data, commit, ambiente e alcance.")
	quit(0)


## As linhas a reescrever, já com o texto final. Nada é aplicado aqui: o mesmo plano serve para
## relatar (sem `--write`) e para gravar, e assim o relatório não pode divergir do que se grava.
func _plan(lines: PackedStringArray, files: int, cases: int, assertions: int) -> Array[Dictionary]:
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
func _rewrite_claims(line: String, claim: RegEx, cases: int, assertions: int) -> String:
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


func _splice(text: String, start: int, end: int, replacement: String) -> String:
	return text.substr(0, start) + replacement + text.substr(end)


## A matriz escreve milhares ora com ponto (`11.837`), ora sem. Preservar o estilo da ocorrência
## evita que sincronizar o número vire, de quebra, uma mudança de formatação no diff.
func _format_like(value: int, sample: String) -> String:
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


## Varredura idêntica à da guarda: mesmos diretórios, mesmo sufixo, casos contados por
## `get_method_list()` — não por texto — para que o número não possa divergir do que o runner chama.
func _sweep_suite() -> Dictionary:
	var files := 0
	var cases := 0
	for dir in TEST_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			printerr("diretório de teste ausente: " + dir)
			return {}
		var entries := Array(DirAccess.get_files_at(dir))
		entries.sort()
		for entry in entries:
			var name := String(entry)
			if not name.ends_with(TEST_SUFFIX):
				continue
			var script: GDScript = load(dir + "/" + name)
			if script == null or not script.can_instantiate():
				printerr("não carregou %s/%s — o runner falharia igual" % [dir, name])
				return {}
			var instance: Variant = script.new()
			if not (instance is TestCase):
				printerr("%s/%s não estende TestCase" % [dir, name])
				return {}
			files += 1
			for method in (instance as TestCase).get_method_list():
				if String(method.name).begins_with("test_"):
					cases += 1
	if files == 0:
		printerr("a varredura não encontrou teste algum — o runner acharia o mesmo")
		return {}
	return {"files": files, "cases": cases}


func _matrix_lines() -> PackedStringArray:
	var handle := FileAccess.open(MATRIX, FileAccess.READ)
	if handle == null:
		printerr("não abriu " + MATRIX)
		return PackedStringArray()
	var lines := PackedStringArray()
	while not handle.eof_reached():
		lines.append(handle.get_line())
	handle.close()
	return lines


func _save(lines: PackedStringArray) -> bool:
	var handle := FileAccess.open(MATRIX, FileAccess.WRITE)
	if handle == null:
		printerr("não abriu para escrita " + MATRIX)
		return false
	handle.store_string("\n".join(lines) + "\n")
	handle.close()
	return true
