# Direção de arte — Lumen Cartography / Atlas Vivo

> **Verificado em** 2026-09-08 · commit `e8307d1` · revisão da direção na integração local Atlas + remoto
> **Alcance:** intenção visual e correspondência com os arquivos atuais; provas históricas de
> contraste permanecem datadas abaixo. A validação final da composição e a calibração humana
> estão em andamento, sem aprovação estética ou publicação inferida desta edição.

A identidade é cartografia bioluminescente: o jogador estabiliza regiões de um mapa vivo e
revela uma paisagem cósmica encoberta. Atlas acrescenta volume individual aos atores, relevo e
uma câmera ortográfica sem transferir a autoridade das células para as malhas. O desenho deve
permitir perceber território seguro, trilha vulnerável, ponto de contato e avisos de ameaça
mesmo durante capturas intensas. A [ADR-0014](decisions/ADR-0014-atlas-lifecycle-depth-stage.md)
registra a composição 2.5D; o [contrato](PROJECT_CONTRACT.md) delimita o domínio.

## Hierarquia e palco

1. A trilha é o compromisso imediato do jogador. Pulso contínuo e leitura de exposição partem
   do traço confirmado; áudio e háptica compartilham a mesma travessia do limiar de risco.
2. Jogador, chefe e inimigos menores precisam de silhuetas distintas, indicação de direção e
   contraste sobre chão seguro e livre. Pontos/sinais táticos preservam a célula de contato
   mesmo quando o volume do modelo ultrapassa essa célula.
3. Borda segura, área livre e região revelada compõem o mapa. Somente CLAIMED abre a ilustração;
   sombra, escama de metal, brilho ou perspectiva não podem fingir território conquistado.
4. Balizas são objetivos reconhecíveis separados das ameaças. Coleta confirmada comunica
   item/efeito e tempo restante; o alerta de perigo conserva prioridade sobre recompensas.
5. HUD, transições e touch ficam fora do plano tático. Texto e controles acompanham a resolução
   da janela, enquanto o espaço lógico continua 240×320.

O palco usa SubViewport tático 720×960, quad com máscara R8 e câmera ortográfica. Seis GLBs
originais representam Cartógrafo, Núcleo, Vagalume, Dardo, Brasa e Baliza. A biblioteca facetada
possui partes editáveis; escala por tipo é autorada em RoundVisualDefinition. Não há colisores
3D decidindo a partida. F2 oferece fallback plano; F4 reduz movimento do palco. Esses caminhos
precisam ser avaliados separadamente para legibilidade, sem alterar checksum.

Esta hierarquia é direção de produto. As medidas históricas abaixo cobrem cores/camadas do
fallback plano; não provam a imagem final de materiais, iluminação, projeção, movimento e
sobreposição dos GLBs. A aprovação perceptiva exige renderer real e uma pessoa jogando.

## Arco das três rodadas

| Rodada | Ambiente | Intenção | Acentos |
|---|---|---|---|
| 1 | Abyssal Relay | entrada legível, profundidade oceânica/cósmica | ciano e turquesa |
| 2 | Aurora Foundry | energia maior, formas minerais e mecânicas abstratas | âmbar e magenta |
| 3 | Verdant Singularity | clímax orgânico, núcleo verde em colapso | verde-lima e coral |

Fundos e modelos são originais do projeto. Fontes, prompts resumidos, hashes e estados de
revisão ficam em [ASSET-PROVENANCE.md](../assets/ASSET-PROVENANCE.md); a fonte Blender e o
manifest dos GLBs estão ligados em [ATLAS_VIVO.md](ATLAS_VIVO.md). Alterar um modelo não muda
seu ponto de contato e não autoriza ampliar a letalidade aparente sem revisão de gameplay.

## Atores e ciclos de vida

| Papel | Leitura necessária | Estado/aviso que sustenta essa leitura |
|---|---|---|
| Cartógrafo | localização precisa, rumo de corte, proteção e reentrada | ponto/célula, proa, escudo e arco de warmup; fragmentação ao morrer |
| Núcleo | corpo ameaçador, direção e padrão distintos | marcas WANDER/PURSUIT/SWEEP, fase, confinamento, estase e footprint letal |
| Vagalume | deslocamento pela fronteira viva | preview extraído da regra real; warmup visível, dormência distinguível |
| Dardo | preparação separada do disparo | aviso de armamento antes de ficar ativo; direção e percurso legíveis |
| Brasa | perseguição sobre a própria trilha | ignição avisada; posição do estado confirmado e dissolução ao extinguir |
| Baliza | objetivo de captura e recompensa | identidade/posição fixas, estado capturado e evento de item |

