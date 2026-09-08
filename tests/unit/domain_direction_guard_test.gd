extends TestCase
## Guarda **geral** da direção entre domínio e apresentação — o achado que ficou aberto em
## `docs/loop/runs/2026-09-07T100000Z.md` e que o backlog carregava como P2 (#74).
##
## ## O buraco que esta guarda fecha
##
## `rules_presentation_exception_test.gd` prova que `game/simulation/` e `game/session/` nunca
## nomeiam `RoundVisualDefinition` nem leem `.visual`. Essa prova é **nominal**: ela conhece o
## nome de **uma** dependência de apresentação, a que já tinha dado problema. A pergunta que
## ficou registrada no relato daquela execução é a outra metade — *quais outras dependências de
## apresentação a sessão pode ler sem aquela guarda nominal perceber?*
##
## A resposta medida antes de escrever este arquivo: **todas as demais**. Nenhuma das guardas
## existentes vê `var hud: QixGameHud` dentro de `GameSession`, nem `var tint := Color("ff0000")`
## dentro de `GameSimulation`. A guarda de domínio (`domain_purity_test.gd`) procura símbolos do
## **mundo real** — relógio, `Input`, `Tween`, float — e nenhum desses nomes é um deles; `Color`
## é quatro floats com outro nome e atravessa a regra do `float` sem tocá-la. A guarda de
## apresentação (`presentation_purity_test.gd`) varre a direção de chamada **dentro das pastas de
## apresentação**, e `game/simulation/`/`game/session/` não são uma delas. As três varreduras
## juntas cobriam tudo menos exatamente esta seta: domínio → apresentação.
##
## ## O que esta guarda prova
##
## 1. **O domínio não nomeia nenhuma classe de apresentação deste repositório.** A lista não é
##    digitada: ela é **derivada** dos `class_name` declarados sob as pastas de apresentação. Uma
##    view nova entra na proibição no mesmo commit em que nasce, sem ninguém lembrar de a listar.
##    Derivar vence vigiar — é a lição que o #82 mediu e o #69 já aplica na matriz de testes.
## 2. **Nem um tipo de apresentação da própria engine.** `Color`, `Texture2D`, `Node`, `Control`,
##    `RenderingServer` e companhia não têm `class_name` neste repositório, logo o passo 1 não os
##    alcança. Cada um está declarado abaixo com o motivo de estar lá.
## 3. **Nenhum arquivo do domínio herda de um nó.** Os 31 arquivos de domínio estendem hoje só
##    `RefCounted` e `Resource`. Herdar de `Node` põe o domínio dentro da árvore de cena, isto é,
##    dentro do quadro — e o invariante 2 diz que ele avança por `step(intent)`, não por quadro.
##
## ## O que ela NÃO prova — dito para ninguém confiar demais
##
## Ela lê símbolos, não semântica, exatamente como as guardas irmãs. Um `Variant` que carregue uma
## view sem nunca ser anotado atravessa; um objeto de apresentação recebido por parâmetro não
## tipado também. Isso continua sendo trabalho de revisão. O que ela cobre, cobre no commit em que
## a violação nasce — e é onde ela é barata.

## O domínio guardado. Deliberadamente as mesmas duas pastas da prova nominal irmã: `game/rules/`
## fica de fora porque **hospeda** apresentação por decisão de conteúdo (`RoundVisualDefinition`),
## e quem cobra o preço dessa exceção é `rules_presentation_exception_test.gd`.
const DOMAIN_DIRS: Array[String] = [
	"res://game/simulation",
	"res://game/session",
]

## As pastas de onde os nomes proibidos são **derivados**. É a mesma lista de
## `presentation_purity_test.gd`: se as duas divergirem, uma camada fica sem seta guardada em
## algum dos dois sentidos — por isso `test_the_two_direction_guards_agree_on_what_presentation_is`
## confronta as duas em vez de as deixar envelhecer em paralelo.
const PRESENTATION_DIRS: Array[String] = [
	"res://game/board",
	"res://game/player",
	"res://game/enemies",
	"res://game/vfx",
	"res://game/audio",
	"res://ui",
	"res://app",
]

const PRESENTATION_GUARD := "res://tests/unit/presentation_purity_test.gd"

