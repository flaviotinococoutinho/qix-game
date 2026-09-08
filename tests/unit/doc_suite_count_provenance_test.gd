extends TestCase
## Guarda de procedência das contagens de suíte — a terceira pergunta sobre a documentação.
##
## `doc_freshness_header_test.gd` prova que o **documento** declara data, commit e ambiente.
## `doc_internal_consistency_test.gd` prova que o documento não afirma duas coisas sobre o mesmo
## fato. Nenhuma das duas alcança o caso que motivou esta guarda, registrado no backlog do
## `LOOP_LEDGER` como "contagem de outro ambiente parece atual fora da matriz" (#69):
##
##   `| suíte headless | 134 testes, 11.489 asserções, 0 falhas | ... |`
##
## A linha é **verdadeira** — foi medida no run de macOS de 2026-09-03 — e por isso nenhuma
## guarda de contradição a acusa. Ela também não é a árvore de hoje, que roda 404 testes no CI
## Linux. O cabeçalho do documento diz a data certa; a linha, lida sozinha, não diz nada. E é
## sozinha que uma linha de tabela é lida: quem procura "quantos testes tem o projeto" varre a
## coluna, não o parágrafo três seções acima.
##
## Daí o recorte: a guarda cobre **linhas que se leem sozinhas** — linhas de tabela e itens de
## lista. Parágrafo corrido fica de fora de propósito, e não por comodidade: `PERFORMANCE.md`
## escreve "Estes números valem para Apple M2/Metal e este bundle local" numa frase que só
## significa alguma coisa junto das duas frases anteriores. Exigir carimbo em cada linha de prosa
## trocaria uma guarda por ruído — o mesmo erro que o #82 mediu e recusou na heurística de
## contradição textual. Linha de continuação de um item (recuada, sem marcador) também fica fora:
## ela pertence ao item acima, e é ali que o leitor a encontra.
##
## Uma linha em alcance satisfaz o contrato de um destes dois modos:
##
##   1. **carimbada** — diz na própria linha de que ambiente e de que data veio; ou
##   2. **derivada** — diz que o número sai da árvore desta branch. Uma contagem derivada não
##      leva data: ela é reconferida a cada execução, e datá-la seria plantar a mentira que esta
##      guarda existe para impedir. Quem a mantém honesta é a guarda de inventário do #69.
##
## `docs/loop/` fica fora pelo mesmo motivo de `doc_internal_consistency_test.gd`: relato de
## execução é histórico append-only, carimbado pelo próprio arquivo. `docs/decisions/` fica fora
## porque uma ADR não é remedida — ela é aceita numa data, que a guarda de cabeçalho já exige.

const LIVING_DOCS_DIR := "res://docs"

## O que conta como afirmação de suíte. Deliberadamente estreito: um número imediatamente antes
## de "testes"/"asserções". "0 falhas" sozinho não entra — ele nunca aparece sem a contagem ao
## lado, e sozinho seria só ruído.
const COUNT_PATTERN := "[0-9][0-9.,]*\\s*(testes|asserç(ões|ão))"

## Linha que se lê sozinha: linha de tabela, ou **início** de item de lista.
const STANDALONE_PATTERN := "^\\s*(\\||[-*+] |[0-9]+\\. )"

## Data explícita (`2026-09-03`) ou a forma curta que o projeto já usa nos títulos de seção
## histórica (`setembro/03`).
const DATE_PATTERN := "([0-9]{4}-[0-9]{2}-[0-9]{2}|(janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)/[0-9]{2})"

## Vocabulário de ambiente. Lista explícita, não heurística: é curto porque os ambientes deste
## projeto são poucos e nomeados em `docs/PROJECT_CONTRACT.md`. Ambiente novo entra aqui junto
## com o primeiro documento que o cita — e essa edição é o momento certo de perguntar se o
## ambiente é mesmo novo ou se é um nome novo para um antigo.
const ENVIRONMENT_TOKENS: Array[String] = [
	"macOS",
	"Linux",
	"Windows",
	"Android",
	"iOS",
	"CI",
	"Apple M2",
]

## Marcas de contagem derivada da árvore desta branch. "árvore" é a palavra que o projeto já usa
## em `TEST_MATRIX.md` para essa distinção.
const DERIVED_TOKENS: Array[String] = [
	"árvore",
	"derivad",
]


