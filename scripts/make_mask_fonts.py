"""Builds the two "stencil" fonts the Hiello widget uses to make a Flip move: 1, 2, 1, 2.

A widget can't play video or GIFs, but a timer label (Text(timerInterval:)) ticks by itself every second
while the widget is on screen. Drawn in one of these fonts the timer becomes a stencil (mask).

iOS draws a widget's live timer character by character and does NOT apply a font's substitution rules
(ligatures etc.), so these fonts use plain character shapes only. Each digit is either a solid block far
bigger than the widget, or nothing. Because the block is so big, where the text sits doesn't matter: the
stencil is open if ANY character in the timer is a solid one, otherwise shut.

The widget then only uses short 10-second timers, whose text only ever contains 0, 1 and one changing
digit, so "is any character solid" answers exactly the question it needs:
  HielloOdd: 1 3 5 7 9 are solid   ("0:0u" is open on odd seconds)
  HielloNZ : 1-9 are solid         ("0:00" is the only shut reading: tells whether a timer has started/ended)

Run: python3 scripts/make_mask_fonts.py   (writes the .ttf files next to the widget's Swift file)
"""
import os, glob
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

OUT = os.path.join(os.path.dirname(__file__), '..', 'native', 'ios', 'HielloWidget')
UPM, ASC, DESC = 1000, 800, -200
DIG = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']
OTHER = {':': 'colon', ' ': 'space', '.': 'period', '∶': 'ratio', ' ': 'nnbsp', ' ': 'thinsp',
         ' ': 'figsp', ' ': 'nbsp', '-': 'hyphen', '−': 'minus'}


def solid():
    p = TTGlyphPen(None)
    p.moveTo((-16000, -16000)); p.lineTo((-16000, 16000)); p.lineTo((16000, 16000)); p.lineTo((16000, -16000)); p.closePath()
    return p.glyph()


def empty():
    return TTGlyphPen(None).glyph()


def make(name, solid_digits):
    names = ['.notdef'] + DIG + list(OTHER.values())
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    cmap = {ord(str(d)): DIG[d] for d in range(10)}
    cmap.update({ord(c): n for c, n in OTHER.items()})
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({n: (solid() if n in DIG and DIG.index(n) in solid_digits else empty()) for n in names})
    # The left side bearing MUST match where the block really starts (-16000), or renderers (CoreText too)
    # slide the block right until it starts at the character's origin, off the widget.
    fb.setupHorizontalMetrics({n: (1000, -16000 if n in DIG and DIG.index(n) in solid_digits else 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC, lineGap=0)
    fb.setupNameTable({'familyName': name, 'styleName': 'Regular', 'uniqueFontIdentifier': name,
                       'fullName': name, 'psName': name, 'version': 'Version 4.0'})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC, usWinDescent=-DESC,
                fsSelection=0x40, achVendID='HILO')
    fb.setupPost(isFixedPitch=1)
    fb.setupHead(unitsPerEm=UPM)
    fb.setupMaxp()
    path = os.path.join(OUT, name + '.ttf')
    fb.save(path)
    return path


FONTS = {'HielloOdd': {1, 3, 5, 7, 9}, 'HielloNZ': set(range(1, 10))}

if __name__ == '__main__':
    for old in glob.glob(os.path.join(OUT, 'Hiello*.ttf')):
        os.remove(old)
    for name, digits in FONTS.items():
        print(make(name, digits), sorted(digits))
