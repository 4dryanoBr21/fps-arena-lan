# FPS Arena LAN

Protótipo de FPS feito em **Godot 4.7** com arena de alvos e multiplayer em rede local (ENet).
Roda em **Windows, Linux e Android** — todos jogam juntos na mesma rede.

## Mapas
- **Arena de Alvos** — treino de mira.
- **Mata-mata: Fundição** — deathmatch entre jogadores.

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
./export_android.sh            # builds/android/FPSArenaLAN.apk
./export_android.sh --install  # gera e instala no celular via adb
```

O build Android precisa do Android SDK (`~/Android/Sdk`) e de uma chave de assinatura
(veja o cabeçalho de `export_android.sh`). Detalhes para jogadores em `LEIA-ME Windows.txt`
e `LEIA-ME Android.txt`.
