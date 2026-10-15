#!/usr/bin/env python3
"""Approaches to the Monolith: a night chart of an estuary whose sands are the
directories of a source tree.

Each top-level directory with enough files is a sandbank, fanned across the
estuary in path order. Along a bank its subdirectories follow in path order:
the bank is broad where a subdirectory holds many files and shoals where its
files lie near the root. Smaller directories are knolls in the channels
between, and the files at the root are rocks awash at the head of the
estuary. The land sits under the shell's widget columns.
"""
import argparse
import json
import math
import os
import tempfile

LOGICAL_W, LOGICAL_H = 1800.0, 1125.0
GRID = 2.0

DIM = "#52616b"
SHOAL = "#0d1a20"
DRYING = "#10241f"


def rgb(h, a=None):
    h = h.lstrip("#")
    c = tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return c if a is None else c + (a,)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", required=True)
    p.add_argument("--width", type=int, default=2880)
    p.add_argument("--height", type=int, default=1800)
    p.add_argument("--src", required=True, help="the source tree to survey")
    p.add_argument("--rev", required=True, help="the revision the tree was taken at")
    p.add_argument("--palette", required=True,
                   help="JSON file of the shell palette: page, raised, text, muted and accentSoft")
    p.add_argument("--font", action="append", default=[],
                   help="EB Garamond 12 Italic, 12 Regular and SC 12 Regular font files")
    return p.parse_args()


def setup_fonts(paths):
    """Expose exactly the given font files to cairo through a private fontconfig."""
    d = tempfile.mkdtemp(prefix="wallpaper-fonts-")
    for f in paths:
        os.symlink(os.path.abspath(f), os.path.join(d, os.path.basename(f)))
    conf = os.path.join(d, "fonts.conf")
    with open(conf, "w") as fh:
        fh.write('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">'
                 f"<fontconfig><dir>{d}</dir><cachedir>{d}/cache</cachedir></fontconfig>")
    os.environ["FONTCONFIG_FILE"] = conf
    from PIL import ImageFont
    roles = {}
    for f in paths:
        fam, style = ImageFont.truetype(f, 12).getname()
        role = "sc" if fam.endswith(" SC") else "italic" if "Italic" in style else "roman"
        roles.setdefault(role, fam)
    missing = {"sc", "italic", "roman"} - set(roles)
    if missing:
        raise SystemExit(f"missing fonts for: {', '.join(sorted(missing))}")
    return roles


def survey(src):
    rows = []
    for d, dirs, files in os.walk(src):
        dirs[:] = [x for x in dirs if x != ".git"]
        for f in files:
            p = os.path.join(d, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            with open(p, "rb") as fh:
                head = fh.read(8192)
            if b"\0" in head:
                continue
            rows.append(os.path.relpath(p, src).split("/"))
    rows.sort()
    return rows


def fbm1(n, length, seed, rough=0.62, longest=360.0, shortest=2.5, closed=False):
    """Fractal offsets along a path, one octave per halving of wavelength."""
    import numpy as np
    from scipy.interpolate import CubicSpline
    r = np.random.default_rng(seed)
    out = np.zeros(n)
    xs = np.linspace(0, length, n)
    wl, amp = longest, 1.0
    while wl >= shortest:
        k = max(2, int(math.ceil(length / wl)))
        knots = r.standard_normal(k + 4)
        if closed:
            knots[-4:] = knots[:4]
        out += amp * CubicSpline(np.arange(k + 4) * wl, knots)(xs)
        wl /= 2
        amp *= rough
    return out


def coast_path(points, seed, amp, closed=False, **kw):
    import numpy as np
    from scipy.interpolate import CubicSpline
    pts = np.array(points, float)
    if closed:
        pts = np.vstack([pts, pts[:1]])
    s = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])
    n = int(s[-1] / 0.8)
    t = np.linspace(0, s[-1], n)
    cs = CubicSpline(s, pts, bc_type="periodic" if closed else "natural")
    p = cs(t)
    tan = cs(t, 1)
    tan /= np.hypot(tan[:, 0], tan[:, 1])[:, None]
    nor = np.stack([-tan[:, 1], tan[:, 0]], 1)
    off = fbm1(n, s[-1], seed, closed=closed, **kw)
    if closed:
        off -= np.linspace(0, 1, n) * (off[-1] - off[0])
    return p + nor * (off * amp)[:, None]


