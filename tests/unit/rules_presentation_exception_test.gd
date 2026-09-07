extends TestCase
## Guarda da fronteira que o invariante 1 deixa implícita: `game/rules/` é varrido como **domínio**,
## mas hospeda um `Resource` que é **só apresentação** — `round_visual_definition.gd`, com seis
## `Color` e uma `Texture2D`.
##
## Hoje esse arquivo passa na guarda de valor real por **ausência de regra**, não por decisão:
## `domain_purity_test.gd` proíbe `float`, literal decimal, `Vector2` e `PackedFloat32Array`, e
## nunca chegou a proibir `Color` — que é quatro floats com outro nome. A exceção **existe**, mas
## mora dentro do comentário das `RULES` de lá ("o caso que ainda não aconteceu…"). Prosa não é
## lista confrontável: no dia em que alguém acrescentar `\bColor\b` às `RULES` — o passo natural,
## porque cor é valor real — a suíte fica vermelha em `game/rules/` e a correção barata parecerá
## ser afrouxar a varredura para a pasta inteira. Era exatamente o que o comentário de lá pede
## para não fazer, e é o que acontece quando a única defesa é um leitor lembrar-se do comentário.
##
## Este teste troca a sorte por uma declaração — e, mais importante, **cobra o preço da exceção**.
## Dizer "isto é apresentação" não basta: `PRESENTATION_ONLY` só é legítima porque o domínio
## comprovadamente nunca vê o visual. As três provas, na ordem em que ficariam vermelhas:
##
## 1. **Ninguém entra na lista de fininho** — um `Color` novo em qualquer outro arquivo de
##    `game/rules/` exige uma entrada com motivo escrito.
## 2. **A lista não envelhece nos dois sentidos** — entrada órfã (arquivo sumiu) e entrada
##    obsoleta (o arquivo já não carrega tipo de apresentação) ficam vermelhas.
## 3. **A isenção é ganha, não pedida** — nenhum arquivo isento tem `canonical_bytes()`, e nenhum
##    arquivo de `game/simulation/` ou `game/session/` sequer **nomeia** o visual. É essa segunda
##    varredura que fecha o invariante 8: o dia em que alguém passar `content.visual` para dentro
##    do tick, a paleta ganha poder sobre o checksum e o replay, e este teste é o custo disso.
##
## O que a varredura **não** prova, dito para ninguém confiar demais: ela lê símbolos, não
## semântica. Um `Variant` que carregue a paleta sem nunca ser anotado atravessa. Isso continua
## sendo trabalho de revisão — e do teste de comportamento no fim deste arquivo, que dirige uma
## sessão de verdade com duas paletas opostas e compara `config_hash` e checksum.

## A pasta que o invariante 1 trata como domínio e que, por decisão de conteúdo, hospeda o visual.
const RULES_DIR := "res://game/rules"

## As duas pastas que **nunca** podem nomear o visual. Se pudessem, a paleta entraria no tick.
const DOMAIN_DIRS: Array[String] = [
	"res://game/simulation",
	"res://game/session",
]

## Reaproveita o removedor de comentários e literais da guarda irmã em vez de copiá-lo: duas cópias
## divergem, e a que diverge em silêncio é a que deixa passar. Se o helper sumir de lá, este teste
## fica vermelho em `test_scanner_catches_planted_violations`, não silenciosamente permissivo.
const DOMAIN_GUARD := "res://tests/unit/domain_purity_test.gd"

## Campo da rota de prova. Pequeno de propósito: quanto menos acontece, mais evidente fica que
## a única variável entre as duas corridas é a paleta.
const FIELD_WIDTH := 13
const FIELD_HEIGHT := 9

## Tipos cuja presença num arquivo é, por si, prova de que ele desenha alguma coisa. `Color` e
## `Texture2D` são os que já estão em uso; os demais são o mesmo erro com outro nome, listados
## agora porque a hora barata de listar é antes de alguém precisar.
const PRESENTATION_TYPES: Array[String] = [
	"Color",
	"Texture2D",
	"Texture",
	"Image",
	"Font",
	"StyleBox",
	"Material",
	"Shader",
	"Gradient",
	"Curve",
	"Node",
	"CanvasItem",
	"Control",
	"RoundVisualDefinition",
]