## Reaproveita o removedor de comentários e literais da guarda de domínio em vez de o copiar: duas
## cópias divergem, e a que diverge em silêncio é a que deixa passar. Se o helper sumir de lá, o
## teste de violações plantadas fica vermelho — não silenciosamente permissivo.
const DOMAIN_GUARD := "res://tests/unit/domain_purity_test.gd"

## Bases que um arquivo de domínio pode estender. `RefCounted` e `Resource` existem fora da árvore
## de cena; é isso que os torna aceitáveis. Qualquer outra base é uma decisão, não um detalhe.
const ALLOWED_BASES: Array[String] = ["RefCounted", "Resource"]

## Tipos de apresentação da **engine** — os que o passo derivado não alcança porque não são
## declarados neste repositório. Cada entrada com o motivo de ser apresentação, e não domínio.
##
## `test_this_guard_does_not_repeat_the_domain_purity_guard` confronta esta lista com as regras de
## `domain_purity_test.gd`: um nome que a guarda irmã já acusa **não pode** estar aqui. É assim que
## `Tween`, `Vector2` e as funções de float ficam de fora sem ninguém precisar lembrar — e é por
## isso que esta lista mede cobertura nova em vez de repetir a que já existe.
const ENGINE_PRESENTATION_TYPES: Dictionary = {
	"Color": "quatro floats com outro nome; paleta é apresentação e não pode tocar o checksum",
	"Texture": "pixels; o território é PackedByteArray (invariante 3)",
	"Texture2D": "pixels; o território é PackedByteArray (invariante 3)",
	"ImageTexture": "pixels; o território é PackedByteArray (invariante 3)",
	"Image": "pixels; o território é PackedByteArray (invariante 3)",
	"Font": "tipografia é do HUD; o domínio não formata texto",
	"StyleBox": "estilo de controle é do HUD; o domínio não formata texto",
	"Theme": "estilo de controle é do HUD; o domínio não formata texto",
	"Material": "estado de GPU não existe no tick",
	"Shader": "estado de GPU não existe no tick",
	"ShaderMaterial": "estado de GPU não existe no tick",
	"Gradient": "rampa de cor é apresentação",
	"Node": "herdar ou nomear um nó põe o domínio na árvore de cena, logo no quadro",
	"Node2D": "herdar ou nomear um nó põe o domínio na árvore de cena, logo no quadro",
	"Node3D": "herdar ou nomear um nó põe o domínio na árvore de cena, logo no quadro",
	"CanvasItem": "quem desenha é a apresentação",
	"CanvasLayer": "quem desenha é a apresentação",
	"Control": "quem desenha é a apresentação",
	"Label": "quem desenha é a apresentação",
	"Sprite2D": "quem desenha é a apresentação",
	"Camera2D": "enquadramento é apresentação",
	"Viewport": "enquadramento é apresentação",
	"Window": "janela é do sistema, não do tick",
	"RenderingServer": "servidor da engine: mundo real dentro do domínio",
	"DisplayServer": "servidor da engine: mundo real dentro do domínio",
	"AudioServer": "servidor da engine: mundo real dentro do domínio",
	"TextServer": "servidor da engine: mundo real dentro do domínio",
	"AudioStream": "som é feedback confirmado, produzido depois do tick",
	"AudioStreamPlayer": "som é feedback confirmado, produzido depois do tick",
	"queue_redraw": "pedir redesenho é a apresentação a agir",
}

## Nomes que o passo derivado **tem** de encontrar. Sem este piso, um erro na varredura de
## `class_name` produziria uma lista vazia e o teste passaria para sempre sem olhar nada.
const EXPECTED_PRESENTATION_CLASSES: Array[String] = [
	"QixBoardView",
	"QixPlayerView",
	"QixEnemyView",
	"QixGameHud",
	"QixFeedbackHub",
	"GameInputAdapter",
]


## Passo 1: nenhuma classe de apresentação deste repositório é nomeada pelo domínio.
func test_the_domain_never_names_a_presentation_class() -> void:
	var classes := _presentation_class_names()
	ok(classes.size() >= EXPECTED_PRESENTATION_CLASSES.size(),
		"derivei só %d class_name de apresentação — varredura vazia não é prova" % classes.size())
	for expected in EXPECTED_PRESENTATION_CLASSES:
		ok(classes.has(expected),
			"a derivação perdeu %s: a lista de proibidos deixou de cobrir a camada" % expected)

	for path in _domain_files():
		var found := _names_in(FileAccess.get_file_as_string(path), classes)
		ok(
			found.is_empty(),
			(
				"%s nomeia apresentação (%s). O domínio não conhece quem o desenha: se uma view "
				+ "entra no tick, mudar a apresentação passa a mover checksum e a invalidar "
				+ "replay (invariantes 6 e 8)."
			) % [path.trim_prefix("res://"), ", ".join(found)],
		)


