"""Adds Hiello's Dark and Tinted icons to the app icon (iOS 18+), next to the normal one.
Run in Codemagic after capacitor-assets has made ios/App/App/Assets.xcassets/AppIcon.appiconset."""
import json, os, shutil, sys
SET = 'ios/App/App/Assets.xcassets/AppIcon.appiconset'
cj = os.path.join(SET, 'Contents.json')
data = json.load(open(cj))
imgs = [i for i in data.get('images', []) if not i.get('appearances')]
main = next((i for i in imgs if i.get('size') == '1024x1024' and i.get('idiom') in ('universal', 'ios-marketing')), None)
if not main:
    print('add_dark_icon: no 1024 icon entry found, leaving the icon as it is'); sys.exit(0)
shutil.copy('resources/icon-dark.png', os.path.join(SET, 'AppIcon-dark.png'))
shutil.copy('resources/icon-tinted.png', os.path.join(SET, 'AppIcon-tinted.png'))
base = {k: v for k, v in main.items() if k not in ('filename', 'appearances')}
base['idiom'] = 'universal'; base.setdefault('platform', 'ios')
imgs += [dict(base, filename='AppIcon-dark.png', appearances=[{'appearance': 'luminosity', 'value': 'dark'}]),
         dict(base, filename='AppIcon-tinted.png', appearances=[{'appearance': 'luminosity', 'value': 'tinted'}])]
data['images'] = imgs
json.dump(data, open(cj, 'w'), indent=2)
print('add_dark_icon: added Dark and Tinted icons')
