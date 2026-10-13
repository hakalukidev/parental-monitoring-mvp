"""Render original Seftly vector geometry into launcher assets. Requires Pillow."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'assets/branding'
COLORS = {'parent': '#176B5B', 'child': '#426585'}
SHIELD = 'M512 225 L744 310 L712 568 Q690 711 512 805 Q334 711 312 568 L280 310 Z'

def curve(start, control, end):
    return [((1-t)**2*start[0]+2*(1-t)*t*control[0]+t*t*end[0], (1-t)**2*start[1]+2*(1-t)*t*control[1]+t*t*end[1]) for t in [i/60 for i in range(61)]]

def draw_logo(variant, background=True):
    image = Image.new('RGBA', (1024, 1024), COLORS[variant] if background else (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    pts = [(512,225),(744,310),(712,568)] + curve((712,568),(690,711),(512,805)) + curve((512,805),(334,711),(312,568)) + [(280,310),(512,225)]
    draw.line(pts, fill='white', width=28)
    for x,y in pts: draw.ellipse((x-14,y-14,x+14,y+14),fill='white')
    draw.ellipse((453,370,565,482), fill='white')
    arc=curve((392,604),(512,476),(632,604))
    for x,y in arc: draw.ellipse((x-16,y-16,x+16,y+16),fill='white')
    if variant == 'parent':
        draw.ellipse((579,472,657,550), fill='white')
        for x,y in curve((550,641),(618,555),(682,641)): draw.ellipse((x-12,y-12,x+12,y+12),fill='white')
    else:
        draw.polygon([(632,584),(643,609),(670,612),(650,630),(655,658),(632,644),(609,658),(614,630),(594,612),(621,609)], fill='#BCE5DB')
    return image

def svg(variant):
    extra = '<circle cx="618" cy="511" r="39" fill="white"/><path d="M550 641 Q618 555 682 641" stroke="white" stroke-width="24" fill="none"/>' if variant == 'parent' else '<path d="M632 584 L643 609 L670 612 L650 630 L655 658 L632 644 L609 658 L614 630 L594 612 L621 609 Z" fill="#BCE5DB"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="{COLORS[variant]}"/><path d="{SHIELD}" stroke="white" stroke-width="28" stroke-linejoin="round" fill="none"/><circle cx="509" cy="426" r="56" fill="white"/><path d="M392 604 Q512 476 632 604" stroke="white" stroke-width="32" stroke-linecap="round" fill="none"/>{extra}</svg>\n'

def vector(variant):
    extra = '<path android:fillColor="#FFFFFFFF" android:pathData="M618,472 A39,39 0,1 1,618,550 A39,39 0,1 1,618,472"/><path android:strokeColor="#FFFFFFFF" android:strokeWidth="24" android:fillColor="#00000000" android:pathData="M550,641 Q618,555 682,641"/>' if variant == 'parent' else '<path android:fillColor="#FFBCE5DB" android:pathData="M632,584 L643,609 L670,612 L650,630 L655,658 L632,644 L609,658 L614,630 L594,612 L621,609 Z"/>'
    return f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024"><path android:fillColor="#00000000" android:strokeColor="#FFFFFFFF" android:strokeWidth="28" android:strokeLineJoin="round" android:pathData="{SHIELD}"/><path android:fillColor="#FFFFFFFF" android:pathData="M509,370 A56,56 0,1 1,509,482 A56,56 0,1 1,509,370"/><path android:fillColor="#00000000" android:strokeColor="#FFFFFFFF" android:strokeWidth="32" android:strokeLineCap="round" android:pathData="M392,604 Q512,476 632,604"/>{extra}</vector>\n'

for variant, folder in [('parent','parent-app/android/app/src/main/res'), ('child','child-app/app/src/main/res')]:
    (BRAND/f'seftly-{variant}.svg').write_text(svg(variant))
    original = draw_logo(variant)
    original.convert('RGB').save(BRAND/f'seftly-{variant}-1024.png')
    res = ROOT/folder
    for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        target = res/f'mipmap-{density}'; target.mkdir(parents=True,exist_ok=True)
        original.resize((size,size),Image.Resampling.LANCZOS).save(target/'ic_launcher.png')
        rounded = original.resize((size,size),Image.Resampling.LANCZOS)
        mask = Image.new('L',(size,size)); ImageDraw.Draw(mask).ellipse((0,0,size-1,size-1),fill=255)
        rounded.putalpha(mask); rounded.save(target/'ic_launcher_round.png')
    (res/'drawable').mkdir(exist_ok=True)
    (res/'drawable/ic_launcher_foreground.xml').write_text(vector(variant))
    (res/'drawable/ic_launcher_background.xml').write_text(f'<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle"><solid android:color="{COLORS[variant]}"/></shape>\n')
    adaptive = res/'mipmap-anydpi-v26'; adaptive.mkdir(exist_ok=True)
    for name in ['ic_launcher','ic_launcher_round']:
        (adaptive/f'{name}.xml').write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@drawable/ic_launcher_background"/><foreground android:drawable="@drawable/ic_launcher_foreground"/></adaptive-icon>\n')
    (res/'drawable/ic_seftly_notification.xml').write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="1024" android:viewportHeight="1024"><path android:fillColor="#FFFFFFFF" android:pathData="M512,120 L856,252 L800,650 Q740,835 512,940 Q284,835 224,650 L168,252 Z"/></vector>\n')
    if variant == 'parent':
        for platform in ['ios','macos']:
            directory = ROOT/f'parent-app/{platform}/Runner/Assets.xcassets/AppIcon.appiconset'
            content = json.loads((directory/'Contents.json').read_text())
            for item in content['images']:
                size = round(float(item['size'].split('x')[0])*float(item['scale'].rstrip('x')))
                original.resize((size,size),Image.Resampling.LANCZOS).convert('RGB').save(directory/item['filename'])
        for file,size in [('favicon.png',32),('icons/Icon-192.png',192),('icons/Icon-512.png',512),('icons/Icon-maskable-192.png',192),('icons/Icon-maskable-512.png',512)]:
            original.resize((size,size),Image.Resampling.LANCZOS).convert('RGB').save(ROOT/'parent-app/web'/file)
        for folder in ['drawable','drawable-v21']:
            path=res/folder/'launch_background.xml'
            path.write_text('<layer-list xmlns:android="http://schemas.android.com/apk/res/android"><item android:drawable="@drawable/ic_launcher_background"/><item android:width="108dp" android:height="108dp" android:gravity="center" android:drawable="@drawable/ic_launcher_foreground"/></layer-list>\n')
preview=Image.new('RGB',(960,520),'#F5F7F5'); d=ImageDraw.Draw(preview)
try: font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',25)
except OSError: font=ImageFont.load_default(size=25)
for variant,x in [('parent',55),('child',525)]:
    d.text((x,25),f'Seftly {variant.title()}',fill='#192F2A',font=font)
    logo=draw_logo(variant).resize((350,350),Image.Resampling.LANCZOS)
    preview.paste(logo,(x,80),logo)
    for i,size in enumerate([48,72,96]):
        small=logo.resize((size,size),Image.Resampling.LANCZOS)
        mask=Image.new('L',(size,size));ImageDraw.Draw(mask).ellipse((0,0,size,size),fill=255)
        preview.paste(small,(x+i*110,440),mask)
preview.save(BRAND/'launcher-preview.png')
print('Generated parent/child vectors, Android densities/adaptive assets, iOS/macOS/Web icons and preview.')
