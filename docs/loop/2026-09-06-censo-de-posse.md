# Censo de posse do backlog: 14 dos 16 itens já têm dono, e os 2 livres exigem alguém jogando

**Verificado em:** 2026-09-06T16:00Z, contra `origin/main` em `cba520a`
**Executado com:** Godot 4.7.2.stable.official.ed1daf0bf (build Linux headless, baixado no sandbox)
**Alcance:** mede *posse* — que PR aberto reivindica cada item do backlog — e o estado de merge da
fila. **Não** julga o mérito de nenhum PR: nenhum foi revisado linha a linha, e o mérito estético
continua fora do alcance de uma sessão headless.

## O achado

`main` não anda desde **2026-09-04 23:57** (`cba520a`, o merge do #19). Nas ~39 horas seguintes o
loop abriu **33 PRs** (#20–#52) e **nenhum** entrou. A consequência não é lentidão: é que o
backlog do `LOOP_LEDGER` **não tem mais itens livres**, e por isso cada execução nova ou duplica
trabalho já feito numa branch aberta, ou gasta a hora medindo a própria fila.

Quatro dos 33 PRs já são meta — trabalho *sobre a fila*, não sobre o jogo: #40, #42, #45, #51.
Este documento é o quinto, e a seção final propõe a regra que impede o sexto.

## Posse item a item

Levantado por diff de cada ramo `ai/loop-*` contra `origin/main`
(`git diff --name-only origin/main...<ramo>`), cruzado com o título de cada PR aberto.

### P0 — a fila

| Item | Dono |
|---|---|
| Drenar a fila de PRs abertos | **#51** (integra #20–#50), **#42** (integra #20–#41, superado) |

### P1 — higiene estrutural

| Item | Dono |
|---|---|
| `antipixel_state_machine/` é a última raiz de terceiros não decidida | **#22** |

### P2 — integridade de contexto

| Item | Dono |
|---|---|
| Sete addons dormentes | **#29** (`addons/README.md`, ADR-0010, `addons_manifest_test.gd`) |
| Invariante 1, segunda metade (`float` no domínio) | **#25** (`domain_purity_test.gd`, `game_session.gd`) |
| Invariante 6 sem guarda mecânica | **#26** (`presentation_purity_test.gd`) |
| Cobertura dourada só alcança a rodada 1 | **#24** (`replay_checksum_golden_test.gd`) |
| Contrato de `session.records` | **#49** (`game_session.gd`, `session_records_contract_test.gd`) |

### P3 — experiência e estética

| Item | Dono |
|---|---|
| **`BOUNDARY`×`TRAIL` a 1,04:1** | **livre — bloqueado** (ver abaixo) |
| Ameaça sobre borda e trilha depende de forma | **#32** (ADR-0011, `enemy_view.gd`) |
| Contorno do jogador é a cor do chão | **#28** (`cursor_contrast_test.gd`, `palette_contrast.gd`) |
| Forma do envelope por intenção | **#23** (`procedural_audio_library.gd`, `audio_envelope_test.gd`) |
| Ritmo do risco: som e háptica da exposição | **#39** (`haptic_feedback.gd`, `trail_exposure.gd`) |
| **Calibrar a curva de exposição com jogo real** | **livre — bloqueado** (ver abaixo) |
| A pontuação não acompanha a subida do contador | **#27** (`game_hud.gd`, ADR-0009) |
| O tempo da transição entre rodadas não tem ritmo | **#50** (`round_transition_view.gd`) |
| A geometria do HUD depende da ordem de construção | **#52** (`game_hud.gd`, `verify_hud_row_geometry.gd`) |

**14 de 16 itens têm dono.** Os outros 15 PRs abertos (#21, #30, #31, #33–#38, #41, #43, #44,
#46, #47, #48) atacam achados que nasceram fora do backlog.

## Os dois itens livres estão bloqueados na mesma coisa

Nenhum dos dois é "livre" no sentido de trabalhável hoje. Os dois exigem exatamente a capacidade
que o sandbox não tem — **alguém vendo o jogo na tela**:

- **`BOUNDARY`×`TRAIL` a 1,04:1.** O critério de pronto escrito no ledger termina em "e alguém
  confirmou por captura que o campo não ficou lavado". Baixar a luminância do contorno ou subir a
  da trilha é uma decisão de identidade visual sobre o par mais frequente do campo. Uma sessão
  headless mede o contraste; não sabe se o resultado ficou legível ou lavado. Empurrar essa
  mudança sem olho humano é a definição de otimismo não verificado que o `CLAUDE.md` proíbe.
- **Calibrar a curva de exposição.** O critério é literalmente "alguém joga as três rodadas e
  confirma". O piso de 8 px e o teto de 127 px são justificáveis no papel e nunca foram vistos em
  jogo.

Escolher qualquer um deles nesta execução produziria um PR que afirma mais do que mediu.

## Estado de merge da fila, medido

| Medição | Resultado |
|---|---|
| `origin/main` (`cba520a`) sozinha | 174 testes, 11837 asserções, **0 falhas** |
| `#51` mescla em `main` sem conflito | `git merge-tree` **limpo**, 76 commits à frente |
| `#51` com a suíte completa | 261 testes, 12713 asserções, **0 falhas** |
| `#51` na rota M2 | `"errors": []` |

**Mesclar o #51 leva a fila de 33 para 2** (#52 e o PR desta execução) e satisfaz o critério de
pronto do item P0 tal como está escrito. É a única ação que devolve o loop ao jogo, e só um humano
pode tomá-la.

### Nenhum PR da fila está vermelho

O portão `.github/workflows/verificacao.yml` roda em `main` desde a integração do #19 e cobre
todos os PRs abertos. Consultadas as execuções de evento `pull_request` do portão:

| | |
|---|---|
| Execuções concluídas | **37** |
| Conclusão `success` | **37** |
| Conclusão `failure`/`cancelled`/`timed_out` | **0** |
| PRs cobertos | **#20–#53**, todos os 34 |

Isso muda a natureza da decisão de merge: a fila não está represada por trabalho duvidoso, e o
revisor não está sendo convidado a mesclar código não verificado. O #51 em particular tem, além da
medição local desta execução, o verde independente do portão (run `34037911211`). O que continua
sem verificação é o **mérito** — nenhum PR foi revisado, e o portão mede a suíte, não se as
mudanças são boas para o jogo.

Se mesclar em bloco não for aceitável, a alternativa mínima é fechar os meta redundantes (#40,
#42, #45 são todos superados pelo #51) — isso não destrava o backlog, mas para de fazer a fila
crescer por trabalho sobre si mesma.

## A regra que falta no protocolo

O protocolo do ledger manda a execução verificar a fila antes de escolher e, se nada estiver
livre, abrir um "PR só de ledger". Esse escape **não tem teto**: com a fila saturada, ele
autoriza um meta-PR por hora, para sempre. #40 e #45 são a prova — os dois dizem, com palavras
diferentes, "a fila está cheia e o backlog não tem itens livres".

A regra proposta, e que este PR acrescenta ao ledger: **um meta-PR só é legítimo se carregar uma
medição que nenhum meta-PR aberto já carrega, e tem de nomear quais ele supera.** Este documento
passa nesse teste — o censo de posse item a item e a verificação verde do #51 não existiam em #40
nem em #45 — e nomeia #40, #42 e #45 como superados.

## O que este documento não mediu

- **Nenhum dos 33 PRs foi revisado.** "Verde" aqui é a suíte do #51 passando, não julgamento sobre
  se as mudanças são boas para o jogo.
- **`tools/profile_board_view.gd` e `tools/shipping/run_shipping_qa.sh` não rodaram.** O primeiro
  porque nada com custo por frame foi tocado; o segundo porque exige SDKs e assinatura.
- **A ordem de merge interna do #51 não foi reverificada.** Confiei na medição do próprio #51 para
  a incompatibilidade #25×#50 que ele declara ter resolvido; o que medi foi o resultado final.
