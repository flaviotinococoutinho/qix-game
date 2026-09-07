extends TestCase
## Guarda de coerência interna da documentação — a resposta ao item (b) do backlog.
##
## `doc_freshness_header_test.gd` prova que a linha `> **Verificado em**` **existe**. Não prova
## que o corpo abaixo dela diz uma coisa só. A diferença não é teórica: a integração de 23:00Z
## produziu um `LOOP_LEDGER.md` de 703 linhas com **cinco** seções "estado da fila" contraditórias
## e três ordens de merge concorrentes, e `TEST_MATRIX.md` chegou a afirmar quatro contagens
## diferentes de testes — tudo verde no teste de cabeçalho. A união automática de Markdown passa
## em qualquer guarda que só olhe o topo do arquivo, porque ela não corrompe a sintaxe: ela
## duplica a afirmação.
##
## Daí o recorte desta guarda. Ela não julga o conteúdo — não tem como saber qual das duas
## afirmações é a verdadeira. Ela recusa a **forma** em que a contradição se apresenta, que é
## barata de detectar e não tem uso legítimo num documento vivo:
##
##   1. **Duas seções com o mesmo título no mesmo documento.** Foi exatamente o que a união
##      automática fabricou. Um leitor que procura "estado da fila" e encontra cinco não tem
##      como escolher; um índice de documento com o mesmo nome duas vezes não é índice.
##   2. **Duas linhas da mesma tabela com a mesma primeira coluna e conteúdo diferente.** A
##      primeira coluna de uma tabela de documentação é a chave — o arquivo, a decisão, o
##      comando, o invariante. Duas respostas para a mesma chave é a contradição em forma
##      tabular. Linhas **idênticas** não são acusadas: repetir não é contradizer.
##
## `docs/loop/runs/` fica **fora** do alcance de propósito. Ali um relatório de execução lista
## legitimamente o mesmo comando em linhas diferentes com medidas diferentes — medido em
## `2026-09-06T160022Z.md`, que roda `tests/run_tests.gd` mais de uma vez na mesma tabela. É
## histórico append-only, não afirmação viva sobre o estado do projeto; aplicar a regra ali
## trocaria uma guarda por ruído. Os documentos vivos são os que respondem "como está agora".

## Documentos vivos: os que afirmam o estado atual do projeto e por isso não podem afirmar duas
## coisas sobre o mesmo fato. Ver a nota acima sobre a ausência de `docs/loop/runs/`.
const LIVING_DIRS: Array[String] = [
	"res://docs",
	"res://docs/decisions",
	"res://docs/loop",
]


func test_living_docs_declare_each_section_once() -> void:
	var scanned := 0
	for path in _living_docs():
		scanned += 1
		var offenders := duplicate_headings(_read_lines(path))
		eq(
			offenders,
			PackedStringArray(),
			(
				"%s repete título de seção. Duas seções com o mesmo nome são duas respostas "
				+ "para a mesma pergunta: funda-as, ou dê a cada uma o seu próprio nome."
			) % path,
		)
	ok(scanned >= 7, "esperava varrer os documentos vivos, varreu %d" % scanned)


func test_living_docs_never_answer_one_table_key_twice() -> void:
	for path in _living_docs():
		var offenders := contradicting_table_rows(_read_lines(path))
		eq(
			offenders,
			PackedStringArray(),
			(
				"%s tem tabela com duas linhas diferentes sob a mesma chave. A primeira coluna "
				+ "é a chave: uma chave, uma resposta."
			) % path,
		)


