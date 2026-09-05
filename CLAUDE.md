# CLAUDE.md — QIX GAME

Jogo territorial original em Godot **4.7.2-stable**, GDScript tipado, 2D, retrato 240×320.
Gramática de Qix, sistemas inspirados em Volfied, identidade visual própria (*Lumen Cartography*).

Este arquivo é o **roteador**, não a enciclopédia. Ele diz onde a verdade mora e quais invariantes
não podem quebrar. Fatos detalhados vivem nos documentos citados — se você se pegar copiando um
número daqui para lá, pare: duplicação é a entropia que este arquivo existe para conter.

## Onde a verdade mora

| Pergunta | Documento |
|---|---|
| Engine, alvos, ownership por camada, comandos reais | `docs/PROJECT_CONTRACT.md` |
| O que está entregue e com que evidência | `docs/IMPLEMENTATION_STATUS.md` |
| Identidade visual, hierarquia, arco das 3 rodadas | `docs/ART_DIRECTION.md` |
| Por que uma decisão é como é | `docs/decisions/ADR-*.md` |
| Orçamento e medição de performance | `docs/PERFORMANCE.md` |
| O que é testado e como | `docs/TEST_MATRIX.md` |
| Estado do gate de publicação | `docs/SHIPPING_PASS.md` |
| Procedência de cada asset | `assets/ASSET-PROVENANCE.md` |
| Como o Volfied resolve um problema do gênero | `reference/volfied/` (leia o `README.md` primeiro) |
| O que o loop de agente já tentou e o que vem a seguir | `docs/LOOP_LEDGER.md` |

**Ordem do tick**: documentada no cabeçalho de `game/simulation/game_simulation.gd`. Esse
comentário é normativo — mudou a ordem, mudou o comentário no mesmo commit.

## Invariantes — quebrar exige ADR, não um commit

1. **O domínio não conhece o mundo real.** Nada em `game/simulation/`, `game/rules/` ou
   `game/session/` lê relógio, `Input`, `Tween`, física ou `delta`. Só inteiros e ponto fixo 8.8.
2. **`GameSimulation.step(intent)` avança exatamente um tick**, 60/s, na ordem documentada.
3. **`BoardState` é a única autoridade sobre território.** `PackedByteArray`,
   estados `FREE/BOUNDARY/TRAIL/CLAIMED`. Ninguém mais escreve células.
4. **`DeterministicRng` é o único acaso.** xorshift32 com seed explícita. `randi()`, `randf()` e
   `RandomNumberGenerator` são proibidos fora dele.
5. **`FloodFillCaptureResolver` é puro.** Devolve `CapturePlan` ou `CaptureError`; não muta nada.
6. **Apresentação observa, nunca muta.** `BoardView`, `PlayerView`, `EnemyView`, HUD, transições,
   VFX, `QixFeedbackHub`, `GameInputAdapter` leem snapshots e eventos **confirmados**. Feedback
   nunca antecipa resultado do domínio.
7. **Replay e checksum são contrato.** Seed, hash de regras/geometria, perfil do boss e checksum
   inicial são validados antes de qualquer mutação. Mexer em `GameRules`, na geometria ou em
   `BossBehaviorProfile` **invalida replays existentes** — isso é uma decisão, não um efeito
   colateral.
8. **Trocar a apresentação não pode mudar checksum.** Se uma mudança estética alterou um checksum,
   ela vazou para o domínio. Reverta e refaça.
9. **`GameRules` é `Resource` imutável em runtime.** Autoração acontece em conteúdo, não em código.
10. **Nenhum byte extraído de ROM entra no jogo.** Arte, som e fontes são originais. Ver
    `assets/ASSET-PROVENANCE.md` e `reference/volfied/README.md`.

## Verificação — evidência antes de afirmar

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot   # macOS local; na nuvem, veja abaixo
cd <repo>

$G --headless --path . --import                                        # 1× por checkout
$G --headless --audio-driver Dummy --path . --script res://tests/run_tests.gd
$G --headless --path . --script res://tools/verify_m2_capture_route.gd  # rota 17,9→82,5%
$G --headless --path . --script res://tools/profile_board_view.gd       # perfil CPU/R8
$G --headless --path . --script res://tools/verify_palette_contrast.gd  # contraste por estado
$G --headless --path . --script res://tools/build_campaign_content.gd   # conteúdo transacional
tools/shipping/run_shipping_qa.sh                                       # exports + probes (macOS)
```

`--import` é **obrigatório uma vez por checkout**: sem ele o cache de `class_name` não existe e
tudo falha por razões que não são a sua mudança.

Nunca escreva "passa", "verde" ou "corrigido" sem ter rodado e lido a saída. Se algo não pôde ser
verificado, diga qual comando não rodou e por quê.

A mesma regra vale para documento: todo `docs/*.md` declara logo abaixo do H1 **quando** foi
verificado, **contra qual commit**, **em que ambiente** e com que **alcance** — inclusive o que
ficou de fora. Documento sem data envelhece em silêncio e vira mentira confiante. Mexeu no doc,
atualize o cabeçalho; não conseguiu reverificar, diga isso no alcance em vez de mudar a data.
`tests/unit/doc_freshness_header_test.gd` recusa doc novo sem cabeçalho e ADR sem data.

## Trabalhando local vs. na nuvem

| | Local (macOS) | Sessão de nuvem |
|---|---|---|
| Godot | `/Applications/Godot_mono.app` | **ausente** — baixe o build Linux headless 4.7.2-stable (o projeto é só GDScript; não precisa de mono) |
| Editor, MCP `godot-ai`/`fennara` | disponíveis | **indisponíveis** (falam com um editor rodando) |
| Rodar o jogo, ver, tirar screenshot | sim | não |
| ROMs e desmontagem do Volfied | em `../` fora do repo | não versionados, ausentes |
| Export/QA de shipping | sim | não (precisa de SDKs e assinatura) |

Se a engine não puder ser instalada, **degrade honestamente**: trabalhe em documentação,
organização e leitura estática, e escreva no PR que nada foi executado. Mudança de comportamento
sem teste é dívida, não entrega.

## Estrutura

```
app/       composition root (bootstrap), adaptadores de entrada, feedback de dispositivo
game/
  simulation/  domínio puro: board, tick, captura, rng, eventos, replay
  rules/       Resources autoráveis: regras, campanha, rodada, conteúdo, visual
  session/     encadeamento de rodadas, registros de tentativa
  board|player|enemies|vfx|audio/  apresentação e feedback
ui/        HUD, transições, controles touch
content/   Resources de campanha gerados transacionalmente
tools/     scripts headless de verificação, perfil, geração e shipping
tests/     unit / integration / smoke — entrada única em tests/run_tests.gd
docs/      contrato, status, arte, performance, matriz de teste, ADRs
reference/ material de estudo derivado (não é especificação deste jogo)
```

Um arquivo novo pertence à camada cuja **regra de ownership** ele obedece, não à pasta mais
conveniente. Na dúvida, a tabela de ownership em `docs/PROJECT_CONTRACT.md` decide.

## Como usar a referência do Volfied

Leia `reference/volfied/README.md` antes de tocar nesses arquivos. Em resumo: **extraia
comportamento, nunca conteúdo**; cite a origem (`reference/volfied/06-gameplay.md §X`) ao adotar
um número; traduza o achado para *Lumen Cartography*. Se a justificativa de uma mudança é "porque
o Volfied faz assim", ela ainda não está justificada — diga o que ela faz pela experiência **deste**
jogo.

## Idioma

Documentação, comentários, ADRs e mensagens de commit em **português**. Identificadores de código
em inglês, como já está no código.
