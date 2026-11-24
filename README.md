# FPS Arena LAN

Protótipo de FPS feito em **Godot 4.7** com arena de alvos e multiplayer em rede local (ENet + WebSocket).
Roda em **Windows, Linux, Android e no navegador** — todos jogam juntos na mesma rede.

## Mapas
- **Arena de Alvos** — treino de mira.
- **Mata-mata: Fundição** — deathmatch entre jogadores.
- **Treino adaptativo** — botão próprio no menu: sozinho contra bots que aprendem com você (veja abaixo).

## Treino adaptativo
O host observa, 10 vezes por segundo, como cada jogador humano se move e atira: para que lado
desvia em combate e com que ritmo troca de lado, quanto pula, agacha e corre, de que distância
atira e com que precisão (perto, médio, longe), quanto demora para reagir e onde fica em cada mapa.
Tudo roda no próprio aparelho, sem internet, com médias móveis (o costume recente pesa mais).

O treino é isolado do mata-mata: roda só no aparelho, sem rede (não abre porta, não aparece na LAN
e ninguém entra), e só ele ensina a IA — partidas com amigos não mexem no que ela aprendeu.
Os bots (mínimo de 2) se alternam entre:
- **Caçador** — mira onde você vai estar (prevê o desvio e a troca de lado pelo seu ritmo),
  patrulha os lugares onde você mais fica e puxa a briga para a distância em que você mira pior;
- **Espelho** — se move como você (lado e ritmo do desvio, pulos, agachar, distância preferida).

A dificuldade dos bots acompanha seus duelos: sobe quando você vence e desce quando perde,
equilibrando em torno de 55% de vitórias suas. No fim de cada treino aparece uma dica, e o botão
**Hábitos (IA)** do menu mostra tudo o que a IA aprendeu (com a opção de apagar). O que a IA sabe
sobre o jogador do host fica salvo em `user://habits.cfg`; quem entra como cliente é aprendido só
durante a sessão. Código: `scripts/player_habits.gd` (modelo), `scripts/habit_tracker.gd`
(observação) e `scripts/bot_brain.gd` (comportamento).

## Arsenal e progresso
Cada partida rende **moedas** e **XP**, decididos pelo servidor:

| Ação | Moedas | XP |
|---|---|---|
| Abate | 100 | 100 |
| Abate na cabeça | 125 | 125 |
| Alvo derrubado (Arena) | 10 | 15 |
| Terminar a partida | 50 | 100 |
| 1º / 2º / 3º lugar (extra) | 200 / 120 / 80 | 200 / 120 / 80 |

O XP sobe o **nível**, que libera itens novos. No botão **Arsenal** do menu dá para:
- comprar armas: Submetralhadora, Escopeta, Fuzil de assalto e Rifle de precisão (principais),
  e Revólver (secundária). Todo mundo começa com Rifle e Pistola;
- comprar equipamento: Colete leve, Botas leves e Colete pesado (um por vez);
- melhorar cada arma em até 3 níveis (pente maior; recarga, recuo e dispersão menores; o dano não muda).

Cada arma tem um modelo low poly próprio (`scripts/weapon_models.gd`), montado com caixas e
cilindros e fundido numa malha por arma, compartilhada por todos os jogadores e pelas miniaturas
do Arsenal.

Animações (procedurais, em `scripts/weapon_animator.gd`): balanço ao andar, respiração, a arma
atrasando ao virar a mira, pose de corrida, recarga (vista também pelos outros), sacar a arma,
recuo com a força de cada arma, tranco na câmera, afundada ao aterrissar, câmera suave ao agachar
e clarão na boca do cano. Cada arma tem o próprio som de tiro, com 3 variações sorteadas a cada
disparo (gerados por `tools/generate_sfx.gd`).

O jogador leva uma arma principal, uma secundária e a **faca** (teclas 1, 2 e 3). A faca não se
compra nem se melhora: não tem munição, acerta até 2,2 m (55 de dano, ou 150 pelas costas, que
mata até de colete pesado) e deixa o jogador 20% mais rápido que com qualquer arma. O servidor
confere o alcance e o golpe pelas costas, e os bots andam de faca e a puxam quando chegam perto. O equipamento escolhido vale a
partir da próxima partida. O progresso fica salvo em cada aparelho (`user://progress.cfg`).
Preços, prêmios e atributos ficam em `data/game_rules.tres`, editável pelo inspetor do Godot.

