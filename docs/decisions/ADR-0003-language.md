# ADR-0003 — Linguagem

**Estado:** aceita (G0, 2026-09-02)

## Contexto
O executável disponível é o build **mono** 4.7.2 e existe um starter C# na máquina. O prompt define GDScript tipado como perfil padrão de projeto novo e só usa C# se 3D/C# forem requisitos deliberados.

## Alternativas
1. **GDScript tipado** — sem `.sln`/`.csproj`, sem SDK .NET no caminho crítico, headless simples, iteração rápida via MCP (`write_or_update_file` + diagnostics).
2. C# (.NET) — tipagem forte; mas o starter documenta armadilhas reais (`.sln` obrigatório no export, `~/.dotnet` x86_64, `DOTNET_ROOT` via LaunchAgent) e o addon LimboAI não expõe tipos a C#.

## Decisão
**GDScript tipado.** Não há requisito de 2.5D nem de C#; o build mono roda GDScript sem custo. O domínio fica em `RefCounted`/`Resource` puros, testável com `--headless --script`.

## Consequências
- `class_name` exige `--import` uma vez por checkout (cache global de classes).
- Inteiros de 64 bits com wrap silencioso: o RNG mascara com `& 0xFFFFFFFF`.
- Migração futura para C# ou 2.5D substitui views, não o domínio.
