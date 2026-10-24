#!/usr/bin/python3 -I
"""Frames the portrait monitor's wallpaper; PortraitWindow recolours it.

    /usr/bin/python3 ~/.config/dotfiles-hypr/quickshell-wall/make-portrait-base.py

Writes portrait-base.png beside this file from SOURCE: a 1080x1920 centre
crop ZOOM times wider than 9:16 would be (so the logo doesn't fill the
width), with the rows above and below filled with the field's own colour
and faded into. Palette-independent, so it's made once and committed -
rerun only after changing SOURCE or ZOOM. The palette part runs on the GPU
(shaders/portrait.frag).

Uses the system python's numpy and Pillow.
"""
import os

import numpy as np
from PIL import Image

W, H = 1080, 1920
ZOOM = 0.75
SOURCE = "arch-linux-wave-flow-4k-wallpaper-258519717.jpg"
OUT = "portrait-base.png"

here = os.path.dirname(os.path.realpath(__file__))
im = Image.open(os.path.join(here, SOURCE)).convert("RGB")
cw = min(im.width, round(im.height * W / H / ZOOM))
x = (im.width - cw) // 2
ih = round(im.height * W / cw)
im = im.crop((x, 0, x + cw, im.height)).resize((W, ih), Image.LANCZOS)
if ih < H:
    top = (H - ih) // 2
    arr = np.asarray(im).astype(float)
    # Past the source's darker edge vignette, which would show as bands.
    band = np.concatenate([arr[ih // 10:ih // 4], arr[-ih // 4:-ih // 10]]).reshape(-1, 3)
    canvas = Image.new("RGB", (W, H), tuple(int(v) for v in np.median(band, 0)))
    f = ih // 4
    mask = np.ones((ih, W))
    ramp = np.linspace(0, 1, f)[:, None] ** 1.5
    mask[:f] *= ramp
    mask[-f:] *= ramp[::-1]
    canvas.paste(im, (0, top), Image.fromarray((mask * 255).astype(np.uint8)))
    im = canvas
im.save(os.path.join(here, OUT), optimize=True)
print(os.path.join(here, OUT))