## Apresentação tolerada dentro de `game/rules/`, cada entrada com o motivo de estar lá. Uma
## exceção sem motivo escrito é uma violação com sorte — a formulação é a da guarda de
## apresentação, e é deliberado que as duas se pareçam.
const PRESENTATION_ONLY: Dictionary = {
	"res://game/rules/round_visual_definition.gd":
	"Resource só de apresentação: paleta e fundo da rodada, lidos por BoardView, PlayerView, EnemyView, HUD e VFX. Não tem canonical_bytes() e nenhum arquivo do domínio o nomeia — ver test_the_domain_never_names_the_visual",
	"res://game/rules/round_content.gd":
	"a costura autoral: junta regras, geometria e seed (que entram no config_hash) ao visual (que não entra). Nomeia o tipo para o guardar num @export; não lê um único campo dele",
}


func test_only_declared_files_in_rules_carry_presentation_types() -> void:
	var files := _gd_files_at(RULES_DIR)
	ok(not files.is_empty(), "nenhum .gd em %s — varredura vazia não é prova" % RULES_DIR)
	for path in files:
		var found := _presentation_types_in(FileAccess.get_file_as_string(path))
		if found.is_empty():
			continue
		ok(
			PRESENTATION_ONLY.has(path),
			(
				"%s carrega tipo de apresentação (%s) dentro de game/rules/, que o invariante 1 "
				+ "varre como domínio. Ou o arquivo sai da pasta, ou entra em PRESENTATION_ONLY "
				+ "com o motivo escrito — nunca afrouxando a varredura da pasta inteira."
			) % [path.trim_prefix("res://"), ", ".join(found)],
		)


func test_every_declared_exemption_is_still_earned() -> void:
	for path in PRESENTATION_ONLY:
		ok(FileAccess.file_exists(path), "entrada órfã: %s não existe mais" % path)
		var reason: String = PRESENTATION_ONLY[path]
		ok(reason.length() >= 40, "%s isento sem motivo escrito" % path)
		ok(
			path.begins_with(RULES_DIR + "/"),
			"%s não está em %s; a isenção não tem o que isentar" % [path, RULES_DIR],
		)
		ok(
			not _presentation_types_in(FileAccess.get_file_as_string(path)).is_empty(),
			(
				"%s já não carrega tipo de apresentação: a isenção ficou obsoleta e deve sair "
				+ "da lista, senão ela passa a cobrir uma violação futura sem ninguém decidir."
			) % path.trim_prefix("res://"),
		)


## O preço da isenção, primeira metade: quem é apresentação não entra no hash de configuração.
## `ReplayLog.config_hash` alimenta-se de `canonical_bytes()` — de `GameRules` e de
## `RoundDefinition`, e de mais nada. Um `canonical_bytes()` num arquivo isento seria a paleta a
## reclamar compatibilidade de replay para si (invariante 7).
func test_no_exempt_file_participates_in_the_config_hash() -> void:
	var with_canonical := PackedStringArray()
	for path in _gd_files_at(RULES_DIR):
		if FileAccess.get_file_as_string(path).contains("func canonical_bytes("):
			with_canonical.append(path)
	for path in PRESENTATION_ONLY:
		ok(
			not with_canonical.has(path),
			(
				"%s é isento por ser apresentação e mesmo assim declara canonical_bytes(): "
				+ "ou entra no hash e deixa de ser apresentação, ou perde o método."
			) % path.trim_prefix("res://"),
		)
	eq(
		with_canonical.size(), 2,
		(
			"o config_hash é regras ⊕ geometria e mais nada; achei %d arquivos com "
			+ "canonical_bytes() em game/rules/ (%s). Um terceiro muda o contrato de replay."
		) % [with_canonical.size(), ", ".join(with_canonical)],
	)


