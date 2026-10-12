"""Generează iconul aplicației Portofel: un buzunar deschis la culoare, cu
trei carduri colorate, pe fondul imaginii de referință."""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SCALE = 4
SIZE = 1024 * SCALE
OUT = sys.argv[1] if len(sys.argv) > 1 else "."


def u(v):
    return v * SIZE


def vertical_gradient(top, bottom, size=SIZE):
    column = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        column.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return column.resize((size, size), Image.BILINEAR)


def blank():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def shadow_of(mask, dx, dy, blur, alpha):
    """Umbră neagră estompată a unei măști, deplasată cu (dx, dy)."""
    shifted = ImageChops.offset(mask, int(u(dx)), int(u(dy)))
    shifted = shifted.filter(ImageFilter.GaussianBlur(u(blur)))
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, alpha))
    layer.putalpha(shifted.point(lambda v: int(v * alpha / 255)))
    return layer


def rounded_mask(box, radius):
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([u(v) for v in box], radius=int(u(radius)), fill=255)
    return mask


def paint(canvas, mask, top, bottom):
    """Umple masca cu un gradient vertical."""
    grad = vertical_gradient(top, bottom).convert("RGBA")
    grad.putalpha(mask)
    return Image.alpha_composite(canvas, grad)


# ── Fundal ──
def glossy_background():
    """Fondul e imaginea de referință `background.png` (din același folder),
    mărită la dimensiunea iconului. Sigla din mijlocul ei rămâne ascunsă sub
    portofel; se văd doar culorile de fond."""
    import os

    ref = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "background.png"))
    base = ref.convert("RGB").resize((SIZE, SIZE), Image.BICUBIC)
    # Netezește urmele de compresie ale imaginii mici, mărite.
    return base.filter(ImageFilter.GaussianBlur(u(0.006))).convert("RGBA")


bg_mask = rounded_mask((0, 0, 1, 1), 0.22)
background = blank()
background.paste(glossy_background(), (0, 0), bg_mask)

# ── Desenul (pe strat transparent, refolosit pentru iconul adaptiv Android) ──
art = blank()

WX0, WX1 = 0.185, 0.815
WY0, WY1 = 0.245, 0.765
R = 0.075

# Spatele portofelului.
back = rounded_mask((WX0, WY0, WX1, WY1), R)
art = Image.alpha_composite(art, shadow_of(back, 0, 0.022, 0.03, 120))
art = paint(art, back, (203, 198, 187), (176, 171, 160))

# Cardurile, de la cel din spate la cel din față.
CX0, CX1 = 0.235, 0.765
cards = [
    (0.300, (21, 140, 250), (10, 118, 232)),   # albastru
    (0.365, (255, 204, 20), (250, 182, 0)),    # galben
    (0.430, (255, 96, 58), (240, 68, 38)),     # roșu-portocaliu
]
for top_y, c_top, c_bottom in cards:
    card = rounded_mask((CX0, top_y, CX1, WY1 - 0.03), 0.045)
    art = Image.alpha_composite(art, shadow_of(card, 0, -0.006, 0.008, 70))
    art = paint(art, card, c_top, c_bottom)

# Buzunarul din față, cu decupajul curbat prin care se vede cardul.
PY0 = 0.505
pocket = rounded_mask((WX0, PY0 - 0.04, WX1, WY1), R)
pd = ImageDraw.Draw(pocket)
# Partea de sus a buzunarului: colțuri mici, nu raza mare a portofelului.
pd.rectangle([u(WX0), 0, u(WX1), u(PY0) - 1], fill=0)
pd.rounded_rectangle([u(WX0), u(PY0), u(WX1), u(PY0 + 0.1)], radius=int(u(0.028)), fill=255)

DEPTH, HALF, FLAT = 0.092, 0.20, 0.36
notch = []
steps = 240
for i in range(steps + 1):
    x = 0.5 - HALF + 2 * HALF * i / steps
    t = abs(x - 0.5) / HALF
    f = 1.0 if t <= FLAT else 0.5 * (1 + math.cos(math.pi * (t - FLAT) / (1 - FLAT)))
    notch.append((u(x), u(PY0 + DEPTH * f)))
pd.polygon([(u(0.5 - HALF), u(PY0) - 4)] + notch + [(u(0.5 + HALF), u(PY0) - 4)], fill=0)
pocket = pocket.filter(ImageFilter.GaussianBlur(u(0.0012)))

art = Image.alpha_composite(art, shadow_of(pocket, 0, -0.012, 0.014, 105))
art = paint(art, pocket, (232, 228, 218), (205, 200, 189))

# Muchie luminoasă fină pe marginea de sus a buzunarului.
edge = ImageChops.subtract(pocket, ImageChops.offset(pocket, 0, int(u(0.005))))
light = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
light.putalpha(edge.point(lambda v: int(v * 0.55)))
art = Image.alpha_composite(art, light)

# Portofelul ocupă cea mai mare parte a iconului: desenul e mărit în jurul
# centrului.
ART_SCALE = 1.12
big = art.resize((int(SIZE * ART_SCALE), int(SIZE * ART_SCALE)), Image.LANCZOS)
off = (big.width - SIZE) // 2
art = big.crop((off, off, off + SIZE, off + SIZE))

# ── Ieșiri ──
FINAL = 1024
full = Image.alpha_composite(background, art).resize((FINAL, FINAL), Image.LANCZOS)
full.save(f"{OUT}/app_icon.png")

flat = Image.new("RGB", (FINAL, FINAL), (12, 2, 40))
flat.paste(Image.alpha_composite(glossy_background(), art).resize((FINAL, FINAL), Image.LANCZOS))
flat.save(f"{OUT}/app_icon_ios.png")

# Iconul adaptiv Android: același desen, micșorat în zona sigură.
adaptive = blank()
scale = 0.66
scaled = art.resize((int(SIZE * scale), int(SIZE * scale)), Image.LANCZOS)
adaptive.paste(scaled, (int((SIZE - scaled.width) / 2), int((SIZE - scaled.height) / 2)), scaled)
adaptive.resize((FINAL, FINAL), Image.LANCZOS).save(f"{OUT}/app_icon_foreground.png")

print("done")
