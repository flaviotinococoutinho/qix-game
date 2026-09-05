extends TestCase
## Guarda mecânica dos invariantes 1 e 4 do `CLAUDE.md`.
##
## Invariante 1: nada em `game/simulation/`, `game/rules/` ou `game/session/` lê relógio, `Input`,
## `Tween`, física ou `delta` de quadro. Invariante 4: `DeterministicRng` é o único acaso.
##
## Um invariante que só existe em prosa é uma intenção, não uma regra: ele não resiste ao dia em
## que alguém precisar de "só um `Time.get_ticks_msec()` para depurar". Este teste é o custo de
## quebrá-lo — a violação para o `run_tests.gd` no mesmo commit em que nasce, antes de contaminar
## checksum e replay, que é onde ela ficaria cara.
##
## O escopo é o que a varredura estática **prova**: um símbolo do mundo real citado em código do
## domínio. Ela não prova ausência de acoplamento indireto (uma chamada a um objeto de apresentação
## passado por parâmetro, por exemplo) — isso continua sendo trabalho de revisão.

const DOMAIN_DIRS: Array[String] = [
	"res://game/simulation",
	"res://game/rules",
	"res://game/session",
]

## Cada regra é `[regex, invariante, por que é proibida]`. As regexes correm sobre a linha já
## limpa de comentários e literais de texto — ver `_strip_comments_and_strings`.
const RULES: Array = [
	# Invariante 4 — o acaso tem um dono só.
	["\\brandi\\s*\\(", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\brandf\\s*\\(", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\brandi_range\\s*\\(", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\brandf_range\\s*\\(", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\brandfn\\s*\\(", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\brandomize\\s*\\(", 4, "semear do relógio destrói a reprodutibilidade"],
	["\\brand_from_seed\\s*\\(", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\bRandomNumberGenerator\\b", 4, "acaso fora do DeterministicRng quebra replay"],
	["\\.shuffle\\s*\\(", 4, "shuffle usa o RNG global, não o determinístico"],
	["\\.pick_random\\s*\\(", 4, "pick_random usa o RNG global, não o determinístico"],
	# Invariante 1 — relógio.
	["\\bTime\\.", 1, "o domínio conta ticks, não mede tempo de parede"],
	["\\bOS\\.", 1, "estado do sistema operacional não entra na simulação"],
	["\\bEngine\\.", 1, "contagem de quadros da engine não é a contagem de ticks"],
	["\\bget_process_delta_time\\b", 1, "delta de quadro não existe no domínio"],
	["\\bget_physics_process_delta_time\\b", 1, "delta de quadro não existe no domínio"],
	# Invariante 1 — entrada. O domínio recebe `MoveIntent`, nunca consulta o dispositivo.
	["\\bInput\\.", 1, "o domínio recebe MoveIntent, não consulta o dispositivo"],
	["\\bInputEvent", 1, "o domínio recebe MoveIntent, não consulta o dispositivo"],
	["\\bInputMap\\b", 1, "o domínio recebe MoveIntent, não consulta o dispositivo"],
	# Invariante 1 — quadro, animação e física.
	["func\\s+_process\\s*\\(", 1, "o domínio avança por step(intent), não por quadro"],
	["func\\s+_physics_process\\s*\\(", 1, "o domínio avança por step(intent), não por quadro"],
	["\\bTween\\b", 1, "interpolação é apresentação"],
	["\\bcreate_tween\\s*\\(", 1, "interpolação é apresentação"],
	["\\bget_tree\\s*\\(", 1, "a árvore de cena é apresentação"],
	["\\bSceneTree\\b", 1, "a árvore de cena é apresentação"],
	["\\bmove_and_slide\\b", 1, "colisão é da engine; o domínio resolve em células"],
	["\\bmove_and_collide\\b", 1, "colisão é da engine; o domínio resolve em células"],
	["\\bPhysicsServer2D\\b", 1, "colisão é da engine; o domínio resolve em células"],
	["\\bawait\\b", 1, "espera assíncrona torna a ordem do tick indeterminada"],
	# Invariante 1, segunda metade — só inteiros e ponto fixo 8.8.
	["\\bfloat\\b", 1, "o domínio só fala em inteiros e ponto fixo 8.8; float é apresentação"],
	["\\bclampf\\s*\\(", 1, "aritmética de float é apresentação"],
	["\\blerpf\\s*\\(", 1, "aritmética de float é apresentação"],
	["\\bVector2\\s*\\(", 1, "Vector2 é float; o domínio usa Vector2i"],
	["\\bsnappedf\\s*\\(", 1, "aritmética de float é apresentação"],
]

## Trechos que a varredura **tem** de acusar. Sem eles, um erro no scanner viraria um teste que
## passa para sempre sem olhar nada — o pior resultado possível para uma guarda.
const POSITIVE_SAMPLES: Array[String] = [
	"var dir := randi() % 4",
	"var rng := RandomNumberGenerator.new()",
	"var agora := Time.get_ticks_msec()",
	"if Input.is_action_pressed(\"ui_left\"):",
	"func _process(frame_delta: float) -> void:",
	"create_tween().tween_property(self, \"position\", alvo, 0.2)",
	"directions.shuffle()",
	"await get_tree().process_frame",
	"func transition_progress() -> float:",
	"\treturn clampf(1.0 - float(a) / float(b), 0.0, 1.0)",
	"\tvar target := Vector2(px, py)",
]

## Trechos legítimos que a varredura **não** pode acusar: `delta` inteiro de pontuação, os nomes
## proibidos citados em comentário e os mesmos nomes dentro de um literal de texto.
const NEGATIVE_SAMPLES: Array[String] = [
	"func _add_score(delta: int, events: Array[GameEvent]) -> void:",
	"\tscore += delta",
	"## Inteiros e ponto fixo 8.8 apenas. Nada aqui lê relógio, Input, Tween ou física.",
	"\tevents.append(GameEvent.make(GameEvent.Kind.SCORE_CHANGED, {\"score\": score, \"delta\": delta}))",
	"\tvar msg := \"não use Input.is_action_pressed aqui\"  # Tween também não",
	"\treturn next_u32() % n",
	"\tvar rand_slot := 3  # 'rand' sem parêntese não é chamada",
	"\tvar cell := Vector2i(x_fp >> 8, y_fp >> 8)",
	"\t@export var speed_fp: int = 96  ## ponto fixo 8.8, nunca float",
]


func test_domain_has_no_real_world_symbols() -> void:
	var scanned := 0
	for dir in DOMAIN_DIRS:
		var files := _gd_files_at(dir)
		ok(not files.is_empty(), "nenhum .gd encontrado em %s — varredura vazia não é prova" % dir)
		for path in files:
			var text := FileAccess.get_file_as_string(path)
			ok(text != "", "não foi possível ler %s" % path)
			ok(
				not text.contains("\"\"\""),
				"%s usa string de três aspas; o scanner não modela esse caso" % path,
			)
			scanned += 1
			for violation in _violations(text):
				fail("%s%s" % [path.trim_prefix("res://"), violation])
	ok(scanned >= 9, "esperava pelo menos 9 arquivos de domínio, varri %d" % scanned)


func test_scanner_catches_planted_violations() -> void:
	for sample in POSITIVE_SAMPLES:
		ok(
			not _violations(sample).is_empty(),
			"o scanner deixou passar uma violação plantada: %s" % sample,
		)


func test_scanner_ignores_legitimate_code() -> void:
	for sample in NEGATIVE_SAMPLES:
		var found := _violations(sample)
		ok(found.is_empty(), "falso positivo em código legítimo: %s →%s" % [sample, "".join(found)])


func test_deterministic_rng_is_the_only_source_of_chance() -> void:
	var text := FileAccess.get_file_as_string("res://game/simulation/replay/deterministic_rng.gd")
	ok(text != "", "não foi possível ler deterministic_rng.gd")
	ok(
		_violations(text).is_empty(),
		"o próprio DeterministicRng não pode depender do mundo real",
	)
	ok(
		text.contains("func next_u32"),
		"DeterministicRng perdeu next_u32; a guarda de acaso está apontando para o arquivo errado",
	)


## Devolve uma descrição por violação, no formato `:linha: regex — porquê (invariante N)`.
func _violations(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	for rule in RULES:
		var re := RegEx.new()
		var err := re.compile(rule[0])
		if err != OK:
			out.append(": regex inválida no próprio teste: %s" % rule[0])
			continue
		for i in lines.size():
			var code := _strip_comments_and_strings(lines[i])
			if re.search(code) != null:
				out.append(
					"\n      :%d: %s — %s (invariante %d)" % [i + 1, rule[0], rule[2], rule[1]]
				)
	return out


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
