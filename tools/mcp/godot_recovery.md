# Godot AI do QIX: launcher, diagnóstico e recuperação

A integração do projeto vive em `tools/mcp/godot_mcp.py` e `godot_runtime.py`, fora do inventário assinado de `addons/godot_ai`. O launcher fixa **Godot AI 4.0.2**, preserva as opções de resolução uv oficiais e usa **HTTP 8001 / WebSocket 9501**. As entradas `godot-ai` de `.mcp.json` e `.codex/config.toml` chamam o mesmo launcher.

## Uso reproduzível

Execute o cliente com a pasta do repositório como diretório de trabalho: os argumentos dos arquivos MCP são relativos a essa pasta. São necessários um `python3` existente no PATH e uma instalação existente de `uvx`. O launcher procura primeiro `QIX_GODOT_UVX`/`--uvx`, depois PATH, instalações de usuário/Homebrew e caches uv. Não instala o executável uv. Ao iniciar stdio, o uv pode resolver o pacote Python fixado no cache; o diagnóstico e o dry-run não fazem instalação nem iniciam servidor/editor.

```sh
python3 -B tools/mcp/godot_mcp.py --print-command
python3 -B tools/mcp/godot_mcp.py --doctor
python3 -B tools/mcp/godot_mcp.py
```

O último comando é o servidor **stdio** para o cliente MCP. Não acrescente impressão de banners no stdout. Falhas/orientações vão para stderr. Overrides de fonte/intérprete/cache `UV_*`, `PYTHONPATH` e `PYTHONHOME` são removidos apenas do subprocesso uv, sem alterar o ambiente global. Origem PyPI, versão e ausência de builds são explícitas no argv.

`--doctor` consulta somente loopback, sem redirects, com limite de resposta e timeout. Usa a capability HTTP privada oficial, inclusive para o status autenticado do v4. Faz initialize/resources-read de `godot://sessions` e encerra somente a sessão HTTP criada pelo próprio diagnóstico. Relatórios omitem tokens, nonce, PID, package_path e corpos de erro. Só retorna exit 0 se servidor/plugin forem 4.0.2, WebSocket for 9501 e houver sessão `ready` de **este caminho de projeto** com plugin 4.0.2. Isso não valida testes nem comprova a execução de gameplay.

Para inspecionar o endpoint legado sem alterá-lo:

```sh
python3 -B tools/mcp/godot_mcp.py --doctor --port 8000 --ws-port 9500
```

## Portas: cliente por projeto, configuração do editor global

O plugin 4.0.2 lê as portas exclusivamente de **EditorSettings** (`client_configurator.gd:79–105`):

- `godot_ai/http_port`
- `godot_ai/ws_port`

Essas duas preferências são **globais para a instalação/perfil de editor**. O setting `godot_ai/mcp_client_scope=project` afeta o arquivo do cliente, não isola portas do editor. Não criar settings homônimos em `project.godot`: o plugin não os lê. O doctor declara essa distinção no campo `plugin_port_settings_scope`.

Em 2026-09-08, o root autorizou 8001/9501 para o editor atual, mantendo o servidor legado 3.2.4 em 8000/9500 e seus 11 bridges. Antes da alteração, as duas propriedades (presença e valor) foram salvas em `/tmp/qix-godot-ports-before-20260908.json`. O root aplicou a mudança via Fennara em `mode=edit`, usando uma cena pequena apenas como contexto, sem marcar/salvar a cena. O helper oficial `addons/godot_ai/utils/plugin_reload.gd::reload_enabled_plugin()` retornou OK e `get_open_scenes()` permaneceu igual. Este registro não implica que todos os clientes externos já foram recarregados.

Procedimento para outra máquina:

1. Garantir que 8001/9501 estejam livres ou correspondam ao servidor 4.0.2 pretendido. Inspecionar antes de qualquer ação; não matar um ocupante por número de porta.
2. Ler e guardar somente as duas propriedades via `EditorInterface.get_editor_settings()`, `has_setting()` e `get_setting()`. Preservar presença para um rollback exato; não copiar configurações ou segredos completos do usuário para o projeto.
3. Configurar `set_setting("godot_ai/http_port", 8001)` e `set_setting("godot_ai/ws_port", 9501)`. EditorSettings salva automaticamente. O efeito é global; outro projeto aberto depois usa essas preferências até novo ajuste.
4. Aplicar pelo Reload Plugin do dock ou pelo helper oficial `reload_enabled_plugin()`. Ele faz disable/enable e persiste o estado de habilitação, sem fechar o editor nem as cenas. Nunca usar o modo `inspect` do Fennara para essa escrita. Um worker de edição precisa ter o Resource EditorSettings como alvo explícito, contexto seguro e guard do caminho do projeto; não chamar `ctx.mark_modified()`.
5. Recarregar a entrada MCP no cliente para usar o launcher do projeto. Confirmar `--doctor`: servidor 4.0.2, endpoint 8001, ws9501, sessão QIX pronta. A configuração de um processo MCP já iniciado não muda só porque o TOML/JSON foi editado.

Rollback: ler o backup, restaurar cada propriedade com `set_setting` quando `present=true`, ou removê-la com `erase` quando ausente originalmente; reaplicar o reload oficial. Restaurar também os dois argumentos de porta do launcher/configuração usados pelo cliente se a decisão for voltar ao endpoint anterior. Reverter portas não atualiza um servidor legado para v4.

