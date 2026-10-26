#!/usr/bin/env python3
"""Renders Support/AppIcon.icns (needs Pillow). Re-run after tweaking the design."""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersampled canvas, downscaled for anti-aliasing
OUT = Path(__file__).resolve().parent.parent / "Support" / "AppIcon.icns"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # macOS icon grid: 824/1024 body with a soft drop shadow.
    inset = int(S * 100 / 1024)
    body = (inset, inset, S - inset, S - inset)
    radius = int((body[2] - body[0]) * 0.225)

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (body[0], body[1] + S * 0.012, body[2], body[3] + S * 0.012), radius, fill=(0, 0, 0, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)))

    # Diagonal indigo → violet → pink gradient.
    grad = Image.new("RGBA", (S, S))
    stops = [(0.0, (79, 70, 229)), (0.55, (139, 92, 246)), (1.0, (236, 72, 153))]
    px = grad.load()
    for y in range(0, S, 4):
        for x in range(0, S, 4):
            t = (x + y) / (2 * S)
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t0 <= t <= t1:
                    c = lerp(c0, c1, (t - t0) / (t1 - t0))
                    break
            for dy in range(4):
                for dx in range(4):
                    px[x + dx, y + dy] = (*c, 255)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Subtle top highlight.
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse((-S * 0.2, -S * 0.75, S * 1.2, S * 0.45), fill=(255, 255, 255, 26))
    hl = hl.filter(ImageFilter.GaussianBlur(S * 0.03))
    hl_mask = Image.new("L", (S, S), 0)
    hl_mask.paste(mask)
    img.paste(hl, (0, 0), Image.composite(hl.split()[3], Image.new("L", (S, S), 0), hl_mask))

    d = ImageDraw.Draw(img)
    cx = cy = S / 2

    # Two cards: the "before" file behind, the "after" file in front.
    cw, ch, cr = S * 0.26, S * 0.32, S * 0.035
    back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(back).rounded_rectangle(
        (cx - cw * 0.95, cy - ch * 0.62, cx + cw * 0.05, cy + ch * 0.38), cr, fill=(255, 255, 255, 95))
    img.alpha_composite(back.rotate(8, center=(cx, cy), resample=Image.BICUBIC))
    front = (cx - cw * 0.05, cy - ch * 0.38, cx + cw * 0.95, cy + ch * 0.62)
    d.rounded_rectangle(front, cr, fill=(255, 255, 255, 255))
    # A tiny landscape on the front card (mountain + sun) in the gradient colour.
    fx0, fy0, fx1, fy1 = front
    fw, fh = fx1 - fx0, fy1 - fy0
    d.ellipse((fx0 + fw * 0.58, fy0 + fh * 0.18, fx0 + fw * 0.80, fy0 + fh * 0.36), fill=(236, 72, 153, 255))
    d.polygon([(fx0 + fw * 0.12, fy0 + fh * 0.82), (fx0 + fw * 0.42, fy0 + fh * 0.42),
               (fx0 + fw * 0.62, fy0 + fh * 0.66), (fx0 + fw * 0.72, fy0 + fh * 0.56),
               (fx0 + fw * 0.88, fy0 + fh * 0.82)], fill=(99, 82, 238, 255))

    # Curved conversion arrow from the back card to the front card.
    r = S * 0.27
    w = int(S * 0.045)
    box = (cx - r, cy - r, cx + r, cy + r)
    d.arc(box, start=200, end=294, fill=(255, 255, 255, 255), width=w)
    end = math.radians(290)
    ex, ey = cx + r * math.cos(end), cy + r * math.sin(end)
    tangent = end + math.pi / 2
    head = S * 0.07
    pts = [
        (ex + head * math.cos(tangent), ey + head * math.sin(tangent)),
        (ex + head * 0.75 * math.cos(tangent + 2.3), ey + head * 0.75 * math.sin(tangent + 2.3)),
        (ex + head * 0.75 * math.cos(tangent - 2.3), ey + head * 0.75 * math.sin(tangent - 2.3)),
    ]
    d.polygon(pts, fill=(255, 255, 255, 255))

    icon = img.resize((1024, 1024), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    icon.save(OUT.with_suffix(".png"))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    sys.exit(main())
