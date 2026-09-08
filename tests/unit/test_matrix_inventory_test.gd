extends TestCase
## Guarda do inventário declarado em `docs/TEST_MATRIX.md`.
##
## `doc_freshness_header_test.gd` prova que o documento **tem** cabeçalho; não prova que o corpo
## diz a verdade. A matriz atravessou onze PRs afirmando "174 testes" enquanto o runner corria
## 262 — verde em todas as guardas, e mentira para quem a lesse. A causa está escrita no próprio
## backlog: a contagem é **digitada à mão** sobre um runner que **varre diretório**. Quem acrescenta
## um arquivo de teste não é obrigado a passar pela matriz, e por isso não passa.
##
## Este teste fecha a volta: deriva o inventário pela mesma varredura que `tests/run_tests.gd`
## usa — mesmos diretórios, mesmo sufixo, mesmo `get_method_list()` — e exige que a matriz
## declare esse número. A partir daqui, acrescentar um teste sem tocar na matriz fica vermelho,
## com a linha exata a escrever impressa na falha.
##
## O que este teste **não** faz, de propósito:
##
##   * não deriva a contagem de asserções. Ela só existe depois de executar a suíte, e inventar
##     um número estático seria a mesma mentira noutra casa. A asserção continua sendo instantâneo
##     datado — é o cabeçalho `> **Verificado em**` que responde por ela;
##   * não vale para os demais `docs/*.md`. `IMPLEMENTATION_STATUS.md` e `SHIPPING_PASS.md` citam
##     **134 testes, 11.489 asserções** de um run de shipping em macOS de 2026-09-03: registro
##     histórico de outro ambiente, que continua verdadeiro por ser histórico. Forçá-lo a bater
##     com a árvore de hoje seria falsificar evidência, não reconciliá-la. A matriz é o documento
##     cujo trabalho é dizer o **agora**; a guarda para nela.

const MATRIX := "res://docs/TEST_MATRIX.md"

## Espelha `tests/run_tests.gd`. Divergir daqui é divergir do que a suíte de facto corre.
const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]
const TEST_SUFFIX := "_test.gd"

## A linha que a matriz precisa carregar. Uma só, visível ao leitor — comentário de HTML seria
## invisível justamente para quem o documento existe.
const INVENTORY_PATTERN := \
	"^\\*\\*Inventário da suíte \\(derivado, não digitado\\):\\*\\* ([0-9]+) arquivos de teste · ([0-9]+) casos"

## O triplo que a matriz usa para falar da suíte inteira: `N testes, M asserções, K falhas`.
## O subconjunto transacional (`22 testes, 353 asserções`) e o parser Python (`10 testes Python`)
## não o formam, e por isso ficam de fora sem precisar de exceção nomeada.
const SUITE_CLAIM_PATTERN := "([0-9][0-9.]*) testes, ([0-9][0-9.]*) asserções, ([0-9]+) falhas"


func test_matrix_declares_the_inventory_the_runner_actually_sweeps() -> void:
	var swept := _sweep_suite()
	var files: int = swept["files"]
	var cases: int = swept["cases"]
	ok(files > 0 and cases > 0, "a varredura não encontrou teste algum — o runner acharia o mesmo")

	var expected_line := (
		"**Inventário da suíte (derivado, não digitado):** %d arquivos de teste · %d casos `test_*`."
		% [files, cases]
	)
	var declared := _declared_inventory()
	ok(
		not declared.is_empty(),
		(
			"TEST_MATRIX.md não declara o inventário. Escreva esta linha na seção "
			+ "\"Comando canônico da suíte\":\n      %s"
		) % expected_line,
	)
	if declared.is_empty():
		return
	eq(
		[declared["files"], declared["cases"]],
		[files, cases],
		(
			"o inventário declarado na matriz não é o que o runner varre. Substitua a linha por:"
			+ "\n      %s"
		) % expected_line,
	)


func test_every_full_suite_claim_in_the_matrix_repeats_the_same_numbers() -> void:
	var cases: int = _sweep_suite()["cases"]
	var claims := _suite_claims()
	ok(
		claims.size() >= 2,
		(
			"a matriz repete a contagem da suíte em prosa e na tabela; achei %d ocorrência(s) de "
			+ "`N testes, M asserções, K falhas`. Se o formato mudou, mude também esta guarda."
		) % claims.size(),
	)
	var assertions_seen := -1
	for claim in claims:
		eq(
			claim["tests"],
			cases,
			(
				"linha %d da matriz afirma %d testes; o runner varre %d. Foi assim que "
				+ "\"174 testes\" sobreviveu a onze PRs."
			) % [claim["line"], claim["tests"], cases],
		)
		if assertions_seen < 0:
			assertions_seen = claim["assertions"]
		else:
			eq(
				claim["assertions"],
				assertions_seen,
				(
					"linha %d afirma %d asserções e outra linha do mesmo documento afirma %d. "
					+ "Duas contagens concorrentes para o mesmo run é a contradição que o "
					+ "cabeçalho de frescor não vê."
				) % [claim["line"], claim["assertions"], assertions_seen],
			)


## Varredura idêntica à de `tests/run_tests.gd`: mesmos diretórios, mesmo sufixo, e os casos
## contados por `get_method_list()` — não por texto — para que a contagem não possa divergir do
## que o runner chama.
func _sweep_suite() -> Dictionary:
	var files := 0
	var cases := 0
	for dir in TEST_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			fail("diretório de teste ausente: " + dir)
			continue
		var entries := Array(DirAccess.get_files_at(dir))
		entries.sort()
		for entry in entries:
			var name := String(entry)
			if not name.ends_with(TEST_SUFFIX):
				continue
			var script: GDScript = load(dir + "/" + name)
			if script == null or not script.can_instantiate():
				fail("não carregou %s/%s — o runner falharia igual" % [dir, name])
				continue
			var instance: Variant = script.new()
			if not (instance is TestCase):
				fail("%s/%s não estende TestCase" % [dir, name])
				continue
			files += 1
			for method in (instance as TestCase).get_method_list():
				if String(method.name).begins_with("test_"):
					cases += 1
	return {"files": files, "cases": cases}


func _declared_inventory() -> Dictionary:
	var pattern := RegEx.create_from_string(INVENTORY_PATTERN)
	for line in _matrix_lines():
		var found := pattern.search(line)
		if found != null:
			return {"files": int(found.get_string(1)), "cases": int(found.get_string(2))}
	return {}


func _suite_claims() -> Array[Dictionary]:
	var pattern := RegEx.create_from_string(SUITE_CLAIM_PATTERN)
	var claims: Array[Dictionary] = []
	var lines := _matrix_lines()
	for i in lines.size():
		for found in pattern.search_all(lines[i]):
			claims.append({
				"line": i + 1,
				"tests": _to_int(found.get_string(1)),
				"assertions": _to_int(found.get_string(2)),
			})
	return claims


## A matriz escreve milhares com ponto (`11.837`), como o resto da documentação em português.
func _to_int(raw: String) -> int:
	return int(raw.replace(".", ""))


func _matrix_lines() -> PackedStringArray:
	var handle := FileAccess.open(MATRIX, FileAccess.READ)
	if handle == null:
		fail("não abriu " + MATRIX)
		return PackedStringArray()
	var lines := PackedStringArray()
	while not handle.eof_reached():
		lines.append(handle.get_line())
	handle.close()
	return lines
