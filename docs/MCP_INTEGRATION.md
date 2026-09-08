# Integração Godot e Blender

> **Verificado em** 2026-09-08 · commit `972fd4c` · integração local Godot 4.7.2 / Blender 5.2
> **Alcance:** launchers, diagnóstico, contratos e recuperação de conexão; veja o relato para recibos de execução.

O projeto usa dois launchers locais em `tools/mcp/`, compartilhados por `.mcp.json` e
`.codex/config.toml`. Abra o cliente MCP com a raiz deste repositório como diretório de
trabalho. Os launchers descobrem as instalações existentes; não exigem caminhos pessoais
gravados no código nem modificam o vendor assinado.

| Integração | Papel | Verificação |
|---|---|---|
| Godot AI 4.0.2 | inspeção e operações do editor, cenas, assets e runtime | versão do servidor/plugin, sessão do caminho correto e readiness |
| Fennara 0.4.2 | diagnóstico de scripts, import e sondas do editor/runtime | resposta explícita, diagnósticos e estado da sessão |
| Blender MCP 1.0.0 | autoria procedural e export dos modelos 2.5D | saída real do Blender, resposta MCP e artefato produzido |

## Uso

```sh
python3 -B tools/mcp/godot_mcp.py --doctor
python3 -B tools/mcp/blender_mcp.py --doctor
python3 -B tools/mcp/blender_mcp.py --discover --receipt /tmp/qix-blender-discovery.json
python3 -B tools/assets/validate_lumen_models.py
```

Sem flags, cada launcher atende o protocolo MCP por stdio. Para apontar instalações
alternativas existentes, use `QIX_GODOT_UVX`, `QIX_BLENDER_MCP_PYTHON` e `BLENDER_PATH`, ou
as opções indicadas em `--help`. O Python do Blender precisa conter `mcp` e `blmcp`;
o launcher procura também a extensão oficial instalada, preservando o ambiente virtual.

O Godot AI usa **HTTP 8001 / WebSocket 9501**. No Godot, as propriedades
`godot_ai/http_port` e `godot_ai/ws_port` pertencem a **EditorSettings globais**. Configuração
de cliente por projeto não transforma essas portas em preferências por projeto.
O procedimento completo, com backup, migração oficial e rollback, está em
[godot_recovery.md](../tools/mcp/godot_recovery.md).

## Testes do jogo e prova de resultado

O runner do QIX descobre `tests/{unit,integration}/*_test.gd` com base `TestCase`.
O `test_run` do addon usa outra convenção. Descobrir zero testes não aprova o jogo.

```sh
python3 -B tools/mcp/godot_mcp.py --test \
  --godot /Applications/Godot_mono.app/Contents/MacOS/Godot \
  --output /tmp/qix-test-evidence
```

A operação mantém log, JSON e avaliação em uma pasta exclusiva. Exige testes e asserções
positivos, zero falhas/erros de descoberta, saída zero e ausência de diagnósticos fatais.
Importação é uma etapa anterior; o comando acima não lança editor nem altera a convenção
da suíte. O gate completo usado no GitHub vive em `tools/ci/headless_gate.py`.

## Pipeline dos atores

`tools/assets/build_lumen_models.py` define a geometria original. A biblioteca editável
fica em `tools/assets/source/lumen_actor_library.blend`; seis GLBs entram no palco do jogo.
`tools/assets/blender_mcp_job.py` executa jobs com recibo, hashes, timeout e verificação do
artefato esperado. No POSIX, timeout/interrupção encerram o grupo do job antes da falha;
no Windows, o fallback encerra somente o processo direto. Um retorno de sucesso textual não pode esconder saída não zero do Blender.

O verificador GLB confere bytes, SHA, triângulos, acessores, índices e hierarquia. Seus limites
são independentes dos números declarados pelo próprio asset. Ele cobre o subconjunto estático
da biblioteca Lumen; modelos animados futuros exigem ampliar o contrato de validação.
Importação Godot e inspeção visual são verificações adicionais.

Antes de regenerar a biblioteca, preserve alterações manuais feitas no `.blend` e incorpore-as
ao gerador quando apropriado. A ferramenta valida o resultado, mas a reconstrução da biblioteca
ainda não usa a transação de conteúdo WAL do jogo.

## Evidência da reconciliação

O [relato de setembro/08](loop/runs/2026-09-08T-mcp-github-integration.md) registra os 33 heads
de PRs auditados, resolução por intenção, preservação do Atlas e resultados executados.
[TEST_MATRIX](TEST_MATRIX.md) contém o inventário atual da suíte; [ATLAS_VIVO](ATLAS_VIVO.md)
explica os atores, autoria, controles e apresentação 2.5D.

Conexão de editor, teste automatizado, imagem inspecionada e build de QA têm alcances distintos.
O manifesto e os recibos registram esses alcances para que uma resposta MCP não seja confundida
com prova de publicação, desempenho em hardware-alvo ou balanceamento aprovado por jogadores.
