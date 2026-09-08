# ADR-0010 — `addons/` só hospeda pasta com estado declarado

## Status

Aceita em 2026-09-05.

## Contexto

`addons/` tem nove pastas. Duas servem ao ferramental (`fennara`, `godot_ai`): estão em
`project.godot`, uma como único plugin habilitado, ambas como autoload. As outras sete — `GDDraw`,
`curve2collision`, `curved_lines_2d`, `guide`, `phantom_camera`, `softbody2d`, `yard` — somam
11,5 MB e 101 cenas, e o inventário de 2026-09-05 não achou consumidor para nenhuma delas por
nenhum dos dois caminhos possíveis:

- **por caminho**: a única citação de `addons/<pasta>` fora de `addons/` é a linha de
  `exclude_filter` de `export_presets.cfg`, que existe justamente para mantê-las fora do pacote;
- **por `class_name`**: nenhum dos ~200 símbolos que essas pastas exportam (`GUIDEAction`,
  `PhantomCamera2D`, `SoftBody2D`, `Registry`, …) aparece em `game/`, `ui/`, `app/`, `tools/`,
  `tests/` ou `content/`.

Nada disso é novo — o inventário do loop já tinha medido o mesmo. O que faltava era **decidir**. E
a ausência de decisão não é estado neutro: ela cobra juros. Quem abre este repositório amanhã vê
`phantom_camera/` e não tem como saber se é lixo de um download ou o plano de alguém para a câmera;
a única forma de descobrir é refazer a varredura que já foi feita três vezes. É exatamente a
entropia que o `CLAUDE.md` existe para conter, só que numa pasta que todo leitor de Godot aprendeu
a não olhar.

Havia a tentação de resolver isto apagando as sete pastas de uma vez. Duas razões contra: o limite
de "uma pasta por vez" existe para que o histórico continue legível, e a poda de
`antipixel_state_machine/` ainda está na fila sem revisão — apagar 11,5 MB antes de um humano ver
como a poda anterior ficou seria empilhar risco, não entregar valor.

## Decisão

Toda pasta de primeiro nível em `addons/` declara um **estado** em `addons/README.md`, escolhido
entre três:

- **`dependencia`** — o código do jogo consome a pasta. Exige ao menos uma citação de
  `addons/<pasta>` fora de `addons/`.
- **`ferramenta`** — serve ao editor ou ao agente e nunca entra no pacote. Exige citação em
  `project.godot`.
- **`a-remover`** — não tem consumidor. Exige o oposto: **nenhuma** citação fora de `addons/`, e
  presença no `exclude_filter` dos dois presets de export, para que uma pasta condenada não possa
  vazar para um build enquanto espera a remoção.

`tests/unit/addons_manifest_test.gd` verifica os três estados contra o disco e recusa pasta sem
linha, linha sem pasta e estado fora do vocabulário.

Aplicando a regra hoje: `fennara` e `godot_ai` ficam como `ferramenta`; as outras sete recebem
`a-remover`. A remoção acontece **uma pasta por PR**, com a mesma evidência de posse de `uid://`
usada na poda dos demos.

## Consequências

O que melhora: a pergunta "isto é lixo ou plano?" passa a ter resposta escrita ao lado da coisa, e
o teste impede que ela envelheça em silêncio. Um addon que comece a ser usado enquanto está marcado
`a-remover` faz a suíte falhar — o autor é obrigado a mudar a linha para `dependencia`, e a decisão
fica registrada em vez de acontecer por acidente.

O que custa: quem copiar uma pasta para `addons/` para experimentar vai ver a suíte vermelha até
escrever uma linha. É o custo pretendido — uma linha é barata, e é a única barreira entre "testei
uma coisa" e "isto virou dependência sem ninguém decidir".

O que fica em aberto: as sete remoções. Elas não estão feitas, e este ADR não as executa — decide
que elas devem acontecer e em que forma. Um revisor que queira manter alguma delas não precisa
reabrir esta decisão: basta trocar o estado da linha e escrever o motivo, que é precisamente para
isso que a coluna existe.

O que **não** muda: nenhum byte de `addons/` entra num build hoje, então nenhum export, checksum ou
replay é afetado. Esta ADR é sobre legibilidade do repositório, não sobre o jogo em execução.
