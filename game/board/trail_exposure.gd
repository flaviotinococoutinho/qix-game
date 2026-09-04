class_name TrailExposure
extends RefCounted
## Leitura de apresentação: quão exposto o jogador está *agora*, num único escalar 0..1.
##
## O domínio já sabe o comprimento da trilha confirmada; ninguém mostrava isso ao jogador antes
## do impacto. Esta classe é a tradução — pura, sem estado, sem relógio — de `trail.size()` para
## a linguagem visual de *Lumen Cartography*: um traço curto é um compromisso, um traço que
## atravessa o setor é uma aposta.
##
## Nada aqui volta para a simulação. É uma função de leitura sobre um snapshot já confirmado,
## e trocar a curva não pode alterar checksum (invariante 8).

## Abaixo de `committed_px` a exposição é zero: o traço ainda é curto e recuperável.
## O piso reaproveita o mesmo limiar que o domínio usa para negar aceleração num segmento novo
## (`GameRules.new_segment_slow_px`, §4.3 de `reference/volfied/06-gameplay.md`), para que o
## momento em que o jogo passa a te empurrar seja o mesmo em que ele passa a te avisar.
##
## O teto é geométrico e não autorado: um quarto do semiperímetro do campo. No campo de
## produção (225×283) isso dá 127 células — uma travessia inteira do interior. Fica fora de
## `GameRules` de propósito: uma curva de apresentação não pode invalidar replays existentes.
static func ceiling_px(width: int, height: int, committed_px: int) -> int:
	@warning_ignore("integer_division")
	var geometric := (maxi(width, 0) + maxi(height, 0)) / 4
	return maxi(maxi(committed_px, 0) + 1, geometric)


## 0.0 = ainda encostado na moldura; 1.0 = a trilha já vale o campo inteiro.
static func ratio(trail_length: int, committed_px: int, width: int, height: int) -> float:
	var floor_px := maxi(committed_px, 0)
	var top_px := ceiling_px(width, height, floor_px)
	if trail_length <= floor_px:
		return 0.0
	return clampf(
		float(trail_length - floor_px) / float(top_px - floor_px),
		0.0,
		1.0,
	)


## Mesma leitura a partir da simulação, para que view e HUD não divirjam por cópia de fórmula.
static func of_simulation(simulation: GameSimulation) -> float:
	if simulation == null or not simulation.trail_active:
		return 0.0
	return ratio(
		simulation.trail.size(),
		simulation.rules.new_segment_slow_px,
		simulation.board.width,
		simulation.board.height,
	)


## Limiar em que a exposição deixa de ser ambiente e vira aviso nomeado no HUD.
const WARNING_RATIO := 0.5


static func is_warning(exposure: float) -> bool:
	return exposure >= WARNING_RATIO
