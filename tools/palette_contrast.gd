extends RefCounted
## Mede a separação entre os estados do campo **como o shader os desenha**, sob visão
## tricromática e sob simulação de protanopia, deuteranopia e tritanopia.
##
## Por que existe: a barra de qualidade em `docs/ART_DIRECTION.md` exige que estado não dependa
## só de cor. Isso só é verdade quando a **luminância** separa os estados sozinha — e isso é um
## número, não uma impressão. Aqui o número é calculado; `tools/verify_palette_contrast.gd`
## imprime a tabela e `tests/unit/palette_contrast_test.gd` recusa uma paleta que piore o que já
## foi medido.
##
## Só apresentação. Nada aqui é lido por `game/simulation`, `game/rules` ou `game/session`, e
## nenhuma medição pode alterar checksum de replay.

## WCAG 2.1 SC 1.4.11 (Non-text Contrast) pede 3:1 entre um componente de interface e o que está
## ao lado dele. Como uma célula do campo ocupa ~1 px em 240×320, 3:1 é piso, não meta.
const TARGET_RATIO := 3.0

## Modulações aplicadas por `game/board/board_reveal.gdshader`. FREE recebe scanline (0.92/1.0),
## BOUNDARY recebe glint (0.86/1.0) e TRAIL oscila entre `trail_color` e `trail_hot_color`.
## Medimos os extremos porque a leitura pior é a que decide se o estado é legível.
##
## O produto é feito sobre componentes sRGB: em GL Compatibility (ADR-0002) o canvas 2D trabalha
## em sRGB, então `source_color` não vira linear antes da multiplicação.
const FREE_SCAN := [0.92, 1.0]
const BOUNDARY_GLINT := [0.86, 1.0]

enum Vision { TRICHROMAT, PROTANOPIA, DEUTERANOPIA, TRITANOPIA }

const VISION_ORDER := [Vision.TRICHROMAT, Vision.PROTANOPIA, Vision.DEUTERANOPIA, Vision.TRITANOPIA]

const VISION_LABELS := {
	Vision.TRICHROMAT: "tricromata",
	Vision.PROTANOPIA: "protanopia",
	Vision.DEUTERANOPIA: "deuteranopia",
	Vision.TRITANOPIA: "tritanopia",
}

## Machado, Oliveira & Fernandes (2009), severidade 1.0, aplicadas em RGB **linear**.
const VISION_MATRICES := {
	Vision.TRICHROMAT: [
		[1.0, 0.0, 0.0],
		[0.0, 1.0, 0.0],
		[0.0, 0.0, 1.0],
	],
	Vision.PROTANOPIA: [
		[0.152286, 1.052583, -0.204868],
		[0.114503, 0.786281, 0.099216],
		[-0.003882, -0.048116, 1.051998],
	],
	Vision.DEUTERANOPIA: [
		[0.367322, 0.860646, -0.227968],
		[0.280085, 0.672501, 0.047413],
		[-0.011820, 0.042940, 0.968881],
	],
	Vision.TRITANOPIA: [
		[1.255528, -0.076749, -0.178779],
		[-0.078411, 0.930809, 0.147602],
		[0.004733, 0.691367, 0.303900],
	],
}

## Cada par é uma decisão real do jogador, não uma combinação exaustiva:
## onde está a borda segura, estou desenhando ou protegido, e onde está a ameaça sobre cada chão.
const PAIRS := [
	["FREE", "BOUNDARY"],
	["FREE", "TRAIL"],
	["BOUNDARY", "TRAIL"],
	["FREE", "THREAT"],
	["BOUNDARY", "THREAT"],
	["TRAIL", "THREAT"],
]

