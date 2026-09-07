extends TestCase
## Guarda mecânica do invariante 6 do `CLAUDE.md`: **apresentação observa, nunca muta**.
##
## O invariante 1 é fácil de guardar porque é um símbolo proibido: `Time.`, `Input.`, `Tween`.
## O 6 é uma **direção de chamada**, e por isso ficou em prosa desde o começo. Prosa não segura o
## dia em que uma view precisar "só zerar `simulation.score` para testar a animação": a escrita
## passa na revisão, o replay diverge três semanas depois, e o checksum acusa um bug que não está
## onde ele nasceu. O custo de descobrir isso tarde é o que este teste compra.
##
## ## O que a varredura prova
##
## Três coisas, e só essas três:
##
## 1. **Nenhum arquivo de apresentação chama um mutador do domínio** — `step`, `reset_round`,
##    `restart_campaign`, `apply_capture_plan`, `set_cell`, `set_index`, e o consumo do
##    `DeterministicRng` (`next_u32`, `next_below`), que desincroniza replay mesmo sem escrever nada.
## 2. **Nenhum arquivo de apresentação atribui a um membro de um identificador tipado como
##    domínio.** O escaneamento coleta, por arquivo, os nomes ligados a um tipo de domínio
##    (parâmetro tipado, `var` tipada, ligação por `as`) e depois acusa `<nome>.<membro> = ...`.
## 3. **Nem por cast anônimo** — `(source as GameSession).simulation = ...` é a forma que escapa
##    da regra 2, porque o receptor nunca ganha nome.
##
## ## O que ela NÃO prova — dito aqui para ninguém confiar demais
##
## - Escrita através de um `Variant` que nunca é anotado nem convertido com `as`.
## - Escrita indireta: a view chama um método de um objeto seu que, lá dentro, muta o domínio.
## - Leitura de estado **não confirmado**. A segunda metade do invariante 6 ("feedback nunca
##   antecipa resultado do domínio") é semântica, não sintática: continua sendo trabalho de revisão
##   e dos testes de comportamento em `presentation_views_test.gd`.
##
## Uma guarda parcial honesta vale mais que uma guarda total imaginária. O que ela cobre, cobre no
## mesmo commit em que a violação nasce.

## Camadas que apenas observam. `res://app` entra porque o invariante 6 nomeia `GameInputAdapter`
## e `QixFeedbackHub`, que moram lá.
const PRESENTATION_DIRS: Array[String] = [
	"res://game/board",
	"res://game/player",
	"res://game/enemies",
	"res://game/vfx",
	"res://game/audio",
	"res://ui",
	"res://app",
]

## Exceções, cada uma com o motivo. Uma exceção sem motivo escrito é uma violação com sorte.
##
## - `app/bootstrap.gd` é o **composition root**, não apresentação: é ele quem dirige o loop e
##   chama `session.step()`. Se ele não pudesse mutar, ninguém poderia, e não haveria jogo.
## - `game/enemies/boss_behavior_controller.gd` é **domínio morando fora de `game/simulation/`**:
##   `GameSimulation` o carrega por `preload` e o consulta dentro do tick, com o
##   `DeterministicRng` na mão. Está em `game/enemies/` por proximidade temática, não por camada.
##   Quem o guarda é `domain_purity_test.gd`, que o varre pelo nome (`DOMAIN_FILES`) — a isenção
##   daqui muda de guarda, não dispensa de guarda. Se este arquivo sair da lista de lá, o teste
##   `test_no_file_falls_between_the_two_purity_guards` fica vermelho.
const EXEMPT_FILES: Dictionary = {
	"res://app/bootstrap.gd": "composition root: é quem avança a sessão",
	"res://game/enemies/boss_behavior_controller.gd": "domínio puro consultado dentro do tick",
}

## Tipos cujo estado é do domínio (simulação, sessão, replay) ou de conteúdo imutável em runtime
## (invariante 9). A apresentação lê todos; não escreve em nenhum.
const DOMAIN_TYPES: Array[String] = [
	"GameSimulation",
	"GameSession",
	"BoardState",
	"DeterministicRng",
	"ReplayLog",
	"CapturePlan",
	"RoundStartState",
	"RoundRunRecord",
	"GameRules",
	"CampaignDefinition",
	"RoundDefinition",
	"RoundContent",
	"RoundVisualDefinition",
	"BossBehaviorProfile",
]

