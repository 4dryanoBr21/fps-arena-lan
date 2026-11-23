#!/usr/bin/env python3
"""Serve a versão de navegador (builds/web) na rede local.

Rode no PC que vai hospedar a partida:
    python tools/servir_web.py            (porta 8060)
    python tools/servir_web.py 9000       (outra porta)
e abra nos outros aparelhos o endereço http://IP-DO-PC:8060 que ele mostra.
O IP do host já vem preenchido no menu do jogo.

Por que HTTP e não HTTPS: uma página HTTPS não pode abrir ws:// (conexão sem
criptografia) para o IP da rede local; o navegador bloqueia. Servida por HTTP
na própria LAN, a página conecta direto no jogo do host.
"""
import functools
import http.server
import socket
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "builds" / "web"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        # Sem cache: depois de exportar de novo, o navegador pega a versão nova.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        if args and str(args[1]).startswith(("4", "5")):
            super().log_message(fmt, *args)


def lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def main() -> None:
    if not (ROOT / "index.html").exists():
        sys.exit(f"Não achei {ROOT / 'index.html'}. Rode ./export_web.sh antes.")
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), functools.partial(Handler, directory=str(ROOT)))
    print(f"Versão de navegador em http://{lan_ip()}:{PORT}  (neste PC: http://localhost:{PORT})")
    print("Crie a partida no jogo deste PC (Windows/Linux) e abra o endereço nos outros aparelhos.")
    print("Ctrl+C para parar.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