## As quatro camadas opacas de `QixPlayerView._draw`, de fora para dentro: o contorno de tinta e a
## silhueta 5×5 que ele envolve (ADR-0012). O halo de
## `accent_color` fica de fora de propósito: é desenhado com alfa sobre o chão, então a cor que
## chega ao olho depende do que está atrás — não é um valor que esta medição possa afirmar.
## `tests/unit/cursor_contrast_test.gd` amarra este mapa ao `presentation_colors()` real da view,
## para que renomear a cor de uma camada não deixe a medição medindo outra coisa.
const CURSOR_LAYERS := [
	["CURSOR_INK", "free_color"],
	["CURSOR_OUTER", "boundary_color"],
	["CURSOR_ACCENT", "accent_color"],
	["CURSOR_CORE", "trail_hot_color"],
]

## "Onde eu estou" é uma leitura tão contínua quanto "onde está a borda", e o jogador passa a
## partida inteira sobre um destes dois chãos: `BOUNDARY` enquanto anda protegido, `FREE` enquanto
## desenha. Cada camada é medida contra os dois porque a silhueta só é legível pela camada que
## sobreviver ao chão do momento.
## `CURSOR_INK` aparece só contra `BOUNDARY`, e a ausência é deliberada: sobre `FREE` a tinta **é**
## o chão, mede ~1:1 por construção e some — é isso que se quer, porque ali as camadas opacas já
## passam com folga. Medi-la contra `FREE` como par de legibilidade afirmaria uma leitura que o
## desenho não pretende. Mesma escolha de `enemy_silhouette_contrast_test.gd` para o anel da
## ameaça. Ver `docs/decisions/ADR-0012-cursor-ink-outline.md`.
const CURSOR_PAIRS := [
	["CURSOR_INK", "BOUNDARY"],
	["CURSOR_OUTER", "FREE"],
	["CURSOR_OUTER", "BOUNDARY"],
	["CURSOR_ACCENT", "FREE"],
	["CURSOR_ACCENT", "BOUNDARY"],
	["CURSOR_CORE", "FREE"],
	["CURSOR_CORE", "BOUNDARY"],
]

## Piso de regressão: pior razão observada em 2026-09-04 sobre a paleta padrão e as três rodadas
## autoradas, arredondada para baixo. Não é aprovação — vários pares estão abaixo de
## `TARGET_RATIO` e isso está registrado em `docs/ART_DIRECTION.md`. É uma catraca: uma paleta
## nova não pode piorar o que já foi medido sem que alguém decida piorar.
const PAIR_FLOOR := {
	"FREE×BOUNDARY": 8.90,
	"FREE×TRAIL": 11.20,
	"BOUNDARY×TRAIL": 1.03,
	"FREE×THREAT": 3.70,
	"BOUNDARY×THREAT": 1.27,
	"TRAIL×THREAT": 1.82,
}

## Pares que hoje ficam abaixo de `TARGET_RATIO` em todas as paletas. Existe para que consertar um
## deles **falhe** o teste: a dívida sai da lista junto com o piso e o texto de `ART_DIRECTION`,
## no mesmo commit, em vez de a documentação envelhecer sozinha.
const KNOWN_DEBT := ["BOUNDARY×TRAIL", "BOUNDARY×THREAT", "TRAIL×THREAT"]

## Mesma catraca de `PAIR_FLOOR`, para a silhueta do cursor: pior razão observada em 2026-09-05
## sobre a paleta padrão e as três rodadas autoradas, arredondada para baixo. Os três pares sobre
## `BOUNDARY` estão registrados como dívida, não como aprovação — ver `docs/ART_DIRECTION.md`.
const CURSOR_FLOOR := {
	"CURSOR_INK×BOUNDARY": 8.92,
	"CURSOR_OUTER×FREE": 12.10,
	"CURSOR_OUTER×BOUNDARY": 1.00,
	"CURSOR_ACCENT×FREE": 5.30,
	"CURSOR_ACCENT×BOUNDARY": 1.11,
	"CURSOR_CORE×FREE": 15.30,
	"CURSOR_CORE×BOUNDARY": 1.03,
}

