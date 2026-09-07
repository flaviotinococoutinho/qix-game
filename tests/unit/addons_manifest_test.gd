extends TestCase
## Guarda do inventário de `addons/` (ADR-0010).
##
## Uma pasta de terceiros sem uma linha que diga por que está ali é uma decisão adiada: quem lê
## o repositório amanhã não distingue dependência real de resto de download, e a única forma de
## descobrir é refazer a varredura. Este teste amarra `addons/README.md` ao disco para que a
## resposta não possa envelhecer em silêncio.
##
## O manifesto é a tabela de `addons/README.md` cujas linhas têm a forma:
##
##   | `pasta` | `estado` | motivo |
##
## e o contrato de cada estado é:
##
##   `dependencia` — o jogo consome a pasta; exige citação de `addons/<pasta>` fora de `addons/`;
##   `ferramenta`  — serve ao editor/agente; exige citação em `project.godot`;
##   `a-remover`   — sem consumidor; exige **nenhuma** citação fora de `addons/` e presença no
##                   `exclude_filter` de todos os presets, para que uma pasta condenada não vaze
##                   para um build enquanto espera a remoção.

const ADDONS_DIR := "res://addons"
const MANIFEST := "res://addons/README.md"
const PROJECT_FILE := "res://project.godot"
const EXPORT_PRESETS := "res://export_presets.cfg"

## Onde uma citação a addon conta como consumo real. `export_presets.cfg` fica de fora de
## propósito: ele cita tudo, inclusive o que está condenado.
const CONSUMER_DIRS := ["res://game", "res://ui", "res://app", "res://tools", "res://tests", "res://content"]
const CONSUMER_EXTENSIONS := [".gd", ".tscn", ".tres", ".gdshader", ".cfg"]

const STATES := ["dependencia", "ferramenta", "a-remover"]

## O fecho da tabela é uma frase com dois números **derivados** dela: quantas pastas continuam
## `a-remover` e quantas cenas somam. Derivado escrito à mão é o que envelhece primeiro — cada
## remoção da ADR-0010 recalcula a frase inteira, e duas remoções abertas ao mesmo tempo chegam
## com totais que se contradizem (medido em 2026-09-07: três PRs abertos escreviam "~7,9 MB / 59
## cenas", "~9,3 MB / 71 cenas" e "~8,8 MB / 82 cenas" para a mesma linha). Resolver esse conflito
## por `--ours`, `--theirs` ou união deixa um total que não descreve árvore nenhuma, e nada ficava
## vermelho. Daqui em diante, fica.
## `(?m)` porque a frase é uma linha no meio do arquivo: sem ele o `^` do PCRE2 ancora no início
## do documento inteiro e a busca nunca casa.
const TOTALS_ROW := "(?m)^Somadas, as ([a-zç]+) pastas `a-remover` ocupam ~[0-9,.]+ MB e declaram ([0-9]+) cenas"

## O fecho do outro extremo: executadas as sete remoções, não resta pasta condenada e a frase no
## plural passa a mentir. Medido em 2026-09-07, ao integrar as sete: a guarda acima, escrita
## quando havia seis, ficava **vermelha exatamente no estado que a ADR-0010 pediu** — o `NUMERALS`
## começa em `duas` e o regex exige o plural. Uma guarda derivada que proíbe o seu próprio fim é a
## mesma falha de acoplamento que o #69 tem na matriz de teste, e não a de números desatualizados.
const EMPTY_TOTALS_ROW := "(?m)^Nenhuma pasta `a-remover` resta"

## Só as formas que a frase pode assumir enquanto restar mais de uma pasta. Chegando a uma ou a
## zero, o plural deixa de servir e a frase tem de ser reescrita — o teste falha e pede isso, em
## vez de aceitar em silêncio uma concordância errada.
const NUMERALS := {
	"duas": 2, "três": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7,
}


func test_every_addon_folder_has_a_manifest_line_and_vice_versa() -> void:
	var declared := _manifest()
	var on_disk := _addon_folders()
	ok(on_disk.size() >= 2, "addons/ deveria ter pastas, obtido %d" % on_disk.size())
	for folder in on_disk:
		ok(
			declared.has(folder),
			(
				"addons/%s não tem linha em addons/README.md. Acrescente uma com o estado "
				+ "(%s) e o motivo — ver ADR-0010."
			) % [folder, "/".join(STATES)],
		)
	for folder in declared:
		ok(
			on_disk.has(folder),
			"addons/README.md declara `%s`, que não existe em addons/" % folder,
		)


