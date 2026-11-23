"""Junta os logs do tests/net_aim_test (host e cliente) e resume a precisão.

    python tools/net_aim_report.py host.log cliente.log
Para cada tiro: posição x do bot que o cliente viu na tela x a que o
servidor usou para decidir o acerto. A cabeça tem 40 cm de largura, então um
erro maior que 20 cm faz um tiro no centro da cabeça virar erro.
"""
import re
import statistics
import sys

sv = {int(m[0]): m for m in re.findall(r"SSHOT (\d+) x=(\S+) rewind=(\d+) rtt=(\d+) hit=(\d) dmg=(\d+) moving=(\d)", open(sys.argv[1], encoding="utf-8", errors="replace").read())}
cl = {int(m[0]): m for m in re.findall(r"CSHOT (\d+) x=(\S+) pred=(\d)", open(sys.argv[2], encoding="utf-8", errors="replace").read())}
ids = sorted(set(sv) & set(cl))
if not ids:
    sys.exit("nenhum tiro em comum nos logs")
for label, want in (("bot parado", "0"), ("bot andando 7 m/s", "1")):
    rows = [i for i in ids if sv[i][6] == want]
    if not rows:
        continue
    errs = [abs(float(sv[i][1]) - float(cl[i][1])) * 100 for i in rows]
    pred = sum(int(cl[i][2]) for i in rows)
    hits = sum(int(sv[i][4]) for i in rows)
    heads = sum(1 for i in rows if int(sv[i][5]) >= 40)
    lost = sum(1 for i in rows if cl[i][2] == "1" and sv[i][4] == "0")
    print(f"== {label}: {len(rows)} tiros no centro da cabeca")
    print(f"   acerto na tela do cliente: {pred}   confirmados pelo servidor: {hits} (cabeca: {heads})")
    print(f"   acertos na tela recusados pelo servidor: {lost}")
    print(f"   diferenca de posicao (cm): media {statistics.mean(errs):.1f}  mediana {statistics.median(errs):.1f}  max {max(errs):.1f}")
    print(f"   rewind usado (ms): {statistics.mean(int(sv[i][2]) for i in rows):.0f}   rtt medido: {statistics.mean(int(sv[i][3]) for i in rows):.0f}")
