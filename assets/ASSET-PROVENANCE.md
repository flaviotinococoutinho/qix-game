# Proveniência dos assets visuais

## Atlas Vivo — biblioteca de atores 2.5D

- Data: 2026-09-07.
- Ferramenta: Blender **5.2.0 LTS**, pelo MCP oficial instalado (`blmcp`), ferramenta
  `execute_blender_code_for_cli`. Não houve instalação nem download de modelos/texturas.
- Autoria: geometria procedural original definida em `tools/assets/build_lumen_models.py`,
  executada pelo adaptador `tools/assets/blender_mcp_job.py`. Materiais e peças também são
  definidos pelo script; não contêm imagens, malhas, sons ou bytes extraídos de ROM.
- Fonte editável: `tools/assets/source/lumen_actor_library.blend`, excluída do import/export
  automático. Cada ator preserva peças nomeadas para edição e futura animação.
- Runtime: seis GLBs em `assets/models/lumen/`. O arquivo `manifest.json` registra versão,
  componentes, tamanho em bytes e SHA-256 de cada arquivo. O Godot instancia essas malhas
  exclusivamente como apresentação, sem colisores que alterem a simulação.
- Rastreabilidade local: `build/modernization/blender-models-receipt.json` preserva a chamada
  MCP; `lumen-models-gallery.png` preserva o render de inspeção. A galeria não é textura de jogo.
- Revisão: os seis modelos foram inspecionados no render Blender e carregados no renderer
  real do Godot. Silhuetas distintas, paleta coerente, ausência de texto e marcas de terceiros.
- Licença: esta geometria e os scripts originais são contribuições ao projeto sob sua licença
  raiz MIT. A proveniência dos fundos gerados anteriormente permanece registrada abaixo.

| Arquivo GLB | Papel | Triângulos |
|---|---|---:|
| `surveyor.glb` | jogador / cartógrafo | 1.192 |
| `core.glb` | núcleo inimigo | 1.380 |
| `walker.glb` | vagalume de fronteira | 572 |
| `dart.glb` | dardo | 260 |
| `ember.glb` | brasa de trilha | 640 |
| `beacon.glb` | baliza capturável | 1.040 |

Regenerar reconstrói a biblioteca a partir do script; antes disso, incorpore alterações
manuais do `.blend` ao gerador ou preserve/exporte a revisão artística separadamente.

## Probe do jogador — drone cartógrafo

- Data: 2026-09-05.
- Arquivo: `_gen/probe_player.png`; PNG RGBA, `32 × 32` pixels.
- Ferramenta: `image_gen.imagegen` integrado ao Codex; uma única geração. Modelo e seed não informados pela ferramenta.
- Rastreabilidade: `exec-15dca976-777c-4632-bed7-3b7cc2063912`.
- Fonte preservada no cache: `/Users/flaviocoutinho/.codex/generated_images/01a06fbc-bbfc-71c0-9a0a-aafd464403a1/exec-15dca976-777c-4632-bed7-3b7cc2063912.png`.
- Tratamento: fonte de `1254 × 1254` reduzida para `32 × 32` por vizinho mais próximo via CoreGraphics, sem suavização e preservando alfa.
- SHA-256: `8741690767f4ce61a45d6353154e118d42993fbd5729efcc2750f2b20f649088`.
- Verificação: arquivo final reaberto; dimensões e canal alfa confirmados, com 800 pixels totalmente transparentes. Inspeção visual da fonte e do sprite final: sujeito único, vista superior, ciano e núcleo dourado, sem texto, marca-d'água ou sombra projetada. Probe sem integração ao runtime.
- Proveniência: geração original OpenAI, sem material extraído de ROM; as observações de uso e revisão deste manifesto continuam aplicáveis.

Prompt final:

```text
Create exactly ONE image. Asset type: pixel art game sprite for a Qix-like territory game. A tiny luminous cartographer drone (the player cursor), one single compact subject centered in one 32x32 px cell, orthographic top-down. Bioluminescent cyan body with a pale gold luminous core. Crisp hard pixel edges, limited palette, simple readable silhouette at 32x32 pixels, no antialiasing, no blur or glow outside the silhouette. Fully transparent background with actual alpha transparency, not a checkerboard drawn into the image. No drop shadow, no text, no watermark. Output one PNG sprite, exactly 32 pixels wide by 32 pixels tall if supported. No extra panels, no sprite sheet, no scene, no other subjects.
```