## Métodos que avançam ou reescrevem o domínio. Chamá-los da apresentação é a violação em forma
## mais direta — e `next_u32`/`next_below` entram porque consumir o RNG determinístico fora do
## tick move o estado do gerador sem escrever em lugar nenhum: o replay diverge em silêncio.
const MUTATOR_CALLS: Array = [
	["step", "avançar o domínio é do composition root, não da view"],
	["reset_round", "reiniciar a rodada é decisão de sessão"],
	["restart_campaign", "reiniciar a campanha é decisão de sessão"],
	["apply_capture_plan", "só BoardState escreve células (invariante 3)"],
	["set_cell", "só BoardState escreve células (invariante 3)"],
	["set_index", "só BoardState escreve células (invariante 3)"],
	["next_u32", "consumir o RNG determinístico fora do tick desincroniza o replay"],
	["next_below", "consumir o RNG determinístico fora do tick desincroniza o replay"],
	["replay_into", "reexecutar um replay não é trabalho de apresentação"],
]

## Cauda de uma atribuição, simples ou composta, sem confundir com comparação. As compostas entram
## porque `board.version += 1` escreve tanto quanto `board.version = 1`; `==`, `!=`, `<=` e `>=`
## ficam de fora porque leem. Escrito uma vez e reusado pelas duas regras de escrita.
const ASSIGN_TAIL := "(?:\\+|-|\\*\\*|\\*|/|%|\\|\\||\\||&&|&|\\^|<<|>>)?=(?!=)"

## Trechos que a varredura **tem** de acusar. Sem eles, uma regex quebrada viraria um teste que
## passa para sempre sem olhar nada — o pior resultado possível para uma guarda.
const POSITIVE_SAMPLES: Array[String] = [
	"func sync(simulation: GameSimulation) -> void:\n\tsimulation.score = 0",
	"func sync(session: GameSession) -> void:\n\tsession.phase = 2",
	"func _refresh(board: BoardState) -> void:\n\tboard.version += 1",
	"var _cached: GameSimulation\nfunc _f() -> void:\n\t_cached.permille = 1000",
	"func sync(sim: GameSimulation) -> void:\n\tsim.step(MoveIntent.new())",
	"func _f(session: GameSession) -> void:\n\tsession.simulation.board.set_cell(0, 0, 3)",
	"func _f(rng: DeterministicRng) -> void:\n\tvar d := rng.next_u32()",
	"func _f(source: Variant) -> void:\n\t(source as GameSession).round_index = 0",
	"func _f(v: RoundVisualDefinition) -> void:\n\tv.accent_color = Color.RED",
	"var sim := source as GameSimulation\nsim.lives = 9",
]

## Trechos legítimos que a varredura **não** pode acusar: leitura de campo, comparação, escrita em
## estado próprio da view, e os nomes proibidos citados em comentário ou dentro de texto.
const NEGATIVE_SAMPLES: Array[String] = [
	"func sync(simulation: GameSimulation) -> void:\n\t_label.text = str(simulation.score)",
	"func sync(simulation: GameSimulation) -> void:\n\tif simulation.phase == GameSimulation.Phase.DYING:",
	"func sync(session: GameSession) -> void:\n\tvar p := session.transition_progress()",
	"func _refresh(board: BoardState) -> void:\n\t_texture.set_data(board.cells)",
	"func _f(board: BoardState) -> void:\n\tvar c := board.get_cell(0, 0)",
	"## A view nunca chama simulation.step(); quem avança é o bootstrap.",
	"\tvar msg := \"não escreva session.phase = 0 aqui\"  # nem simulation.score = 0",
	"func sync(simulation: GameSimulation) -> void:\n\t_bytes_uploaded += simulation.tick",
	"func _f(session: GameSession) -> void:\n\t_accent = session.current_content().visual.accent_color",
	"\tvar step_px := 4\n\tstep_px = 8",
	# Comparações: leem, não escrevem. Foi o `+=` que obrigou a cauda de atribuição a aceitar
	# operadores compostos, e é aqui que se prova que ela não passou a engolir `<=`, `>=` e `!=`.
	"func _f(simulation: GameSimulation) -> void:\n\tif simulation.tick >= 60:",
	"func _f(simulation: GameSimulation) -> void:\n\tif simulation.lives <= 0:",
	"func _f(session: GameSession) -> void:\n\tif session.round_index != 0:",
]