## Mesma função de `KNOWN_DEBT`, para o cursor. Que a lista tenha **as três** camadas é o achado:
## sobre `BOUNDARY` nenhuma cor autorada da silhueta separa por luminância, em nenhuma paleta.
##
## A lista **continua** completa depois da ADR-0012, e isso é correto — os pares cromáticos não
## melhoraram. O que mudou é que a leitura deixou de depender deles: `CURSOR_INK×BOUNDARY`, acima,
## carrega-a a 8,93:1. Fechar a dívida cromática segue em aberto, agora sem urgência. Mesma
## consequência que a ADR-0011 registrou para `BOUNDARY`×`THREAT` e `TRAIL`×`THREAT`.
const CURSOR_KNOWN_DEBT := [
	"CURSOR_OUTER×BOUNDARY",
	"CURSOR_ACCENT×BOUNDARY",
	"CURSOR_CORE×BOUNDARY",
]

## Folga numérica da catraca. Absorve ruído de ponto flutuante, não mudança de paleta.
const FLOOR_TOLERANCE := 0.01


## Luminância relativa da WCAG 2.1, com a transferência sRGB padrão (limiar 0.04045; a norma
## imprime 0.03928, diferença irrelevante para três casas).
static func relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linearize(color.r)
		+ 0.7152 * _linearize(color.g)
		+ 0.0722 * _linearize(color.b)
	)


## Razão de contraste da WCAG 2.1: 1.0 é indistinguível por luminância, 21.0 é preto sobre branco.
static func contrast_ratio(first: Color, second: Color) -> float:
	var a := relative_luminance(first)
	var b := relative_luminance(second)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## Projeta a cor no gamute visível por uma dicromacia. `Vision.TRICHROMAT` devolve a cor original.
static func simulate(color: Color, vision: int) -> Color:
	var matrix: Array = VISION_MATRICES[vision]
	var r := _linearize(color.r)
	var g := _linearize(color.g)
	var b := _linearize(color.b)
	return Color(
		_delinearize(matrix[0][0] * r + matrix[0][1] * g + matrix[0][2] * b),
		_delinearize(matrix[1][0] * r + matrix[1][1] * g + matrix[1][2] * b),
		_delinearize(matrix[2][0] * r + matrix[2][1] * g + matrix[2][2] * b),
		color.a,
	)


## Cores efetivamente desenhadas por estado, já com as modulações do shader.
## `visual` nunca é nulo: `RoundVisualDefinition.new()` já carrega a paleta padrão.
static func rendered_swatches(visual: RoundVisualDefinition) -> Dictionary:
	return {
		"FREE": _modulated(visual.free_color, FREE_SCAN),
		"BOUNDARY": _modulated(visual.boundary_color, BOUNDARY_GLINT),
		"TRAIL": [visual.trail_color, visual.trail_hot_color],
		"THREAT": [visual.threat_color],
	}


## Cores opacas de cada camada da silhueta do cursor, na ordem de empilhamento de `_draw`.
## Cada camada é uma lista de um elemento só: ao contrário do chão, a view não modula o cursor.
static func cursor_swatches(visual: RoundVisualDefinition) -> Dictionary:
	var result := {}
	for layer in CURSOR_LAYERS:
		var authored: Color = visual.get(layer[1])
		var single: Array[Color] = [authored]
		result[layer[0]] = single
	return result


## Mede todos os pares de `PAIRS` para uma paleta. Devolve o pior caso por par (extremos do shader
## × quatro modelos de visão), a retenção de diferença cromática e quem está abaixo da meta.
static func measure(visual: RoundVisualDefinition) -> Dictionary:
	return _measure(rendered_swatches(visual), PAIRS, PAIR_FLOOR)


## Mede a silhueta do cursor contra os dois chãos em que ele anda. Mesma métrica, mesma catraca:
## o que muda é o conjunto de pares e o piso, porque "onde eu estou" e "onde está a borda" são
## perguntas diferentes e podem regredir independentemente.
static func measure_cursor(visual: RoundVisualDefinition) -> Dictionary:
	var swatches := rendered_swatches(visual)
	swatches.merge(cursor_swatches(visual))
	return _measure(swatches, CURSOR_PAIRS, CURSOR_FLOOR)


