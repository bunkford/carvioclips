#!/usr/bin/env python3
"""Wavy flag relief bases: flat-backed STL models of a flag rippling in the wind.

One STL per flag ratio (hoist : fly). Every flag has the same hoist height, so the folds are
the same size on all of them, and the fly gets longer with the ratio. Stack flag artwork on
top of one in Carvio's 3D modelling to give any flag a waving look.

    python3 make_wavy_flags.py [out-dir]

Needs numpy and Pillow (Pillow only for the preview pictures). Writes wavy-flag-<ratio>.stl,
wavy-flag-<ratio>-outline.svg (the wavy outline as a vector, for the cut-out) and
wavy-flag-<ratio>.png for each ratio, plus all-flags.png.

The surface is built from:
  * diagonal folds running from the top near the hoist down towards the fly, bowed slightly,
    getting wider and deeper from the hoist out to the fly,
  * a fold profile with broad rounded crests and narrower creased troughs (a trochoid, the
    way cloth bends) rather than a plain sine,
  * fold-by-fold changes of depth and folds that swell and fade along their length,
  * a weaker second set of small folds that comes and goes in patches,
  * a long gentle billow over the whole flag,
and a top and bottom edge that dip a little where the cloth is pulled into a trough.
"""

import math
import os
import struct
import sys

import numpy as np

HOIST = 200.0          # flag height in mm (Y)
RIPPLE = 8.0           # crest to trough depth in mm
BASE = 3.0             # solid material under the deepest trough, mm
CELL = 1.0             # mesh spacing, mm
EDGE_WAVE = 1.2        # how far the top and bottom edges dip at a trough, mm

RATIOS = [("1x1", 1.0), ("2x3", 1.5), ("3x5", 5 / 3), ("1x2", 2.0), ("1x1.9", 1.9)]


class Waves:
    """A few smooth random cosines: low-frequency noise for warping and modulation."""

    def __init__(self, rng, n, wavelength, dims=2):
        self.k = []
        for _ in range(n):
            ang = rng.uniform(0, 2 * math.pi)
            wl = wavelength * rng.uniform(0.7, 1.4)
            amp = rng.uniform(0.6, 1.0)
            ph = rng.uniform(0, 2 * math.pi)
            if dims == 1:
                self.k.append((2 * math.pi / wl, 0.0, ph, amp))
            else:
                self.k.append((2 * math.pi / wl * math.cos(ang), 2 * math.pi / wl * math.sin(ang), ph, amp))
        self.norm = 1.0 / math.sqrt(sum(a * a for *_, a in self.k) / 2)

    def __call__(self, x, y=0.0):
        s = 0.0
        for kx, ky, ph, amp in self.k:
            s = s + amp * np.cos(kx * x + ky * y + ph)
        return s * self.norm


def trochoid(phi, k):
    """Cloth fold profile for phase phi: -1 at a crease, +1 on a crest. Solves
    phi = t - k*sin(t) so the trough at t = 0 is squeezed narrow and the crest is broad."""
    t = np.array(phi, dtype=float)
    for _ in range(12):
        t = t - (t - k * np.sin(t) - phi) / (1 - k * np.cos(t))
    return -np.cos(t)


class Flag:
    def __init__(self, width, height, seed=7):
        self.W, self.H = width, height
        rng = np.random.default_rng(seed)
        H = height
        # Fold direction: lines leaning back from the fly, about 62 degrees from horizontal.
        ang = math.radians(62)
        self.nx, self.ny = math.sin(ang), math.cos(ang)
        self.bow = 0.22                       # folds bow (curve) along their length
        self.warp = Waves(rng, 5, 0.9 * H)    # wanders the fold lines
        self.warp2 = Waves(rng, 4, 0.45 * H)
        self.foldAmp = Waves(rng, 4, 3.2, dims=1)   # depth per fold (by fold number)
        self.along = Waves(rng, 5, 0.7 * H)   # folds swell and fade along their length
        self.small = Waves(rng, 3, 0.8 * H)   # where the small folds show
        self.billow = Waves(rng, 3, 1.6 * H)
        self.l0, self.l1 = 0.15 * H, 0.23 * H     # fold wavelength at hoist and at fly
        self.umax = self.nx * width + self.ny * H

    def u(self, x, y):
        H = self.H
        yc = (y - 0.5 * H) / H
        u = self.nx * x + self.ny * y              # grows towards the fly and upwards
        u = u + self.bow * H * (yc * yc - 1 / 12)  # bowed folds
        u = u + 0.02 * H * self.warp(x, y) + 0.006 * H * self.warp2(x, y)
        return u

    def phase(self, u):
        l0, l1, um = self.l0, self.l1, self.umax
        g = (l1 - l0) / um
        uu = np.maximum(u, -0.2 * um)
        return 2 * math.pi * np.log((l0 + g * uu) / l0) / g

    def raw(self, x, y):
        x = np.asarray(x, float)
        y = np.asarray(y, float)
        H, W = self.H, self.W
        phi = self.phase(self.u(x, y))
        fold = phi / (2 * math.pi)
        amp = 1.0 + 0.28 * self.foldAmp(fold)
        amp = amp * (1.0 + 0.22 * self.along(x, y))
        # Folds grow from the hoist out to the fly, the hoist is held by the pole.
        s = np.clip(x / W, 0, 1)
        amp = amp * (0.55 + 0.45 * (1 - (1 - s) ** 2))
        z = amp * trochoid(phi, 0.25)
        # A weaker set of short folds, at a slightly steeper angle, in patches.
        phi2 = 1.7 * phi + 1.2 * (x / H)
        mask = np.clip(0.5 + 0.8 * self.small(x, y), 0, 1)
        z = z + 0.12 * mask * trochoid(phi2, 0.2) * amp
        # Long billow over the whole flag.
        z = z + 0.35 * self.billow(x, y) * (0.4 + 0.6 * s)
        return z

    def edges(self, xs):
        """Bottom and top edge Y for each column: the edges dip where the cloth folds down."""
        H = self.H
        zt = self.raw(xs, np.full_like(xs, H))
        zb = self.raw(xs, np.zeros_like(xs))
        top = H - EDGE_WAVE * np.clip((1.0 - zt) / 2.0, 0, 1.3)
        bot = EDGE_WAVE * np.clip((1.0 - zb) / 2.0, 0, 1.3)
        # Hold the corners at the hoist (the pole) square.
        hold = np.clip(xs / (0.08 * self.W), 0, 1)
        return bot * hold, top * hold + H * (1 - hold)


