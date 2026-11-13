"""Makes Hiello's Dark and Tinted Home Screen icons from resources/icon-only.png.

Dark: same icon, at night. The silver plate becomes dark gunmetal (rivets kept), the navy square goes
near-black with a hint of navy, the "hi" stays white and the pink heart stays exactly as it is
(like Locket keeps its gold heart). Tinted: a grayscale version iOS colors with the user's tint.
Run: python3 scripts/make_dark_icon.py  -> resources/icon-dark.png, resources/icon-tinted.png
"""
from PIL import Image
import colorsys, os

ROOT = os.path.join(os.path.dirname(__file__), '..', 'resources')
src = Image.open(os.path.join(ROOT, 'icon-only.png')).convert('RGB')
W, H = src.size
px = src.load()

# the navy square: bounding box of navy pixels
xs, ys = [], []
for y in range(0, H, 2):
    for x in range(0, W, 2):
        r, g, b = px[x, y]
        if b > 70 and b > r + 35 and r < 60:
            xs.append(x); ys.append(y)
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
rad = (x1 - x0) * 0.17


def inside(x, y):
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    cx = min(max(x, x0 + rad), x1 - rad); cy = min(max(y, y0 + rad), y1 - rad)
    return (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad


dark = Image.new('RGB', (W, H)); dp = dark.load()
tint = Image.new('RGB', (W, H)); tp = tint.load()
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        pinkish = (r > 150 and r > b + 25 and r > g + 25) or (r > 110 and g < 70 and b < 80)   # heart + red outline
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        if pinkish:
            dp[x, y] = (r, g, b)
        elif inside(x, y):
            if lum > 150 and s < 0.25:                 # the white "hi"
                dp[x, y] = (236, 239, 244)
            else:                                       # navy -> near-black with a hint of navy
                t = min(1, lum / 90)
                dp[x, y] = (int(10 + 8 * t), int(12 + 10 * t), int(20 + 18 * t))
        else:                                           # silver plate, rim, rivets -> gunmetal
            v = lum / 255
            base = 26 + 46 * v
            dp[x, y] = (int(base), int(base + 2), int(base + 6))
        # tinted: light marks on black, so iOS can color them
        tl = 255 if (inside(x, y) and lum > 150 and s < 0.25) or pinkish else (40 if not inside(x, y) else 0)
        tp[x, y] = (tl, tl, tl)

dark.save(os.path.join(ROOT, 'icon-dark.png'))
tint.save(os.path.join(ROOT, 'icon-tinted.png'))
print('box', x0, x1, y0, y1, '-> icon-dark.png, icon-tinted.png')
