"""Generates a suggestive, polished app icon for Portofel (wallet + coin)."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math

SCALE = 4
SIZE = 1024 * SCALE

def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def vertical_gradient(size, top_color, bottom_color):
    img = Image.new("RGB", (size, size))
    for y in range(size):
        t = y / (size - 1)
        color = lerp_color(top_color, bottom_color, t)
        for x in range(size):
            img.putpixel((x, y), color)
    return img

def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask

# ---- Background: teal gradient rounded square ----
bg_grad = vertical_gradient(SIZE, (0, 121, 107), (38, 166, 154))  # teal 800 -> teal 400
bg_mask = rounded_rect_mask(SIZE, radius=int(SIZE * 0.22))
background = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
background.paste(bg_grad, (0, 0), bg_mask)

# subtle radial highlight top-left for depth
highlight = Image.new("L", (SIZE, SIZE), 0)
hd = ImageDraw.Draw(highlight)
hd.ellipse(
    [-SIZE * 0.3, -SIZE * 0.35, SIZE * 0.75, SIZE * 0.55],
    fill=60,
)
highlight = highlight.filter(ImageFilter.GaussianBlur(SIZE * 0.08))
white_layer = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
background = Image.composite(
    Image.alpha_composite(background, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))),
    background,
    bg_mask,
)
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
glow.paste(white_layer, (0, 0), highlight)
background = Image.alpha_composite(background, Image.composite(glow, Image.new("RGBA", (SIZE, SIZE), (0,0,0,0)), bg_mask))

# All wallet/card/coin artwork is drawn on a transparent "foreground" layer
# first (reused as-is for the Android adaptive icon foreground), then
# composited onto the gradient background for the full icon.
canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(canvas)

cx, cy = SIZE / 2, SIZE / 2

# ---- Wallet shadow ----
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
wallet_w, wallet_h = SIZE * 0.74, SIZE * 0.54
wx0, wy0 = cx - wallet_w / 2, cy - wallet_h / 2
sd.rounded_rectangle(
    [wx0 + SIZE * 0.02, wy0 + SIZE * 0.035, wx0 + wallet_w + SIZE * 0.02, wy0 + wallet_h + SIZE * 0.035],
    radius=int(SIZE * 0.06),
    fill=(0, 40, 35, 110),
)
shadow = shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.018))
canvas = Image.alpha_composite(canvas, shadow)
draw = ImageDraw.Draw(canvas)

# ---- Wallet body (leather brown, rounded) ----
body_color = (93, 64, 55)      # brown 700
body_light = (121, 85, 72)     # brown 500 (flap)
gold = (255, 202, 40)          # amber 400
gold_dark = (255, 179, 0)      # amber 700

wx1, wy1 = wx0 + wallet_w, wy0 + wallet_h
radius = int(SIZE * 0.06)
draw.rounded_rectangle([wx0, wy0, wx1, wy1], radius=radius, fill=body_color)

# top flap (slightly lighter, only top portion). Drawn as a fully rounded
# rect, then its bottom corners are squared off by painting over them, so
# only the top corners stay rounded and there is no seam against the body.
flap_h = wallet_h * 0.42
draw.rounded_rectangle([wx0, wy0, wx1, wy0 + flap_h], radius=radius, fill=body_light)
draw.rectangle([wx0, wy0 + flap_h - radius, wx1, wy0 + flap_h], fill=body_light)

# stitch line under flap
stitch_y = wy0 + flap_h + SIZE * 0.01
draw.line([wx0 + SIZE * 0.02, stitch_y, wx1 - SIZE * 0.02, stitch_y], fill=(60, 40, 35, 200), width=int(SIZE * 0.004))

# gold clasp (rounded rect) at center of flap edge
clasp_w, clasp_h = SIZE * 0.09, SIZE * 0.065
draw.rounded_rectangle(
    [cx - clasp_w / 2, stitch_y - clasp_h / 2, cx + clasp_w / 2, stitch_y + clasp_h / 2],
    radius=int(SIZE * 0.015),
    fill=gold_dark,
)

# ---- Tăietura din clapă prin care ies cardurile: doar o linie fină,
# întunecată — NU o formă/cutie cu colțuri rotunjite. Cardurile vor ieși
# direct din această tăietură, iar jumătatea lor de jos va fi acoperită
# (prin re-desenarea clapei peste ea), ca să pară înfipte direct în piele.
card_w, card_h = wallet_w * 0.64, wallet_h * 0.27  # carduri late (format real de card)
slit_w = wallet_w * 0.82  # mai lată decât grupul de carduri, ca să se vadă clar pe lături
slit_h = SIZE * 0.022     # mai groasă, vizibilă clar ca un buzunar, nu doar o linie
slit_color = lerp_color(body_color, (0, 0, 0), 0.55)  # maro foarte închis
slit_y = wy0 + SIZE * 0.13


def draw_slit():
    draw.rectangle(
        [cx - slit_w / 2, slit_y - slit_h / 2, cx + slit_w / 2, slit_y + slit_h / 2],
        fill=slit_color,
    )


draw_slit()

# ---- Cards ieșind direct din tăietură, ca în iconul Wallet (Portofel) de
# pe iOS: carduri DREPTE (fără înclinare), stivuite unul peste altul.
# Centrul fiecărui card e pe linia tăieturii (slit_y), astfel încât
# jumătatea de sus iese vizibil afară, iar jumătatea de jos e acoperită mai
# jos de clapă. Ordinea culorilor, de la cel mai din spate la cel din
# față: albastru, galben, portocaliu. Cardurile din spate sunt ridicate mai
# sus decât cel din față, ca să se vadă clar ieșind și pe sus, nu doar pe
# lateral (efect de evantai pe verticală, fără înclinare).
card_specs = [
    (-wallet_w * 0.055, -wallet_h * 0.045, (30, 100, 220)),  # albastru, cel mai din spate — cel mai sus
    (0, -wallet_h * 0.02, (255, 213, 79)),                   # galben, mijloc
    (wallet_w * 0.055, 0, (255, 138, 61)),                   # portocaliu, cel din față (cel mai jos)
]
card_anchor_y = slit_y

for dx, dy, color in card_specs:
    layer_w, layer_h = int(card_w * 1.3), int(card_h * 1.3)
    card_layer = Image.new("RGBA", (layer_w, layer_h), (0, 0, 0, 0))
    cld = ImageDraw.Draw(card_layer)
    cl0 = (layer_w - card_w) / 2
    ct0 = (layer_h - card_h) / 2
    # umbră sub fiecare card, ca să se vadă clar stratificarea
    cld.rounded_rectangle(
        [cl0 + SIZE * 0.006, ct0 + SIZE * 0.012, cl0 + card_w + SIZE * 0.006, ct0 + card_h + SIZE * 0.012],
        radius=int(card_w * 0.14),
        fill=(0, 0, 0, 50),
    )
    cld.rounded_rectangle(
        [cl0, ct0, cl0 + card_w, ct0 + card_h],
        radius=int(card_w * 0.14),
        fill=color,
    )

    # Pe cardul din față (portocaliu) desenăm doar cipul auriu, în partea
    # dreaptă a cardului, ca să se vadă clar că e un card.
    # NOTĂ: jumătatea de jos a cardului e acoperită mai târziu (cardul pare
    # înfipt pe jumătate în buzunar), deci cipul trebuie să încapă STRICT
    # în jumătatea de sus (local y < card_h * 0.48).
    if color == (255, 138, 61):
        chip_w, chip_h = card_w * 0.24, card_h * 0.24
        chip_x0 = cl0 + card_w * 0.56
        chip_y0 = ct0 + card_h * 0.2
        chip_color = (222, 190, 120, 255)
        cld.rounded_rectangle(
            [chip_x0, chip_y0, chip_x0 + chip_w, chip_y0 + chip_h],
            radius=int(chip_w * 0.22),
            fill=chip_color,
        )
        for i in range(1, 3):
            line_y = chip_y0 + chip_h * i / 3
            cld.line(
                [chip_x0, line_y, chip_x0 + chip_w, line_y],
                fill=(150, 120, 60, 200),
                width=max(1, int(SIZE * 0.0015)),
            )

    paste_x = int(cx + dx - layer_w / 2)
    paste_y = int(card_anchor_y + dy - layer_h / 2)
    canvas.paste(card_layer, (paste_x, paste_y), card_layer)

draw = ImageDraw.Draw(canvas)

# Re-desenăm clapa PESTE jumătatea de jos a cardurilor (aceeași culoare ca
# clapa, deci nu adaugă nicio formă vizibilă nouă) — astfel cardurile par
# să iasă direct din tăietură, nu lipite peste o cutie. Tăietura în sine nu
# e acoperită, deci rămâne vizibilă în stânga/dreapta cardurilor.
mask_top = slit_y + slit_h / 2
draw.rectangle([wx0, mask_top, wx1, wy0 + flap_h], fill=body_light)
draw = ImageDraw.Draw(canvas)

# ---- Moneda cu euro, centrată pe servietă, mai jos — ca cardurile să fie
# complet vizibile, fără să se intersecteze cu moneda ----
coin_r = SIZE * 0.12
coin_cx, coin_cy = cx, stitch_y + SIZE * 0.07

coin_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
csd = ImageDraw.Draw(coin_shadow)
csd.ellipse(
    [coin_cx - coin_r + SIZE*0.012, coin_cy - coin_r + SIZE*0.02, coin_cx + coin_r + SIZE*0.012, coin_cy + coin_r + SIZE*0.02],
    fill=(0, 30, 25, 90),
)
coin_shadow = coin_shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.012))
canvas = Image.alpha_composite(canvas, coin_shadow)
draw = ImageDraw.Draw(canvas)

draw.ellipse([coin_cx - coin_r, coin_cy - coin_r, coin_cx + coin_r, coin_cy + coin_r], fill=gold)
draw.ellipse(
    [coin_cx - coin_r * 0.8, coin_cy - coin_r * 0.8, coin_cx + coin_r * 0.8, coin_cy + coin_r * 0.8],
    outline=gold_dark, width=int(SIZE * 0.008),
)

# Euro symbol on coin
try:
    font = ImageFont.truetype("arialbd.ttf", int(coin_r * 1.15))
except Exception:
    font = ImageFont.load_default()
text = "€"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text((coin_cx - tw / 2 - bbox[0], coin_cy - th / 2 - bbox[1]), text, font=font, fill=(110, 74, 10))

# ---- Composite foreground artwork onto the gradient background ----
foreground = canvas  # wallet + cards + coins, transparent elsewhere
full = Image.alpha_composite(background, foreground)

# ---- Downscale for anti-aliasing ----
final_size = 1024
full = full.resize((final_size, final_size), Image.LANCZOS)
full.save("app_icon.png")

# Version without alpha (flat background) for iOS (no transparency allowed)
flat = Image.new("RGB", (final_size, final_size), (0, 105, 92))
flat.paste(full, (0, 0), full)
flat.save("app_icon_ios.png")

# Android adaptive icon foreground: same artwork, transparent background,
# shrunk and centered so it survives the launcher's circular/rounded crop
# (safe zone is roughly the center 66% of the canvas).
adaptive = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
scale = 0.68
scaled = foreground.resize((int(SIZE * scale), int(SIZE * scale)), Image.LANCZOS)
offset = (int((SIZE - scaled.width) / 2), int((SIZE - scaled.height) / 2))
adaptive.paste(scaled, offset, scaled)
adaptive = adaptive.resize((final_size, final_size), Image.LANCZOS)
adaptive.save("app_icon_foreground.png")

print("done")