## Tiros e hitboxes
O servidor decide cada acerto. Paredes e alvos são testados pela física; os jogadores, por
**hitboxes no formato do boneco** (`scripts/hitboxes.gd`): cabeça (dano de cabeça), tronco (dano
normal) e pernas (75%). As caixas giram com o jogador e descem quando ele agacha. A **compensação
de latência** volta cada vítima no tempo exatamente o quanto o atirador a via atrasada: um ping
inteiro mais a interpolação para clientes, nada para o host contra os bots (que ele vê no presente).
O histórico guarda posição, direção e agachamento. O traço e o som de acerto na tela de quem
atira usam as mesmas hitboxes, então o que parece acerto é acerto.

## HUD e câmera
- **Números de dano:** cada acerto mostra o dano acima da cabeça do inimigo, só para quem atirou
  (branco no corpo, amarelo na cabeça, vermelho no abate). Dá para desligar em Configurações.
- **Hotbar:** no PC fica embaixo, no centro, com as três armas, a tecla (1, 2, 3), a miniatura, o
  nome e a munição; a arma na mão fica destacada. No toque fica compacta no alto da tela e tocar
  numa vaga troca de arma. A roda do mouse também troca (para baixo = próxima).
- **Terceira pessoa (F5, ou o botão CAM no celular):** primeira pessoa → câmera atrás → câmera de
  frente. A câmera de trás encosta nas paredes e o tiro vai do olho até o ponto sob a mira.

## Interface em qualquer tela
- **Tamanho físico constante:** `scripts/ui_scale.gd` mede a densidade da tela (DPI) e aumenta a
  interface até o texto ter ~2,4 mm de altura (num monitor fica como está; num celular cresce até
  1,5×). Em **Configurações > Tamanho da interface** dá para ajustar de 75% a 150%.
- **Painéis responsivos** (`scripts/ui_fit.gd`): colunas lado a lado viram uma coluna quando falta
  largura, listas internas crescem em telas grandes e cedem altura em telas baixas, e o painel
  rola em vez de encolher até ficar ilegível.
- **Tema único** para botões, campos, listas, abas, sliders e interruptores; a ação principal de
  cada tela (Treinar, Entrar, Voltar ao jogo, Fechar) vem na cor de destaque.
- Para conferir: `python tools/capturar_telas.py` abre o jogo em 8 perfis (PC 1080p/720p,
  ultrawide, 4:3, janela pequena, celulares e tablet) e monta uma folha com as capturas.

## Desempenho
| Técnica | Como está no jogo |
|---|---|
| Frustum culling | Automático da engine (caixas das malhas calculadas pela própria Godot). |
| Occlusion culling | Oclusor gerado da geometria de cada mapa (`tools/bake_occluders.gd`): jogadores, armas, alvos e efeitos atrás das paredes não são desenhados. |
| LOD | Modelos já são low poly; barra de vida, arma dos outros e faíscas somem de longe (distância de visibilidade). Limiar de LOD das malhas sobe nas qualidades menores. |
| Static batching | O mapa é mesclado em uma malha por material (`tools/bake_maps.gd`): ~6 draw calls para o cenário inteiro. |
| Texturas | Quase não há texturas (cores sólidas); as que existem usam compressão S3TC/BPTC no PC e ETC2/ASTC no celular. |
| Sombras | Só o sol projeta sombra, com distância limitada (60 m / 35 m), 4 cascatas no Alto e 2 no Médio, borda suave só no Alto e desligada no Baixo. |
| Pós-processamento | Sem SSAO/SSR/motion blur; glow só no Alto; MSAA 2× só no Alto; escala de resolução 3D ajustável. |
| Tiros | Hitscan (raycast) com hitboxes simples de caixa por parte do corpo; nada de projétil físico. |
| Object pooling | Traços, faíscas, clarões, números de dano e players de som vêm de pools fixos. |
| Rede | Sincronização a 20 Hz, interpolação de 100 ms nos outros jogadores e volta no tempo (lag compensation) no servidor. |