## Passo 2: nem um tipo de apresentação da engine, que o passo 1 não alcança.
func test_the_domain_never_names_an_engine_presentation_type() -> void:
	var names := PackedStringArray(ENGINE_PRESENTATION_TYPES.keys())
	for path in _domain_files():
		var found := _names_in(FileAccess.get_file_as_string(path), names)
		for name in found:
			ok(
				false,
				(
					"%s nomeia o tipo de apresentação %s — %s. Ou o cálculo é de apresentação e "
					+ "sai do domínio, ou o tipo é o errado para o que se quer calcular."
				) % [path.trim_prefix("res://"), name, ENGINE_PRESENTATION_TYPES[name]],
			)
		ok(found.is_empty(), "%s carrega tipo de apresentação da engine" % path.trim_prefix("res://"))


## Passo 3: o domínio vive fora da árvore de cena.
func test_every_domain_file_extends_only_off_tree_bases() -> void:
	var files := _domain_files()
	ok(files.size() >= 25, "esperava pelo menos 25 arquivos de domínio, achei %d" % files.size())
	for path in files:
		var base := _base_of(FileAccess.get_file_as_string(path))
		ok(
			ALLOWED_BASES.has(base),
			(
				"%s estende %s. O domínio só pode estender %s: qualquer nó vive na árvore de "
				+ "cena e avança por quadro, e o invariante 2 diz que o domínio avança por "
				+ "step(intent)."
			) % [path.trim_prefix("res://"), base, " ou ".join(ALLOWED_BASES)],
		)


## Cada entrada declarada precisa **acrescentar** cobertura. Um nome que `domain_purity_test.gd`
## já acusa não pertence aqui: duas guardas a dizer a mesma coisa envelhecem em direções
## diferentes, e a que ninguém lê é a que fica errada. Foi esta prova que manteve `Tween` fora
## da lista acima — ele já é proibido lá, com o motivo dele.
func test_this_guard_does_not_repeat_the_domain_purity_guard() -> void:
	var sibling := load(DOMAIN_GUARD)
	ok(sibling != null, "a guarda irmã precisa carregar: %s" % DOMAIN_GUARD)
	if sibling == null:
		return
	var rules: Array = sibling.RULES
	ok(not rules.is_empty(), "RULES vazia na guarda irmã — o confronto não mediria nada")
	for name in ENGINE_PRESENTATION_TYPES:
		var reason: String = ENGINE_PRESENTATION_TYPES[name]
		ok(reason.length() >= 20, "%s declarado sem motivo escrito" % name)
		var probe := "\tvar probe := %s.new()" % name
		for rule in rules:
			var re := RegEx.new()
			if re.compile(rule[0]) != OK:
				continue
			ok(
				re.search(probe) == null,
				(
					"%s já é acusado por domain_purity_test.gd (%s) — tire-o desta lista em vez "
					+ "de guardar o mesmo símbolo duas vezes."
				) % [name, rule[2]],
			)


## As duas guardas de direção têm de concordar sobre o que é apresentação. Se a irmã ganhar uma
## pasta e esta não, a camada nova fica proibida de mutar o domínio mas livre para ser nomeada
## por ele — meia seta guardada, que é pior que nenhuma porque parece cobertura.
func test_the_two_direction_guards_agree_on_what_presentation_is() -> void:
	var sibling := load(PRESENTATION_GUARD)
	ok(sibling != null, "a guarda irmã precisa carregar: %s" % PRESENTATION_GUARD)
	if sibling == null:
		return
	var theirs: Array = sibling.PRESENTATION_DIRS.duplicate()
	var mine: Array = PRESENTATION_DIRS.duplicate()
	theirs.sort()
	mine.sort()
	eq(mine, theirs,
		"PRESENTATION_DIRS divergiu de presentation_purity_test.gd: uma camada ficou meio guardada")
	for dir in PRESENTATION_DIRS:
		ok(DirAccess.dir_exists_absolute(dir), "pasta de apresentação declarada e ausente: %s" % dir)