func test_every_declared_state_belongs_to_the_vocabulary() -> void:
	var declared := _manifest()
	ok(not declared.is_empty(), "addons/README.md não rendeu nenhuma linha de inventário")
	for folder in declared:
		ok(
			STATES.has(declared[folder]),
			(
				"addons/%s declara estado `%s`, fora do vocabulário (%s)"
			) % [folder, declared[folder], ", ".join(STATES)],
		)


func test_tool_addons_are_named_by_the_project_file() -> void:
	var declared := _manifest()
	var project := _read(PROJECT_FILE)
	ok(project != "", "não leu " + PROJECT_FILE)
	for folder in declared:
		if declared[folder] != "ferramenta":
			continue
		ok(
			project.contains("addons/" + folder),
			(
				"addons/%s está como `ferramenta` mas project.godot não a cita. "
				+ "Ferramenta sem plugin habilitado nem autoload é `a-remover`."
			) % folder,
		)


func test_addons_marked_for_removal_have_no_consumer_left() -> void:
	var declared := _manifest()
	var doomed := PackedStringArray()
	for folder in declared:
		if declared[folder] == "a-remover":
			doomed.append(folder)
	# A asserção aqui é que o manifesto **foi lido**, não que ainda haja pasta condenada: com as
	# sete remoções da ADR-0010 executadas, `doomed` vazio é o estado de chegada da decisão, não
	# um parser que devolveu nada. Escrita como `not doomed.is_empty()`, a guarda proibia
	# exatamente o fim que a ADR pediu.
	ok(not declared.is_empty(), "addons/README.md não rendeu nenhuma linha de inventário")
	var citations := _citations(doomed)
	for folder in doomed:
		var cited: PackedStringArray = citations[folder]
		ok(
			cited.is_empty(),
			(
				"addons/%s está como `a-remover` mas é citada por: %s. "
				+ "Se passou a ser usada, mude a linha para `dependencia` em addons/README.md."
			) % [folder, ", ".join(cited)],
		)


func test_dependency_addons_have_at_least_one_consumer() -> void:
	var declared := _manifest()
	var used := PackedStringArray()
	for folder in declared:
		if declared[folder] == "dependencia":
			used.append(folder)
	# Hoje nenhuma pasta é `dependencia`; a asserção existe para que o estado tenha sentido no dia
	# em que alguém o usar, em vez de virar sinônimo educado de "não sei".
	ok(true, "estado `dependencia` declarado por %d pasta(s)" % used.size())
	var citations := _citations(used)
	for folder in used:
		var cited: PackedStringArray = citations[folder]
		ok(
			not cited.is_empty(),
			(
				"addons/%s está como `dependencia` mas nenhum arquivo fora de addons/ a cita"
			) % folder,
		)


func test_addons_marked_for_removal_stay_out_of_every_export_preset() -> void:
	var declared := _manifest()
	var filters := _exclude_filters()
	ok(filters.size() >= 1, "export_presets.cfg não rendeu linha de exclude_filter")
	for folder in declared:
		if declared[folder] != "a-remover":
			continue
		for i in filters.size():
			ok(
				String(filters[i]).contains("addons/%s/**" % folder),
				(
					"addons/%s está como `a-remover` mas o exclude_filter nº %d não a exclui — "
					+ "uma pasta condenada não pode vazar para um build enquanto espera a remoção."
				) % [folder, i + 1],
			)


