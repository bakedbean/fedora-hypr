#!/usr/bin/env python3
"""Generate the HYPEDORA screensaver wordmark (half-block ASCII, tte's logo.txt format).

Reuses tools/gen-plymouth-logo.py's glyph recovery/derivation/composition code (same
source ~/.local/share/omarchy/default/plymouth/logo.png, same H Y P E D O R A cell
grid) instead of duplicating it, then renders the boolean cell grid as two grid rows
per text line the way Omarchy's own logo.txt is drawn:
  both rows set    -> "█"
  top row only     -> "▀"
  bottom row only  -> "▄"
  neither          -> " " (trimmed from line ends)

`tte` (terminaltexteffects, the screensaver's animator) reads this file directly, so
the output has no color codes -- just the glyph. Deterministic: the boolean grid comes
only from the source PNG's alpha channel, no randomness.

Usage:
  tools/gen-screensaver-logo.py [--source ~/.local/share/omarchy/default/plymouth/logo.png]
                                 [--out system/usr/share/fedora-hypr/logo.txt]

Needs Pillow + numpy, same as gen-plymouth-logo.py. Without them on the host:
  podman run --rm -v "$PWD:/w:z" -v ~/.local/share/omarchy/default/plymouth:/src:ro,z \
    registry.fedoraproject.org/fedora:44 bash -c \
    'dnf -q install -y python3-pillow python3-numpy && cd /w && python3 tools/gen-screensaver-logo.py --source /src/logo.png'
"""
import argparse
import importlib.util
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def log(*a):
    print(*a, file=sys.stderr)


def load_plymouth_module():
    """Import tools/gen-plymouth-logo.py as a module (its name has a dash, so a plain
    `import` won't do it) to reuse recover_grid/segment/derive/compose verbatim."""
    path = os.path.join(HERE, "gen-plymouth-logo.py")
    spec = importlib.util.spec_from_file_location("gen_plymouth_logo", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def render_halfblock(grid):
    """Boolean (rows x cols) grid -> half-block ASCII text, two grid rows per line."""
    rows, cols = grid.shape
    lines = []
    for y in range(0, rows, 2):
        top = grid[y]
        bottom = grid[y + 1] if y + 1 < rows else np.zeros(cols, bool)
        line = []
        for x in range(cols):
            t, b = bool(top[x]), bool(bottom[x])
            if t and b:
                line.append("█")  # full block
            elif t:
                line.append("▀")  # upper half block
            elif b:
                line.append("▄")  # lower half block
            else:
                line.append(" ")
        lines.append("".join(line).rstrip())
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=os.path.expanduser("~/.local/share/omarchy/default/plymouth/logo.png"))
    ap.add_argument("--out", default="system/usr/share/fedora-hypr/logo.txt")
    ap.add_argument("--word", default="HYPEDORA")
    args = ap.parse_args()

    pl = load_plymouth_module()

    src = np.array(Image.open(args.source).convert("RGBA"))
    alpha = src[..., 3]
    grid, pitch = pl.recover_grid(alpha)
    log("source grid:")
    log(pl.ascii_art(grid))

    glyphs, gap = pl.segment(grid, "OMARCHY")
    g = {gl.name: gl for gl in glyphs}
    log(f"inter-letter gap: {gap} cells")

    pl.derive(g)

    # fidelity check: recompose the source word and compare grids (same guard as
    # gen-plymouth-logo.py's self-check, cheap to repeat here since it is pure logic)
    regrid = pl.compose(g, "OMARCHY", gap)
    if regrid.shape != grid.shape or (regrid != grid).any():
        sys.exit("recomposed OMARCHY grid differs from the source grid; glyph derivation is wrong")

    word_grid = pl.compose(g, args.word, gap)
    log(f"final wordmark {args.word}: {word_grid.shape[1]} cols x {word_grid.shape[0]} rows")
    log(pl.ascii_art(word_grid))

    lines = render_halfblock(word_grid)
    log("half-block rendering:")
    for line in lines:
        log(line)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    log(f"wrote {args.out} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
