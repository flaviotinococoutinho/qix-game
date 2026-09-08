# ADR-0014 — Atlas Vivo: ciclo de vida determinístico e palco 2.5D

**Estado:** aceita para a implementação local em 2026-09-07, por solicitação do dono do projeto.

## Contexto

O pedido é renovar o jogo com desafio inspirado em Volfied, atores extensíveis, estados de
ciclo de vida e apresentação 2.5D. A branch `feat/lumen-threat-roster`, base `a1afb90`, já
continha mudanças locais de input, pools, diretor e fases. Essa base foi preservada e integrada.
A spec Atlas Vivo de 2026-09-05 orienta o desenho; não é prova de que todos os seus itens existem.

## Decisão

1. `BoardState`, tick de 60 Hz, inteiros/ponto fixo, RNG e resolução pura continuam sendo
   autoridade. Nenhuma colisão depende de Blender, malha, câmera ou tempo de quadro.
2. `ActorLifecycle` define `DESPAWNED/WARMUP/ACTIVE/DORMANT/DYING`. Capacidades descrevem o
   papel de cada tipo. Identidade não é posição no array: jogador e chefe têm IDs reservados;
   cada spawn menor recebe um novo ID. Slot em dissipação não pode ser reutilizado.
3. Pools de produção permanecem limitados a 4 vagalumes, 6 dardos e 4 brasas. Isso é orçamento
   explícito de leitura/custo. Ampliação exige medir a nova capacidade; escalabilidade não
   significa spawn ilimitado nem um Node de física por célula.
4. Balizas são objetivos separados do território. A captura confirmada pode gerar velocidade,
   estase, congelamento do escudo ou purga, com contadores inteiros. `ItemProfile` e
   `BonusLadder` são Resources autoráveis e fazem parte do hash de regras.
5. `RULES_VERSION = 4` e `ThreatProfile.PROFILE_VERSION = 2` invalidam replays anteriores.
   A mudança é deliberada: justiça de warmup/respawn, identidade, tempos, objetivos e bônus
   alteram comportamento. Os novos dourados são medidos pelo gerador de checksums existente.
6. A janela usa `canvas_items`; o espaço lógico continua 240×320 e a máscara territorial
   continua 225×283 R8. O palco usa um SubViewport 720×960 para a camada tática, um quad com
   material sem iluminação e câmera ortográfica. HUD e controles permanecem fora do plano.
7. Seis GLBs originais do Blender são proxies 3D sem colisores. Tamanhos são autoráveis em
   `RoundVisualDefinition`, que não entra no replay. IDs e slots do snapshot limitam o pool
   de apresentação; F2 permite fallback plano, F4 reduz movimento, M alterna som.
8. Na vitória, a sessão arquiva e congela o checksum. A dissipação subsequente é guiada pelo
   progresso de transição da apresentação, sem continuar mutando a simulação arquivada.

## Alternativas e consequências

Reescrever o domínio com RigidBody3D/CharacterBody3D acoplaria a captura à física e invalidaria
o contrato determinístico. Inclinar apenas um Sprite2D seria barato, mas não daria volume
individual aos atores. O palco com GLBs preserva o domínio e permite ampliar materiais,
animação e cenografia; custa um passe de SubViewport e exige perfil gráfico por aparelho.

Sombras/contornos e sinais táticos carregam a leitura; glow HDR não é requisito. A implementação
Compatibility de glow tem limitações documentadas. A arte atual é uma biblioteca original
facetada, não assets finais de produção AAA nem reprodução do elenco original de Volfied.

## Evidência e origem dos números

- Referência local `reference/volfied/06-gameplay.md`: §§3–4 (trilha/movimento), §7.3 (cadeia),
  §9 (escudo), §10 (escada de ameaça), §11 (itens), §12 (encerramentos/bônus).
- Durações e redução do elenco são decisões locais da spec Atlas Vivo. `SEALED` mede a área
  livre restante no commit; tem precedência sobre alvo quando alcançado na mesma captura.
  Não é uma simulação de múltiplos chefes nem garantia de que todo setor oferece esse atalho.
- [SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html),
  [Camera3D](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html),
  [BaseMaterial3D](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html),
  [Environment](https://docs.godotengine.org/en/4.7/classes/class_environment.html).
- MCP oficial Blender instalado: ferramenta `execute_blender_code_for_cli`, Blender 5.2.0
  LTS, código-fonte de geometria e `.blend` preservados; hashes em `assets/models/lumen/manifest.json`.

## Próxima decisão

Variações de campanha, armas, múltiplos chefes e encontros completos do repertório de Volfied
exigem contratos adicionais e rotas jogáveis. Não estão implicitamente entregues por esta ADR.