def build(width, height, seed=7):
    f = Flag(width, height, seed)
    nx = int(round(width / CELL)) + 1
    ny = int(round(height / CELL)) + 1
    xs = np.linspace(0, width, nx)
    bot, top = f.edges(xs)
    t = np.linspace(0, 1, ny)
    X = np.repeat(xs[None, :], ny, 0)
    Y = bot[None, :] + t[:, None] * (top - bot)[None, :]
    Z = f.raw(X, Y)
    Z = (Z - Z.min()) / (Z.max() - Z.min())
    Z = BASE + RIPPLE * Z
    return X, Y, Z


def write_stl(path, X, Y, Z):
    ny, nx = Z.shape
    top = np.stack([X, Y, Z], -1).astype(np.float32)
    bot = top.copy()
    bot[..., 2] = 0
    tris = []
    # Top surface: two triangles per cell, counter-clockwise seen from above.
    a = top[:-1, :-1].reshape(-1, 3); b = top[:-1, 1:].reshape(-1, 3)
    c = top[1:, 1:].reshape(-1, 3); d = top[1:, :-1].reshape(-1, 3)
    tris.append(np.stack([a, b, c], 1)); tris.append(np.stack([a, c, d], 1))
    # Bottom: one quad per column strip, plus fans over the hoist and fly edges.
    b0 = bot[0, :-1]; b1 = bot[0, 1:]; t1 = bot[-1, 1:]; t0 = bot[-1, :-1]
    tris.append(np.stack([b0, t1, b1], 1)); tris.append(np.stack([b0, t0, t1], 1))
    # The strip quads use only the edge rows, so the hoist and fly columns need their middle
    # vertices fanned in: replace the first and last strips with fans.
    tris[-2] = tris[-2][1:-1]; tris[-1] = tris[-1][1:-1]
    hoist = bot[:, 0]; fly = bot[:, -1]
    p = bot[0, 1]
    tris.append(np.stack([np.repeat(p[None], ny - 1, 0), hoist[:-1], hoist[1:]], 1))
    tris.append(np.array([[p, hoist[-1], bot[-1, 1]]]))
    q = bot[0, -2]
    tris.append(np.stack([np.repeat(q[None], ny - 1, 0), fly[1:], fly[:-1]], 1))
    tris.append(np.array([[q, bot[-1, -2], fly[-1]]]))
    # Walls round the outline.
    def wall(e_top, e_bot, flip):
        a, b = e_top[:-1], e_top[1:]
        c, d = e_bot[1:], e_bot[:-1]
        if flip:
            return [np.stack([a, c, b], 1), np.stack([a, d, c], 1)]
        return [np.stack([a, b, c], 1), np.stack([a, c, d], 1)]
    tris += wall(top[0, :], bot[0, :], True)      # bottom edge, faces -Y
    tris += wall(top[-1, :], bot[-1, :], False)   # top edge, faces +Y
    tris += wall(top[:, 0], bot[:, 0], False)     # hoist, faces -X
    tris += wall(top[:, -1], bot[:, -1], True)    # fly, faces +X
    T = np.concatenate(tris, 0).astype(np.float32)
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    rec = np.zeros(len(T), dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    rec["n"] = n
    rec["v"] = T
    with open(path, "wb") as fh:
        fh.write(b"Carvio wavy flag base".ljust(80, b" "))
        fh.write(struct.pack("<I", len(T)))
        fh.write(rec.tobytes())
    return T


def write_outline_svg(path, X, Y, width, height):
    """The flag's outline (wavy top and bottom edges) as a closed vector in mm, for the
    cut-out profile or for clipping artwork to the flag."""
    pts = [(X[0, i], Y[0, i]) for i in range(X.shape[1])]                 # bottom, hoist to fly
    pts += [(X[-1, i], Y[-1, i]) for i in range(X.shape[1] - 1, -1, -1)]  # top, fly to hoist
    d = "M " + " L ".join(f"{x:.3f},{height - y:.3f}" for x, y in pts) + " Z"
    with open(path, "w") as fh:
        fh.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.3f}mm" height="{height:.3f}mm"'
                 f' viewBox="0 0 {width:.3f} {height:.3f}">\n'
                 f'  <path d="{d}" fill="none" stroke="#000" stroke-width="0.2"/>\n</svg>\n')