## Pares que caíram abaixo do piso registrado. Vazio significa "não piorou", nunca "está bom".
## O piso vem dentro da medição para que os dois conjuntos de pares usem a mesma catraca sem que
## quem chama precise lembrar qual tabela é a certa.
static func regressions(measurement: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var floors: Dictionary = measurement["floor"]
	for entry in measurement["pairs"]:
		var name: String = entry["pair"]
		if not floors.has(name):
			found.append("%s: par sem piso registrado" % name)
			continue
		var floor_value: float = floors[name]
		var ratio: float = entry["worst_ratio"]
		if ratio < floor_value - FLOOR_TOLERANCE:
			found.append("%s: %.3f abaixo do piso %.3f" % [name, ratio, floor_value])
	return found


static func _measure(swatches: Dictionary, pairs_to_measure: Array, floors: Dictionary) -> Dictionary:
	var pairs: Array[Dictionary] = []
	var worst_ratio := INF
	var worst_pair := ""
	var below_target := PackedStringArray()
	for pair in pairs_to_measure:
		var entry := _measure_pair(swatches, pair[0], pair[1])
		pairs.append(entry)
		if not entry["meets_target"]:
			below_target.append(entry["pair"])
		if entry["worst_ratio"] < worst_ratio:
			worst_ratio = entry["worst_ratio"]
			worst_pair = entry["pair"]
	return {
		"pairs": pairs,
		"worst_ratio": worst_ratio,
		"worst_pair": worst_pair,
		"below_target": below_target,
		"floor": floors,
	}


static func _measure_pair(swatches: Dictionary, first: String, second: String) -> Dictionary:
	var lefts: Array = swatches[first]
	var rights: Array = swatches[second]
	var by_vision := {}
	var worst_ratio := INF
	var worst_vision := ""
	for vision in VISION_ORDER:
		var ratio := INF
		for left in lefts:
			for right in rights:
				ratio = minf(ratio, contrast_ratio(simulate(left, vision), simulate(right, vision)))
		by_vision[VISION_LABELS[vision]] = ratio
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst_vision = VISION_LABELS[vision]
	return {
		"pair": "%s×%s" % [first, second],
		"worst_ratio": worst_ratio,
		"worst_vision": worst_vision,
		"by_vision": by_vision,
		"chroma_retention": _chroma_retention(lefts[0], rights[0]),
		"meets_target": worst_ratio >= TARGET_RATIO,
	}


## Fração da diferença cromática que sobrevive à pior dicromacia, em RGB linear. Perto de 1.0 a
## distinção não dependia de cor; perto de 0.0 ela dependia quase inteiramente — e nesse caso a
## luminância precisa carregar o par sozinha. Acima de 1.0 é possível e não é erro: a projeção não
## é uma contração em todas as direções, então um par já separado por luminância pode até se
## afastar. O que importa é o piso, não o teto.
static func _chroma_retention(first: Color, second: Color) -> float:
	var base := _linear_distance(first, second)
	if base <= 0.0:
		return 0.0
	var retention := INF
	for vision in VISION_ORDER:
		if vision == Vision.TRICHROMAT:
			continue
		var simulated := _linear_distance(simulate(first, vision), simulate(second, vision))
		retention = minf(retention, simulated / base)
	return retention


static func _linear_distance(first: Color, second: Color) -> float:
	var dr := _linearize(first.r) - _linearize(second.r)
	var dg := _linearize(first.g) - _linearize(second.g)
	var db := _linearize(first.b) - _linearize(second.b)
	return sqrt(dr * dr + dg * dg + db * db)


static func _modulated(color: Color, factors: Array) -> Array[Color]:
	var result: Array[Color] = []
	for factor in factors:
		result.append(Color(color.r * factor, color.g * factor, color.b * factor, color.a))
	return result


static func _linearize(channel: float) -> float:
	var value := clampf(channel, 0.0, 1.0)
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)


static func _delinearize(channel: float) -> float:
	var value := clampf(channel, 0.0, 1.0)
	return value * 12.92 if value <= 0.0031308 else 1.055 * pow(value, 1.0 / 2.4) - 0.055