func test_presentation_never_mutates_the_domain() -> void:
	var scanned := 0
	for dir in PRESENTATION_DIRS:
		var files := _gd_files_at(dir)
		ok(not files.is_empty(), "nenhum .gd encontrado em %s — varredura vazia não é prova" % dir)
		for path in files:
			if EXEMPT_FILES.has(path):
				continue
			var text := FileAccess.get_file_as_string(path)
			ok(text != "", "não foi possível ler %s" % path)
			ok(
				not text.contains("\"\"\""),
				"%s usa string de três aspas; o scanner não modela esse caso" % path,
			)
			scanned += 1
			for violation in _violations(text):
				fail("%s%s" % [path.trim_prefix("res://"), violation])
	ok(scanned >= 8, "esperava pelo menos 8 arquivos de apresentação, varri %d" % scanned)


func test_scanner_catches_planted_violations() -> void:
	for sample in POSITIVE_SAMPLES:
		ok(
			not _violations(sample).is_empty(),
			"o scanner deixou passar uma violação plantada: %s" % sample,
		)


func test_scanner_ignores_legitimate_observation() -> void:
	for sample in NEGATIVE_SAMPLES:
		var found := _violations(sample)
		ok(found.is_empty(), "falso positivo em código legítimo: %s →%s" % [sample, "".join(found)])


## Toda exceção tem de existir em disco e trazer motivo escrito. Sem isto, um arquivo apagado
## deixaria uma isenção órfã protegendo um caminho que ninguém mais lê.
func test_exemptions_are_real_and_justified() -> void:
	for path in EXEMPT_FILES:
		ok(FileAccess.file_exists(path), "isenção órfã: %s não existe mais" % path)
		var reason: String = EXEMPT_FILES[path]
		ok(reason.length() >= 20, "isenção de %s sem motivo escrito" % path)


## Devolve uma descrição por violação, no formato `:linha: o quê — porquê`.
func _violations(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var code := PackedStringArray()
	for line in lines:
		code.append(_strip_comments_and_strings(line))
	var bound := _domain_identifiers(code)

	for entry in MUTATOR_CALLS:
		var re := _compiled("\\.%s\\s*\\(" % entry[0], out)
		if re == null:
			continue
		for i in code.size():
			if re.search(code[i]) != null:
				out.append("\n      :%d: chama %s() — %s" % [i + 1, entry[0], entry[1]])

	for name in bound:
		var re := _compiled("\\b%s(\\.\\w+)+\\s*%s" % [name, ASSIGN_TAIL], out)
		if re == null:
			continue
		for i in code.size():
			if re.search(code[i]) != null:
				out.append(
					"\n      :%d: escreve em %s.… — apresentação observa, nunca muta" % [i + 1, name]
				)

	var cast_re := _compiled(
		"\\bas\\s+(?:%s)\\s*\\)(\\.\\w+)+\\s*%s" % ["|".join(DOMAIN_TYPES), ASSIGN_TAIL], out
	)
	if cast_re != null:
		for i in code.size():
			if cast_re.search(code[i]) != null:
				out.append(
					"\n      :%d: escreve no domínio por cast anônimo — apresentação observa" % [i + 1]
				)
	return out


## Nomes ligados a um tipo de domínio neste arquivo: parâmetro tipado, `var` tipada, ou ligação
## por `as`. É a lista de receptores cuja escrita de membro é proibida.
func _domain_identifiers(code: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var joined := "\n".join(code)
	var types := "|".join(DOMAIN_TYPES)
	for pattern in ["\\b(\\w+)\\s*:\\s*(?:%s)\\b" % types, "\\b(\\w+)\\s*:?=[^\\n]*\\bas\\s+(?:%s)\\b" % types]:
		var re := RegEx.new()
		if re.compile(pattern) != OK:
			continue
		for m in re.search_all(joined):
			var name := m.get_string(1)
			if name != "" and not out.has(name):
				out.append(name)
	return out


func _compiled(pattern: String, out: PackedStringArray) -> RegEx:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		out.append("\n      : regex inválida no próprio teste: %s" % pattern)
		return null
	return re


## Remove literais de texto e comentários de uma linha de GDScript, preservando o resto.
## Sem isso, o comentário que *documenta* o invariante seria acusado de violá-lo.
func _strip_comments_and_strings(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
			i += 1
			continue
		if c == "\"" or c == "'":
			quote = c
			i += 1
			continue
		if c == "#":
			break
		out += c
		i += 1
	return out


func _gd_files_at(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files_at(dir + "/" + sub))
	out.sort()
	return out
