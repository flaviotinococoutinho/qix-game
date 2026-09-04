# Conteúdo autorável da campanha

`main_campaign.tres` é a entrada oficial de conteúdo. Todos os valores de gameplay e
apresentação podem ser editados no Inspector do Godot sem alterar scripts.

## Estrutura

- `campaigns/main_campaign.tres`: ordem das rodadas e duração das transições.
- `rounds/round_*.tres`: composição de cada rodada, com `round_id`, seed e referências.
- `rules/standard.tres`, `pressure.tres` e `expert.tres`: alvo, escudo, pontuação,
  velocidade, cadência e referência ao comportamento do boss.
- `rules/boss_wander.tres`, `boss_pursuit.tres` e `boss_sweep.tres`: padrão de direção,
  jitter/varredura e pulsos autoráveis de velocidade do boss.
- `rounds/definitions/*.tres`: geometria e posições iniciais.
- `visuals/*.tres`: nome, subtítulo, fundo e paleta; não participa do replay determinístico.

Cada rodada referencia arquivos externos — não `sub_resource` embutidos — para permitir reuso,
diffs pequenos e revisão independente entre design, balanceamento e arte.

## Fluxo de autoria

1. Duplique um conjunto `rules`, `definition`, `visual` e `round` no Inspector.
2. Atribua um `round_id` e uma seed não zero e únicos.
3. Mantenha o fundo com as mesmas dimensões do campo (`225 × 283` na campanha atual).
4. Adicione o novo `RoundContent` ao array ordenado de `main_campaign.tres`.
5. Escolha ou duplique um `BossBehaviorProfile`; mantenha seus limites válidos e lembre que
   ele participa do contrato determinístico de regras/replay.
6. Rode os testes `authored_campaign_test`, `boss_campaign_balance_test` e a suíte completa
   antes de publicar.

O script `res://tools/build_campaign_content.gd` recompõe a baseline oficial de três rodadas e
é idempotente. Ele **substitui** 16 Resources; portanto, mudanças manuais devem ser incorporadas
ao script antes de regenerar a baseline.

A geração usa uma transação write-ahead v3 persistente:

1. adquire um lock interprocessual exclusivo por listener TCP em `127.0.0.1`, com porta derivada
   do staging do projeto e metadata de owner; colisão ou ownership divergente falha fechado;
2. sob o lock, recupera qualquer transação incompleta encontrada em
   `user://qix-campaign-content-staging/` antes de iniciar trabalho novo;
3. valida destinos e usa o slot estável `txn_active`, com payloads, backups e uma cópia shadow
   do grafo dentro do staging;
4. serializa os payloads que serão promovidos e recarrega o grafo shadow com
   `ResourceLoader.CACHE_MODE_IGNORE`, sem tocar nos destinos oficiais;
5. persiste tamanho e SHA-256 de cada payload/backup no manifest
   `qix.campaign-content-transaction.v3`; o SHA-256 canônico desse manifest é repetido em cada
   record do journal JSONL append-only;
6. valida a sequência inteira do WAL como máquina de estados: um único `prepared`, início
   `committing` em zero, progresso estritamente monotônico e terminal `committed` ou
   `rolled_back` coerente, sem records posteriores;
7. copia cada payload para um vizinho `.qix-next-*` do destino e o promove por rename; o journal
   registra o progresso arquivo a arquivo;
8. em falha, percorre o manifest ao contrário, restaura existentes, remove destinos que não
   existiam e devolve o ownership anterior do cache de Resources;
9. se o processo for interrompido durante o commit, a próxima execução usa manifest, journal e
   backups em disco para fazer rollback; em estado terminal, os targets e temporários reais são
   verificados antes de limpar o staging.

A transação v3 possui **22 testes e 353 asserções** cobrindo sucesso, validação e corrupção de
metadata/artefatos, lock entre processos, interrupção abrupta, rollback byte a byte, cache,
recovery e targets terminais. A execução oficial mais recente terminou com **16 staged / 16
committed**.

Os hashes detectam divergência acidental, mas não são HMAC nem autenticam um atacante capaz de
reescrever manifest, WAL e artefatos em conjunto. O listener é um lock cooperativo entre
geradores que seguem o protocolo, não uma trava universal do filesystem. WAL, `flush()` e rename
também não substituem garantias de durabilidade do volume, backup externo ou versionamento. Para
publicação, rode o gerador até obter sucesso, execute a suíte e revise o diff dos 16 arquivos em
um repositório Git válido.
