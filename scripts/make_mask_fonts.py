"""Builds the tiny "stencil" fonts the Hiello widget uses to make a Flip move: 1, 2, 1, 2.

A widget can't play video or GIFs, but a timer label (Text(timerInterval:)) ticks by itself every second
while the widget is on screen. Drawn in one of these fonts, the timer becomes a stencil (mask) that is
either fully open (one solid block far bigger than the widget) or fully shut (nothing) each second.
Where the text sits on screen doesn't matter, so a picture can never be cut in half.

Two independent ways get from the timer's text to open/shut, so it works however iOS writes the timer:
  1. whole readings: "0:07", "12:31", "0:12:31", "1:00:00" each become one glyph (ligatures)
  2. last two digits, whatever comes before them: the font marks the last digit and the one before it
     (contextual substitution) and decides from just those two
Both are registered under the always-on OpenType features (ccmp, rlig) as well as liga/calt, so they
apply even where normal ligatures are switched off. Every plain character is blank, so if none of it
applies the widget simply shows picture 1.

  HielloB{n}{p}{f}: open on person p's turn (of n taking turns, 10 seconds each) AND beat f
                    (f=0 on even seconds, f=1 on odd seconds)
  HielloC{n}{p}   : open on person p's whole turn (names and notes)
  HielloProbe     : test font for the Hiello Lab widget (open on odd seconds)

Only the final open/shut glyph has width; every other glyph is zero-width, so the text is always exactly
one square that the widget centers over itself.

Run: python3 scripts/make_mask_fonts.py   (writes the .ttf files next to the widget's Swift file)
"""
import os, glob
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

OUT = os.path.join(os.path.dirname(__file__), '..', 'native', 'ios', 'HielloWidget')
UPM, ASC, DESC = 1000, 800, -200
DIG = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']
OTHER = {':': 'colon', ' ': 'space', '.': 'period', '∶': 'ratio', ' ': 'nnbsp', ' ': 'thinsp', ' ': 'figsp'}
CHAR_NAMES = {**{str(d): DIG[d] for d in range(10)}, **OTHER}
HOUR = 3600


def readings():
    """The usual ways the timer writes 0..3600 seconds, with the seconds it means."""
    out = {}
    for e in range(HOUR + 1):
        h, m, s, tm = e // 3600, (e // 60) % 60, e % 60, e // 60
        out[f'{tm}:{s:02d}'] = e             # 0:07, 12:31, 60:00
        out[f'{h}:{m:02d}:{s:02d}'] = e      # 0:12:31, 1:00:00
    return out


def solid():
    p = TTGlyphPen(None)
    p.moveTo((-16000, -16000)); p.lineTo((-16000, 16000)); p.lineTo((16000, 16000)); p.lineTo((16000, -16000)); p.closePath()
    return p.glyph()


def empty():
    return TTGlyphPen(None).glyph()


def make(name, cond):
    """cond(tens_digit, units_digit) -> open?  (the last two digits of the timer)"""
    base = DIG + list(OTHER.values())
    marked = [d + '.n' for d in DIG] + [d + '.t' for d in DIG]
    names = ['.notdef'] + base + marked + ['open', 'shut']
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({ord(c): n for c, n in CHAR_NAMES.items()})
    fb.setupGlyf({n: (solid() if n == 'open' else empty()) for n in names})
    # Only the final open/shut glyph takes up room; everything else has zero width, so all glyphs stack on
    # one spot and the text's frame is exactly one square (the widget may clip drawing to that frame).
    fb.setupHorizontalMetrics({n: ((1000, 0) if n in ('open', 'shut') else (0, 0)) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC, lineGap=0)
    fb.setupNameTable({'familyName': name, 'styleName': 'Regular', 'uniqueFontIdentifier': name,
                       'fullName': name, 'psName': name, 'version': 'Version 3.0'})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC, usWinDescent=-DESC,
                fsSelection=0x40, achVendID='HILO')
    fb.setupPost(isFixedPitch=1)
    fb.setupHead(unitsPerEm=UPM)
    fb.setupMaxp()

    def oc(t, u):
        return 'open' if cond(t, u) else 'shut'

    fea = ['languagesystem DFLT dflt;', 'languagesystem latn dflt;',
           f"@D = [{' '.join(DIG)}];", f"@DN = [{' '.join(d + '.n' for d in DIG)}];",
           f"@DT = [{' '.join(d + '.t' for d in DIG)}];", f"@ANY = [@D {' '.join(OTHER.values())} open shut];"]
    lookups = []
    # 1. whole readings -> one glyph (longest first so "12:31" wins over "2:31")
    rules = [f"  sub {' '.join(CHAR_NAMES[c] for c in txt)} by {oc((e % 60) // 10, e % 10)};"
             for txt, e in sorted(readings().items(), key=lambda kv: -len(kv[0]))]
    for i in range(0, len(rules), 1200):
        lookups.append(f'W{i // 1200}')
        fea.append(f'lookup W{i // 1200} {{\n' + '\n'.join(rules[i:i + 1200]) + f'\n}} W{i // 1200};')
    # 2. last two digits
    fea += ['lookup toN { sub @D by @DN; } toN;', 'lookup toT { sub @DN by @DT; } toT;',
            'lookup toOpen { sub @D by open; } toOpen;', 'lookup toShut { sub @D by shut; } toShut;',
            "lookup K1 { sub @D' lookup toN @ANY; } K1;",           # every digit with something after it
            "lookup K2 { sub @DN' lookup toT @D; } K2;",            # ...the one right before the last digit
            'lookup K3 {\n' + '\n'.join(f"  sub {DIG[t]}.t {DIG[u]}' lookup to{'Open' if cond(t, u) else 'Shut'};"
                                         for t in range(10) for u in range(10)) + '\n} K3;',
            'lookup K4 {\n' + '\n'.join(f"  sub {DIG[u]}' lookup to{'Open' if cond(0, u) else 'Shut'};"
                                         for u in range(10)) + '\n} K4;']
    lookups += ['K1', 'K2', 'K3', 'K4']
    for feat in ('ccmp', 'rlig', 'liga', 'calt'):
        fea.append(f'feature {feat} {{\n' + ''.join(f'  lookup {l};\n' for l in lookups) + f'}} {feat};')
    addOpenTypeFeaturesFromString(fb.font, '\n'.join(fea) + '\n')
    path = os.path.join(OUT, name + '.ttf')
    fb.save(path)
    return path


FONTS = {'HielloProbe': lambda t, u: u % 2 == 1}
# Whose turn depends only on the tens-of-seconds digit: minutes add multiples of 6 tens, and 6 divides
# evenly by 1, 2 and 3 people.
for n in (1, 2, 3):
    for p in range(n):
        for f in (0, 1):
            FONTS[f'HielloB{n}{p}{f}'] = (lambda n, p, f: lambda t, u: t % n == p and u % 2 == f)(n, p, f)
        if n > 1:
            FONTS[f'HielloC{n}{p}'] = (lambda n, p: lambda t, u: t % n == p)(n, p)

if __name__ == '__main__':
    for old in glob.glob(os.path.join(OUT, 'Hiello*.ttf')):
        os.remove(old)
    for name, fn in FONTS.items():
        print(make(name, fn))
