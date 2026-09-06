extends TestCase
## Guarda mecânica do invariante 10 do `CLAUDE.md`: **nenhum byte extraído de ROM entra no jogo**.
##
## Dos dez invariantes, este é o único cuja quebra não aparece num checksum, num teste de
## comportamento nem numa revisão de diff distraída: um PNG a mais numa pasta é um arquivo
## binário que ninguém abre. É também o único cujo custo não é técnico — arte de terceiros
## dentro do jogo é um problema de licença, e ele só se descobre quando já está distribuído.
##
## `assets/ASSET-PROVENANCE.md` existe justamente para responder "de onde veio isto?" por
## arquivo. Até aqui esse manifesto era uma promessa em prosa: nada obrigava um asset novo a
## entrar nele, e nada percebia se um asset já declarado fosse trocado por outros bytes com o
## mesmo nome. Este teste transforma o manifesto em contrato verificado.
##
## ## O que a varredura prova
##
## 1. **Todo arquivo de mídia de primeira mão está declarado** — nas pastas do jogo (`assets`,
##    `game`, `ui`, `app`, `content`, `tools`, `tests`) e também em `reference`, onde
##    `reference/volfied/README.md` §"Não contém dados de ROM" promete por escrito que nenhum
##    byte de imagem, sprite, paleta binária ou sample entrou. Declarado significa: o SHA-256
##    real do arquivo **e** o seu nome aparecem no manifesto.
## 2. **Nada declarado mudou de bytes.** Como o critério é o hash, trocar a imagem mantendo o
##    nome deixa o teste vermelho no mesmo commit — que é quando a troca ainda tem autor.
## 3. **O manifesto não guarda entrada morta.** Todo SHA-256 nele ou pertence a um arquivo
##    presente, ou está numa linha marcada `(removido)` — a tabela de tentativa rejeitada.
##    Sem isso, um hash obsoleto continuaria "provando" um arquivo que já não existe.
## 4. **Arquivo dado como removido continua removido.** Os caminhos marcados `(removido)` não
##    podem reaparecer em `res://` sem uma decisão explícita que reescreva o manifesto.
##
## ## O que ela NÃO prova — dito aqui para ninguém confiar demais
##
## - **Que a origem declarada é verdadeira.** Nenhuma varredura distingue arte gerada de arte
##   extraída; o manifesto continua sendo uma afirmação humana. O que o teste garante é que a
##   afirmação existe, é específica por arquivo e envelhece junto com os bytes.
## - `addons/` e `antipixel_state_machine/` ficam **fora** do escopo: são raízes de terceiros,
##   governadas por `addons/README.md` e pela decisão de poda, não por este manifesto. Incluí-las
##   aqui misturaria "de onde veio a nossa arte" com "que dependência mantemos".
## - Extensões fora de `MEDIA_EXTENSIONS` (um `.res` binário, por exemplo) passam despercebidas.

## Onde arte de primeira mão pode legitimamente morar, mais `reference` — a pasta cuja promessa
## de ausência de bytes de ROM é a mais fácil de quebrar sem querer.
const SCANNED_DIRS: Array[String] = [
	"res://assets",
	"res://game",
	"res://ui",
	"res://app",
	"res://content",
	"res://tools",
	"res://tests",
	"res://reference",
]

const MEDIA_EXTENSIONS: Array[String] = [
	"png", "jpg", "jpeg", "webp", "bmp", "svg", "tga",
	"wav", "ogg", "mp3", "ttf", "otf",
]

const MANIFEST := "res://assets/ASSET-PROVENANCE.md"

## Um SHA-256 em hexadecimal minúsculo, como o manifesto os escreve.
const HASH_PATTERN := "\\b[0-9a-f]{64}\\b"

## A marca que a tabela de tentativa rejeitada usa: `` `caminho` (removido) ``.
const REMOVED_PATTERN := "`([^`]+)`\\s*\\(removido\\)"

## Bytes que o manifesto não declara, usados para provar que a checagem discrimina. O conteúdo é
## fixo de propósito: uma amostra aleatória tornaria o próprio teste não determinístico.
const UNDECLARED_SAMPLE := "estes bytes nunca foram declarados no manifesto de proveniência"


