extends TestCase
## Guarda do cabeçalho de verificação da documentação.
##
## Um documento sem data envelhece em silêncio e vira mentira confiante: quem lê não
## consegue separar o que ainda vale do que já foi contradito pelo código. O contrato é:
##
##   1. todo `docs/*.md` declara, logo abaixo do H1, **quando** foi verificado, **contra
##      qual commit** e **em que ambiente**, seguido do **alcance** — o que foi conferido e
##      o que ficou de fora;
##   2. todo `docs/decisions/ADR-*.md` carrega a data da decisão no cabeçalho de estado.
##      Uma ADR não é reverificada: ela é aceita numa data e, se deixar de valer, é
##      superada por outra. Por isso lhe basta a data, sem alcance.
##
## Este teste existe para que um documento novo sem cabeçalho falhe aqui, e não seis meses
## depois na cabeça de quem confiou nele.

const DOCS_DIR := "res://docs"
const ADR_DIR := "res://docs/decisions"

const HEADER_PATTERN := "^> \\*\\*Verificado em\\*\\* [0-9]{4}-[0-9]{2}-[0-9]{2} · commit `[0-9a-f]{7,40}` · .+$"
const SCOPE_PATTERN := "^> \\*\\*Alcance:\\*\\* .+$"
const DATE_PATTERN := "[0-9]{4}-[0-9]{2}-[0-9]{2}"

## Quantas linhas do topo o cabeçalho pode ocupar antes de deixar de ser cabeçalho.
const HEADER_WINDOW := 6
const ADR_WINDOW := 8


func test_every_doc_declares_verification_date_commit_and_scope() -> void:
	var header := RegEx.create_from_string(HEADER_PATTERN)
	var scope := RegEx.create_from_string(SCOPE_PATTERN)
	var files := _markdown_files(DOCS_DIR)
	ok(files.size() >= 7, "docs/ deveria listar os documentos de topo, obtido %d" % files.size())
	for file_name in files:
		var lines := _head_lines(DOCS_DIR + "/" + file_name, HEADER_WINDOW)
		var header_line := -1
		for i in lines.size():
			if header.search(lines[i]) != null:
				header_line = i
				break
		ok(
			header_line >= 0,
			(
				"%s não declara verificação nas primeiras %d linhas. Esperado: "
				+ "`> **Verificado em** AAAA-MM-DD · commit `abc1234` · ambiente`"
			) % [file_name, HEADER_WINDOW],
		)
		if header_line < 0:
			continue
		var has_scope := header_line + 1 < lines.size() and scope.search(lines[header_line + 1]) != null
		ok(
			has_scope,
			"%s declara data mas não declara `> **Alcance:**` na linha seguinte" % file_name,
		)


func test_every_adr_declares_the_date_of_the_decision() -> void:
	var date := RegEx.create_from_string(DATE_PATTERN)
	var files := _markdown_files(ADR_DIR)
	ok(files.size() >= 8, "docs/decisions/ deveria listar as ADRs, obtido %d" % files.size())
	for file_name in files:
		if not file_name.begins_with("ADR-"):
			continue
		var lines := _head_lines(ADR_DIR + "/" + file_name, ADR_WINDOW)
		var dated := false
		for line in lines:
			if date.search(line) != null:
				dated = true
				break
		ok(
			dated,
			"%s não datou a decisão nas primeiras %d linhas" % [file_name, ADR_WINDOW],
		)


func _markdown_files(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		fail("diretório ausente: " + dir)
		return result
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if String(f).ends_with(".md"):
			result.append(String(f))
	return result


func _head_lines(path: String, count: int) -> PackedStringArray:
	var result := PackedStringArray()
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		fail("não abriu " + path)
		return result
	while result.size() < count and not handle.eof_reached():
		result.append(handle.get_line())
	handle.close()
	return result
