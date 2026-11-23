"""Proxy UDP que atrasa os pacotes, para simular ping de internet em testes.

Escuta em OUVIR:PORTA e repassa para DESTINO:PORTA com ATRASO ms em cada
sentido (ida e volta = 2x ATRASO). Feito para o ENet do jogo:
    python tools/proxy_latencia.py --ouvir 127.0.0.2 --destino 127.0.0.1 --porta 7777 --atraso 40
e o cliente entra em 127.0.0.2. --jitter soma um atraso aleatório de 0..J ms.
"""
import argparse
import heapq
import random
import select
import socket
import time

ap = argparse.ArgumentParser()
ap.add_argument("--ouvir", default="127.0.0.2")
ap.add_argument("--destino", default="127.0.0.1")
ap.add_argument("--porta", type=int, default=7777)
ap.add_argument("--atraso", type=float, default=40.0)
ap.add_argument("--jitter", type=float, default=0.0)
ap.add_argument("--duracao", type=float, default=120.0)
a = ap.parse_args()

front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
front.bind((a.ouvir, a.porta))
back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
back.bind((a.ouvir, 0))
client_addr = None
fila = []  # (hora de sair, seq, socket, dados, destino)
seq = 0
fim = time.monotonic() + a.duracao
print(f"proxy {a.ouvir}:{a.porta} -> {a.destino}:{a.porta}, {a.atraso} ms por sentido", flush=True)


def agenda(sock, dados, dest):
    global seq
    atraso = a.atraso + random.uniform(0, a.jitter)
    heapq.heappush(fila, (time.monotonic() + atraso / 1000.0, seq, sock, dados, dest))
    seq += 1


while time.monotonic() < fim:
    espera = 0.001
    if fila:
        espera = max(0.0, min(espera, fila[0][0] - time.monotonic()))
    prontos, _, _ = select.select([front, back], [], [], espera)
    for s in prontos:
        try:
            dados, origem = s.recvfrom(65536)
        except ConnectionResetError:
            # Windows: "porta inacessível" de um pacote anterior; ignora.
            continue
        if s is front:
            client_addr = origem
            agenda(back, dados, (a.destino, a.porta))
        elif client_addr is not None:
            agenda(front, dados, client_addr)
    agora = time.monotonic()
    while fila and fila[0][0] <= agora:
        _, _, sock, dados, dest = heapq.heappop(fila)
        sock.sendto(dados, dest)
