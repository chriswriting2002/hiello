"""Builds the tiny "stencil" fonts the Hiello widget uses to animate a Flip.

A widget can't play video or GIFs, but a timer label (Text(timerInterval:)) ticks by itself every
second. In these fonts some digits are solid squares and every other character is blank, so a
timer drawn in one of them works as a stencil (mask) that opens and closes on the beat.

  HielloBeat1  : odd digits are solid   -> the last digit of the seconds shows picture 2 on 1,3,5,7,9
  HielloS{n}{k}: digit d is solid when d % n == k -> the tens-of-seconds digit picks whose hi shows
                 (n = how many people are taking turns, k = which person)

Every glyph is exactly 1000 units wide and the em is 1000, so at font size S each character is an
S-wide column. The solid squares are taller than the line so they always cover the widget.

Run: python3 scripts/make_mask_fonts.py   (writes the .ttf files next to the widget's Swift file)
"""
import os
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

OUT = os.path.join(os.path.dirname(__file__), '..', 'native', 'ios', 'HielloWidget')
UPM, ASC, DESC = 1000, 800, -200
CHARS = '0123456789:. '


def block():
    p = TTGlyphPen(None)
    p.moveTo((0, -1400)); p.lineTo((0, 2000)); p.lineTo((1000, 2000)); p.lineTo((1000, -1400)); p.closePath()
    return p.glyph()


def empty():
    return TTGlyphPen(None).glyph()


def make(name, solid_digits):
    names = ['.notdef', 'blank', 'solid']
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({ord(c): ('solid' if c.isdigit() and int(c) in solid_digits else 'blank') for c in CHARS})
    fb.setupGlyf({'.notdef': empty(), 'blank': empty(), 'solid': block()})
    fb.setupHorizontalMetrics({n: (1000, 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC, lineGap=0)
    fb.setupNameTable({'familyName': name, 'styleName': 'Regular', 'uniqueFontIdentifier': name,
                       'fullName': name, 'psName': name, 'version': 'Version 1.0'})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC, usWinDescent=-DESC,
                fsSelection=0x40, achVendID='HILO')
    fb.setupPost(isFixedPitch=1)
    fb.setupHead(unitsPerEm=UPM)
    fb.setupMaxp()
    path = os.path.join(OUT, name + '.ttf')
    fb.save(path)
    return path


FONTS = {'HielloBeat1': {1, 3, 5, 7, 9}}
for n in (2, 3):
    for k in range(n):
        FONTS[f'HielloS{n}{k}'] = {d for d in range(10) if d % n == k}

if __name__ == '__main__':
    for name, digits in FONTS.items():
        print(make(name, digits), sorted(digits))
