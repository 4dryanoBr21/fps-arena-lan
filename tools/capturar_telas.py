#!/usr/bin/env python3
"""Captura as telas do jogo em várias resoluções e monta uma folha de contato.

    python tools/capturar_telas.py                 (todas as telas e telas-alvo)
    python tools/capturar_telas.py menu hud        (só essas telas)
    python tools/capturar_telas.py --saida pasta   (onde salvar; padrão builds/telas)

Usa o modo --shot do jogo (scripts/main.gd): abre a tela pedida, salva a
imagem e fecha. Os perfis de celular passam --touch e --ui-dpi para simular a
densidade de pixels de um aparelho de verdade. A folha (folha.png) precisa do
Pillow; sem ele ficam só as imagens soltas.
"""
import argparse
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / "tools" / "bin" / (
    "Godot_v4.7.2-stable_win64.exe" if platform.system() == "Windows" else "Godot_v4.7.2-stable_linux.x86_64")

# nome, largura, altura, argumentos extras do jogo. A janela precisa caber no
# monitor: telas maiores entram reduzidas na mesma proporção, com o DPI reduzido
# junto (a interface escala pela altura, então o resultado é o mesmo).
PROFILES = [
    ("PC 1080p", 1920, 1080, []),
    ("PC 720p", 1280, 720, []),
    ("Ultrawide 21:9", 1890, 810, []),
    ("Monitor 4:3", 1024, 768, []),
    ("Janela pequena", 800, 500, []),
    ("Celular 20:9", 1800, 810, ["--touch", "--ui-dpi=300"]),
    ("Celular pequeno", 1520, 720, ["--touch", "--ui-dpi=320"]),
    ("Tablet", 1600, 1000, ["--touch", "--ui-dpi=200"]),
]
SCREENS = ["menu", "hud", "pause", "settings", "shop", "habits", "crosshair", "results"]
THUMB_WIDTH = 520
COLUMNS = 4


def capture(screen: str, profile: tuple, out_dir: Path) -> Path | None:
    name, width, height, extra = profile
    path = out_dir / f"{screen}_{name.replace(' ', '_').replace(':', '-')}.png"
    cmd = [str(GODOT), "--path", str(ROOT), "--resolution", f"{width}x{height}", "--",
           f"--shot={path.as_posix()}", f"--screen={screen}", f"--window={width}x{height}", *extra]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    except subprocess.TimeoutExpired:
        print(f"  {screen} / {name}: tempo esgotado")
        return None
    if "SCRIPT ERROR" in result.stdout + result.stderr:
        print(f"  {screen} / {name}: erro de script\n{result.stdout[-2000:]}{result.stderr[-2000:]}")
    return path if path.exists() else None


def contact_sheet(shots: dict, screens: list, out_dir: Path) -> None:
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Sem Pillow: imagens soltas em", out_dir)
        return
    label_h = 22
    rows = []
    for screen in screens:
        tiles = []
        for profile in PROFILES:
            path = shots.get((screen, profile[0]))
            if path is None:
                continue
            image = Image.open(path).convert("RGB")
            thumb_h = round(image.height * THUMB_WIDTH / image.width)
            # Mesma altura de célula para todos (ultrawide fica baixo, 4:3 alto).
            cell = Image.new("RGB", (THUMB_WIDTH, 300 + label_h), (24, 24, 28))
            thumb = image.resize((THUMB_WIDTH, min(thumb_h, 300)) if thumb_h <= 300
                                 else (round(image.width * 300 / image.height), 300))
            cell.paste(thumb, ((THUMB_WIDTH - thumb.width) // 2, label_h))
            ImageDraw.Draw(cell).text((6, 4), f"{screen} | {profile[0]} {profile[1]}x{profile[2]}",
                                      fill=(255, 220, 120))
            tiles.append(cell)
        if tiles:
            # Grade de COLUMNS por linha: dá para ler numa imagem só.
            cols = min(COLUMNS, len(tiles))
            lines = (len(tiles) + cols - 1) // cols
            cell_h = tiles[0].height
            row = Image.new("RGB", (THUMB_WIDTH * cols + 4 * (cols - 1), cell_h * lines + 4 * (lines - 1)), (0, 0, 0))
            for i, tile in enumerate(tiles):
                row.paste(tile, ((i % cols) * (THUMB_WIDTH + 4), (i // cols) * (cell_h + 4)))
            rows.append(row)
    if not rows:
        return
    sheet = Image.new("RGB", (max(r.width for r in rows), sum(r.height + 4 for r in rows)), (0, 0, 0))
    y = 0
    for row in rows:
        sheet.paste(row, (0, y))
        y += row.height + 4
    for screen, row in zip(screens, rows):
        row.save(out_dir / f"folha_{screen}.png")
    sheet.save(out_dir / "folha.png")
    print("Folha:", out_dir / "folha.png", "(e uma por tela: folha_<tela>.png)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("screens", nargs="*", default=SCREENS)
    parser.add_argument("--saida", default=str(ROOT / "builds" / "telas"))
    args = parser.parse_args()
    if not GODOT.exists():
        sys.exit(f"Não achei o Godot em {GODOT}")
    out_dir = Path(args.saida)
    out_dir.mkdir(parents=True, exist_ok=True)
    shots = {}
    for screen in args.screens:
        for profile in PROFILES:
            path = capture(screen, profile, out_dir)
            if path:
                shots[(screen, profile[0])] = path
        print(f"{screen}: {sum(1 for k in shots if k[0] == screen)}/{len(PROFILES)} capturas")
    contact_sheet(shots, args.screens, out_dir)


if __name__ == "__main__":
    main()
