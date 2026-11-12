"""Builds the tiny "stencil" fonts the Hiello widget uses to make a Flip move: 1, 2, 1, 2.

A widget can't play video or GIFs, but a timer label (Text(timerInterval:)) ticks by itself every second
while the widget is on screen. These fonts turn each whole timer reading ("0:07", "12:31", "1:00:00", ...)
into ONE glyph through ligatures: either a huge solid block or nothing. Drawn in one of these fonts, the
timer becomes a stencil (mask) that is fully open or fully shut each second. Where the text sits doesn't
matter (the block is far bigger than the widget), so a picture can never be cut in half.
If ligatures were ever ignored, every plain character is blank, so the widget just shows picture 1.

  HielloB{n}{p}{f}: open when it's person p's turn (of n taking turns, 10 seconds each) AND beat f
                    (f=0 on even seconds, f=1 on odd seconds)
  HielloC{n}{p}   : open on person p's whole turn (names and notes)

Run: python3 scripts/make_mask_fonts.py   (writes the .ttf files next to the widget's Swift file)
"""
import os, glob
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

OUT = os.path.join(os.path.dirname(__file__), '..', 'native', 'ios', 'HielloWidget')
UPM, ASC, DESC = 1000, 800, -200
CHAR_NAMES = {**{str(d): n for d, n in zip('0123456789', ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'])},
              ':': 'colon', ' ': 'space', '.': 'period'}
HOUR = 3600


def readings():
    """Every way the timer can write 0..3600 seconds, with the seconds it means."""
    out = {}
    for e in range(HOUR + 1):
        h, m, s = e // 3600, (e // 60) % 60, e % 60
        tm = e // 60
        out[f'{tm}:{s:02d}'] = e                 # 0:07, 12:31, 60:00
        out[f'{tm:02d}:{s:02d}'] = e             # 00:07
        out[f'{h}:{m:02d}:{s:02d}'] = e          # 0:00:07, 1:00:00
        out[f'{h:02d}:{m:02d}:{s:02d}'] = e      # 00:00:07
    return out


def solid():
    p = TTGlyphPen(None)
    p.moveTo((-16000, -16000)); p.lineTo((-16000, 16000)); p.lineTo((16000, 16000)); p.lineTo((16000, -16000)); p.closePath()
    return p.glyph()


def empty():
    return TTGlyphPen(None).glyph()


def make(name, is_open):
    chars = list(CHAR_NAMES.values())
    names = ['.notdef'] + chars + ['open', 'shut']
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({ord(c): n for c, n in CHAR_NAMES.items()})
    fb.setupGlyf({n: (solid() if n == 'open' else empty()) for n in names})
    fb.setupHorizontalMetrics({n: (1000, 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC, lineGap=0)
    fb.setupNameTable({'familyName': name, 'styleName': 'Regular', 'uniqueFontIdentifier': name,
                       'fullName': name, 'psName': name, 'version': 'Version 2.0'})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC, usWinDescent=-DESC,
                fsSelection=0x40, achVendID='HILO')
    fb.setupPost(isFixedPitch=1)
    fb.setupHead(unitsPerEm=UPM)
    fb.setupMaxp()
    # longest readings first so "12:31" wins over a shorter match inside it
    rules = [f"  sub {' '.join(CHAR_NAMES[c] for c in txt)} by {'open' if is_open(e) else 'shut'};"
             for txt, e in sorted(readings().items(), key=lambda kv: -len(kv[0]))]
    # split into small lookups so no single table grows past the font format's 64 KB limit
    chunks = [rules[i:i + 1200] for i in range(0, len(rules), 1200)]
    fea = 'languagesystem DFLT dflt;\nlanguagesystem latn dflt;\n'
    fea += ''.join(f'lookup L{i} {{\n' + '\n'.join(c) + f'\n}} L{i};\n' for i, c in enumerate(chunks))
    fea += 'feature liga {\n' + ''.join(f'  lookup L{i};\n' for i in range(len(chunks))) + '} liga;\n'
    addOpenTypeFeaturesFromString(fb.font, fea)
    path = os.path.join(OUT, name + '.ttf')
    fb.save(path)
    return path


def turn(e, n):
    return (e // 10) % n


FONTS = {}
for n in (1, 2, 3):
    for p in range(n):
        for f in (0, 1):
            FONTS[f'HielloB{n}{p}{f}'] = (lambda n, p, f: lambda e: turn(e, n) == p and e % 2 == f)(n, p, f)
        if n > 1:
            FONTS[f'HielloC{n}{p}'] = (lambda n, p: lambda e: turn(e, n) == p)(n, p)

if __name__ == '__main__':
    for old in glob.glob(os.path.join(OUT, 'Hiello*.ttf')):
        os.remove(old)
    for name, fn in FONTS.items():
        print(make(name, fn))
