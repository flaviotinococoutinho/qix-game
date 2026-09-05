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
	ok(not doomed.is_empty() or declared.is_empty(), "inventário sem nenhuma pasta condenada")
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