## O fecho da tabela conta pastas e cenas. Os dois números saem do disco, não da prosa.
##
## Os megabytes ficam **de fora de propósito**: o número da tabela foi medido com contagem por
## blocos, e o mesmo conteúdo dá 6,8 MB somando o tamanho dos arquivos e 16 MB somando blocos
## neste checkout. Nenhuma das duas leituras é errada, e uma guarda que exigisse uma delas ficaria
## vermelha conforme o sistema de arquivos de quem roda. Contagem de pasta e de cena não tem essa
## ambiguidade: é a mesma em qualquer máquina, e é o que a frase promete ao leitor.
func test_removal_totals_match_the_folders_on_disk() -> void:
	var declared := _manifest()
	var doomed := PackedStringArray()
	for folder in declared:
		if declared[folder] == "a-remover":
			doomed.append(folder)

	var scenes := 0
	for folder in doomed:
		scenes += _count_scenes(ADDONS_DIR + "/" + folder)

	var manifest := _read(MANIFEST)
	var m := RegEx.create_from_string(TOTALS_ROW).search(manifest)

	# Zero pastas condenadas é o estado de chegada da ADR-0010, e a frase de fecho no plural deixa
	# de descrever coisa nenhuma. Aqui a guarda inverte-se: exige a frase de encerramento e recusa
	# um plural sobrevivente, para que a última remoção não deixe para trás um total que já não
	# soma nada. Os números históricos dessa frase não são deriváveis do disco — as pastas não
	# estão lá —, por isso o que se confere é a declaração de vazio, não a aritmética.
	if doomed.is_empty():
		ok(
			RegEx.create_from_string(EMPTY_TOTALS_ROW).search(manifest) != null,
			(
				"nenhuma pasta continua `a-remover`, mas addons/README.md não declara o fecho da "
				+ "ADR-0010 (`Nenhuma pasta `a-remover` resta`). Escreva-o: o leitor tem de "
				+ "distinguir 'a decisão acabou' de 'alguém apagou a linha'."
			),
		)
		ok(
			m == null,
			(
				"addons/README.md ainda promete `as %s pastas a-remover`, mas nenhuma resta. "
				+ "A última remoção atualizou a tabela e esqueceu o fecho."
			) % [m.get_string(1) if m != null else ""],
		)
		return

	ok(
		m != null,
		(
			"addons/README.md não tem a frase de fecho no formato esperado (`Somadas, as <numeral> "
			+ "pastas `a-remover` ocupam ~<n> MB e declaram <n> cenas`). Restam %d pasta(s) e %d "
			+ "cena(s): reescreva a frase mantendo os dois números conferíveis."
		) % [doomed.size(), scenes],
	)
	if m == null:
		return

	var numeral := m.get_string(1)
	ok(
		NUMERALS.has(numeral),
		(
			"addons/README.md diz `as %s pastas a-remover`, numeral que a guarda não conhece. "
			+ "Restam %d pasta(s) — se o plural deixou de servir, reescreva a frase."
		) % [numeral, doomed.size()],
	)
	if NUMERALS.has(numeral):
		ok(
			int(NUMERALS[numeral]) == doomed.size(),
			(
				"addons/README.md diz `as %s pastas a-remover` (%d), mas a tabela declara %d. "
				+ "Uma remoção da ADR-0010 atualizou a tabela e esqueceu o fecho."
			) % [numeral, int(NUMERALS[numeral]), doomed.size()],
		)

	ok(
		m.get_string(2).to_int() == scenes,
		(
			"addons/README.md promete %s cenas nas pastas `a-remover`, mas o disco tem %d. "
			+ "Ver ADR-0010: o fecho da tabela é derivado, e derivado desatualizado mente sem "
			+ "que nada fique vermelho."
		) % [m.get_string(2), scenes],
	)


## Cenas declaradas sob um caminho, recursivamente.
func _count_scenes(dir: String) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var total := 0
	for sub in DirAccess.get_directories_at(dir):
		total += _count_scenes(dir + "/" + String(sub))
	for f in DirAccess.get_files_at(dir):
		if String(f).ends_with(".tscn"):
			total += 1
	return total


## Lê a tabela de inventário. Chave: nome da pasta; valor: estado declarado.
func _manifest() -> Dictionary:
	var result := {}
	var row := RegEx.create_from_string("^\\| `([A-Za-z0-9_.-]+)` \\| `([a-z-]+)` \\|")
	for line in _read(MANIFEST).split("\n"):
		var m := row.search(line)
		if m != null:
			result[m.get_string(1)] = m.get_string(2)
	return result


func _addon_folders() -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(ADDONS_DIR):
		fail("diretório ausente: " + ADDONS_DIR)
		return result
	var dirs := Array(DirAccess.get_directories_at(ADDONS_DIR))
	dirs.sort()
	for d in dirs:
		result.append(String(d))
	return result


## Para cada pasta pedida, os arquivos fora de `addons/` que citam `addons/<pasta>`.
func _citations(folders: PackedStringArray) -> Dictionary:
	var result := {}
	for folder in folders:
		result[folder] = PackedStringArray()
	if folders.is_empty():
		return result
	for path in _consumer_files():
		var text := _read(path)
		for folder in folders:
			if text.contains("addons/" + folder):
				result[folder].append(path)
	return result


func _consumer_files() -> PackedStringArray:
	var result := PackedStringArray()
	for dir in CONSUMER_DIRS:
		_collect(dir, result)
	result.append(PROJECT_FILE)
	return result


func _collect(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + String(sub), out)
	for f in DirAccess.get_files_at(dir):
		var name := String(f)
		for ext in CONSUMER_EXTENSIONS:
			if name.ends_with(ext):
				out.append(dir + "/" + name)
				break


func _exclude_filters() -> PackedStringArray:
	var result := PackedStringArray()
	for line in _read(EXPORT_PRESETS).split("\n"):
		if String(line).begins_with("exclude_filter="):
			result.append(String(line))
	return result


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		fail("não abriu " + path)
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
