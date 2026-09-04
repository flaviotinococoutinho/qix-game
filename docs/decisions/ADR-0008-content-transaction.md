# ADR-0008 — Geração de campanha usa WAL v3, lock, staging e rollback

## Status

Aceita em 2026-09-03.

## Contexto

O gerador recompõe vários Resources relacionados. Uma falha após gravações parciais poderia
deixar campanha, regras, boss, geometria e visual em versões incompatíveis.

## Decisão

O gerador prepara os Resources em memória e entrega a lista ordenada a
`CampaignContentTransaction`. Antes de recovery ou mutação, a transação adquire um lock
interprocessual por `TCPServer` em `127.0.0.1`, numa porta determinística derivada do staging do
projeto. O listener mantido pelo kernel é o guardião; o diretório `.txn_active.lock` é metadata de
owner. Metadata stale só pode ser removida depois de adquirir a porta. Uma colisão com outro
processo, inclusive não cooperante, falha fechado.

Sob esse lock, a transação usa o slot estável
`user://qix-campaign-content-staging/txn_active` e, antes de qualquer mutação oficial:

1. recupera transações incompletas deixadas por uma execução anterior;
2. rejeita destinos duplicados, traversal, extensões inválidas e caminhos fora de `res://` ou
   `user://`;
3. persiste backups byte a byte dos destinos existentes, com tamanho e SHA-256;
4. serializa os payloads que serão promovidos e recarrega um grafo shadow inteiramente dentro do
   staging, registrando também tamanho e SHA-256 dos payloads;
5. grava manifest `qix.campaign-content-transaction.v3`, calcula seu SHA-256 canônico e ancora
   esse digest em todo record do journal JSONL append-only.

Antes de autorizar commit ou rollback, a implementação valida schemas, campos e paths canônicos,
digests/tamanhos dos artefatos, âncora do manifest e a sequência completa do WAL. A máquina de
estados exige exatamente um `prepared` com contador zero, `committing` iniciado em zero e depois
monotônico de um em um, terminal `committed` apenas após todos os entries ou `rolled_back` com
progresso coerente, e nenhum record após um terminal.

O commit copia cada payload validado para um arquivo `.qix-next-*` adjacente ao destino e o
promove por rename, registrando o contador após cada arquivo. Sucesso registra `committed`; falha
percorre o manifest ao contrário, restaura existentes a partir dos backups em disco, remove novos
destinos, registra `rolled_back` e restaura o ownership anterior do cache de Resources.

Se o processo morrer entre commits, o kernel libera o listener e o diretório transacional
permanece. Antes da transação seguinte, um estado não terminal válido é revertido a partir de
manifest e backups. Um estado terminal só permite limpar o staging depois que bytes reais dos
targets e ausência dos temporários conferem com `committed` ou `rolled_back`.

## Consequências

Falhas normais de I/O têm rollback verificável, e kill/crash durante um commit pode ser recuperado
por uma execução posterior sem depender da memória do processo. A transação v3 possui 22 testes e
353 asserções cobrindo commit/rollback, lock entre processos, interrupção abrupta,
integridade/autorização, máquina de estados, cache, recovery e targets terminais; o gerador
oficial concluiu 16 payloads staged/committed.

O WAL reduz o risco de um conjunto parcialmente gravado, mas não é uma transação de filesystem
nem substitui backup ou versionamento. SHA-256 aqui garante detecção de divergência, não
autenticidade: não há HMAC ou raiz de confiança externa contra adulteração coordenada de manifest,
WAL e artefatos. O lock é cooperativo e escopado aos geradores que usam o protocolo. Corrupção de
mídia, perda do staging/backup ou falha de energia em uma camada que não honre os flushes também
continuam fora do contrato. Publicação exige suíte verde e revisão de diff em um repositório Git
válido.