## Uma guarda verde numa árvore limpa não prova que ela vê alguma coisa. Este teste alimenta os
## dois detectores com a forma exata do defeito histórico e exige que eles acusem — e com a forma
## legítima vizinha (linha repetida idêntica, títulos parecidos mas distintos) e exige silêncio.
func test_the_guard_fires_on_the_shape_it_exists_to_catch() -> void:
	var union_merge_artifact := PackedStringArray([
		"# LEDGER",
		"",
		"## Estado da fila",
		"A fila está em 0.",
		"",
		"## Estado da fila",
		"A fila está em 30.",
	])
	eq(
		duplicate_headings(union_merge_artifact),
		PackedStringArray(["## Estado da fila"]),
		"o detector precisa acusar as duas seções homônimas da união automática",
	)

	var distinct_headings := PackedStringArray([
		"# LEDGER",
		"## Estado da fila",
		"## Estado da fila de exports",
		"### Estado da fila",
	])
	eq(
		duplicate_headings(distinct_headings),
		PackedStringArray(),
		"títulos distintos, e o mesmo texto noutro nível, não são o defeito",
	)

	var contradicting_table := PackedStringArray([
		"| Documento | Contagem |",
		"|---|---|",
		"| `TEST_MATRIX.md` | 174 testes |",
		"| `TEST_MATRIX.md` | 262 testes |",
	])
	eq(
		contradicting_table_rows(contradicting_table),
		PackedStringArray(["`test_matrix.md`"]),
		"o detector precisa acusar duas contagens sob a mesma chave",
	)

	var repeated_identical_row := PackedStringArray([
		"| Documento | Contagem |",
		"|---|---|",
		"| `TEST_MATRIX.md` | 262 testes |",
		"| `TEST_MATRIX.md` | 262 testes |",
	])
	eq(
		contradicting_table_rows(repeated_identical_row),
		PackedStringArray(),
		"repetir não é contradizer: linhas idênticas não são acusadas",
	)

	var two_separate_tables := PackedStringArray([
		"| Documento | Contagem |",
		"|---|---|",
		"| `TEST_MATRIX.md` | 174 testes |",
		"",
		"Texto entre as tabelas.",
		"",
		"| Documento | Contagem |",
		"|---|---|",
		"| `TEST_MATRIX.md` | 262 testes |",
	])
	eq(
		contradicting_table_rows(two_separate_tables),
		PackedStringArray(),
		"a chave é por tabela: duas tabelas separadas podem repetir a mesma primeira coluna",
	)

	var fenced_lookalike := PackedStringArray([
		"# DOC",
		"```bash",
		"## Estado da fila",
		"## Estado da fila",
		"| a | b |",
		"| a | c |",
		"```",
	])
	eq(
		duplicate_headings(fenced_lookalike),
		PackedStringArray(),
		"comentário de shell dentro de bloco de código não é título",
	)
	eq(
		contradicting_table_rows(fenced_lookalike),
		PackedStringArray(),
		"pipe dentro de bloco de código não é tabela",
	)


## Títulos repetidos, na ordem em que aparecem, sem repetir a acusação.
## O nível conta: `## Estado` e `### Estado` são seções diferentes numa hierarquia.
static func duplicate_headings(lines: PackedStringArray) -> PackedStringArray:
	var offenders := PackedStringArray()
	var seen := {}
	var fenced := false
	for raw in lines:
		var line := raw.strip_edges()
		if line.begins_with("```"):
			fenced = not fenced
			continue
		if fenced or not line.begins_with("#"):
			continue
		var key := line.to_lower()
		if seen.has(key):
			if not offenders.has(line):
				offenders.append(line)
			continue
		seen[key] = true
	return offenders


## Chaves de tabela que recebem duas respostas diferentes, em minúsculas e na ordem de aparição.
## O escopo é uma tabela: um bloco contíguo de linhas que começam e terminam em `|`. Qualquer
## linha fora desse formato fecha a tabela e zera as chaves.
static func contradicting_table_rows(lines: PackedStringArray) -> PackedStringArray:
	var offenders := PackedStringArray()
	var answers := {}
	var fenced := false
	for raw in lines:
		var line := raw.strip_edges()
		if line.begins_with("```"):
			fenced = not fenced
			answers.clear()
			continue
		if fenced or not _is_table_row(line):
			if not fenced:
				answers.clear()
			continue
		var cells := line.substr(1, line.length() - 2).split("|")
		if cells.size() < 2:
			continue
		var key := cells[0].strip_edges().to_lower()
		if key.is_empty() or _is_separator_cell(key):
			continue
		var answer := line.substr(line.find("|", 1))
		if answers.has(key) and answers[key] != answer and not offenders.has(key):
			offenders.append(key)
		answers[key] = answer
	return offenders


static func _is_table_row(line: String) -> bool:
	return line.length() >= 2 and line.begins_with("|") and line.ends_with("|")


## A linha separadora do Markdown (`|---|---|`, com ou sem `:`) é sintaxe, não chave.
static func _is_separator_cell(cell: String) -> bool:
	for character in cell:
		if character != "-" and character != ":" and character != " ":
			return false
	return not cell.is_empty()


func _living_docs() -> PackedStringArray:
	var result := PackedStringArray()
	for dir in LIVING_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			fail("diretório ausente: " + dir)
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for file_name in files:
			if String(file_name).ends_with(".md"):
				result.append(dir + "/" + String(file_name))
	return result


func _read_lines(path: String) -> PackedStringArray:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		fail("não abriu " + path)
		return PackedStringArray()
	var lines := PackedStringArray()
	while not handle.eof_reached():
		lines.append(handle.get_line())
	handle.close()
	return lines