Iluminação pré-calculada (lightmaps) não foi usada: o bake do LightmapGI só roda no editor e
exigiria UV2 nos mapas gerados; com um único sol, o custo de luz em tempo real já é pequeno e
desligado nas qualidades baixas. `--perf` junto do modo de captura mede objetos e draw calls com
e sem occlusion culling.

## Mira
Em **Configurações > Mira** dá para escolher um estilo pronto (cruz, cruz em T, ponto, círculo,
cruz com ponto) com cor, opacidade, tamanho, espessura, espaço no meio e contorno, ou **desenhar a
própria mira** pixel a pixel numa grade 21×21 (com espelhamento nos 4 quadrantes e borracha).
A prévia mostra o tamanho real e tudo fica salvo nas configurações. O acerto pinta a mira de
amarelo (vermelho no abate), qualquer que seja a cor escolhida.

## Controles
| PC | Android |
|---|---|
| WASD mover | Joystick na metade esquerda |
| Mouse mirar | Arrastar na metade direita |
| Clique esquerdo atirar (segure para atirar sem parar) · roda do mouse troca de arma | Botão vermelho (segure para atirar sem parar) |
| Espaço pular | Botão azul |
| ESC pausar | Botão de pausa ou "voltar" |

No PC dá para testar os controles de toque com `godot --path . -- --touch`.

## Como jogar em rede
1. Um jogador escolhe o mapa e toca em **Host LAN** (o IP aparece na tela).
2. Os outros digitam esse IP e entram com **Entrar (Join)**.
3. Porta padrão: **7777/UDP**. Todos precisam estar na mesma rede.

### Versão de navegador
- O navegador não tem UDP: ele entra na partida por **WebSocket na porta 7779/TCP** (porta do
  jogo + 2). O host (Windows, Linux ou Android) abre as duas ao mesmo tempo
  (`scripts/dual_server_peer.gd`), então app e navegador jogam juntos na mesma partida.
- O navegador **não hospeda** e não acha partidas sozinho (sem broadcast): digita-se o IP do host.
  O **Treino adaptativo** funciona sozinho no navegador.
- Sirva a página pelo PC do host com `python tools/servir_web.py` (porta 8060) e abra
  `http://IP-do-host:8060` nos outros aparelhos; o IP já vem preenchido. Página em **HTTPS**
  (site na internet) não consegue abrir `ws://` para a rede local — o navegador bloqueia.
- Build sem threads: qualquer servidor HTTP serve, sem cabeçalhos COOP/COEP.

## Gerar os builds
Precisa do Godot 4.7.2 e dos templates de exportação.

```bash
./export_windows.sh            # builds/windows/FPSArenaLAN.exe
./export_linux.sh              # builds/linux/FPSArenaLAN.x86_64 (+ builds/FPSArenaLAN-linux.tar.gz)
./export_android.sh            # builds/android/FPSArenaLAN.apk
./export_android.sh --install  # gera e instala no celular via adb
./export_web.sh                # builds/web/index.html (+ builds/FPSArenaLAN-web.zip)
```

Para publicar uma versão: gere os três builds, crie a tag `vX.Y.Z` e a Release com
`builds/FPSArenaLAN-windows.zip`, `builds/FPSArenaLAN-linux.tar.gz` e
`builds/android/FPSArenaLAN.apk` (`gh release create`). O CI só exporta e publica sozinho se a
variável do repositório `CI_RELEASE` for `true` (e com os segredos da chave Android); os builds
dele saem sem shaders pré-compilados, porque o runner não tem placa de vídeo.

O build Android precisa do Java 17, do Android SDK (`~/Android/Sdk` no Linux,
`%LOCALAPPDATA%\Android\Sdk` no Windows) e de uma chave de assinatura
(veja o cabeçalho de `export_android.sh`). Detalhes para jogadores em `LEIA-ME Windows.txt`,
`LEIA-ME Linux.txt`, `LEIA-ME Android.txt` e `LEIA-ME Web.txt`.
