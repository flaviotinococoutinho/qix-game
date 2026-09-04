# ADR-0002 — Renderer

**Estado:** aceita (G0, 2026-09-02)

## Contexto
Projeto novo, 2D puro, viewport 240×320, alvos macOS (primário) e Android retrato (secundário). O prompt manda escolher pelo alvo após o preflight.

## Alternativas
1. **GL Compatibility** — OpenGL 3.3 / GLES 3.0; maior cobertura de dispositivos Android; suporta shaders de canvas e headless.
2. Mobile — Vulkan; menor cobertura em Android antigo; sem ganho para 2D pixel-art.
3. Forward+ — desktop only; descartado pelo alvo Android.

## Decisão
**GL Compatibility** em `rendering_method` e `rendering_method.mobile`. O jogo não usa nada que exija Vulkan; a máscara de revelação é um `canvas_item` shader ou `ImageTexture` atualizada por região.

## Consequências
- Verificar no G4 que o shader de máscara compila no Compatibility.
- Se surgir necessidade de recurso exclusivo do Mobile, registrar novo ADR; não trocar silenciosamente.
