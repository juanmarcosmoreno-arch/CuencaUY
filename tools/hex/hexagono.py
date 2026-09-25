"""Hexágono CuencaUY (formato de stickers de R, 2 × 2,31 pulgadas).

Usa el símbolo del logo oficial (docs/marca) y la tipografía del atlas.
Uso: python3 tools/hex/hexagono.py   →  man/figures/logo.png y docs/marca/cuencauy-hex*.png
Requiere Pillow.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BRAND, BRAND_DARK, INK, CREAM = "#176B60", "#0F4F47", "#172B2A", "#F5F3EE"
SS = 4                      # supermuestreo para bordes suaves
W, H = 1040, 1200           # 2 × 2,31 pulgadas a 520 ppp

def hexagon(cx, cy, r):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            for a in range(-90, 270, 60)]

def symbol():
    im = Image.open(ROOT / "docs/marca/cuencauy-logo-oficial-transparente.png").convert("RGBA")
    c = im.crop((0, 0, 500, im.height))
    mask = c.split()[-1].point(lambda v: 255 if v > 20 else 0)
    return c.crop(mask.getbbox())

def render():
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = h / 2
    border = 34 * SS
    d.polygon(hexagon(w / 2, h / 2, r), fill=BRAND)
    d.polygon(hexagon(w / 2, h / 2, r - border / math.cos(math.radians(30))), fill=CREAM)

    # Símbolo
    s = symbol()
    sh = int(0.43 * h)
    s = s.resize((round(s.width * sh / s.height), sh), Image.LANCZOS)
    img.alpha_composite(s, (round((w - s.width) / 2), round(0.15 * h)))

    # Nombre: «Cuenca» en tinta, «UY» en verde de marca
    font = ImageFont.truetype(str(ROOT / "tools/fonts/InterAtlas-SemiBold.ttf"), 112 * SS)
    a, b = "Cuenca", "UY"
    wa, wb = d.textlength(a, font=font), d.textlength(b, font=font)
    x0 = (w - wa - wb) / 2
    y = 0.635 * h
    d.text((x0, y), a, font=font, fill=INK)
    d.text((x0 + wa, y), b, font=font, fill=BRAND)

    small = ImageFont.truetype(str(ROOT / "tools/fonts/InterAtlas-Regular.ttf"), 33 * SS)
    tag = "la lechería uruguaya en el mapa"
    d.text(((w - d.textlength(tag, font=small)) / 2, 0.75 * h), tag, font=small, fill="#667773")
    return img.resize((W, H), Image.LANCZOS)

if __name__ == "__main__":
    hexa = render()
    out = ROOT / "man/figures"; out.mkdir(parents=True, exist_ok=True)
    hexa.resize((240, 277), Image.LANCZOS).save(out / "logo.png")      # tamaño que usa pkgdown
    hexa.save(ROOT / "docs/marca/cuencauy-hex.png")
    hexa.resize((520, 600), Image.LANCZOS).save(ROOT / "docs/marca/cuencauy-hex-520.png")
    print("listo")
