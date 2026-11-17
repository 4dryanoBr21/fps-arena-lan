# FPS Arena LAN

Protótipo de FPS feito em **Godot 4.7** com arena de alvos e multiplayer em rede local (ENet).
Roda em **Windows, Linux e Android** — todos jogam juntos na mesma rede.

## Mapas
- **Arena de Alvos** — treino de mira.
- **Mata-mata: Fundição** — deathmatch entre jogadores.
- **Treino adaptativo: Fundição** — mata-mata contra bots que aprendem com você (veja abaixo).

## Treino adaptativo
O host observa, 10 vezes por segundo, como cada jogador humano se move e atira: para que lado
desvia em combate e com que ritmo troca de lado, quanto pula, agacha e corre, de que distância
atira e com que precisão (perto, médio, longe), quanto demora para reagir e onde fica em cada mapa.
Tudo roda no próprio aparelho, sem internet, com médias móveis (o costume recente pesa mais).

No Treino adaptativo (mínimo de 2 bots) os bots se alternam entre:
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

O jogador leva uma arma principal e uma secundária (teclas 1 e 2). O equipamento escolhido vale a
partir da próxima partida. O progresso fica salvo em cada aparelho (`user://progress.cfg`).
Preços, prêmios e atributos ficam em `data/game_rules.tres`, editável pelo inspetor do Godot.

## Controles
| PC | Android |
|---|---|
| WASD mover | Joystick na metade esquerda |
| Mouse mirar | Arrastar na metade direita |
| Clique esquerdo atirar | Botão vermelho (segure para atirar sem parar) |
| Espaço pular | Botão azul |
| ESC pausar | Botão de pausa ou "voltar" |

No PC dá para testar os controles de toque com `godot --path . -- --touch`.

## Como jogar em rede
1. Um jogador escolhe o mapa e toca em **Host LAN** (o IP aparece na tela).
2. Os outros digitam esse IP e entram com **Entrar (Join)**.
3. Porta padrão: **7777/UDP**. Todos precisam estar na mesma rede.

## Gerar os builds
Precisa do Godot 4.7.2 e dos templates de exportação.

```bash
./export_windows.sh            # builds/windows/FPSArenaLAN.exe
./export_linux.sh              # builds/linux/FPSArenaLAN.x86_64 (+ builds/FPSArenaLAN-linux.tar.gz)
./export_android.sh            # builds/android/FPSArenaLAN.apk
./export_android.sh --install  # gera e instala no celular via adb
```

O build Android precisa do Android SDK (`~/Android/Sdk`) e de uma chave de assinatura
(veja o cabeçalho de `export_android.sh`). Detalhes para jogadores em `LEIA-ME Windows.txt`,
`LEIA-ME Linux.txt` e `LEIA-ME Android.txt`.
