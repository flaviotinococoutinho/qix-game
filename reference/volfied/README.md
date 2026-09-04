# Referência Volfied — análise derivada

Estes documentos são **prosa analítica original** produzida ao estudar o funcionamento de
*Volfied* (Taito, 1989), set `volfied` (World, rev 1). Vivem aqui para que qualquer agente ou
pessoa trabalhando neste projeto tenha a base factual do gênero sem precisar do material de
origem.

## O que este diretório é

| Arquivo | Assunto | Uso típico neste projeto |
|---|---|---|
| `00-visao-geral.md` | índice da desmontagem | ponto de entrada |
| `01-hardware.md` | três CPUs, chips Taito, osciladores | contexto; raramente acionável |
| `02-mapa-de-memoria.md` | três espaços de endereçamento, latch PC060HA, janela do C-Chip | contexto |
| `03-video.md` | word de VRAM → cor, imagens A/B, `VIDEO_MASK`, duas páginas, lista de sprites | **paleta, máscara de revelação, camadas** |
| `04-c-chip.md` | TC0030CMD: controles, moedas, aritmética | contexto |
| `05-som.md` | fila na RAM, latch de nibbles, intérprete Z80, YM2203, formato dos dados | **timbre, envelope, cadência de eventos sonoros** |
| `06-gameplay.md` | máquina de estados de 3 níveis, laço principal, frame, movimento, **algoritmo de preenchimento**, percentagem, pontuação, vidas, escudo, itens, 16 rondas, chefes | **a fonte mais acionável** |
| `07-texto-e-fonte.md` | texto como um sprite por carácter, HUD, ranking, staff roll | **tipografia e layout de HUD** |
| `08-ferramentas-e-reproducao.md` | ambiente, ROMs, imagens planas, desmontagem, testes | metodologia |
| `ACHADOS_ANOTACAO.md` | matéria-prima; itens marcados como dúvida não são verdade estabelecida | rastrear origem de uma afirmação |
| `HARDWARE_GROUND_TRUTH.md` | fatos verificados do hardware | checagem cruzada |

## O que este diretório NÃO é

- **Não contém dados de ROM.** Nenhum byte de imagem, sprite, paleta binária, sample ou código
  do Volfied está aqui. As ROMs e a desmontagem (`src/`, `symbols/`) ficam fora deste repositório
  por decisão explícita.
- **Não é especificação deste jogo.** Volfied é *referência de gênero*, não alvo de clone. O que
  vale para este projeto está em `docs/PROJECT_CONTRACT.md`, `docs/ART_DIRECTION.md` e nos ADRs.

## Como usar sem contaminar o projeto

O contrato é simples e vale para agentes e pessoas:

1. **Extraia comportamento, nunca conteúdo.** "O preenchimento escolhe a região *sem* inimigo e
   a percentagem sobe em passos discretos" é comportamento — é adotável. Um mapa de cores, uma
   forma de sprite ou um nome de personagem é conteúdo — não é.
2. **Cite a origem ao adotar um número.** Ao trazer uma velocidade, um limiar ou uma cadência,
   registre `reference/volfied/06-gameplay.md §X` na ADR ou no comentário. Números sem origem
   viram folclore em três iterações.
3. **Traduza para a identidade própria.** `docs/ART_DIRECTION.md` define *Lumen Cartography*. Um
   fato do Volfied entra no projeto convertido para essa linguagem, nunca copiado como está.
4. **Dúvida em `ACHADOS_ANOTACAO.md` continua dúvida.** Não promova a fato sem verificação.

> Regra de ouro: se a mudança só se justifica dizendo "porque o Volfied faz assim", ela ainda não
> está justificada. Diga o que ela faz pela experiência **deste** jogo.
