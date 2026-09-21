#!/usr/bin/env python3
"""Generate the HYPEDORA Plymouth wordmark in the pixel style of the upstream logo.

Reads the upstream ``logo.png`` (800x188, blocky wordmark "OMARCHY" on transparent),
recovers its cell grid, cuts the seven glyphs, derives P/E/D from R/C/O and
composes H Y P E D O R A with the original letter spacing, colour and rendering.

Usage:
  tools/gen-plymouth-logo.py [--source ~/.local/share/omarchy/default/plymouth/logo.png]
                             [--out system/usr/share/plymouth/themes/hypedora/logo.png]
                             [--preview docs/hypedora-logo-preview.png]

Needs Pillow + numpy. Without them on the host:
  podman run --rm -v "$PWD:/w:z" -v ~/.local/share/omarchy/default/plymouth:/src:ro,z \
    registry.fedoraproject.org/fedora:44 bash -c \
    'dnf -q install -y python3-pillow python3-numpy && cd /w && python3 tools/gen-plymouth-logo.py --source /src/logo.png'

ASCII art of every glyph (source, derived, and the final wordmark) goes to stderr.
"""
import argparse
import os
import sys
from fractions import Fraction

import numpy as np
from PIL import Image

WORD = "HYPEDORA"
BG_PREVIEW = (0x1A, 0x1B, 0x26, 255)  # ConsoleLogBackgroundColor of the theme


def log(*a):
    print(*a, file=sys.stderr)


def ascii_art(mask):
    return "\n".join("".join("#" if v else "." for v in row) for row in mask)


# ---------------------------------------------------------------- grid recovery

def runs(mask):
    """Lengths of every horizontal run of set pixels."""
    out = []
    for row in mask:
        c = 0
        for v in row:
            if v:
                c += 1
            elif c:
                out.append(c)
                c = 0
        if c:
            out.append(c)
    return out


def recover_grid(alpha):
    """Return (grid bool array, pitch as a Fraction).

    The source is a cell grid that was resampled to 800x188, so the pitch is not
    an integer (81x19 cells -> 9.88 px). The shortest run gives the pitch to
    within a pixel; the exact cell count is the one for which every cell is
    uniformly opaque or uniformly transparent.
    """
    h, w = alpha.shape
    mask = alpha > 128
    approx = min(min(runs(mask)), min(runs(mask.T)))
    log(f"shortest run: {approx}px (image {w}x{h})")
    best = None
    for rows in range(round(h / approx) - 1, round(h / approx) + 2):
        for cols in range(round(w / approx) - 1, round(w / approx) + 2):
            py, px = h / rows, w / cols
            bad = 0
            grid = np.zeros((rows, cols), bool)
            for r in range(rows):
                for c in range(cols):
                    blk = alpha[int(r * py) + 2:int((r + 1) * py) - 2,
                                int(c * px) + 2:int((c + 1) * px) - 2]
                    if (blk == 255).all():
                        grid[r, c] = True
                    elif not (blk == 0).all():
                        bad += 1
            if best is None or bad < best[0]:
                best = (bad, rows, cols, grid)
    bad, rows, cols, grid = best
    if bad:
        sys.exit(f"could not find a consistent cell grid (best {rows}x{cols}, {bad} mixed cells)")
    # the pitch is the same both ways and a simple fraction (79/8 for the source)
    pitch = Fraction(w / cols).limit_denominator(16)
    log(f"cell grid: {cols} cols x {rows} rows, pitch {pitch} = {float(pitch):.4f} px "
        f"(w/cols {w / cols:.4f}, h/rows {h / rows:.4f})")
    return grid, pitch


# ---------------------------------------------------------------- glyphs

class Glyph:
    """A letter as a (rows x width) mask plus its 'body' columns.

    Cross bars (A, R, H, Y) overhang the vertical strokes by one cell into the
    inter-letter gap; letters are spaced by their body (stroke) columns, so the
    overhang is kept as a negative/extra offset and spills into the gap exactly
    as in the original.
    """

    def __init__(self, name, mask, body_start, body_end):
        self.name, self.mask = name, mask
        self.body_start, self.body_end = body_start, body_end  # inclusive, in mask columns

    @property
    def body_width(self):
        return self.body_end - self.body_start + 1

    def show(self):
        log(f"--- {self.name} ({self.mask.shape[1]} cols, body {self.body_width})")
        log(ascii_art(self.mask))