def check_closed(T):
    """Every edge must be shared by exactly two triangles, once each way."""
    from collections import Counter
    v = np.round(T.astype(np.float64), 4)
    e = Counter()
    for i, j in ((0, 1), (1, 2), (2, 0)):
        for a, b in zip(map(tuple, v[:, i]), map(tuple, v[:, j])):
            e[(a, b)] += 1
    bad = sum(1 for (a, b), c in e.items() if c != 1 or e.get((b, a), 0) != 1)
    return bad


def shade(Z, cell, light=(-0.6, 0.45, 0.42)):
    gy, gx = np.gradient(Z, cell)
    L = np.array(light); L = L / np.linalg.norm(L)
    nz = 1 / np.sqrt(gx * gx + gy * gy + 1)
    d = (-gx * L[0] - gy * L[1] + L[2]) * nz
    return 0.3 + 0.75 * np.clip(d, 0, 1) ** 1.2


def render(X, Y, Z, width, height, scale=3.0):
    """Top-down picture with raking light, outline drawn from the mesh edges."""
    from PIL import Image, ImageDraw
    W, H = int(width * scale) + 1, int(height * scale) + 1
    # Resample the height onto a regular image grid column by column.
    xs = X[0]
    img = np.zeros((H, W))
    msk = np.zeros((H, W), bool)
    ys = (np.arange(H)[::-1] + 0.5) / scale
    fx = np.clip((np.arange(W) + 0.5) / scale / CELL, 0, len(xs) - 1.001)
    c0 = fx.astype(int)
    w1 = fx - c0
    for i in range(W):
        c = c0[i]
        za = np.interp(ys, Y[:, c], Z[:, c])
        zb = np.interp(ys, Y[:, c + 1], Z[:, c + 1])
        img[:, i] = za * (1 - w1[i]) + zb * w1[i]
        yb = Y[0, c] * (1 - w1[i]) + Y[0, c + 1] * w1[i]
        yt = Y[-1, c] * (1 - w1[i]) + Y[-1, c + 1] * w1[i]
        msk[:, i] = (ys >= yb) & (ys <= yt)
    s = shade(img[::-1], 1 / scale)[::-1]
    s = np.where(msk, 0.12 + 0.86 * s, 0)
    rgb = np.empty((H, W, 3))
    bg = np.array([58, 60, 64]) / 255
    face = np.array([236, 233, 226]) / 255
    rgb[:] = bg
    rgb[msk] = (s[msk][:, None] * face)
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    pics = []
    for name, ratio in RATIOS:
        width = HOIST * ratio
        X, Y, Z = build(width, HOIST)
        T = write_stl(os.path.join(out, f"wavy-flag-{name}.stl"), X, Y, Z)
        write_outline_svg(os.path.join(out, f"wavy-flag-{name}-outline.svg"), X, Y, width, HOIST)
        bad = check_closed(T)
        print(f"{name}: {width:.1f} x {HOIST:.1f} x {Z.max():.2f} mm, {len(T)} triangles,"
              f" open edges {bad}")
        try:
            im = render(X, Y, Z, width, HOIST)
            im.save(os.path.join(out, f"wavy-flag-{name}.png"))
            pics.append((name, im))
        except ImportError:
            pass
    if pics:
        from PIL import Image, ImageDraw, ImageFont
        pad = 60
        rows = [pics[:3], pics[3:]]
        rw = [sum(p.width for _, p in r) + pad * (len(r) + 1) for r in rows]
        Wt = max(rw)
        Ht = sum(max(p.height for _, p in r) + pad * 2 for r in rows) + pad
        sheet = Image.new("RGB", (Wt, Ht), (58, 60, 64))
        dr = ImageDraw.Draw(sheet)
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", 64)
        except OSError:
            font = ImageFont.load_default()
        y = pad
        for r, w in zip(rows, rw):
            x = (Wt - w) // 2 + pad
            h = max(p.height for _, p in r)
            for name, p in r:
                sheet.paste(p, (x, y + (h - p.height)))
                label = name.replace("x", ":")
                tw = dr.textlength(label, font=font)
                dr.text((x + (p.width - tw) / 2, y + h + 12), label, fill=(225, 225, 225), font=font)
                x += p.width + pad
            y += h + pad * 2
        sheet.save(os.path.join(out, "all-flags.png"))


if __name__ == "__main__":
    main()
