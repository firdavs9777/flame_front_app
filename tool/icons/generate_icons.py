#!/usr/bin/env python3
"""Regenerate every Flame logo asset from one 2048px master.

    python3 tool/icons/generate_icons.py "<master.png>"
    dart run flutter_launcher_icons && dart run flutter_native_splash:create

The master is the square store icon: a cream droplet on the brand gradient.
Four different shapes are cut from it, because each target needs a different
one — shipping the same square everywhere is what makes an Android icon look
cropped and an iOS upload get rejected.

  app_icon.png            square, opaque   — Android legacy launcher
  app_icon_ios.png        square, NO alpha — App Store rejects any alpha
  app_icon_foreground.png droplet only, transparent, inside the adaptive
                          safe zone — Android masks this into a circle/squircle
  app_icon_background.png the gradient with the droplet inpainted away, so the
                          foreground droplet is not drawn on top of a second one
  images/logo.png         square, opaque   — settings screen (app-icon look)
  images/logo_mark.png    droplet only, transparent — the mark, for use on a
                          coloured background where a second gradient square
                          would just blend into the first
  splash_logo.png         droplet only, transparent — native splash
"""
import sys, os
from PIL import Image, ImageDraw, ImageFilter

ICON_DIR = 'assets/icon'
IMAGE_DIR = 'assets/images'
CREAM = (251, 238, 220)
CREAM_TOL = 60

# Android reserves the outer ~25% of an adaptive icon for masking and parallax;
# only the central 66/108dp is guaranteed visible.
#
# flutter_launcher_icons already wraps the foreground in <inset android:inset=
# "16%">, which shrinks whatever we hand it to 68% of the canvas. So the art
# fraction here is pre-inset: 0.90 x 0.68 = 0.61 of the finished icon, which
# lands inside the safe zone. Sizing this to 0.58 as if the inset did not exist
# renders the droplet at 39% — correct but conspicuously small next to every
# other icon on the home screen.
ADAPTIVE_INSET = 0.68
ADAPTIVE_ART_FRACTION = 0.90
SPLASH_ART_FRACTION = 0.62

# The droplet edge is anti-aliased, so the pixels just outside the colour-matched
# silhouette are part cream. Interpolating between those leaves a droplet-shaped
# ghost in the "removed" background. Grow the mask well past the blend before
# inpainting so both endpoints are true gradient.
INPAINT_DILATE = 25


def droplet_mask(im):
    """Silhouette of the droplet: the cream body plus the hole it encloses."""
    w, h = im.size
    px = im.load()
    mask = Image.new('L', (w, h), 0)
    m = mask.load()
    for y in range(h):
        for x in range(w):
            if sum(abs(a - b) for a, b in zip(px[x, y], CREAM)) < CREAM_TOL:
                m[x, y] = 255

    # The inner drop is a different colour, so colour-matching alone leaves a
    # hole. Flood the inverse from a corner; whatever the flood cannot reach is
    # enclosed by the body and belongs to the logo.
    inv = Image.new('L', (w, h), 0)
    iv = inv.load()
    for y in range(h):
        for x in range(w):
            iv[x, y] = 0 if m[x, y] else 255
    ImageDraw.floodfill(inv, (0, 0), 128, thresh=10)
    iv = inv.load()
    for y in range(h):
        for x in range(w):
            if iv[x, y] == 255:
                m[x, y] = 255
    return mask


def inpaint_gradient(im, mask):
    """The gradient with the droplet removed.

    Interpolates each row between the last background pixel on either side.
    The gradient is linear along a row, so this reproduces it to within 2/255 —
    a bilinear fit from the four corners is off by up to 48.
    """
    w, h = im.size
    out = im.copy()
    px = out.load()
    m = mask.load()
    for y in range(h):
        x = 0
        while x < w:
            if m[x, y] == 0:
                x += 1
                continue
            start = x
            while x < w and m[x, y]:
                x += 1
            end = x                      # first background pixel to the right
            left = start - 1
            if left < 0 and end >= w:
                continue
            a = px[left, y] if left >= 0 else px[end, y]
            b = px[end, y] if end < w else px[left, y]
            span = end - start + 1
            for i, xi in enumerate(range(start, end), start=1):
                t = i / span
                px[xi, y] = tuple(
                    int(round(a[c] + (b[c] - a[c]) * t)) for c in range(3))
    return out


def centred(art, size, fraction):
    """Scale `art` so its long edge is `fraction` of `size`, centred, on clear."""
    aw, ah = art.size
    target = size * fraction
    scale = target / max(aw, ah)
    new = (max(1, round(aw * scale)), max(1, round(ah * scale)))
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.paste(art.resize(new, Image.LANCZOS),
                 ((size - new[0]) // 2, (size - new[1]) // 2))
    return canvas


def main(master_path):
    os.makedirs(ICON_DIR, exist_ok=True)
    master = Image.open(master_path).convert('RGB')
    if master.size[0] != master.size[1]:
        raise SystemExit(f'master must be square, got {master.size}')

    mask = droplet_mask(master)
    box = mask.getbbox()
    if box is None:
        raise SystemExit('no droplet found — is this the right master?')

    # Droplet on transparency, cropped tight.
    drop = Image.new('RGBA', master.size, (0, 0, 0, 0))
    drop.paste(master, (0, 0), mask)
    drop = drop.crop(box)

    background = inpaint_gradient(
        master, mask.filter(ImageFilter.MaxFilter(INPAINT_DILATE)))
    square = master.resize((1024, 1024), Image.LANCZOS)

    written = []

    def save(img, path, keep_alpha):
        if not keep_alpha:
            img = img.convert('RGB')
        img.save(path)
        written.append(path)

    save(square, f'{ICON_DIR}/app_icon.png', False)
    save(square, f'{ICON_DIR}/app_icon_ios.png', False)
    save(background.resize((1024, 1024), Image.LANCZOS),
         f'{ICON_DIR}/app_icon_background.png', False)
    save(centred(drop, 1024, ADAPTIVE_ART_FRACTION),
         f'{ICON_DIR}/app_icon_foreground.png', True)
    save(centred(drop, 1024, SPLASH_ART_FRACTION),
         f'{ICON_DIR}/splash_logo.png', True)
    save(square, f'{IMAGE_DIR}/logo.png', False)
    save(centred(drop, 1024, 0.92), f'{IMAGE_DIR}/logo_mark.png', True)

    w = master.size[0]
    bg = background.load()
    mid = '#%02X%02X%02X' % bg[w // 2, w // 2]
    for p in written:
        im = Image.open(p)
        print(f'  {p:44} {im.size[0]}x{im.size[1]}  '
              f'{"alpha" if im.mode == "RGBA" else "opaque"}')
    print(f'\n  brand mid-gradient colour: {mid}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'assets/icon/master.png')