def islet(cx, cy, r, seed, stretch=1.0, angle=0.0):
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for i in range(9):
        t = 2 * math.pi * i / 9
        x, y = r * stretch * math.cos(t), r * math.sin(t)
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return coast_path(pts, seed, r * 0.22, closed=True, longest=r * 2.5, shortest=1.2)


def main():
    args = parse_args()
    with open(args.palette) as fh:
        palette = json.load(fh)
    PAGE, RAISED, TEXT, MUTED, ACCENT_SOFT = (palette[k] for k in ("page", "raised", "text", "muted", "accentSoft"))
    fonts = setup_fonts(args.font)
    import numpy as np
    from scipy import ndimage as ndi
    from skimage import measure, draw
    import cairo

    W, H = args.width, args.height
    scale = max(W / LOGICAL_W, H / LOGICAL_H)
    ox = (W - LOGICAL_W * scale) / 2
    oy = (H - LOGICAL_H * scale) / 2
    gw, gh = int(LOGICAL_W / GRID) + 1, int(LOGICAL_H / GRID) + 1
    ii, jj = np.mgrid[0:gh, 0:gw].astype(float)
    X, Y = jj * GRID, ii * GRID

    # Land: a long western shore ending in a peninsula, under the left
    # widget column, and a headland under the to-do list.
    west = coast_path([(395, -40), (432, 40), (478, 118), (452, 196), (392, 262), (350, 340),
                       (338, 430), (352, 520), (398, 590), (380, 668), (362, 742), (402, 812),
                       (488, 866), (602, 902), (716, 918), (770, 948), (742, 986), (650, 1004),
                       (590, 1046), (612, 1102), (660, 1170)], 4, 13.0)
    west_poly = np.vstack([[[-60, 1200]], west[::-1], [[-60, -60]]])[::-1]
    east = coast_path([(1392, -40), (1384, 90), (1400, 190), (1370, 300), (1384, 402),
                       (1446, 456), (1540, 470), (1612, 512), (1700, 528), (1860, 560)], 9, 12.0)
    east_poly = np.vstack([east, [[1880, -60]]])
    islets = [islet(842, 978, 13, 21, 1.5, 0.5), islet(882, 1006, 5, 22), islet(903, 1024, 3.5, 23),
              islet(1322, 492, 10, 24, 1.4, -0.3), islet(1290, 522, 4.5, 25),
              islet(528, 250, 7, 26, 1.3, 1.0)]
    rocks = [(918, 1040), (930, 1053), (1272, 540), (1263, 553), (546, 268)]

    def raster(poly):
        rr, cc = draw.polygon(poly[:, 1] / GRID, poly[:, 0] / GRID, (gh, gw))
        m = np.zeros((gh, gw), bool)
        m[rr, cc] = True
        return m

    land = raster(west_poly) | raster(east_poly)
    for p in islets:
        land |= raster(p)
    dist = ndi.distance_transform_edt(~land) * GRID

    # The tree.
    rows = survey(args.src)
    tops = {}
    root_files = []
    for parts in rows:
        if len(parts) == 1:
            root_files.append(parts[0])
            continue
        sub = parts[1] if len(parts) > 2 else ""
        tops.setdefault(parts[0], {}).setdefault(sub, []).append(len(parts) - 1)
    size = {name: sum(len(v) for v in subs.values()) for name, subs in tops.items()}
    banks = [n for n in sorted(tops) if size[n] >= 150]
    knolls = [n for n in sorted(tops) if size[n] < 150]

    # The estuary opens from the north-west; its sands run with the stream.
    rng = np.random.default_rng(5)
    apex = np.array([-700.0, -1300.0])
    th_lo, th_hi = math.radians(35.5), math.radians(63.5)

    def bend(r):
        return 0.05 * ((r - 2400) / 1000.0) ** 2

    def at(r, th):
        a = th + bend(r)
        return apex[0] + r * np.cos(a), apex[1] + r * np.sin(a)

    def smooth_noise(seed, octaves):
        nr = np.random.default_rng(seed)
        out = np.zeros((gh, gw))
        for s_, a_ in octaves:
            base = nr.standard_normal((int(gh * GRID / s_) + 3, int(gw * GRID / s_) + 3))
            out += a_ * ndi.zoom(base, s_ / GRID, order=3)[:gh, :gw]
        return out

    # The sands are drawn on a gently warped plane so no two are alike.
    warp_x = 14 * smooth_noise(31, ((110, 1.0), (45, 0.4)))
    warp_y = 14 * smooth_noise(32, ((110, 1.0), (45, 0.4)))
    Xw, Yw = X + warp_x, Y + warp_y
    r = np.hypot(Xw - apex[0], Yw - apex[1])
    th = np.arctan2(Yw - apex[1], Xw - apex[0]) - bend(r)
    channel = 4.0 + 12.0 * np.clip((r - 1500) / 1700, 0, 1)
    depth = channel.copy()
    weights = np.array([math.log(1 + size[n]) for n in banks])
    edges = th_lo + (th_hi - th_lo) * np.concatenate([[0], np.cumsum(weights)]) / weights.sum()
    sands = []
    for k, name in enumerate(banks):
        subs = tops[name]
        lo, hi = edges[k], edges[k + 1]
        mid = 0.5 * (lo + hi) + rng.normal(0, 0.08) * (hi - lo)
        half = 0.5 * (hi - lo) * (0.42 + 0.5 * rng.random())
        r0 = 1650 + 450 * rng.random()
        r1 = r0 + 250 + 95 * math.log(size[name])
        ph1, ph2 = rng.random(2) * 2 * math.pi
        skew = 0.75 + 0.5 * rng.random()
        curl = rng.normal(0, 0.03)
        keys = sorted(subs)
        seg = np.array([math.log(2 + len(subs[s])) for s in keys])
        cuts = np.concatenate([[0], np.cumsum(seg)]) / seg.sum()
        centres = 0.5 * (cuts[:-1] + cuts[1:])
        target = np.array([np.mean(subs[s]) - 2.3 for s in keys])
        breadth = 0.45 + 0.75 * seg / seg.max()

        def wob(rr, half=half, ph1=ph1, ph2=ph2, curl=curl):
            return (half * (0.35 * np.sin(rr / 190.0 + ph1) + 0.15 * np.sin(rr / 71.0 + ph2))
                    + curl * ((rr - 2300) / 1000.0) ** 2)

        t = (r - r0) / (r1 - r0)
        tc = np.clip(t, 0, 1)
        across = (th - mid - wob(r)) / (half * np.interp(tc, centres, breadth))
        across = np.where(across > 0, across / skew, across * skew)
        env = np.sin(tc * math.pi) ** 0.5 * (t > 0) * (t < 1)
        h = np.exp(-np.abs(across) ** 2.2 * 1.4) * env
        depth = np.minimum(depth, channel - (channel - np.interp(tc, centres, target)) * h)
        sands.append(dict(name=name, mid=mid, r0=r0, r1=r1, wob=wob, centres=centres,
                          breadth=breadth, half=half))

    # Small directories lie between the sands as knolls.
    for name in knolls:
        left = [s for s in sands if s["name"] < name]
        right = [s for s in sands if s["name"] > name]
        a = left[-1]["mid"] if left else th_lo
        b = right[0]["mid"] if right else th_hi
        kth = 0.5 * (a + b) + rng.normal(0, 0.1) * (b - a)
        kr = 1750 + 900 * rng.random()
        kx, ky = at(kr, kth)
        ka = kth + bend(kr) + rng.normal(0, 0.12)
        rad = 9 + 4.5 * math.sqrt(size[name])
        tgt = np.mean([d for v in tops[name].values() for d in v]) - 2.3
        u = (Xw - kx) * math.cos(ka) + (Yw - ky) * math.sin(ka)
        v = (Yw - ky) * math.cos(ka) - (Xw - kx) * math.sin(ka)
        hump = np.exp(-(u / (1.9 * rad)) ** 2 - (v / (0.75 * rad)) ** 2)
        depth = np.minimum(depth, channel - (channel - tgt) * hump)

    # The files at the root are rocks awash at the head of the estuary.
    roots = []
    rr_ = np.random.default_rng(13)
    while len(roots) < len(root_files):
        x, y = 610 + 34 * rr_.standard_normal(), 104 + 15 * rr_.standard_normal()
        if not (60 < y < 170) or dist[int(y / GRID), int(x / GRID)] < 30:
            continue
        if all((x - a) ** 2 + (y - b) ** 2 > 10.5 ** 2 for a, b in roots):
            roots.append((x, y))
    foul = np.full((gh, gw), 1e9)
    for x, y in roots:
        foul = np.minimum(foul, np.hypot(X - x, Y - y))
    foul = ndi.gaussian_filter(foul, 2.0)

    depth = depth + 0.35 * smooth_noise(8, ((90, 0.5), (36, 0.25)))
    shore = 1 - np.exp(-dist / 45.0)
    depth = np.minimum(depth, depth * shore - 0.35 + 0.35 * shore)
    depth = ndi.gaussian_filter(depth, 1.6)
    depth[land] = -4

    # Tints, rasterised at output resolution.
    FY, FX = np.meshgrid((np.arange(H) - oy) / scale / GRID, (np.arange(W) - ox) / scale / GRID,
                         indexing="ij")
    D = ndi.map_coordinates(depth, [FY, FX], order=1, mode="nearest")
    del FY, FX
    gmag = np.hypot(*np.gradient(D)) + 1e-6
    img = np.empty((H, W, 3), np.float32)
    img[:] = rgb(PAGE)
    for level, col in ((2, SHOAL), (0, DRYING)):
        a = np.clip(0.5 + (level - D) / gmag, 0, 1)[..., None]
        img += (np.array(rgb(col), np.float32) - img) * a
    del D, gmag

    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
    buf = np.ndarray((H, W, 4), np.uint8, surf.get_data())
    u8 = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    buf[..., 0], buf[..., 1], buf[..., 2], buf[..., 3] = u8[..., 2], u8[..., 1], u8[..., 0], 255
    surf.mark_dirty()
    del img, u8, buf
    g = cairo.Context(surf)
    g.translate(ox, oy)
    g.scale(scale, scale)
    g.set_line_join(cairo.LINE_JOIN_ROUND)
    g.set_line_cap(cairo.LINE_CAP_ROUND)

    def path(pts, close=False):
        g.move_to(*pts[0])
        for x, y in pts[1:]:
            g.line_to(x, y)
        if close:
            g.close_path()

    def contour_lines(f, level, min_len=10):
        return [np.stack([c[:, 1] * GRID, c[:, 0] * GRID], 1)
                for c in measure.find_contours(f, level) if len(c) >= min_len]

    def face(role, size):
        g.select_font_face(fonts[role], cairo.FONT_SLANT_ITALIC if role == "italic" else cairo.FONT_SLANT_NORMAL,
                           cairo.FONT_WEIGHT_NORMAL)
        g.set_font_size(size)

    busy = np.zeros((gh, gw), bool)

    def occupy(cx, cy, w, h, angle=0.0, pad=4.0, test=False):
        ca, sa = math.cos(angle), math.sin(angle)
        corners = [(-w / 2 - pad, -h / 2 - pad), (w / 2 + pad, -h / 2 - pad),
                   (w / 2 + pad, h / 2 + pad), (-w / 2 - pad, h / 2 + pad)]
        xs = [cx + x * ca - y * sa for x, y in corners]
        ys = [cy + x * sa + y * ca for x, y in corners]
        rr, cc = draw.polygon(np.array(ys) / GRID, np.array(xs) / GRID, (gh, gw))
        hit = busy[rr, cc].any()
        if not test:
            busy[rr, cc] = True
        return hit

    def tracked(text, size, tracking):
        face("italic", size)
        widths = [g.text_extents(ch).x_advance for ch in text]
        return widths, sum(widths) + tracking * size * (len(text) - 1)

    def show_tracked(text, cx, cy, angle, size, tracking, col, alpha):
        widths, total = tracked(text, size, tracking)
        g.save()
        g.translate(cx, cy)
        g.rotate(angle)
        g.set_source_rgba(*rgb(col, alpha))
        x = -total / 2
        for ch, w in zip(text, widths):
            g.move_to(x, size * 0.32)
            g.show_text(ch)
            x += w + tracking * size
        g.restore()
        return total

    # Keep the bar, the widget hint and the title block clear.
    busy[: int(42 / GRID), :] = True
    busy[int(1080 / GRID):, int(1405 / GRID):] = True
    tx, ty = 1505, 868
    title = [("sc", "Graphide", 11, MUTED, 0.95, 0),
             ("roman", "Approaches to the Monolith", 27, TEXT, 0.78, 32),
             ("italic", f"from a survey of the source tree at {args.rev}", 10.5, MUTED, 0.95, 52),
             ("italic", f"{len(rows):,} files sounded".replace(",", " "), 10.5, MUTED, 0.95, 66),
             ("italic", "Soundings in fathoms and feet. Each sand is a directory, laid down in path", 9.2, DIM, 1.0, 88),
             ("italic", "order, and shoals where its files lie nearest the root.", 9.2, DIM, 1.0, 100)]
    occupy(tx, ty + 46, 400, 125, 0, 6)

    # Names go on the sands first; everything else keeps clear of them.
    def unwarp(x, y):
        px, py = x, y
        for _ in range(3):
            c = [[py / GRID], [px / GRID]]
            px = x - float(ndi.map_coordinates(warp_x, c, order=1, mode="nearest")[0])
            py = y - float(ndi.map_coordinates(warp_y, c, order=1, mode="nearest")[0])
        return px, py

    names = []
    for sand in sands:
        n = size[sand["name"]]
        word = "Sand" if n >= 2000 else "Bank" if n >= 500 else "Shoal"
        label = f"{sand['name'][0].upper()}{sand['name'][1:]} {word}"
        fs = 7.0 + 1.55 * math.log10(n)
        _, total = tracked(label, fs, 0.14)
        cands = []
        for t in np.linspace(0.15, 0.85, 36):
            rr = sand["r0"] + t * (sand["r1"] - sand["r0"])
            x, y = unwarp(*at(rr, sand["mid"] + sand["wob"](rr)))
            x2, y2 = unwarp(*at(rr + 6, sand["mid"] + sand["wob"](rr + 6)))
            ang = math.atan2(y2 - y, x2 - x)
            if ang > math.pi / 2:
                ang -= math.pi
            elif ang < -math.pi / 2:
                ang += math.pi
            ex, ey = 0.5 * total * math.cos(ang), 0.5 * total * math.sin(ang)
            if all(400 < px < 1370 and 70 < py < 1050 and dist[int(py / GRID), int(px / GRID)] > 14
                   for px, py in ((x - ex, y - ey), (x + ex, y + ey))):
                score = np.interp(t, sand["centres"], sand["breadth"]) - 1.5 * abs(t - 0.5)
                cands.append((score, x, y, ang))
        for _, x, y, ang in sorted(cands, reverse=True):
            if not occupy(x, y, total, fs, ang, 3, test=True):
                occupy(x, y, total, fs, ang, 3)
                names.append((label, x, y, ang, fs))
                break

    # Contour labels go in gaps cut in the lines, as on the engraved charts.
    styles = {0: ([], 0.45, ACCENT_SOFT, 0.4),
              2: ([0.01, 1.8], 0.75, ACCENT_SOFT, 0.45),
              5: ([6, 1.8, 0.01, 1.8, 0.01, 1.8], 0.55, ACCENT_SOFT, 0.36),
              10: ([9, 3.2], 0.5, MUTED, 0.36)}
    contours = {lv: contour_lines(np.where(land, -4, depth), lv, 14) for lv in styles}
    labels = []
    for lv in (5, 10):
        for c in contours[lv]:
            seg = np.hypot(*np.diff(c, axis=0).T)
            s = np.concatenate([[0], np.cumsum(seg)])
            if s[-1] < 260:
                continue
            for frac in (0.3, 0.7) if s[-1] > 900 else (0.5,):
                k = int(np.searchsorted(s, frac * s[-1]))
                k = min(max(k, 3), len(c) - 4)
                x, y = c[k]
                if not (380 < x < 1380 and 60 < y < 1060) or busy[int(y / GRID), int(x / GRID)]:
                    continue
                dx, dy = c[k + 3] - c[k - 3]
                ang = math.atan2(dy, dx)
                if ang > math.pi / 2:
                    ang -= math.pi
                elif ang < -math.pi / 2:
                    ang += math.pi
                if occupy(x, y, 9, 7, ang, 2):
                    continue
                labels.append((lv, c, s[k], x, y, ang))

    def gaps(c, lv):
        cut = np.zeros(len(c), bool)
        s = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(c, axis=0).T))])
        for lv2, c2, s0, *_ in labels:
            if lv2 == lv and c2 is c:
                cut |= np.abs(s - s0) < 7.5
        pieces, start = [], None
        for i, flag in enumerate(cut):
            if not flag and start is None:
                start = i
            if flag and start is not None:
                pieces.append(c[start:i])
                start = None
        if start is not None:
            pieces.append(c[start:])
        return [p for p in pieces if len(p) > 1]

    # Land.
    g.set_source_rgb(*rgb(RAISED))
    for p in [west_poly, east_poly] + islets:
        path(p, True)
    g.fill()

    # Waterlining, the engraver's echo of the shore.
    shoreline = np.where(land, 0, dist)
    for k, off in enumerate((3.5, 8.0, 13.5, 20.0)):
        for c in contour_lines(shoreline, off, 6):
            path(c)
            g.set_line_width(0.45)
            g.set_source_rgba(*rgb(ACCENT_SOFT, 0.20 * (1 - k / 4.6)))
            g.stroke()

    # Depth contours in the old dot-and-dash code.
    for lv, (dash, lw, col, a) in styles.items():
        for c in contours[lv]:
            for piece in gaps(c, lv):
                path(piece)
                g.set_dash(dash)
                g.set_line_width(lw)
                g.set_source_rgba(*rgb(col, a))
                g.stroke()
    g.set_dash([])
    face("italic", 7.6)
    for lv, c, s0, x, y, ang in labels:
        g.save()
        g.translate(x, y)
        g.rotate(ang)
        e = g.text_extents(str(lv))
        g.move_to(-e.x_advance / 2, 2.6)
        g.set_source_rgba(*rgb(ACCENT_SOFT, 0.55))
        g.show_text(str(lv))
        g.restore()

    # Coastline.
    for p in [west, east] + islets:
        path(p)
        g.set_line_width(0.9)
        g.set_source_rgba(*rgb(MUTED, 0.85))
        g.stroke()

    # Rocks: a cross for those that never dry, dotted when awash.
    def rock(x, y, awash):
        g.set_line_width(0.6)
        g.set_source_rgba(*rgb(MUTED, 0.85))
        for a in (0, math.pi / 2):
            g.move_to(x - 3.2 * math.cos(a), y - 3.2 * math.sin(a))
            g.line_to(x + 3.2 * math.cos(a), y + 3.2 * math.sin(a))
        g.stroke()
        if awash:
            for q in range(4):
                t = math.pi / 4 + q * math.pi / 2
                g.arc(x + 2.6 * math.cos(t), y + 2.6 * math.sin(t), 0.45, 0, 2 * math.pi)
                g.fill()
        occupy(x, y, 8, 8, 0, 3)

    for x, y in rocks:
        rock(x, y, True)
    for x, y in roots:
        rock(x, y, True)
    for c in contour_lines(foul, 12.0, 6):
        path(c)
        g.set_dash([0.01, 2.0])
        g.set_line_width(0.8)
        g.set_source_rgba(*rgb(MUTED, 0.7))
        g.stroke()
        g.set_dash([])
    busy |= foul < 16
    rx = max(x for x, _ in roots) + 18
    ry = float(np.mean([y for _, y in roots]))
    face("italic", 10)
    g.set_source_rgba(*rgb(MUTED, 0.9))
    g.move_to(rx, ry + 3.5)
    g.show_text("The Roots")
    occupy(rx + 24, ry, 50, 12, 0, 3)

    # Names along the sands.
    for label, x, y, ang, fs in names:
        show_tracked(label, x, y, ang, fs, 0.14, MUTED, 0.9)

    # Title block.
    for role, text, fs, col, alpha, dy in title:
        face(role, fs)
        e = g.text_extents(text)
        g.move_to(tx - e.x_advance / 2, ty + dy)
        g.set_source_rgba(*rgb(col, alpha))
        g.show_text(text)

    # Soundings, closer together in shoal water and kept off the lines.
    srng = np.random.default_rng(1)
    gmag_c = np.hypot(*np.gradient(depth)) / GRID + 1e-6
    placed = {}
    bucket = 24.0
    face("italic", 9.5)
    for x, y in srng.random((60000, 2)) * [LOGICAL_W, LOGICAL_H]:
        i, j = int(y / GRID), int(x / GRID)
        if land[i, j] or dist[i, j] < 7 or busy[i, j]:
            continue
        dv = depth[i, j]
        if min(abs(dv - lv) for lv in styles) / gmag_c[i, j] < 6:
            continue
        rad = 17 + 2.6 * max(dv, 0) + 0.04 * max(dist[i, j] - 60, 0)
        bi, bj = int(x // bucket), int(y // bucket)
        if any((qx - x) ** 2 + (qy - y) ** 2 < max(rad, qr) ** 2
               for a in range(bi - 3, bi + 4) for b in range(bj - 3, bj + 4)
               for qx, qy, qr in placed.get((a, b), ())):
            continue
        placed.setdefault((bi, bj), []).append((x, y, rad))
        whole = int(math.floor(abs(dv)))
        feet = int(math.floor((abs(dv) - whole) * 6))
        face("italic", 9.5)
        s = str(whole)
        e = g.text_extents(s)
        g.set_source_rgba(*rgb(MUTED, 0.8))
        g.move_to(x - e.x_advance / 2, y + 3)
        g.show_text(s)
        if feet and whole < 11:
            face("italic", 6.5)
            g.move_to(x + e.x_advance / 2 + 0.2, y + 5.2)
            g.show_text(str(feet))
        if dv < 0:
            g.set_line_width(0.45)
            g.move_to(x - e.x_advance / 2 - 0.5, y + 5.2)
            g.line_to(x + e.x_advance / 2 + 0.5, y + 5.2)
            g.stroke()

    surf.write_to_png(args.out)


if __name__ == "__main__":
    main()
