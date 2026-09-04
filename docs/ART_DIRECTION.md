# Direção de arte — Lumen Cartography

O G2 usa uma identidade original de **cartografia bioluminescente**: o jogador não
“pinta” uma chapa sólida; ele estabiliza regiões de um mapa vivo e revela uma paisagem
cósmica que estava encoberta. A leitura do estado continua imediata mesmo em 240×320.

## Hierarquia visual

1. `TRAIL` é o elemento de maior luminância e pulsa entre amarelo e branco. O pulso **não é
   constante**: acelera e ergue o piso de luminância conforme a trilha se afasta da moldura
   (`TrailExposure`), de modo que a exposição seja legível antes do impacto. O aviso viaja por
   frequência e brilho, nunca por matiz.
2. Jogador e chefe têm silhuetas compactas, núcleos contrastantes e leitura em 1×.
3. `BOUNDARY` desenha o contorno seguro em ciano/verde.
4. `CLAIMED` revela a ilustração original da rodada.
5. `FREE` permanece sob uma cobertura azul-noturna para proteger a legibilidade.
6. HUD e overlays vivem fora do campo e não escondem decisões de movimento.

## Arco das três rodadas

| Rodada | Ambiente | Intenção | Acentos |
|---|---|---|---|
| 1 | Abyssal Relay | entrada legível, profundidade oceânica/cósmica | ciano e turquesa |
| 2 | Aurora Foundry | energia maior, formas minerais e mecânicas abstratas | âmbar e magenta |
| 3 | Verdant Singularity | clímax orgânico, núcleo verde em colapso | verde-lima e coral |

Todas as imagens são composições originais geradas para este projeto, sem personagens,
marcas ou material extraído de ROM. Fontes, prompts resumidos, dimensões, hash e estado
de aprovação ficam em `assets/ASSET-PROVENANCE.md`.

## Barra de qualidade do slice

- Sem texto embutido, assinatura, watermark ou IP de terceiros.
- Fundo válido exatamente em 225×283, sem crop em runtime.
- Estados territoriais distinguíveis por forma, cor e luminância — cor não é o único
  canal para ameaça e segurança.
- Mudanças de rodada têm intro, resultado, confirmação opcional e continuidade clara de
  score/vidas.
- Feedback de captura nasce de eventos confirmados e nunca antecipa resultado do domínio.
- A apresentação pode ser trocada sem alterar checksum ou compatibilidade de replay.

“AAA” neste marco é uma barra de coesão, resposta, legibilidade e mensuração do vertical slice.
O shipping pass acrescenta áudio e feedback, mas o termo ainda não afirma escala de conteúdo,
QA multiplataforma concluído, validação humana/física ou prontidão comercial.