## Uma varredura que não sabe acusar nada é um teste que passa para sempre sem olhar. Os trechos
## abaixo **têm** de ser acusados; os de baixo, não. A violação plantada que o backlog pedia é a
## primeira: uma dependência de apresentação **que não é o visual**, dentro de `game/session/`.
func test_scanner_catches_planted_violations() -> void:
	var classes := _presentation_class_names()
	eq(
		_names_in("\tvar hud := QixGameHud.new()", classes),
		PackedStringArray(["QixGameHud"]),
		"o scanner deixou passar uma view plantada no domínio",
	)
	eq(
		_names_in("\tfunc _init(feedback: QixFeedbackHub) -> void:", classes),
		PackedStringArray(["QixFeedbackHub"]),
		"o scanner deixou passar um parâmetro de apresentação plantado no domínio",
	)
	var engine := PackedStringArray(ENGINE_PRESENTATION_TYPES.keys())
	eq(
		_names_in("\tvar tint := Color(\"ff00ff\")", engine),
		PackedStringArray(["Color"]),
		"o scanner deixou passar um Color plantado no domínio",
	)
	eq(
		_names_in("\tRenderingServer.force_draw()", engine),
		PackedStringArray(["RenderingServer"]),
		"o scanner deixou passar um servidor da engine plantado no domínio",
	)
	eq(
		_names_in("## a view é QixGameHud e a cor é Color — citadas, não usadas", classes + engine),
		PackedStringArray(),
		"citar o nome em comentário não é usá-lo: o helper de strip não correu",
	)
	eq(
		_names_in("\tvar rotulo := \"QixGameHud\"", classes),
		PackedStringArray(),
		"literal de texto não é uso: o helper de strip não correu",
	)
	eq(
		_names_in("\tvar Colorimetria := 1", engine),
		PackedStringArray(),
		"'Color' colado a outra palavra não é o tipo",
	)
	eq(_base_of("extends Node2D\n"), "Node2D", "o leitor de base não achou a herança plantada")
	ok(
		not ALLOWED_BASES.has(_base_of("class_name X\nextends CanvasItem\n")),
		"o leitor de base aceitou um nó como base de domínio",
	)
	eq(_base_of("extends RefCounted\n"), "RefCounted", "o leitor de base recusou a base legítima")


# ---------------------------------------------------------------------------------------------
# varredura
# ---------------------------------------------------------------------------------------------

## Os `class_name` declarados sob as pastas de apresentação, em ordem. É esta derivação — e não
## uma lista digitada — que faz uma view nova nascer proibida no domínio.
func _presentation_class_names() -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.new()
	if re.compile("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)") != OK:
		return out
	for dir in PRESENTATION_DIRS:
		for path in _gd_files_at(dir):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var hit := re.search(line)
				if hit != null:
					out.append(hit.get_string(1))
	out.sort()
	return out


func _domain_files() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in DOMAIN_DIRS:
		out.append_array(_gd_files_at(dir))
	out.sort()
	return out


## Nomes citados em código real, sem repetições e na ordem em que aparecem em `names`.
## Comentários e literais de texto não contam — quem documenta a regra não a viola.
func _names_in(source: String, names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var stripped := PackedStringArray()
	for line in lines:
		stripped.append(_strip(line))
	for name in names:
		var re := RegEx.new()
		if re.compile("\\b%s\\b" % name) != OK:
			out.append("regex inválida para %s" % name)
			continue
		for line in stripped:
			if re.search(line) != null:
				out.append(name)
				break
	return out


## A base declarada pelo arquivo, ou `""` se ele não estende nada explicitamente.
func _base_of(source: String) -> String:
	var re := RegEx.new()
	if re.compile("^extends\\s+([A-Za-z_][A-Za-z0-9_]*)") != OK:
		return ""
	for line in source.split("\n"):
		var hit := re.search(line)
		if hit != null:
			return hit.get_string(1)
	return ""


## Instância única e preguiçosa: `load()` por linha varrida custaria mais que a varredura toda.
var _stripper: RefCounted = null


func _strip(line: String) -> String:
	if _stripper == null:
		var guard := load(DOMAIN_GUARD)
		if guard == null:
			return line
		_stripper = guard.new()
	return _stripper._strip_comments_and_strings(line)


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