O vocabulário comum é DESPAWNED/WARMUP/ACTIVE/DORMANT/DYING. Nem todo ator usa todos os estados;
a view traduz o estado que o domínio já confirmou. Não representar warmup ou dormência como
uma ameaça já armada. IDs distinguem spawns; reusar um slot não deve conservar o visual do ator
anterior. Dissipação posterior à vitória usa a transição visual, mantendo a simulação arquivada
congelada. F3 é diagnóstico de autoria e não informação obrigatória para uma pessoa jogar.

## Contornos e direção no fallback plano

As decisões remotas de tinta foram preservadas na composição, junto de lifecycle e proxies 3D.
A [ADR-0011](decisions/ADR-0011-threat-ink-outline.md) define o anel do chefe e a
[ADR-0012](decisions/ADR-0012-cursor-ink-outline.md) define o contorno do cursor. No fallback,
o cursor mantém cruz 5×5 com tinta de 1 px, proa externa e halo; o chefe mantém losango com
anel de tinta. A tinta usa free_color: separa o corpo dos chãos claros e se funde ao chão livre.

A marca de direção do losango nasce na interseção do rumo com sua borda, incluindo diagonais;
um raio circular deixava a marca solta. No palco, os GLBs assumem o corpo e os sinais táticos
continuam presentes. Medir tinta do fallback não certifica o contorno do GLB: ambos precisam
funcionar nos estados, escalas e condições em que realmente são apresentados.

## Captura, exposição e transições

A captura é encenada sobre o foco da trilha que fechou a região, com resposta global discreta
da moldura. O foco tem piso de 24 unidades lógicas por lado e é recortado ao campo. Marcadores
ficam contidos e usam a sequência de distribuição da apresentação para evitar concentração em
larguras ressonantes; isso não consome RNG de domínio nem cria uma partícula por célula.

O foco deriva incrementalmente da trilha já observada. Sem uma trilha anterior observada,
a apresentação pode usar o campo inteiro. O brilho, a varredura e as marcas começam após
CAPTURED; nunca anunciam como certa uma captura ainda sujeita a colisão.

Intro e resultado revelam informação em ordem, mantendo a barra de tempo linear e a
continuidade de score/vidas. Pausa e painéis terminais abrem completos. A causa da morte dura
a fase DYING e termina na reentrada, incluindo causas dos atores menores. Alertas de perigo,
coleta e expiração devem ter som e forma próprios sem transformar toda tela em alarme.

## Registro histórico de contraste do campo — 2026-09-04

Medição de tools/verify_palette_contrast.gd sobre o shader plano e suas variações de scanline,
glint e extremos do pulso. Cada número registra o pior caso entre visão tricromática e as
simulações de protanopia/deuteranopia/tritanopia usadas pelo tooling. O piso adotado no projeto
é 3:1 para esses sinais não textuais. Este registro não é um ensaio do palco 3D integrado.

| Par | Padrão | Abyssal Relay | Aurora Foundry | Verdant Singularity | Meta 3:1 |
|---|---|---|---|---|---|
| `FREE`×`BOUNDARY` | 8,93 | 9,57 | 9,01 | 9,98 | ok |
| `FREE`×`TRAIL` | 11,36 | 12,37 | 11,23 | 12,87 | ok |
| `BOUNDARY`×`TRAIL` | 1,04 | 1,04 | 1,05 | 1,04 | **abaixo** |
| `FREE`×`THREAT` | 3,73 | 4,34 | 4,48 | 4,48 | ok |
| `BOUNDARY`×`THREAT` | 1,39 | 1,36 | 1,28 | 1,42 | **abaixo** |
| `TRAIL`×`THREAT` | 2,04 | 1,99 | 1,83 | 2,04 | **abaixo** |

