"""Generates the Slime Coin mesh + texture.

    python3 tools/make_coin.py            -> assets/coin/SlimeCoin.obj/.mtl/_tex.png

14-sided faceted coin with a bevelled rim, recessed face and a raised, puffy
slime emblem on both sides. Flat-shaded (per-face normals) for the faceted
look. Eyes/smile/highlights live in the texture.

Import: Studio > Avatar/Home > Import 3D > SlimeCoin.obj. If the texture
doesn't come through, upload SlimeCoin_tex.png and set MeshPart.TextureID.
Coin faces +Z/-Z; diameter 2 studs, thickness ~0.48 before scaling.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIDES = 14
INNER_SEG = SIDES * 4
R0, R1, R2, R3 = 1.0, 0.94, 0.80, 0.74   # outer, bevel top, rim inner, recess floor
Z_SIDE, Z_RIM, Z_FLOOR = 0.13, 0.19, 0.12
EMB_BASE, EMB_EDGE, EMB_MID, EMB_TOP = 0.12, 0.185, 0.225, 0.238
TEX = 1024
UVS = 0.48  # planar uv scale


def poly_pt(i, r, n, z, phase):
    a = phase + 2 * math.pi * i / n
    return (r * math.cos(a), r * math.sin(a), z)


# ---------------------------------------------------------------- emblem outline
def in_blob(x, y):
    body = (abs(x / 0.47) ** 2.3 + abs((y + 0.12) / 0.37) ** 2.3) <= 1 and y > -0.47
    neck = (x / 0.12) ** 2 + ((y - 0.2) / 0.15) ** 2 <= 1
    nub = x * x + (y - 0.33) ** 2 <= 0.105 ** 2
    return body or neck or nub


BLOB_C = (0.0, -0.02)


def blob_outline(n=112):
    pts = []
    for k in range(n):
        a = math.pi / 2 - 2 * math.pi * k / n  # start at top, go clockwise... then reverse below
        dx, dy = math.cos(a), math.sin(a)
        r = 0.0
        while in_blob(BLOB_C[0] + dx * (r + 0.002), BLOB_C[1] + dy * (r + 0.002)) and r < 1:
            r += 0.002
        pts.append((BLOB_C[0] + dx * r, BLOB_C[1] + dy * r))
    pts.reverse()  # counter-clockwise
    return pts


# ---------------------------------------------------------------- mesh building
verts, uvs, normals, faces = [], [], [], []


def uv_of(p, back):
    x, y = p[0], p[1]
    if back:
        x = -x
    return (0.5 + x * UVS, 0.5 + y * UVS)


def tri(a, b, c, back=False):
    """a,b,c counter-clockwise when seen from outside."""
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    l = math.sqrt(nx * nx + ny * ny + nz * nz)
    if l < 1e-12:
        return
    normals.append((nx / l, ny / l, nz / l))
    ni = len(normals)
    idx = []
    for p in (a, b, c):
        verts.append(p)
        uvs.append(uv_of(p, back))
        idx.append(len(verts))
    faces.append((idx, ni))


def quad(a, b, c, d, back=False):
    tri(a, b, c, back)
    tri(a, c, d, back)


def side(sign):
    back = sign < 0
    z = lambda v: v * sign

    def T(a, b, c):
        # flip winding on the back so faces point outward
        if back:
            tri(a, c, b, True)
        else:
            tri(a, b, c, False)

    def Q(a, b, c, d):
        T(a, b, c)
        T(a, c, d)

    ph = math.pi / 2
    outer_mid = [poly_pt(i, R0, SIDES, z(0), ph) for i in range(SIDES)]
    outer = [poly_pt(i, R0, SIDES, z(Z_SIDE), ph) for i in range(SIDES)]
    bevel = [poly_pt(i, R1, SIDES, z(Z_RIM), ph) for i in range(SIDES)]
    inner = [poly_pt(j, R2, INNER_SEG, z(Z_RIM), ph) for j in range(INNER_SEG)]
    floor = [poly_pt(j, R3, INNER_SEG, z(Z_FLOOR), ph) for j in range(INNER_SEG)]

    for i in range(SIDES):
        i2 = (i + 1) % SIDES
        Q(outer_mid[i], outer_mid[i2], outer[i2], outer[i])  # half side wall
        Q(outer[i], outer[i2], bevel[i2], bevel[i])  # bevel
        # rim top: bridge the 14-gon edge to its 4 inner circle segments
        for k in range(4):
            j, j2 = 4 * i + k, (4 * i + k + 1) % INNER_SEG
            anchor = bevel[i] if k < 2 else bevel[i2]
            T(anchor, inner[j2], inner[j])
        T(bevel[i], bevel[i2], inner[(4 * i + 2) % INNER_SEG])
    for j in range(INNER_SEG):
        j2 = (j + 1) % INNER_SEG
        Q(inner[j], inner[j2], floor[j2], floor[j])  # inner slope down to floor
    # floor disc with a hole is approximated by fanning to centre; emblem sits on top
    centre = (0, 0, z(Z_FLOOR))
    for j in range(INNER_SEG):
        j2 = (j + 1) % INNER_SEG
        T(floor[j], floor[j2], centre)

    # raised puffy emblem
    out = blob_outline()
    n = len(out)
    cx, cy = BLOB_C
    ring = lambda s, h: [(cx + (x - cx) * s, cy + (y - cy) * s, z(h)) for x, y in out]
    base = ring(1.0, EMB_BASE + 0.002)
    edge = ring(0.97, EMB_EDGE)
    mid = ring(0.72, EMB_MID)
    top = ring(0.38, EMB_TOP)
    peak = (cx, cy, z(EMB_TOP + 0.004))
    for k in range(n):
        k2 = (k + 1) % n
        Q(base[k], base[k2], edge[k2], edge[k])
        Q(edge[k], edge[k2], mid[k2], mid[k])
        Q(mid[k], mid[k2], top[k2], top[k])
        T(top[k], top[k2], peak)


# ---------------------------------------------------------------- texture
def px(x, y, s):
    return ((0.5 + x * UVS) * TEX * s, (0.5 - y * UVS) * TEX * s)


def make_texture(path):
    s = 2
    img = Image.new("RGB", (TEX * s, TEX * s), (165, 70, 235))
    d = ImageDraw.Draw(img)
    ph = math.pi / 2
    light, dark = (196, 102, 250), (158, 62, 232)
    for i in range(SIDES):
        a0 = ph + 2 * math.pi * i / SIDES
        a1 = ph + 2 * math.pi * (i + 1) / SIDES
        poly = [
            px(1.05 * math.cos(a0), 1.05 * math.sin(a0), s),
            px(1.05 * math.cos(a1), 1.05 * math.sin(a1), s),
            px(R2 * math.cos(a1), R2 * math.sin(a1), s),
            px(R2 * math.cos(a0), R2 * math.sin(a0), s),
        ]
        d.polygon(poly, fill=light if i % 2 == 0 else dark)
    # glossy rim edge line
    rim_pts = [px(R1 * math.cos(ph + 2 * math.pi * i / SIDES), R1 * math.sin(ph + 2 * math.pi * i / SIDES), s) for i in range(SIDES + 1)]
    d.line(rim_pts, fill=(235, 175, 255), width=5 * s)
    # recess
    def circle(r, fill):
        x0, y0 = px(-r, r, s)
        x1, y1 = px(r, -r, s)
        d.ellipse([x0, y0, x1, y1], fill=fill)
    circle(R2, (122, 38, 205))
    circle(R3, (128, 34, 218))
    # soft lighter band in upper half of recess
    glow = Image.new("L", img.size, 0)
    gd = ImageDraw.Draw(glow)
    x0, y0 = px(-0.6, 0.72, s)
    x1, y1 = px(0.6, 0.05, s)
    gd.ellipse([x0, y0, x1, y1], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(40 * s))
    img.paste((160, 70, 240), mask=glow)

    # blob
    outline = [px(x, y, s) for x, y in blob_outline(240)]
    d = ImageDraw.Draw(img)
    d.polygon(outline, fill=(196, 96, 250))
    shade = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(shade)
    x0, y0 = px(-0.5, -0.25, s)
    x1, y1 = px(0.5, -0.6, s)
    sd.ellipse([x0, y0, x1, y1], fill=120)
    shade = shade.filter(ImageFilter.GaussianBlur(30 * s))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    from PIL import ImageChops
    img.paste((160, 60, 232), mask=ImageChops.multiply(shade, mask))
    # gloss highlights
    hl = Image.new("L", img.size, 0)
    hd = ImageDraw.Draw(hl)
    x0, y0 = px(-0.36, 0.16, s)
    x1, y1 = px(-0.12, 0.02, s)
    hd.ellipse([x0, y0, x1, y1], fill=200)
    x0, y0 = px(-0.02, 0.41, s)
    x1, y1 = px(0.06, 0.33, s)
    hd.ellipse([x0, y0, x1, y1], fill=210)
    hl = hl.filter(ImageFilter.GaussianBlur(6 * s))
    img.paste((240, 200, 255), mask=hl)
    d = ImageDraw.Draw(img)
    # eyes
    for ex in (-0.16, 0.16):
        x0, y0 = px(ex - 0.062, -0.0, s)
        x1, y1 = px(ex + 0.062, -0.17, s)
        d.ellipse([x0, y0, x1, y1], fill=(92, 22, 150))
        x0, y0 = px(ex + 0.0, -0.025, s)
        x1, y1 = px(ex + 0.04, -0.065, s)
        d.ellipse([x0, y0, x1, y1], fill=(245, 225, 255))
    # smile
    x0, y0 = px(-0.075, -0.14, s)
    x1, y1 = px(0.075, -0.26, s)
    d.arc([x0, y0, x1, y1], start=20, end=160, fill=(92, 22, 150), width=int(0.022 * UVS * TEX * s))
    img = img.resize((TEX, TEX), Image.LANCZOS)
    img.save(path)


def write_obj(folder):
    name = "SlimeCoin"
    with open(os.path.join(folder, name + ".mtl"), "w") as f:
        f.write(f"newmtl {name}\nKa 1 1 1\nKd 1 1 1\nKs 0.3 0.3 0.3\nNs 60\nmap_Kd {name}_tex.png\n")
    with open(os.path.join(folder, name + ".obj"), "w") as f:
        f.write(f"# Slime Coin\nmtllib {name}.mtl\no {name}\n")
        for v in verts:
            f.write(f"v {v[0]:.5f} {v[1]:.5f} {v[2]:.5f}\n")
        for u in uvs:
            f.write(f"vt {u[0]:.5f} {u[1]:.5f}\n")
        for n in normals:
            f.write(f"vn {n[0]:.5f} {n[1]:.5f} {n[2]:.5f}\n")
        f.write(f"usemtl {name}\ns off\n")
        for idx, ni in faces:
            f.write("f " + " ".join(f"{i}/{i}/{ni}" for i in idx) + "\n")


def main(folder):
    os.makedirs(folder, exist_ok=True)
    side(1)
    side(-1)
    write_obj(folder)
    make_texture(os.path.join(folder, "SlimeCoin_tex.png"))
    print(f"wrote {folder}: {len(faces)} tris")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "coin"))
