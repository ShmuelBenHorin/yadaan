from PIL import Image, ImageDraw, ImageFont
import os

base       = r"C:\Users\1\Desktop\high-tech\trivia_master\screen shots\ios"
font_path  = r"C:/Windows/Fonts/arial.ttf"
emoji_path = r"C:/Windows/Fonts/seguiemj.ttf"

configs = [
    {
        "input":  "ss1.jpg",
        "output": "ss1_final.jpg",
        "main":   "!בחן את הידע שלך",
        "sub":    "חידון ידע כללי בעברית",
        "emoji":  "🧠",
    },
    {
        "input":  "ss2.jpg",
        "output": "ss2_final.jpg",
        "main":   "התקדם דרך עשרות שלבים",
        "sub":    "אסוף כוכבים ופתח רמות חדשות",
        "emoji":  "⭐",
    },
    {
        "input":  "ss3.jpg",
        "output": "ss3_final.jpg",
        "main":   "מאות שאלות מאתגרות",
        "sub":    "ישראל · מדע · ספורט · מוזיקה ועוד",
        "emoji":  "🎯",
    },
    {
        "input":  "ss4.jpg",
        "output": "ss4_final.jpg",
        "main":   "למד מכל שאלה",
        "sub":    "הסברים מפורטים לכל תשובה",
        "emoji":  "📚",
    },
]

MARGIN   = 24   # px from each side
GAP      = 12   # gap between emoji and text
HEADER_H = 230

def fit_font(draw, text, emoji, font_path, emoji_path,
             start_size, min_size, max_w, direction='rtl'):
    """Shrink font until text+emoji fit within max_w."""
    size = start_size
    while size >= min_size:
        f  = ImageFont.truetype(font_path,  size)
        fe = ImageFont.truetype(emoji_path, int(size * 0.88))
        bb  = draw.textbbox((0, 0), text,  font=f,  direction=direction)
        bbe = draw.textbbox((0, 0), emoji, font=fe)
        tw  = bb[2]  - bb[0]
        te  = bbe[2] - bbe[0]
        if tw + GAP + te <= max_w:
            return f, fe, tw, te
        size -= 2
    # Return smallest available
    f  = ImageFont.truetype(font_path,  min_size)
    fe = ImageFont.truetype(emoji_path, int(min_size * 0.88))
    bb  = draw.textbbox((0, 0), text,  font=f,  direction=direction)
    bbe = draw.textbbox((0, 0), emoji, font=fe)
    return f, fe, bb[2]-bb[0], bbe[2]-bbe[0]


for cfg in configs:
    img = Image.open(os.path.join(base, cfg["input"])).convert("RGBA")
    w, h = img.size
    max_w = w - MARGIN * 2

    # ── Build header ────────────────────────────────────────────────────
    header = Image.new("RGBA", (w, HEADER_H), (10, 20, 60, 255))
    # Gradient fade at bottom
    fade = 50
    for y in range(fade):
        alpha = int(255 * (1 - y / fade))
        for x in range(w):
            header.putpixel((x, HEADER_H - 1 - y), (10, 20, 60, alpha))

    new_img = Image.new("RGBA", (w, h + HEADER_H), (10, 20, 60, 255))
    new_img.paste(header, (0, 0))
    new_img.paste(img, (0, HEADER_H))
    draw = ImageDraw.Draw(new_img)

    # ── Main text ────────────────────────────────────────────────────────
    f_main, fe_main, tw_main, te_main = fit_font(
        draw, cfg["main"], cfg["emoji"],
        font_path, emoji_path,
        start_size=68, min_size=38, max_w=max_w
    )

    total_main = tw_main + GAP + te_main
    x0 = (w - total_main) // 2          # left edge of emoji
    x_txt = x0 + te_main + GAP          # left edge of hebrew text

    # Center vertically in top half of header
    bb   = draw.textbbox((0, 0), cfg["main"],  font=f_main,  direction='rtl')
    bbe  = draw.textbbox((0, 0), cfg["emoji"], font=fe_main)
    th   = bb[3]  - bb[1]
    the  = bbe[3] - bbe[1]
    y_main = (HEADER_H // 2 - 20 - th) // 2

    draw.text((x_txt, y_main), cfg["main"],
              font=f_main, direction='rtl',
              fill=(255, 215, 0),
              stroke_width=2, stroke_fill=(0, 0, 0))
    draw.text((x0, y_main + (th - the) // 2), cfg["emoji"],
              font=fe_main, fill=(255, 255, 255))

    # ── Sub text ─────────────────────────────────────────────────────────
    f_sub, fe_sub, tw_sub, te_sub = fit_font(
        draw, cfg["sub"], cfg["emoji"],
        font_path, emoji_path,
        start_size=36, min_size=24, max_w=max_w
    )

    total_sub = tw_sub + GAP + te_sub
    x0s    = (w - total_sub) // 2
    x_txts = x0s + te_sub + GAP

    bbs  = draw.textbbox((0, 0), cfg["sub"],   font=f_sub,  direction='rtl')
    bbes = draw.textbbox((0, 0), cfg["emoji"],  font=fe_sub)
    ths  = bbs[3]  - bbs[1]
    thes = bbes[3] - bbes[1]
    y_sub = HEADER_H // 2 + 10 + (HEADER_H // 2 - 10 - ths) // 2 - 30

    draw.text((x_txts, y_sub), cfg["sub"],
              font=f_sub, direction='rtl',
              fill=(200, 220, 255),
              stroke_width=1, stroke_fill=(0, 0, 0))
    draw.text((x0s, y_sub + (ths - thes) // 2), cfg["emoji"],
              font=fe_sub, fill=(255, 255, 255))

    # ── Save ─────────────────────────────────────────────────────────────
    out = new_img.convert("RGB")
    out.save(os.path.join(base, cfg["output"]), quality=97)
    print(f"Done: {cfg['output']}  main={f_main.size}pt  sub={f_sub.size}pt")

print("All done!")
