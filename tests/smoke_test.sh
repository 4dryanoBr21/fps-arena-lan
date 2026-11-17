#!/usr/bin/env bash
# Teste de fumaça de rede, sem janela: sobe um host com 2 bots no mata-mata e
# um cliente que entra pela rede local; confere que o cliente conectou, que o
# mapa está no caminho que os RPCs esperam (World/Map), que o equipamento do
# Arsenal do cliente chegou ao host e que houve combate.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-./tools/bin/Godot_v4.7.2-stable_linux.x86_64}"
LOGS="$(mktemp -d)"
trap 'rm -rf "$LOGS"' EXIT

"$GODOT" --headless --path . -- --host --bots=2 --map=1 --name=Host --quit-after=30 > "$LOGS/host.log" 2>&1 &
HOST_PID=$!
sleep 4
"$GODOT" --headless --path . -- --join=127.0.0.1 --name=Cliente --loadout=smg,revolver,heavy_vest --quit-after=22 > "$LOGS/client.log" 2>&1
wait "$HOST_PID" || true

fail() { echo "FALHOU: $1"; echo "--- host"; cat "$LOGS/host.log"; echo "--- cliente"; cat "$LOGS/client.log"; exit 1; }
grep -q "SCRIPT ERROR" "$LOGS/host.log" "$LOGS/client.log" && fail "erro de script"
grep -q "LOCAL_PLAYER_SPAWNED" "$LOGS/client.log" || fail "jogador do cliente não apareceu"
grep -q "RESULT online=true role=Cliente map_ok=true" "$LOGS/client.log" || fail "cliente não terminou conectado com o mapa em World/Map"
grep -q "Cliente:" "$LOGS/client.log" || fail "apelido do cliente não chegou ao placar"
# A lista de equipamentos que o cliente usa vem do servidor: achar o dele
# aqui prova a ida (cliente -> servidor) e a volta (servidor -> todos).
grep -q "Cliente=smg+revolver+heavy_vest" "$LOGS/client.log" || fail "equipamento do cliente não voltou do servidor"
DEATHS=$(grep -o "deaths=[0-9]*" "$LOGS/client.log" | head -1 | cut -d= -f2)
[[ "${DEATHS:-0}" -gt 0 ]] || fail "nenhuma morte em 20 s (bots não lutaram?)"
echo "OK: cliente conectou, mapa em World/Map, $DEATHS morte(s) registradas."
grep -h "SCORES\|LOADOUTS" "$LOGS/client.log"

# Treino adaptativo: o host, no piloto automático, desvia mais para a direita
# (75% do tempo) e atira nos bots. A IA precisa perceber o lado do desvio e
# contar os tiros. (Paredes travam parte do desvio, então o viés medido varia
# de rodada para rodada; o texto das dicas é coberto em tests/unit_tests.gd.)
"$GODOT" --headless --path . -- --host --map=2 --bots=3 --name=Host --autopilot --quit-after=55 > "$LOGS/training.log" 2>&1
tfail() { cat "$LOGS/training.log"; echo "FALHOU: $1"; exit 1; }
grep -q "SCRIPT ERROR" "$LOGS/training.log" && tfail "erro de script no treino"
grep -q "Caçador 1" "$LOGS/training.log" || tfail "bots de treino sem personalidade"
HABITS=$(grep -o "HABITS .*" "$LOGS/training.log")
BIAS=$(echo "$HABITS" | sed -E 's/.*bias=(-?[0-9.]+).*/\1/')
SHOTS=$(echo "$HABITS" | sed -E 's/.*shots=([0-9]+).*/\1/')
awk -v b="$BIAS" 'BEGIN { exit !(b > 0.1) }' || tfail "a IA não percebeu o desvio para a direita ($HABITS)"
[[ "${SHOTS:-0}" -gt 0 ]] || tfail "a IA não contou os tiros ($HABITS)"
echo "OK: treino adaptativo aprendeu ($HABITS)."
grep -h "HABITS_TIP" "$LOGS/training.log"