Este manifesto registra a origem e o tratamento dos fundos usados pela campanha
`lumen_cartography`. Ele separa explicitamente fontes geradas, derivados de runtime e
tentativas rejeitadas. Nenhuma arte de ROM, screenshot de outro jogo ou referência externa
protegida foi incorporada a estes arquivos.

## Método de geração

- Data: 2026-09-02.
- Ferramenta: gerador de imagens OpenAI integrado ao Codex (`imagegen`).
- Direção visual: cartografia bioluminescente, composição vertical abstrata, alto detalhe no
  interior e bordas legíveis sob uma máscara de captura.
- Restrições comuns aos prompts: fundo original para jogo, sem personagens, HUD, letras,
  logotipos, assinatura ou marca-d'água.
- Tratamento: as saídas-fonte foram normalizadas para `225 × 283` PNG, exatamente a grade
  visual do campo. Os arquivos em `assets/source/backgrounds/` preservam as saídas antes da
  normalização; os arquivos em `assets/backgrounds/` são os derivados usados pelo runtime.

## Assets aprovados

| Rodada | Arquivo | Dimensões | SHA-256 | Prompt resumido |
|---|---|---:|---|---|
| Abyssal Relay | `source/backgrounds/abyssal_relay_source.png` | 1119 × 1406 | `839533df5ed4ba468b28b1964c61d9134ec6e1e9ead9f2bac25e90c110f3daaa` | Relay abissal como mapa tecnológico bioluminescente, azul profundo, ciano e turquesa, estruturas legíveis e sem texto. |
| Abyssal Relay | `backgrounds/abyssal_relay.png` | 225 × 283 | `f7f35ad5e9392f955d6d3b8bc9b57c5c0e1c66e1b6ebe4f596b0a34e90c4fa46` | Derivado normalizado para runtime. |
| Aurora Foundry | `source/backgrounds/aurora_foundry_source.png` | 1117 × 1408 | `cf4c0392d862f6884ac55f401f0b0b1a90262dd0cce58ebe6a76ef505e4a6c42` | Forja auroral abstrata, metal e energia em violeta, ciano e âmbar, profundidade vertical e sem texto. |
| Aurora Foundry | `backgrounds/aurora_foundry.png` | 225 × 283 | `57517e7e47e6317e1371493ee15ae24c1160b98ef920cae8ab64270991448bf2` | Derivado normalizado para runtime. |
| Verdant Singularity v2 | `source/backgrounds/verdant_singularity_source_v2.png` | 1117 × 1408 | `9e4215a576dfb352909996bf5c49f2e54ce333713459bad29286eb215fbebbd7` | Singularidade botânica viva em verde-esmeralda e teal; revisão dirigida para remover qualquer marca semelhante a assinatura. |
| Verdant Singularity v2 | `backgrounds/verdant_singularity_v2.png` | 225 × 283 | `1857ed1a085f62310e4f7252ef006aa2415ab59a1d62db841579b19cbf14100b` | Derivado normalizado para runtime e único Verdant referenciado pela campanha. |

Rastreabilidade das gerações: `exec-dd3597a7-c0e1-4104-854c-fed61ee441a3`
(Abyssal), `exec-907ef0ba-c1c9-45d0-91e5-33615db46f7a` (Aurora) e
`exec-a79ac434-b090-4d47-a6d7-f98d73aa60cc` (Verdant v2).

## Tentativa rejeitada — removida de `res://`

| Arquivo | Dimensões | SHA-256 | Motivo |
|---|---:|---|---|
| `source/backgrounds/verdant_singularity_source.png` (removido) | 1118 × 1407 | `9233366e9ce593f0bfc508d923bf6704b916a10c06dc607f25910dc14ade1734` | Pequena marca vermelho-alaranjada semelhante a assinatura; reprovada na inspeção visual. |
| `backgrounds/verdant_singularity.png` (removido) | 225 × 283 | `2d0e87b661340e41100246f40c733f37c0d5c2d5959b94ad992d81880984755d` | Derivado rejeitado; removido para não entrar acidentalmente em exports que incluam todo `res://`. |