## O preço da isenção, segunda metade — e a prova que sustenta as outras. O visual é apresentação
## porque o domínio **não o alcança**: nem `game/simulation/` nem `game/session/` nomeiam o tipo
## ou leem `.visual`. `GameSession._start_current_round` passa `content.rules`,
## `content.round_definition` e `content.seed_value` ao `GameSimulation` — a paleta fica de fora
## do construtor, e é essa omissão que este teste transforma em regra.
func test_the_domain_never_names_the_visual() -> void:
	var scanned := 0
	var forbidden := RegEx.new()
	ok(
		forbidden.compile("\\bRoundVisualDefinition\\b|\\.visual\\b") == OK,
		"regex inválida no próprio teste",
	)
	for dir in DOMAIN_DIRS:
		var files := _gd_files_at(dir)
		ok(not files.is_empty(), "nenhum .gd em %s — varredura vazia não é prova" % dir)
		for path in files:
			scanned += 1
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for index in lines.size():
				ok(
					forbidden.search(_strip(lines[index])) == null,
					(
						"%s:%d nomeia o visual da rodada. A paleta é apresentação: se ela entra "
						+ "no tick, uma mudança estética passa a mover checksum e a invalidar "
						+ "replay (invariantes 6 e 8)."
					) % [path.trim_prefix("res://"), index + 1],
				)
	ok(scanned >= 9, "esperava pelo menos 9 arquivos de domínio, varri %d" % scanned)


## Uma varredura que não sabe acusar nada é um teste que passa para sempre sem olhar. Os dois
## trechos abaixo **têm** de ser acusados; se deixarem de ser, o helper emprestado mudou de
## comportamento e as varreduras acima estão cegas.
func test_scanner_catches_planted_violations() -> void:
	eq(
		_presentation_types_in("@export var glow: Color = Color(\"ffffff\")"),
		PackedStringArray(["Color"]),
		"o scanner deixou passar um Color plantado em game/rules/",
	)
	eq(
		_presentation_types_in("## a paleta usa Color e Texture2D  # e um Node"),
		PackedStringArray(),
		"comentário citando os tipos proibidos não é uso: o helper de strip não correu",
	)
	eq(
		_presentation_types_in("var rotulo := \"Color\""),
		PackedStringArray(),
		"literal de texto não é uso: o helper de strip não correu",
	)
	eq(
		_presentation_types_in("var Colorimetry := 1"),
		PackedStringArray(),
		"'Color' colado a outra palavra não é o tipo",
	)


## A prova de comportamento, pela via real: duas paletas opostas na mesma rodada, dirigidas pela
## `GameSession` como o `bootstrap` a dirige. Se um dia o visual atravessar para o tick, é aqui
## que se vê — e vê-se como o jogador veria, em checksum divergente, não em símbolo proibido.
func test_authoring_every_visual_field_moves_neither_config_hash_nor_checksum() -> void:
	var pale := _session_with_visual(_visual_pale())
	var loud := _session_with_visual(_visual_loud())

	eq(
		ReplayLog.config_hash(pale.current_content().rules, pale.current_content().round_definition),
		ReplayLog.config_hash(loud.current_content().rules, loud.current_content().round_definition),
		"autorar a paleta mudou o config_hash: a apresentação vazou para o contrato de replay",
	)

	_drive(pale)
	_drive(loud)

	eq(
		loud.simulation.state_checksum(), pale.simulation.state_checksum(),
		"autorar a paleta mudou o checksum do domínio — invariante 8 quebrado",
	)
	eq(loud.simulation.tick, pale.simulation.tick, "a paleta mudou a contagem de ticks")
	eq(loud.simulation.permille, pale.simulation.permille, "a paleta mudou o território tomado")
	eq(loud.simulation.score, pale.simulation.score, "a paleta mudou a pontuação")
	ok(
		pale.simulation.permille > 0,
		"a rota precisa mesmo capturar território, senão a comparação não mede nada",
	)


