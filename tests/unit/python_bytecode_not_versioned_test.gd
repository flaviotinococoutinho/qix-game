extends TestCase
## Guarda do limite "não versione artefato derivado", aplicado ao bytecode de Python.
##
## ## Por que esta guarda existe (o caso real, não o hipotético)
##
## O ferramental de `tools/ci/` e `tools/profile/` é Python, e o comando que o próprio CI
## documenta — `python3 -m unittest discover -s tools/ci -p 'test_*.py'` — escreve `__pycache__/`
## na árvore de trabalho **antes de terminar de correr**. Até 2026-09-07 o `.gitignore` não tinha
## regra nenhuma para bytecode. O protocolo do loop prescreve `git add -A`; a soma das duas coisas
## é determinística: quem roda os testes e comita varre o bytecode para dentro do commit sem ver.
##
## Foi o que aconteceu. `main` carregava `tools/profile/__pycache__/*.cpython-314.pyc` — bytecode
## de um interpretador que **não** é o que a CI usa — e três PRs abertos acrescentavam
## `*.cpython-311.pyc` por cima. Nenhum deles quis fazer isso.
##
## O custo não é o disco. É que `.pyc` é binário: o git não o mescla. Num repositório com fila de
## PRs, cada cópia versionada é um conflito cuja resolução não tem significado — não existe
## "escolher o bytecode certo", só existe regenerá-lo. E porque muda a cada execução em máquina
## diferente, aparece como ruído em todo diff, no repositório cujo contrato inteiro é evidência.
##
## ## O que este teste prova
##
## 1. A regra existe e é **não ancorada** — sem `/` inicial e sem prefixo de pasta. É isso que a
##    faz valer para `tools/ci/`, `tools/profile/` e para qualquer pasta de Python que venha
##    depois, sem que ninguém se lembre de vir aqui acrescentá-la.
## 2. Há regra que cobre a extensão do bytecode solto (`*.py[cod]` ou `*.pyc`), e não só o
##    diretório: um `.pyc` gerado fora de `__pycache__/` continua sendo derivado.
## 3. Nenhuma linha posterior **desfaz** a regra com negação (`!`) — no git, a última regra que
##    casa é a que decide, e uma negação distraída deixaria o `.gitignore` verde e inútil.
## 4. A varredura não é vazia: existe de facto pasta com fonte Python sob `res://tools/`. Sem esta
##    afirmação, apagar o ferramental tornaria as outras três verdadeiras por ausência.
##
## ## O que ele NÃO prova — dito aqui para ninguém confiar demais
##
## - **Que não há `.pyc` versionado neste instante.** Um teste headless não consulta o índice do
##   git, e o `.pyc` em disco é legítimo: qualquer execução dos testes de Python o recria. Aferir
##   presença em disco deixaria a guarda vermelha por motivo certo em hora errada. O que esta
##   guarda defende é a **regra** — que foi o que faltou, e cuja remoção é a única forma de o
##   problema voltar.
## - **Que o git interpreta o padrão como este teste supõe.** A leitura aqui é textual; a
##   semântica de `.gitignore` é do git. O que se afirma é a forma da regra, não o comportamento
##   do git.

const GITIGNORE := "res://.gitignore"

## A regra de diretório: casa `__pycache__/` em qualquer profundidade justamente por não estar
## ancorada. Se alguém a reescrever como `/tools/ci/__pycache__/`, esta guarda fica vermelha.
const DIRECTORY_RULE := "__pycache__/"

## Formas aceitáveis para a regra de extensão. `*.py[cod]` cobre `.pyc`, `.pyo` e `.pyd`; `*.pyc`
## sozinho cobre o caso real. Qualquer uma serve — o que não serve é nenhuma.
const EXTENSION_RULES: Array[String] = ["*.py[cod]", "*.pyc"]

const TOOLS_ROOT := "res://tools"


