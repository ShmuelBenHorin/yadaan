from PIL import Image
import os

base   = r"C:\Users\1\Desktop\high-tech\trivia_master\screen shots\ios"
TARGET = (1242, 2688)

files = ["ss1.jpg", "ss2.jpg", "ss3.jpg", "ss4.jpg", "ss5.jpg"]

tw, th = TARGET

for src in files:
    img   = Image.open(os.path.join(base, src)).convert("RGB")
    w, h  = img.size
    scale = tw / w
    new_h = int(h * scale)
    img   = img.resize((tw, new_h), Image.LANCZOS)

    if new_h >= th:
        img = img.crop((0, 0, tw, th))
    else:
        canvas = Image.new("RGB", (tw, th), (0, 0, 0))
        canvas.paste(img, (0, 0))
        img = canvas

    dst = src.replace(".jpg", "_store.jpg")
    img.save(os.path.join(base, dst), quality=97)
    print(f"{src} ({w}x{h}) -> {dst} ({tw}x{th})")

print("Done!")