def segment(grid, letters):
    """Split the grid into glyphs (4-connected components, left to right); return
    the glyphs and the body-to-body gap width. Empty columns cannot be used: H's
    cross bar overhangs into the gap and touches the column after C."""
    rows, cols = grid.shape
    label = np.full(grid.shape, -1, int)
    comps = []
    for y0 in range(rows):
        for x0 in range(cols):
            if not grid[y0, x0] or label[y0, x0] >= 0:
                continue
            idx = len(comps)
            stack, cells = [(y0, x0)], []
            label[y0, x0] = idx
            while stack:
                y, x = stack.pop()
                cells.append((y, x))
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < rows and 0 <= nx < cols and grid[ny, nx] and label[ny, nx] < 0:
                        label[ny, nx] = idx
                        stack.append((ny, nx))
            comps.append(cells)
    comps.sort(key=lambda c: min(x for _, x in c))
    if len(comps) != len(letters):
        sys.exit(f"expected {len(letters)} glyphs, found {len(comps)} connected shapes")
    glyphs, positions = [], []
    for name, cells in zip(letters, comps):
        a, b = min(x for _, x in cells), max(x for _, x in cells)
        m = np.zeros((rows, b - a + 1), bool)
        for y, x in cells:
            m[y, x - a] = True
        # body columns: a vertical stroke spans >= 6 rows (C's arm tips are the
        # shortest); an overhanging cross bar is 2 rows, and A has two of them (4)
        body = np.where(m.sum(axis=0) >= 5)[0]
        glyphs.append(Glyph(name, m, int(body[0]), int(body[-1])))
        positions.append(a)
    # spacing is measured body-to-body: an overhanging bar narrows the raw gap
    body_gaps = []
    for i in range(len(glyphs) - 1):
        this_end = positions[i] + glyphs[i].body_end
        next_start = positions[i + 1] + glyphs[i + 1].body_start
        body_gaps.append(next_start - this_end - 1)
    log(f"glyph x offsets: {positions}; body-to-body gaps: {body_gaps}")
    if len(set(body_gaps)) != 1:
        sys.exit(f"inconsistent letter spacing: {body_gaps}")
    return glyphs, body_gaps[0]


def derive(g):
    """P from R, E from C, D from O."""
    R, C, O = g["R"], g["C"], g["O"]
    rows = R.mask.shape[0]

    # P: R without the leg. Keep everything down to the bar that closes the bowl
    # (the first row below the top where nothing is set right of the stem), then
    # only the stem down to the common baseline (last row of O).
    stem_w = 3
    stem = R.mask[:, R.body_start:R.body_start + stem_w]
    bowl_rows = [r for r in range(rows) if R.mask[r, R.body_start + stem_w:].any()]
    # bowl closes where the bar ends and the leg has not started yet (first gap in bowl rows)
    bowl_end = next(r for r in bowl_rows if r + 1 not in bowl_rows)
    baseline = max(r for r in range(rows) if O.mask[r].any())
    P = np.zeros_like(R.mask)
    P[:bowl_end + 1] = R.mask[:bowl_end + 1]
    P[bowl_end + 1:baseline + 1, R.body_start:R.body_start + stem_w] = stem[bowl_end + 1:baseline + 1]
    P = P[:, :R.body_end + 1]  # the leg was the only thing right of the body
    g["P"] = Glyph("P", P, R.body_start, R.body_end)

    # E: C plus a middle bar on the rows of H's cross bar. Like C's bottom arm and
    # R's bowl-closing bar, it stops one cell short of full width and its tip
    # tapers by one more cell on the second row.
    H = g["H"]
    mid = (H.body_start + H.body_end) // 2
    bar_rows = [r for r in range(rows) if H.mask[r, mid]]
    E = C.mask.copy()
    for i, r in enumerate(bar_rows):
        E[r, C.body_start:C.body_end - i] = True  # row 0: to body_end-1, row 1: to body_end-2
    g["E"] = Glyph("E", E, C.body_start, C.body_end)

    # D: O with the left column straightened. The stem is 3 cells wide and runs the
    # full height of O; the right side keeps O's rounded corners.
    D = O.mask.copy()
    top = min(r for r in range(rows) if O.mask[r].any())
    bottom = max(r for r in range(rows) if O.mask[r].any())
    D[top:bottom + 1, O.body_start:O.body_start + stem_w] = True
    g["D"] = Glyph("D", D, O.body_start, O.body_end)