func test_standalone_suite_counts_declare_environment_and_date() -> void:
	var scanned := 0
	var checked := 0
	for file_name in _living_docs():
		scanned += 1
		var path := LIVING_DOCS_DIR + "/" + file_name
		var lines := _read_lines(path)
		for index in lines.size():
			var line := lines[index]
			if not is_standalone_suite_count(line):
				continue
			checked += 1
			ok(
				declares_provenance(line),
				(
					"%s:%d afirma uma contagem de suíte sem dizer, na própria linha, de que "
					+ "ambiente e data ela veio — nem que é derivada desta árvore. Uma linha de "
					+ "tabela é lida sozinha, e sozinha ela parece atual.\n      linha: %s"
				) % [file_name, index + 1, line.strip_edges()],
			)
	ok(scanned >= 7, "esperava varrer os documentos vivos de docs/, varreu %d" % scanned)
	# Se o alcance chegar a zero, a guarda passou a não medir nada e ninguém perceberia.
	ok(checked >= 5, "esperava encontrar contagens de suíte para conferir, encontrou %d" % checked)


## Prova nos dois sentidos, sem depender de plantar texto num documento real: a mesma linha, com
## e sem carimbo, precisa cair dos dois lados da regra.
func test_the_rule_separates_a_stamped_line_from_a_bare_one() -> void:
	var bare := "| suíte headless | 134 testes, 11.489 asserções, 0 falhas | contratos verdes |"
	ok(is_standalone_suite_count(bare), "linha de tabela com contagem deveria entrar no alcance")
	ok(not declares_provenance(bare), "linha sem ambiente nem data deveria ser recusada")

	var dated := bare.replace("0 falhas", "0 falhas em 2026-09-03")
	ok(not declares_provenance(dated), "só a data não basta: falta o ambiente")

	var located := bare.replace("0 falhas", "0 falhas em macOS")
	ok(not declares_provenance(located), "só o ambiente não basta: falta a data")

	var stamped := bare.replace("0 falhas", "0 falhas — macOS, 2026-09-03")
	ok(declares_provenance(stamped), "linha com ambiente e data deveria ser aceita")

	var derived := bare.replace("0 falhas", "0 falhas desta árvore")
	ok(declares_provenance(derived), "contagem derivada da árvore deveria ser aceita sem data")


func test_prose_and_continuation_lines_stay_out_of_scope() -> void:
	ok(
		not is_standalone_suite_count("Resultado da suíte integrada: 404 testes, 19009 asserções."),
		"parágrafo corrido não é lido sozinho e fica fora do alcance",
	)
	ok(
		not is_standalone_suite_count("  O parser teve 16 testes Python aprovados: descarta o"),
		"continuação recuada pertence ao item acima e fica fora do alcance",
	)
	ok(
		not is_standalone_suite_count("| perfil isolado do board | R8 p50/p95 1/1 µs em 240 amostras |"),
		"linha de tabela sem contagem de suíte não entra no alcance",
	)


## Verdadeiro quando a linha se lê sozinha **e** afirma uma contagem de suíte.
func is_standalone_suite_count(line: String) -> bool:
	var standalone := RegEx.create_from_string(STANDALONE_PATTERN)
	if standalone.search(line) == null:
		return false
	var count := RegEx.create_from_string(COUNT_PATTERN)
	return count.search(line) != null


## Verdadeiro quando a linha carimba a medição (ambiente **e** data) ou se declara derivada.
func declares_provenance(line: String) -> bool:
	for token in DERIVED_TOKENS:
		if line.findn(token) >= 0:
			return true
	var date := RegEx.create_from_string(DATE_PATTERN)
	if date.search(line) == null:
		return false
	for token in ENVIRONMENT_TOKENS:
		if line.find(token) >= 0:
			return true
	return false


func _living_docs() -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(LIVING_DOCS_DIR):
		fail("diretório ausente: " + LIVING_DOCS_DIR)
		return result
	var files := Array(DirAccess.get_files_at(LIVING_DOCS_DIR))
	files.sort()
	for f in files:
		if String(f).ends_with(".md"):
			result.append(String(f))
	return result


func _read_lines(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		fail("não abriu " + path)
		return result
	while not handle.eof_reached():
		result.append(handle.get_line())
	handle.close()
	return result