func test_gitignore_declares_an_unanchored_pycache_rule() -> void:
	var rules := _rules()
	ok(
		rules.has(DIRECTORY_RULE),
		(
			"`.gitignore` não tem a regra `%s`. Sem ela, `python3 -m unittest discover -s tools/ci` "
			+ "deixa bytecode na árvore e o `git add -A` do protocolo do loop comita-o."
		) % DIRECTORY_RULE,
	)
	for rule in rules:
		if not rule.ends_with(DIRECTORY_RULE):
			continue
		eq(
			rule,
			DIRECTORY_RULE,
			(
				"a regra de bytecode está ancorada como `%s`. Ancorada, ela cobre uma pasta e "
				+ "perde a seguinte: `tools/profile/` foi exatamente a que escapou."
			) % rule,
		)


func test_gitignore_covers_loose_bytecode_files() -> void:
	var rules := _rules()
	var found := ""
	for candidate in EXTENSION_RULES:
		if rules.has(candidate):
			found = candidate
			break
	ok(
		found != "",
		(
			"`.gitignore` cobre `__pycache__/` mas não a extensão solta. Esperava uma de %s: "
			+ "um `.pyc` fora do diretório de cache continua sendo binário derivado."
		) % str(EXTENSION_RULES),
	)


func test_no_later_rule_re_admits_bytecode() -> void:
	# No git a última regra que casa é a que vale, então uma negação depois da regra reabre a porta
	# sem tocar na linha que este teste verifica.
	for rule in _rules():
		if not rule.begins_with("!"):
			continue
		var negated := rule.substr(1)
		ok(
			not (negated.contains("__pycache__") or negated.contains(".py")),
			(
				"a linha `%s` nega a regra de bytecode. No git a última regra que casa decide: "
				+ "isto deixa o `.gitignore` verde e sem efeito."
			) % rule,
		)


func test_the_scan_is_not_vacuous() -> void:
	# Sem esta afirmação, apagar `tools/*.py` tornaria as guardas acima verdadeiras por ausência —
	# o modo silencioso de uma guarda virar decoração.
	var dirs := _dirs_with_python_sources(TOOLS_ROOT)
	ok(
		dirs.size() >= 2,
		(
			"esperava ao menos duas pastas com fonte Python sob `tools/` (é `tools/ci/` e "
			+ "`tools/profile/` que motivam a regra), encontrei %d: %s"
		) % [dirs.size(), str(dirs)],
	)


## A guarda tem de ser capaz de ficar vermelha. Aqui a leitura é exercitada sobre um `.gitignore`
## sintético que contém o problema real — regra ancorada numa pasta só — para provar que o
## critério discrimina, em vez de aceitar qualquer texto que mencione `__pycache__`.
func test_the_check_rejects_an_anchored_rule() -> void:
	var anchored := _parse("# comentário\n/tools/ci/__pycache__/\n\n.DS_Store\n")
	ok(
		not anchored.has(DIRECTORY_RULE),
		"o critério aceitou `/tools/ci/__pycache__/` como se cobrisse a árvore inteira",
	)
	var good := _parse("# comentário\n__pycache__/\n*.py[cod]\n")
	ok(good.has(DIRECTORY_RULE), "o critério recusou a regra correta `__pycache__/`")
	ok(good.has("*.py[cod]"), "o critério perdeu a regra de extensão numa leitura válida")


func _rules() -> Array[String]:
	var file := FileAccess.open(GITIGNORE, FileAccess.READ)
	ok(file != null, "não foi possível ler %s" % GITIGNORE)
	if file == null:
		return [] as Array[String]
	return _parse(file.get_as_text())


## Linhas úteis de um `.gitignore`: sem comentário, sem branco, sem espaço em volta.
func _parse(text: String) -> Array[String]:
	var rules: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		rules.append(line)
	return rules


func _dirs_with_python_sources(root: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var has_python := false
		var entry := dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var path := current.path_join(entry)
				if dir.current_is_dir():
					pending.append(path)
				elif entry.get_extension() == "py":
					has_python = true
			entry = dir.get_next()
		dir.list_dir_end()
		if has_python:
			found.append(current)
	found.sort()
	return found
