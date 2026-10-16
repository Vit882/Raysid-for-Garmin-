#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Draws the launcher icon (radiation trefoil) in the sizes that need their own
# resources-icon<N> directory (see monkey.jungle). The 40x40 base icon in
# resources/drawables is hand-made and not generated.
# Usage: python3 tools/gen-icons.py 54 60 65
import os, sys
from PIL import Image, ImageDraw

def icon(size):
    n = 1000
    im = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    orange, rim = (255, 170, 0, 255), (90, 30, 0, 255)
    d.ellipse([10, 10, n - 10, n - 10], fill=rim)
    d.ellipse([28, 28, n - 28, n - 28], fill=orange)
    r = 410
    for a in (90, 210, 330):
        d.pieslice([c - r, c - r, c + r, c + r], -a - 30, -a + 30, fill='black')
    d.ellipse([c - 150, c - 150, c + 150, c + 150], fill=orange)
    d.ellipse([c - 95, c - 95, c + 95, c + 95], fill='black')
    return im.resize((size, size), Image.LANCZOS)

root = os.path.join(os.path.dirname(__file__), '..')
for s in map(int, sys.argv[1:]):
    out = os.path.join(root, 'resources-icon%d' % s, 'drawables')
    os.makedirs(out, exist_ok=True)
    icon(s).save(os.path.join(out, 'launcher_icon.png'))
    with open(os.path.join(out, 'drawables.xml'), 'w') as f:
        f.write('<drawables>\n    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>\n</drawables>\n')
    print('resources-icon%d' % s)
