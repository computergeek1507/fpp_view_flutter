"""Generate the FPP View app icon: a stylized RGB-pixel grid (evoking LED
matrix / pixel controllers) with a subtle radio-discovery wave, on a deep
night-blue rounded background. Outputs a 1024x1024 master PNG.
"""
import math
from PIL import Image, ImageDraw

SIZE = 1024
BG_TOP = (13, 27, 62)      # deep navy
BG_BOT = (24, 52, 112)     # lighter blue
PIXEL_ON = [
    (255, 64, 64),   # red
    (64, 220, 96),   # green
    (72, 132, 255),  # blue
    (255, 200, 48),  # amber
]


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bot):
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def lerp(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def main():
    base = vertical_gradient(SIZE, BG_TOP, BG_BOT).convert("RGBA")
    draw = ImageDraw.Draw(base)

    # --- discovery waves (concentric arcs) emanating from top-right ---
    cx, cy = int(SIZE * 0.80), int(SIZE * 0.20)
    for i, rad in enumerate(range(120, 460, 110)):
        alpha = 70 - i * 16
        if alpha < 12:
            alpha = 12
        bbox = [cx - rad, cy - rad, cx + rad, cy + rad]
        draw.arc(bbox, start=95, end=185, fill=(120, 170, 255, alpha), width=14)

    # --- pixel grid (the LED matrix) ---
    cols = rows = 5
    margin = int(SIZE * 0.18)
    grid = SIZE - margin * 2
    cell = grid / cols
    dot = cell * 0.62
    # A diagonal sweep determines brightness so it looks like a running chase.
    for r in range(rows):
        for c in range(cols):
            x0 = margin + c * cell + (cell - dot) / 2
            y0 = margin + r * cell + (cell - dot) / 2
            color = PIXEL_ON[(r + c) % len(PIXEL_ON)]
            # brightness wave along the anti-diagonal
            phase = (c - r) / (cols + rows)
            bright = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * math.pi * 2))
            lit = lerp((26, 38, 70), color, bright)
            # glow halo for lit pixels
            if bright > 0.6:
                halo = int(dot * 0.34)
                draw.ellipse(
                    [x0 - halo, y0 - halo, x0 + dot + halo, y0 + dot + halo],
                    fill=color + (60,),
                )
            draw.ellipse([x0, y0, x0 + dot, y0 + dot], fill=lit + (255,))
            # specular highlight
            hl = dot * 0.26
            draw.ellipse(
                [x0 + dot * 0.18, y0 + dot * 0.16, x0 + dot * 0.18 + hl, y0 + dot * 0.16 + hl],
                fill=(255, 255, 255, 70),
            )

    # round the corners
    mask = rounded_mask(SIZE, int(SIZE * 0.22))
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)

    out.save("assets/icon/app_icon.png")

    # A foreground-only version (transparent bg) for Android adaptive icons.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fgd = ImageDraw.Draw(fg)
    # re-draw just the pixel grid, scaled in a bit for adaptive safe zone
    inset = int(SIZE * 0.26)
    grid2 = SIZE - inset * 2
    cell2 = grid2 / cols
    dot2 = cell2 * 0.62
    for r in range(rows):
        for c in range(cols):
            x0 = inset + c * cell2 + (cell2 - dot2) / 2
            y0 = inset + r * cell2 + (cell2 - dot2) / 2
            color = PIXEL_ON[(r + c) % len(PIXEL_ON)]
            phase = (c - r) / (cols + rows)
            bright = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * math.pi * 2))
            lit = lerp((26, 38, 70), color, bright)
            fgd.ellipse([x0, y0, x0 + dot2, y0 + dot2], fill=lit + (255,))
    fg.save("assets/icon/app_icon_foreground.png")
    print("wrote assets/icon/app_icon.png and app_icon_foreground.png")


if __name__ == "__main__":
    main()
