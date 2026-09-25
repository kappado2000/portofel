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
wallet_w, wallet_h = SIZE * 0.66, SIZE * 0.48
wx0, wy0 = cx - wallet_w / 2, cy - wallet_h / 2 + SIZE * 0.05
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

# ---- Cards peeking out of the wallet, tucked under the flap ----
# Each card is drawn on its own layer, rotated, then pasted so its lower
# half sinks behind where the flap will be drawn (covering it) and only
# the top pokes out above the wallet's edge.
flap_h_preview = wallet_h * 0.42  # same value used below for the flap
card_w, card_h = wallet_w * 0.24, wallet_h * 0.4
card_specs = [
    (-12, -wallet_w * 0.20, (245, 245, 245)),   # white, left, tilted left
    (3, -wallet_w * 0.03, (179, 229, 252)),      # light blue, center
    (16, wallet_w * 0.13, (255, 224, 178)),      # soft peach, right, tilted right
]
# Cards mostly poke out ABOVE the wallet's top edge; only a small sliver at
# the bottom sinks into the flap area so it can hide the seam.
card_anchor_y = wy0 + card_h * 0.32

for angle, dx, color in card_specs:
    pad = int(max(card_w, card_h) * 0.4)
    layer_size = int(max(card_w, card_h) + pad * 2)
    card_layer = Image.new("RGBA", (layer_size, layer_size), (0, 0, 0, 0))
    cld = ImageDraw.Draw(card_layer)
    cl0 = (layer_size - card_w) / 2
    ct0 = (layer_size - card_h) / 2
    cld.rounded_rectangle(
        [cl0, ct0, cl0 + card_w, ct0 + card_h],
        radius=int(card_w * 0.14),
        fill=color,
        outline=(0, 0, 0, 40),
        width=max(1, int(SIZE * 0.002)),
    )
    # a thin accent stripe near the top of the card, like a bank card
    cld.rectangle(
        [cl0 + card_w * 0.12, ct0 + card_h * 0.16, cl0 + card_w * 0.88, ct0 + card_h * 0.24],
        fill=(0, 0, 0, 35),
    )
    rotated = card_layer.rotate(angle, resample=Image.BICUBIC, expand=False)
    paste_x = int(cx + dx - layer_size / 2)
    paste_y = int(card_anchor_y - layer_size / 2)
    canvas.paste(rotated, (paste_x, paste_y), rotated)

draw = ImageDraw.Draw(canvas)

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

# ---- Coin peeking from top-right, overlapping wallet ----
coin_r = SIZE * 0.135
coin_cx, coin_cy = wx1 - SIZE * 0.05, wy0 - SIZE * 0.02

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

# ---- Second smaller coin bottom-left of wallet for balance ----
coin2_r = SIZE * 0.075
c2x, c2y = wx0 + SIZE * 0.06, wy1 - SIZE * 0.02
draw.ellipse([c2x - coin2_r, c2y - coin2_r, c2x + coin2_r, c2y + coin2_r], fill=(255, 213, 79))
draw.ellipse(
    [c2x - coin2_r * 0.78, c2y - coin2_r * 0.78, c2x + coin2_r * 0.78, c2y + coin2_r * 0.78],
    outline=gold_dark, width=int(SIZE * 0.006),
)
try:
    font2 = ImageFont.truetype("arialbd.ttf", int(coin2_r * 1.1))
except Exception:
    font2 = ImageFont.load_default()
text2 = "L"
bbox2 = draw.textbbox((0, 0), text2, font=font2)
tw2, th2 = bbox2[2] - bbox2[0], bbox2[3] - bbox2[1]
draw.text((c2x - tw2 / 2 - bbox2[0], c2y - th2 / 2 - bbox2[1]), text2, font=font2, fill=(110, 74, 10))

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