A dívida BOUNDARY×TRAIL motivou a combinação de padrões e pulso, e permanece um ponto de revisão
humana. Os pares de corpo de ameaça sobre borda/trilha motivaram tinta, em vez de depender apenas
de matiz. Floors e KNOWN_DEBT no tooling são catracas explícitas; melhorá-los exige atualizar
expectativas e documentar a mudança, sem tratar números antigos como medição recém-executada.

## Registro histórico das camadas do cursor — 2026-09-05

Medição das camadas opacas da cruz 5×5, sem halo composto. Os números descrevem essas cores
emprestadas do campo, antes de o contorno de tinta fornecer o canal adicional de separação.
Não descrevem o material ou a luminância final do modelo 3D.

| Camada | Cor autorada | Padrão | Abyssal | Aurora | Verdant | Meta 3:1 |
|---|---|---|---|---|---|---|
| `CURSOR_OUTER`×`FREE` | `boundary_color` | 12,19 | 13,08 | 12,28 | 13,67 | ok |
| `CURSOR_ACCENT`×`FREE` | `accent_color` | 6,52 | 6,49 | 5,38 | 8,89 | ok |
| `CURSOR_CORE`×`FREE` | `trail_hot_color` | 15,33 | 16,35 | 15,99 | 15,87 | ok |
| `CURSOR_OUTER`×`BOUNDARY` | `boundary_color` | 1,00 | 1,00 | 1,00 | 1,00 | **abaixo** |
| `CURSOR_ACCENT`×`BOUNDARY` | `accent_color` | 1,37 | 1,46 | 1,65 | 1,12 | **abaixo** |
| `CURSOR_CORE`×`BOUNDARY` | `trail_hot_color` | 1,10 | 1,09 | 1,12 | 1,04 | **abaixo** |

CURSOR_OUTER×BOUNDARY é estruturalmente 1:1 quando ambos usam boundary_color. Isso não implica
que o contorno de tinta também desapareça: ele é uma camada distinta, medida no registro abaixo.
Não apresentar a dívida das três camadas como se a implementação atual dependesse só do halo.

## Registro histórico da tinta — decisões de setembro/05 e setembro/07

Cursor, medido em 2026-09-07 pelo tooling do fallback:

| Par | Padrão | Abyssal | Aurora | Verdant | Meta 3:1 |
|---|---|---|---|---|---|
| `CURSOR_INK`×`BOUNDARY` | 8,93 | 9,57 | 9,01 | 9,98 | ok |

Ameaça, derivada dos pares de free_color já registrados na medição de setembro/04 e usada na
ADR-0011 de setembro/05:

| Par | Pior razão | Pior visão | Meta 3:1 |
|---|---|---|---|
| tinta × `BOUNDARY` | 8,93 | deuteranopia | ok |
| tinta × `TRAIL` | 11,23 | protanopia | ok |
| tinta × `THREAT` | 3,73 | protanopia | ok |

As tabelas e seus alcances originais permanecem no histórico Git anterior à reconciliação,
inclusive em e8307d1:docs/ART_DIRECTION.md. Não houve remedição nesta edição documental.
A aceitação do jogo exige confirmar contornos no renderer e em movimento, não apenas comparar
triplas de cor isoladas.

## Barra de qualidade e próximos marcos

- Território, direção, warmup, dormência, perigo e objetivo distinguíveis sem depender só de matiz.
- Jogador e todos os tipos de ameaça legíveis em palco e fallback, incluindo modelos sobre
  trilha/borda/fundo revelado e em escalas autoráveis.
- Célula de contato inequívoca; nenhuma promessa visual de imunidade ou dano ausente do domínio.
- HUD e touch utilizáveis em resoluções e densidades reais; controles não escondem o próximo corte.
- Captura e transição comunicam ganho e continuidade sem encobrir o risco relevante.
- Modo de menor movimento e opções de som avaliados com pessoas; F4 hoje controla o palco,
  não representa uma certificação abrangente de acessibilidade.
- Arte, animação e áudio com proveniência, coerência por setor e revisão humana registrada.
- Trocar apresentação preserva checksum; guardas mecânicas e inspeção real se complementam.

A biblioteca atual é uma fundação original para produzir e iterar. AAA continua um objetivo de
conteúdo, arte, engenharia, acessibilidade e QA, não uma conclusão extraída de um refactor,
de modelos 3D ou de uma suíte verde. Resultados atuais e pendências estão em
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) e [TEST_MATRIX.md](TEST_MATRIX.md).
