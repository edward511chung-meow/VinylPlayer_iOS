"""Deterministic variants of the reviewed imagegen master (user-authorized).
Run from the project root. Hardware and layout are never regenerated.
"""
from pathlib import Path
import json, shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parents[1] / 'VinylPlayer' / 'Assets.xcassets'
source = Image.open(ROOT / 'generated/AppIcon_light.png').convert('RGB')
a = np.asarray(source).astype(np.float32) / 255
h, w = a.shape[:2]
y, x = np.mgrid[:h, :w]
# Saturated warm wood isolates the plinth from metal, record and neutral backdrop.
wood = (a[:,:,0] > a[:,:,1]*1.12) & (a[:,:,1] > a[:,:,2]*1.12) & (a[:,:,0]-a[:,:,2] > .12)
edge = np.array([np.flatnonzero(row)[-1] if row.any() else 0 for row in wood],dtype=float)
# Median removes isolated paper/shadow noise without changing the rounded corner.
edge = np.median(np.pad(edge,(2,2),mode='edge')[np.arange(h)[:,None]+np.arange(5)],axis=1)
foreground = x <= edge[:,None]
background_level = np.median(a[:,-32:,:],axis=(1,2))[:,None]
luma = a @ np.array([.2126,.7152,.0722])
shadow = np.maximum(0, 1-luma / background_level)
shadow = np.where(shadow > .012, shadow, 0)
alpha = np.where(foreground, 1., shadow).astype(np.float32)
# The neutral background becomes a real black translucent shadow; no white matte.

hardware = Image.new('L',(w,h))
d=ImageDraw.Draw(hardware)
d.ellipse((-50,-105,166,103),fill=255)
d.line([(63,0),(545,427)],fill=255,width=79)
d.polygon([(490,397),(549,371),(660,467),(616,524),(558,544),(516,485)],fill=255)
hardware=hardware.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(3))
protected=np.asarray(hardware)/255
# The tonearm pivot projects just outside the diagonal wooden edge. Retain
# its dark silhouette and highlights rather than treating it as a shadow.
foreground |= (protected > .7) & (luma < .70)
alpha = np.where(foreground, 1., shadow).astype(np.float32)
base_rgb = np.where(foreground[:,:,None],a,0)
radius=np.hypot(x-76,y-622)
record=np.clip((487-radius)/2,0,1)*np.clip((radius-169)/2,0,1)*(1-protected)
# Avoid tinting source hardware and lettering along the wood edge.
wood_mask=np.asarray(Image.fromarray((wood*255).astype('uint8')).filter(ImageFilter.GaussianBlur(.6)))/255
wood_mask*=foreground

def variant(wood_tone, disc=None, dark=False):
    rgb=base_rgb.copy()
    lum=luma
    if wood_tone != 'walnut' or dark:
        targets={
            'walnut':(.39,.245,.14) if dark else (.65,.46,.27),
            'darkWalnut':(.25,.15,.095) if dark else (.35,.235,.16),
            'whiteOak':(.57,.52,.43) if dark else (.83,.77,.65),
            'ebony':(.105,.10,.09) if dark else (.18,.17,.15)
        }
        target=np.array(targets[wood_tone])
        texture=np.clip(lum/.49,.25,1.65)
        recolored=np.clip(texture[:,:,None]*target,0,1)
        rgb=rgb*(1-wood_mask[:,:,None])+recolored*wood_mask[:,:,None]
    if disc:
        if disc=='clear':
            v=np.clip(.28+np.sqrt(lum)*.82,0,1)
            tint=np.stack([v*.94,v*.98,v],axis=-1)
        else:
            color=np.array({'orange':(1.,.40,.035),'blue':(.065,.30,1.)}[disc])
            strength=np.clip(.30+np.sqrt(lum)*1.7,0,1.30)
            tint=np.clip(strength[:,:,None]*color,0,1)
        rgb=rgb*(1-record[:,:,None])+tint*record[:,:,None]
    return rgb

variants=[('AppIcon','walnut',None),('AppIconDarkWalnut','darkWalnut',None),
          ('AppIconWhiteOak','whiteOak',None),('AppIconEbony','ebony',None),
          ('AppIconOrange','walnut','orange'),('AppIconBlue','walnut','blue'),('AppIconClear','walnut','clear')]
final=ROOT/'final';final.mkdir(exist_ok=True)
for name,wood_tone,disc in variants:
    for appearance in ['light','dark','tinted']:
        rgb=variant(wood_tone,disc,dark=appearance=='dark')
        if appearance=='tinted':
            pixels=np.dstack([rgb,alpha])
            im=Image.fromarray(np.uint8(np.clip(pixels,0,1)*255))
        else:
            bg=np.array([.965,.962,.955] if appearance=='light' else [.085,.087,.09])
            pixels=rgb*alpha[:,:,None]+bg*(1-alpha[:,:,None])
            im=Image.fromarray(np.uint8(np.clip(pixels,0,1)*255))
        im=im.resize((1024,1024),Image.Resampling.LANCZOS)
        im.save(final/f'{name}_{appearance}.png')
        contents=json.loads((ASSETS/f'{name}.appiconset/Contents.json').read_text())
        entry=next(e for e in contents['images'] if (e.get('appearances',[{'value':'light'}])[0]['value'])==appearance)
        shutil.copy2(final/f'{name}_{appearance}.png',ASSETS/f'{name}.appiconset'/entry['filename'])
    preview_set=('AppIconPreviewV2' if name=='AppIcon' else name+'PreviewV2')+'.imageset'
    with Image.open(final/f'{name}_light.png') as im:
        im.resize((256,256),Image.Resampling.LANCZOS).save(ASSETS/preview_set/'preview.png')
# User-facing named replacements of the three standalone originals.
for src,dest in [('AppIcon_light','vinyl_player_light_app_icon'),('AppIcon_dark','vinyl_player_dark_app_icon'),('AppIcon_tinted','vinylplayer_light_icon_transparent')]:
    shutil.copy2(final/f'{src}.png',final/f'{dest}.png')
# Review all variants at actual icon-like sizes on light and dark backgrounds.
sheet=Image.new('RGB',(7*180,3*204),(235,235,235));draw=ImageDraw.Draw(sheet)
for col,(name,_,_) in enumerate(variants):
    for row,appearance in enumerate(['light','dark','tinted']):
        im=Image.open(final/f'{name}_{appearance}.png').convert('RGBA').resize((164,164),Image.Resampling.LANCZOS)
        tile=Image.new('RGBA',(164,164),(40,45,55,255) if row else (250,250,250,255))
        tile.alpha_composite(im)
        sheet.paste(tile.convert('RGB'),(col*180+8,row*204+8))
        draw.text((col*180+8,row*204+176),name.replace('AppIcon','') or 'Walnut',fill='black')
        draw.text((col*180+8,row*204+190),appearance,fill='black')
sheet.save(ROOT/'review.png')
print('Wrote 21 app icons, 7 previews, 3 named exports and review.png')
