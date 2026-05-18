from PIL import Image, ImageDraw, ImageFont
import random, os

OUT  = r"C:\Users\1\Desktop\high-tech\trivia_master\screen shots\feature_graphic.jpg"
W, H = 1024, 500

img  = Image.new("RGB", (W, H))
draw = ImageDraw.Draw(img)

# ── Gradient background ────────────────────────────────────────────────
for y in range(H):
    t = y / H
    r = int(4  + t * 8)
    g = int(8  + t * 18)
    b = int(40 + t * 55)
    draw.line([(0, y), (W, y)], fill=(r, g, b))

# ── Stars ─────────────────────────────────────────────────────────────
random.seed(7)
for _ in range(260):
    x  = random.randint(0, W)
    y  = random.randint(0, H)
    sz = random.choice([1, 1, 1, 1, 2])
    br = random.randint(150, 255)
    draw.ellipse([x-sz, y-sz, x+sz, y+sz], fill=(br, br, br))

# ── Soft glow left ────────────────────────────────────────────────────
for r in range(160, 0, -1):
    a = int(18 * (1 - r/160))
    c = (10 + a, 50 + a*2, 180 + a)
    draw.ellipse([160-r, 250-r, 160+r, 250+r], fill=c)

# ── Soft glow right ───────────────────────────────────────────────────
for r in range(120, 0, -1):
    a = int(18 * (1 - r/120))
    c = (80 + a, 20 + a, 160 + a*2)
    draw.ellipse([864-r, 280-r, 864+r, 280+r], fill=c)

# ── Fonts ─────────────────────────────────────────────────────────────
font_title = ImageFont.truetype(r"C:/Windows/Fonts/arialbd.ttf", 120)
font_sub   = ImageFont.truetype(r"C:/Windows/Fonts/arial.ttf",    38)
font_tag   = ImageFont.truetype(r"C:/Windows/Fonts/arial.ttf",    28)

# ── Title "ידען" ──────────────────────────────────────────────────────
title = "ידען"
bb  = draw.textbbox((0,0), title, font=font_title, direction='rtl')
tw  = bb[2]-bb[0]; th = bb[3]-bb[1]
tx  = (W - tw) // 2
ty  = H//2 - th//2 - 28

# Glow behind text
for offset in range(12, 0, -1):
    alpha = int(30 * (1 - offset/12))
    draw.text((tx - offset//2, ty + offset//2), title,
              font=font_title, direction='rtl',
              fill=(255, 200, 0, alpha))

# Shadow
draw.text((tx+3, ty+4), title, font=font_title, direction='rtl',
          fill=(80, 50, 0))
# Main gold
draw.text((tx, ty), title, font=font_title, direction='rtl',
          fill=(255, 215, 0),
          stroke_width=2, stroke_fill=(160, 100, 0))

# ── Subtitle ──────────────────────────────────────────────────────────
sub = "חידון ידע כללי בעברית"
bbs = draw.textbbox((0,0), sub, font=font_sub, direction='rtl')
sw  = bbs[2]-bbs[0]
sy  = ty + th + 14
draw.text(((W-sw)//2, sy), sub, font=font_sub, direction='rtl',
          fill=(210, 230, 255),
          stroke_width=1, stroke_fill=(0, 0, 30))

# ── Tag line ──────────────────────────────────────────────────────────
tag = "ישראל  ·  מדע  ·  ספורט  ·  מוזיקה  ·  היסטוריה"
bbt = draw.textbbox((0,0), tag, font=font_tag, direction='rtl')
tw2 = bbt[2]-bbt[0]
draw.text(((W-tw2)//2, sy + 52), tag, font=font_tag, direction='rtl',
          fill=(140, 170, 220))

img.save(OUT, quality=98)
print(f"Saved {W}x{H}: {OUT}")