def compose(glyphs, word, gap):
    rows = glyphs[word[0]].mask.shape[0]
    # place bodies; overhangs may go left of 0, so collect then shift
    placed, x = [], 0
    for ch in word:
        gl = glyphs[ch]
        placed.append((x - gl.body_start, gl))
        x += gl.body_width + gap
    left = min(off for off, _ in placed)
    right = max(off + gl.mask.shape[1] for off, gl in placed)
    canvas = np.zeros((rows, right - left), bool)
    for off, gl in placed:
        canvas[:, off - left:off - left + gl.mask.shape[1]] |= gl.mask
    # trim empty columns only: the row count (and so the image height and the
    # baseline the script positions the dialog under) stays the source's, even
    # when no glyph uses the top row (only M's peak does)
    xs = np.where(canvas.any(0))[0]
    return canvas[:, xs[0]:xs[-1] + 1]


# ---------------------------------------------------------------- rendering

def render(grid, color, pitch):
    """Cells -> pixels the way the source was made.

    The source cell pitch is 79/8 px: each output pixel's alpha is the exact area
    fraction covered by set cells (an edge pixel that straddles a cell boundary
    gets 1/8, 3/8 ... coverage). Reproduce that exactly: paint the grid at
    pitch.numerator px per cell, then box-average pitch.denominator^2 blocks.
    """
    n, d = pitch.numerator, pitch.denominator
    rows, cols = grid.shape
    big = np.repeat(np.repeat(grid, n, axis=0), n, axis=1).astype(np.float64)
    out_h, out_w = -(-rows * n // d), -(-cols * n // d)  # ceil
    padded = np.zeros((out_h * d, out_w * d))
    padded[:big.shape[0], :big.shape[1]] = big
    cov = padded.reshape(out_h, d, out_w, d).mean(axis=(1, 3))
    rgba = np.zeros((out_h, out_w, 4), np.uint8)
    rgba[..., :3] = color[:3]
    rgba[..., 3] = np.round(cov * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default=os.path.expanduser("~/.local/share/omarchy/default/plymouth/logo.png"))
    ap.add_argument("--out", default="system/usr/share/plymouth/themes/hypedora/logo.png")
    ap.add_argument("--preview", default="docs/hypedora-logo-preview.png")
    ap.add_argument("--word", default=WORD)
    args = ap.parse_args()

    src = np.array(Image.open(args.source).convert("RGBA"))
    alpha = src[..., 3]
    grid, pitch = recover_grid(alpha)
    color = tuple(int(v) for v in src[alpha == 255].reshape(-1, 4)[0])
    log(f"foreground RGBA: {color}")
    log("source grid:")
    log(ascii_art(grid))

    glyphs, gap = segment(grid, "OMARCHY")
    g = {gl.name: gl for gl in glyphs}
    log(f"inter-letter gap: {gap} cells")
    for gl in glyphs:
        gl.show()

    derive(g)
    for name in "PED":
        g[name].show()

    # fidelity check: recompose the source word and compare with the source image
    regrid = compose(g, "OMARCHY", gap)
    if regrid.shape != grid.shape or (regrid != grid).any():
        log("recomposed grid:")
        log(ascii_art(regrid))
        sys.exit("recomposed OMARCHY grid differs from the source grid")
    check = render(regrid, color, pitch)
    if check.size != tuple(reversed(alpha.shape)):
        sys.exit(f"recomposed OMARCHY is {check.size}, source is {alpha.shape[::-1]}")
    diff = np.abs(np.array(check)[..., 3].astype(int) - alpha.astype(int))
    flipped = ((np.array(check)[..., 3] > 127) != (alpha > 127)).mean()
    log(f"recomposed OMARCHY vs source: mean alpha diff {diff.mean():.2f}/255, "
        f"{flipped:.2%} of pixels flip at 50% alpha (the source's cell edges jitter by "
        f"a fraction of a pixel; anything under 1% is the same picture)")
    if diff.mean() > 3 or flipped > 0.01:
        sys.exit("recomposition does not match the source; grid recovery is wrong")

    word = compose(g, args.word, gap)
    log(f"final wordmark {args.word}: {word.shape[1]} cols x {word.shape[0]} rows")
    log(ascii_art(word))

    out = render(word, color, pitch)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    out.save(args.out, optimize=True)
    log(f"wrote {args.out} ({out.size[0]}x{out.size[1]})")

    if args.preview:
        big = out.resize((out.size[0] * 2, out.size[1] * 2), Image.NEAREST)
        pad = 40
        bg = Image.new("RGBA", (big.size[0] + 2 * pad, big.size[1] + 2 * pad), BG_PREVIEW)
        bg.alpha_composite(big, (pad, pad))
        os.makedirs(os.path.dirname(args.preview), exist_ok=True)
        bg.convert("RGB").save(args.preview, optimize=True)
        log(f"wrote {args.preview}")


if __name__ == "__main__":
    main()