Isolamento completo de EditorSettings entre projetos exige outro perfil/instalação de editor. Godot documenta modo self-contained; XDG_CONFIG_HOME é suporte Linux/BSD, não uma promessa de isolamento no macOS. Não modificar o bundle assinado compartilhado para improvisar isolamento. [Documentação Godot de caminhos](https://docs.godotengine.org/en/latest/tutorials/io/data_paths.html).

## Por que não substituir cegamente o 3.2.4

A auditoria identificou servidor 3.2.4 `owner_type=attach`, zero sessões de editor, 11 leases e **nenhum capability record v4** para porta8000. O fluxo Replace do plugin v4 exige registro privado, nonce autenticado e prova do processo (`server_lifecycle.gd:1094–1133`); sem isso, o endpoint antigo é classificado como ocupado/externo. Não assumir que Restart Server estará autorizado só porque o nome e a versão aparecem no status.

O caminho de encerramento normal do v3 é feito pelos clientes proprietários dos leases: desconectar cada bridge executa `LeaseClient.close()`, que libera o próprio lease. Heartbeat padrão10s, TTL30s. O servidor attach arma um reaper que considera sessões de editor + leases; com ambos zerados, o grace padrão120s e polling5s levam ao encerramento automático. Variáveis de opt-out/grace podem alterar isso; não foram lidas do processo. Não inventar lease IDs nem liberar leases alheios. Esta migração escolheu portas novas para continuar trabalhando sem interromper os 11 bridges.

Fontes primárias: código Python3.2.4 instalado (`attach/lease.py`, `orphan_reaper.py`, `server.py`), [migração v4](https://github.com/hi-godot/godot-ai/blob/v4.0.2/docs/v4-migration.md), [release4.0.2](https://github.com/hi-godot/godot-ai/releases/tag/v4.0.2).

## Suíte QIX: contrato independente do test_run do addon

O MCP `test_run` procura `tests/test_*.gd` estendendo McpTestSuite. QIX usa `tests/{unit,integration}/*_test.gd` estendendo TestCase. O resultado MCP `total=0` não aprova QIX. Não renomear suítes nem trocar sua base para contornar essa diferença.

O runner `tests/run_tests.gd` oferece `--json PATH` após o separador `--`. A integração explícita do projeto conserva log/JSON/assessment em uma pasta exclusiva por execução, fora do projeto, e limita o processo ao timeout. Ela **não faz import** nem inicia gameplay/editor.

```sh
python3 -B tools/mcp/godot_mcp.py --test \
  --godot /Applications/Godot_mono.app/Contents/MacOS/Godot \
  --output /tmp/qix-test-evidence --timeout 300

python3 -B tools/mcp/godot_mcp.py --test \
  --godot /Applications/Godot_mono.app/Contents/MacOS/Godot \
  --filter actor_presentation --output /tmp/qix-test-evidence
```

O JSON exige `schema_version:1`, `total`, `assertions`, `failures` e `discovery_errors` como inteiros. Aprovação exige total>0, assertions>0, failures=0, discovery_errors=0, exit0 e nenhum ERROR/SCRIPT ERROR/SHADER ERROR/USER ERROR no log. Timeout, JSON ausente/malformado e resultado antigo nunca viram aprovação. Somente um coordenador deve executar import/engine/export; o wrapper não prova que outro operador não iniciou Godot em paralelo.

## Validação da integração

```sh
python3 -B -m unittest discover -s tools/mcp -p test_godot_mcp.py -v
```

As 21 regressões Python passaram em 2026-09-08: resolução, política uv, capability privada, HTTP/SSE, sessão de projeto, omissão de segredos, zero testes, erros de engine e processo artificial com timeout. Elas não executam Godot. O root centraliza a validação da suíte real, reconexão v4 e recibos MCP de leitura de cenas/GLBs. Não tratar esta suíte Python como aceite visual ou de gameplay.

## Recibo de conexão real em 2026-09-08

Após alterar as portas, o servidor4.0.2 já respondia, mas a sessão de editor permanecia ausente: o plugin estava DORMANT, `normal_start_released=false`, aguardando o botão oficial **Retry client migration**. O banner dizia `claude_code status failed: probe timed out`. O probe Claude tem limite6s; uma leitura posterior do CLI no projeto concluiu em5,18s com Scope Project/Status Connected. Não se modificou esse limite no vendor.

Com autorização do root, preservaram-se9arquivos de configuração existentes entre27caminhos reconhecidos/projetados, em diretório privado `qix-godot-client-backup-20260908-836wyf0y` sob o diretório temporário do macOS. O manifesto contém caminhos, hashes e cópias600; o diretório é700. O retry foi solicitado pela mesma API do botão, `_on_dock_post_update_action_requested("retry")`, com guard do projeto e comprovação de backup. Nenhum estado de autoridade, marcador de migração ou `_release_normal_startup` foi manipulado para contornar a barreira.

A migração oficial alterou somente entradas `godot-ai` em6configurações globais: Claude Desktop, Codex, Antigravity, VSCode, Gemini CLI e OpenCode. A comparação estrutural contra os backups comprovou preservação dos demais campos em todos6arquivos; `.mcp.json` e `.codex/config.toml` do projeto, incluindo Blender e o launcher próprio, ficaram idênticos aos backups.

O doctor então retornou `ready`, servidor/plugin4.0.2, HTTP8001/WS9501, sessão do caminho exato QIX e gameplay parado. Um recibo em `/tmp/qix-20260908-godot-readonly-receipt.json` conserva as leituras MCP de sessão/editor, hierarquia de `app/bootstrap.tscn` (9nós) e dos6GLBs originais (`surveyor`, `core`, `walker`, `dart`, `ember`, `beacon`), todos carregados como PackedScene. As8operações finais concluíram sem erro. O recibo também conserva uma tentativa anterior da hierarquia com argumento incorreto, corrigida para o `depth` previsto pelo schema; essa tentativa não alterou o editor.

Essa evidência comprova a conexão e a leitura de recursos importados pelo editor. Não substitui validação visual, testes de gameplay ou export, que continuam sob coordenação do root.