func test_every_media_file_is_declared_in_the_manifest() -> void:
	var manifest := _manifest_text()
	var files := _media_files()
	ok(
		files.size() >= 7,
		"esperava pelo menos os 7 arquivos de mídia do jogo, encontrei %d — varredura vazia não é prova"
		% files.size(),
	)
	for path in files:
		var digest := FileAccess.get_sha256(path)
		var file_name := path.get_file()
		ok(digest != "", "não foi possível calcular o SHA-256 de %s" % path)
		ok(
			manifest.contains(digest),
			(
				"%s não está declarado em ASSET-PROVENANCE.md pelo hash %s. "
				+ "Ou o arquivo é novo e falta a linha de proveniência, ou os bytes mudaram "
				+ "e o manifesto ficou para trás (invariante 10)."
			) % [path.trim_prefix("res://"), digest],
		)
		ok(
			manifest.contains(file_name),
			"o hash de %s está no manifesto, mas o nome do arquivo não aparece em lado nenhum"
			% path.trim_prefix("res://"),
		)


func test_manifest_has_no_orphan_hashes() -> void:
	var lines := _manifest_text().split("\n")
	var present := {}
	for path in _media_files():
		present[FileAccess.get_sha256(path)] = path
	var re := RegEx.create_from_string(HASH_PATTERN)
	var seen := 0
	for line in lines:
		var is_removed := line.contains("(removido)")
		for m in re.search_all(line):
			var digest := m.get_string()
			seen += 1
			ok(
				present.has(digest) or is_removed,
				(
					"o manifesto declara o hash %s, mas nenhum arquivo presente tem esses bytes "
					+ "e a linha não está marcada `(removido)`. Entrada órfã diz que algo está "
					+ "documentado quando já não está."
				) % digest,
			)
	ok(seen >= 7, "esperava ao menos 7 hashes no manifesto, li %d" % seen)


func test_files_declared_as_removed_are_still_absent() -> void:
	var re := RegEx.create_from_string(REMOVED_PATTERN)
	# O padrão é exercitado numa linha sintética antes de correr sobre o manifesto: se ele deixasse
	# de casar (uma reformatação da tabela, por exemplo), a varredura viraria um laço vazio que
	# passa sem olhar nada, e ninguém perceberia.
	var probe := re.search("| `backgrounds/exemplo.png` (removido) | 1 × 1 |")
	ok(probe != null, "o padrão de `(removido)` deixou de casar a forma da tabela do manifesto")
	if probe != null:
		eq(probe.get_string(1), "backgrounds/exemplo.png", "o padrão capturou o caminho errado")
	for m in re.search_all(_manifest_text()):
		var path := "res://assets/" + m.get_string(1)
		ok(
			not FileAccess.file_exists(path),
			(
				"%s está marcado `(removido)` no manifesto e voltou a existir. "
				+ "Reintroduzir um asset reprovado exige reescrever a decisão, não recriar o arquivo."
			) % path.trim_prefix("res://"),
		)


## Uma guarda que não pode ficar vermelha é uma guarda decorativa. Aqui a checagem é exercitada
## contra bytes que sabidamente não estão declarados: se ela deixasse isto passar, também deixaria
## passar um asset de origem desconhecida.
func test_declaration_check_rejects_undeclared_bytes() -> void:
	var manifest := _manifest_text()
	var undeclared := UNDECLARED_SAMPLE.sha256_text()
	eq(undeclared.length(), 64, "sha256_text devia devolver 64 dígitos hexadecimais")
	ok(
		not manifest.contains(undeclared),
		"o manifesto contém o hash da amostra de controle; a checagem não discrimina nada",
	)
	ok(
		not manifest.contains("asset_que_nunca_existiu.png"),
		"o manifesto contém um nome de arquivo inventado; a checagem por nome não discrimina nada",
	)


func test_manifest_exists_and_names_the_invariant() -> void:
	var manifest := _manifest_text()
	ok(manifest != "", "ASSET-PROVENANCE.md não pôde ser lido — o invariante 10 perdeu o registro")
	ok(
		manifest.to_lower().contains("rom"),
		"o manifesto deixou de dizer explicitamente que nenhuma arte de ROM foi incorporada",
	)


func _manifest_text() -> String:
	return FileAccess.get_file_as_string(MANIFEST)


func _media_files() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in SCANNED_DIRS:
		out.append_array(_media_files_at(dir))
	out.sort()
	return out


func _media_files_at(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if MEDIA_EXTENSIONS.has(f.get_extension().to_lower()):
			out.append(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_media_files_at(dir + "/" + sub))
	return out
