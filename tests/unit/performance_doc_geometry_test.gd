extends TestCase
## Guarda dos números **estruturais** de `docs/PERFORMANCE.md`.
##
## O documento mistura duas espécies de número, e só uma delas depende de hardware:
##
##   - **tempo** (µs, ms, p95, GPU, frame pacing) — medido num M2 com o bundle exportado. Não
##     se reproduz na nuvem, e o alcance do documento diz isso com razão;
##   - **geometria e payload** (quantas células tem o board, quantos bytes sobem por refresh) —
##     saem de `GameSimulation`/`BoardState` e são os mesmos em qualquer máquina.
##
## O argumento inteiro da ADR-0005 repousa na segunda espécie: "reduz em 4× o payload por
## atualização" é uma razão entre dois inteiros, não uma leitura de cronômetro. Enquanto esses
## inteiros forem prosa digitada à mão, uma mudança de geometria — que já invalida replay pelo
## invariante 7 — deixa o documento a afirmar um ganho que ninguém remediu, e nada fica vermelho.
##
## Este teste não julga desempenho. Ele só recusa que o documento e o domínio discordem sobre
## quantas células existem e quantos bytes sobem.

const DOC := "res://docs/PERFORMANCE.md"

## `Board real: 225×283 = 63.675 células.` — o `×` é o sinal de multiplicação (U+00D7) que o
## documento usa, não a letra `x`.
const BOARD_LINE := "(?m)^Board real: ([0-9.]+)×([0-9.]+) = ([0-9.]+) c[ée]lulas"

## Rótulo da linha da tabela → quantos bytes por refresh o documento promete para aquele caminho.
## O valor conferido é sempre a **última** coluna (`Bytes/refresh`).
const PAYLOAD_ROWS := {
	"máscara R8, steady-state": 1,
	"cold start R8": 1,
	"RGBA8 legado sintético": 4,
}


func test_board_geometry_in_the_doc_matches_the_domain() -> void:
	var board := _production_board()
	var text := _read(DOC)
	var match_ := RegEx.create_from_string(BOARD_LINE).search(text)
	ok(
		match_ != null,
		(
			"docs/PERFORMANCE.md não tem a linha `Board real: <l>×<a> = <n> células`. "
			+ "O board de produção é %d×%d = %s células."
		) % [board.width, board.height, _pt(board.cells.size())],
	)
	if match_ == null:
		return

	eq(
		_int(match_.get_string(1)),
		board.width,
		"docs/PERFORMANCE.md diz que o board tem %s de largura; o domínio dá %d"
			% [match_.get_string(1), board.width],
	)
	eq(
		_int(match_.get_string(2)),
		board.height,
		"docs/PERFORMANCE.md diz que o board tem %s de altura; o domínio dá %d"
			% [match_.get_string(2), board.height],
	)
	eq(
		_int(match_.get_string(3)),
		board.cells.size(),
		(
			"docs/PERFORMANCE.md promete %s células e o domínio tem %s. Mudou a geometria: "
			+ "reveja o perfil e lembre que o invariante 7 já invalidou os replays existentes."
		) % [match_.get_string(3), _pt(board.cells.size())],
	)


func test_upload_payload_in_the_doc_matches_the_cell_count() -> void:
	var cells := _production_board().cells.size()
	var seen := 0
	for line in _read(DOC).split("\n"):
		var text := String(line)
		for label in PAYLOAD_ROWS:
			if not text.begins_with("| " + String(label)):
				continue
			seen += 1
			var expected: int = cells * int(PAYLOAD_ROWS[label])
			var declared := _last_cell(text)
			eq(
				_int(declared),
				expected,
				(
					"docs/PERFORMANCE.md declara %s bytes/refresh em `%s`, mas %d células a "
					+ "%d byte(s) por célula dão %s. O ganho de 4× do R8 é essa razão: se um "
					+ "dos dois números anda sozinho, o documento passa a prometer outro ganho."
				) % [declared, label, cells, int(PAYLOAD_ROWS[label]), _pt(expected)],
			)
	eq(
		seen,
		PAYLOAD_ROWS.size(),
		(
			"esperava conferir %d linha(s) de `Bytes/refresh` no perfil do board e encontrei %d. "
			+ "Renomear um caminho da tabela sem atualizar esta guarda deixa-a a passar sem medir."
		) % [PAYLOAD_ROWS.size(), seen],
	)


## O board que `tools/profile_board_view.gd` mede: regras e rodada de produção, sem autoração.
func _production_board() -> BoardState:
	return GameSimulation.new(GameRules.new(), RoundDefinition.new(), 0xB04D).board


## Última célula não vazia de uma linha de tabela markdown.
func _last_cell(line: String) -> String:
	var parts := line.split("|")
	for i in range(parts.size() - 1, -1, -1):
		var cell := String(parts[i]).strip_edges()
		if cell != "":
			return cell
	return ""


## O documento escreve inteiros à portuguesa (`63.675`); o ponto é separador de milhar.
func _int(text: String) -> int:
	return text.replace(".", "").to_int()


func _pt(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += "."
		out += digits[i]
	return out


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		fail("não abriu " + path)
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