Rastreabilidade da tentativa rejeitada: `exec-72a0cc06-62e2-4251-b009-c20c70eb858b`.
Os arquivos e sidecars `.import` foram removidos do projeto em 2026-09-02; a saída-fonte
permanece recuperável pelo cache local da geração enquanto ele existir, e os hashes acima
permitem conferir uma eventual restauração.

## Uso e revisão

Os três assets aprovados passaram por inspeção visual de composição, limpeza de bordas,
ausência de texto/marca-d'água e legibilidade na proporção final. A campanha referencia apenas
os derivados aprovados. Antes de redistribuição pública, devem ser observados os termos de uso
vigentes do serviço OpenAI aplicáveis às imagens geradas.

## Ícone de shipping — QIX GAME

- Data: 2026-09-03.
- Arquivo: `icons/qix_game_icon.png`.
- Ferramenta: gerador de imagens OpenAI integrado ao Codex (`image_gen`); o modelo e o seed não
  são expostos pela ferramenta integrada.
- Rastreabilidade: geração `exec-fe8afa87-270b-4a8a-9c29-b007eb1b3d62`; saída-fonte preservada
  no cache local em
  `/Users/flaviocoutinho/.codex/generated_images/01a065d0-ae66-73a2-b21e-da18fd7e15b8/exec-fe8afa87-270b-4a8a-9c29-b007eb1b3d62.png`.
- Propriedades: PNG RGB, `1254 × 1254`, sem canal alfa, composição full-bleed.
- SHA-256: `ffb9ba86b4a9f9a637e6a96274ea9874a41411d2820bbf1a55e658ab586dd1a6`.
- Revisão visual: aprovado no master e em redução para `32 × 32`; aderência `5/5`,
  enquadramento/legibilidade `4/5`, fundo `5/5`, coerência de paleta `5/5`, limpeza `5/5` e
  estilo `5/5`. Não foram observados texto, assinatura, marca-d'água, propriedade intelectual
  de terceiros ou artefatos incompatíveis com o uso como ícone.
- Licença/proveniência: geração original por OpenAI; conferir os termos vigentes do serviço
  antes de distribuição comercial.

Prompt final, preservado integralmente:

```text
Use case: stylized-concept
Asset type: final square master app/game icon for the Godot game QIX GAME
Primary request: Create an entirely original, premium game icon that communicates capturing territory by drawing a boundary and revealing a luminous world underneath.
Scene/backdrop: a deep near-black navy square field with subtle abyssal depth, full bleed to every edge.
Subject: one bold central geometric territory mass, visibly split between an opaque dark unclaimed region and a richly revealed bioluminescent cartography region. A single crisp electric cyan trail cuts in from the outer boundary and closes a polygonal loop; the newly captured interior blooms into cyan-to-violet luminous terrain. Include one tiny bright player spark on the trail only if it remains legible at thumbnail size.
Style/medium: polished 2D game-key-art icon; graphic, emblematic, high-end sci-fi fantasy cartography; painterly material inside simple hard-edged shapes; strong silhouette; restrained detail.
Composition/framing: centered single symbol occupying about 72 percent of the square; large simple masses; clear negative space; generous safe margin so platform masks can crop it; readable at 32 px; no outer badge, no container shape.
Lighting/mood: luminous cyan edge light with violet-magenta core accents, mysterious and kinetic; very high contrast against near-black navy.
Color palette: near-black navy, electric cyan, ultraviolet, sparse magenta; no orange, no green.
Materials/textures: subtle crystalline and organic-map texture confined inside the revealed territory; clean sharp boundary outside it.
Constraints: square raster artwork; original design; no text, no letters, no numbers, no typography, no logos, no trademarks, no signature, no watermark; no character or face; no HUD; no screenshot; no rounded-square frame; no circular badge; no bevelled app-icon mockup; no device mockup; no drop shadow outside the art; do not imitate any existing game or artist.
Avoid: clutter, tiny filigree, thin low-contrast lines, photorealistic landscape, generic neon triangle, generic letter Q, gradients that wash out the silhouette.
```