# ---------------------------------------------------------------------------------------------
# rota
# ---------------------------------------------------------------------------------------------

## Campo pequeno e chefe imóvel: qualquer divergência de checksum só pode ter vindo da paleta.
func _session_with_visual(visual: RoundVisualDefinition) -> GameSession:
	var rules := GameRules.new()
	rules.boss_substeps = 0
	rules.boss_speed_fp = 0
	rules.boss_turn_every_ticks = 0
	rules.target_permille = 1000

	var round_definition := RoundDefinition.new()
	round_definition.field_width = FIELD_WIDTH
	round_definition.field_height = FIELD_HEIGHT
	round_definition.player_spawn = Vector2i(4, 0)
	round_definition.boss_start = Vector2i(11, 4)
	round_definition.boss_dir_index = 0

	var content := RoundContent.new()
	content.round_id = &"exception_probe"
	content.rules = rules
	content.round_definition = round_definition
	content.seed_value = 23
	content.visual = visual

	var campaign := CampaignDefinition.new()
	campaign.campaign_id = &"exception_probe"
	var rounds: Array[RoundContent] = [content]
	campaign.rounds = rounds
	campaign.intro_ticks = 0
	campaign.clear_ticks = 0
	return GameSession.new(campaign)


## A paleta padrão do `Resource`, com o fundo mínimo que a validação de conteúdo exige.
func _visual_pale() -> RoundVisualDefinition:
	var visual := RoundVisualDefinition.new()
	visual.background = _background(Color.BLACK)
	return visual


## **Todos** os campos autoráveis trocados — as seis cores, os dois textuais e o fundo. Se algum
## deles alimentasse o domínio por um caminho que a varredura de símbolos não vê, a divergência
## apareceria no checksum comparado acima.
func _visual_loud() -> RoundVisualDefinition:
	var visual := RoundVisualDefinition.new()
	visual.display_name = "SETOR BERRANTE"
	visual.subtitle = "cada campo trocado de propósito"
	visual.free_color = Color("2b0030")
	visual.boundary_color = Color("ff9a00")
	visual.trail_color = Color("00ffd0")
	visual.trail_hot_color = Color("ffffff")
	visual.threat_color = Color("7a00ff")
	visual.accent_color = Color("103040")
	visual.background = _background(Color.WHITE)
	return visual


## `RoundVisualDefinition.validation_errors` exige um fundo com exatamente as dimensões do campo,
## e `GameSession._init` valida a campanha antes de tocar no domínio — logo o fundo faz parte da
## rota real, não é adereço de teste.
func _background(fill: Color) -> Texture2D:
	var image := Image.create_empty(FIELD_WIDTH, FIELD_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	return ImageTexture.create_from_image(image)


## Desce desenhando e volta pela moldura: fecha um corte, logo mexe em `permille` e no checksum.
func _drive(session: GameSession) -> void:
	_steps(session, MoveIntent.Dir.DOWN, true, 4)
	_steps(session, MoveIntent.Dir.RIGHT, false, 2)
	_steps(session, MoveIntent.Dir.UP, true, 4)


func _steps(session: GameSession, direction: int, drawing: bool, ticks: int) -> void:
	for _tick in ticks:
		session.step(MoveIntent.make(direction, drawing))


# ---------------------------------------------------------------------------------------------
# varredura
# ---------------------------------------------------------------------------------------------

## Nomes de `PRESENTATION_TYPES` citados em código real do arquivo, sem repetições e na ordem da
## constante. Comentários e literais de texto não contam — quem documenta a regra não a viola.
func _presentation_types_in(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	for type_name in PRESENTATION_TYPES:
		var re := RegEx.new()
		if re.compile("\\b%s\\b" % type_name) != OK:
			out.append("regex inválida para %s" % type_name)
			continue
		for line in lines:
			if re.search(_strip(line)) != null:
				out.append(type_name)
				break
	return out


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
