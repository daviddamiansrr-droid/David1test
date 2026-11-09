"""Generates assets/honeycomb.png: a seamless, transparent honeycomb tile.

Upload it to Roblox (Creator Hub > Development Items > Images, or the Asset
Manager in Studio), then put the id in Config.Fence.HexTexture. Lines are white
so the Texture's Color3 tints them.

Tile covers 3 hex sides wide x sqrt(3) sides tall (flat-top hexes), which is
what Config.Fence.HexSide expects for StudsPerTileU/V.
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 96            # hex side in output pixels
SS = 4            # supersample
W = 3 * S
H = round(math.sqrt(3) * S)
LINE = 5          # line width in output pixels


def main(out):
    w, h, s = W * SS, H * SS, S * SS
    ky = h / (math.sqrt(3) * s)  # tiny vertical correction so the tile is exact
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    g = ImageDraw.Draw(glow)
    dx, dy = 1.5 * s, math.sqrt(3) * s * ky
    for c in range(-2, 4):
        for r in range(-2, 4):
            cx = c * dx
            cy = r * dy + (dy / 2 if c % 2 else 0)
            pts = [(cx + s * math.cos(math.radians(60 * k)), cy + s * math.sin(math.radians(60 * k)) * ky) for k in range(7)]
            g.line(pts, fill=(255, 255, 255, 90), width=LINE * SS * 4, joint="curve")
            d.line(pts, fill=(255, 255, 255, 255), width=LINE * SS, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(radius=6 * SS))
    out_img = Image.alpha_composite(glow, img).resize((W, H), Image.LANCZOS)
    out_img.save(out)
    print(f"wrote {out} ({W}x{H})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/honeycomb.png")
