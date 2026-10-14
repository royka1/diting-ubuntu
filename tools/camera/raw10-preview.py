#!/usr/bin/python3
"""Quick preview of a MIPI RAW10 (packed) Bayer frame: half-size demosaic,
grey-world white balance, gamma. For checking captures, not for photos.

Usage: raw10-preview.py RAW W H STRIDE ORDER OUT.png   (ORDER: RGGB, GRBG, GBRG, BGGR)
"""
import sys
import numpy as np
from PIL import Image

path, w, h, stride, order, out = sys.argv[1], *map(int, sys.argv[2:5]), sys.argv[5], sys.argv[6]
buf = np.fromfile(path, dtype=np.uint8)[:stride * h].reshape(h, stride)
b = buf[:, :w // 4 * 5].reshape(h, -1, 5).astype(np.uint16)
px = np.empty((h, w // 4 * 4), np.uint16)
for i in range(4):
    px[:, i::4] = (b[:, :, i] << 2) | ((b[:, :, 4] >> (2 * i)) & 3)
print(f'raw min {px.min()} max {px.max()} mean {px.mean():.1f}')
q = {order[0]: px[0::2, 0::2], order[1]: px[0::2, 1::2],
     order[2]: px[1::2, 0::2], order[3]: px[1::2, 1::2]}
g = (px[0::2, 1::2].astype(np.float32) + px[1::2, 0::2]) / 2 if order[1] == 'G' else \
    (px[0::2, 0::2].astype(np.float32) + px[1::2, 1::2]) / 2
r = q['R'].astype(np.float32)
bl = q['B'].astype(np.float32)
black = 64.0
r, g, bl = (np.clip(c - black, 0, None) for c in (r, g, bl))
r *= g.mean() / max(r.mean(), 1e-3)
bl *= g.mean() / max(bl.mean(), 1e-3)
rgb = np.stack([r, g, bl], -1)
rgb /= max(np.percentile(rgb, 99.5), 1)
rgb = np.clip(rgb, 0, 1) ** (1 / 2.2)
Image.fromarray((rgb * 255).astype(np.uint8)).save(out)
print('wrote', out)
