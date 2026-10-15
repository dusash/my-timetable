"""生成「我的课表」的桌面图标。

不依赖任何第三方图形库（这台机器上装不了 Pillow），
直接用标准库里的 zlib + struct 手写 PNG，图形按比例逐个尺寸重绘。
好处是每个 dpi 都是矢量式画出来的，放大缩小都清晰。

用法：
    python tool/make_icon.py
"""

import os
import struct
import zlib

# 与 App 主题色一致
BG = (63, 111, 181)  # #3F6FB5
WHITE = (255, 255, 255)
ACCENT = (255, 194, 75)  # #FFC24B

# 网格布局（全部用 0~1 的比例表示，跟画布大小无关）
GRID_LEFT = 0.22
GRID_TOP = 0.22
CELL = 0.1567
GAP = 0.045
RADIUS = 0.024

# 哪一格高亮（行, 列），从 0 开始
HIGHLIGHT = (1, 0)

DPI_SIZES = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]


def write_png(path, width, height, rgba):
    """把 RGBA 字节流写成 PNG 文件。"""

    def chunk(tag, data):
        body = tag + data
        return (
            struct.pack(">I", len(data))
            + body
            + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    raw = b"".join(
        b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height)
    )
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def in_round_rect(x, y, x0, y0, x1, y1, r):
    """点 (x, y) 是否落在圆角矩形里。"""
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    # 把点夹到「圆角圆心构成的矩形」上，比较距离即可。
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    dx = x - cx
    dy = y - cy
    return dx * dx + dy * dy <= r * r


def coverage(test, px, py, samples=3):
    """用超采样估算一个像素被图形覆盖的比例，用来做平滑边缘。"""
    hit = 0
    for i in range(samples):
        for j in range(samples):
            sx = px + (i + 0.5) / samples
            sy = py + (j + 0.5) / samples
            if test(sx, sy):
                hit += 1
    return hit / (samples * samples)


def blend(base, color, alpha):
    return tuple(round(b + (c - b) * alpha) for b, c in zip(base, color))


def draw_icon(size):
    """按给定边长画一张图标，返回 RGBA 字节流。"""
    # 底：整幅主题色（铺满，系统怎么裁都不会露白边）
    pixels = bytearray()
    for _ in range(size):
        for _ in range(size):
            pixels.extend(BG + (255,))

    def paint(x0, y0, x1, y1, color, radius):
        r = radius * size
        for py in range(int(y0), int(y1) + 1):
            for px in range(int(x0), int(x1) + 1):
                a = coverage(
                    lambda x, y: in_round_rect(x, y, x0, y0, x1, y1, r),
                    px,
                    py,
                )
                if a <= 0:
                    continue
                idx = (py * size + px) * 4
                cur = (pixels[idx], pixels[idx + 1], pixels[idx + 2])
                new = blend(cur, color, a)
                pixels[idx] = new[0]
                pixels[idx + 1] = new[1]
                pixels[idx + 2] = new[2]

    # 九宫格：3 列 × 3 行的小方块，像一张迷你课表
    for row in range(3):
        for col in range(3):
            x0 = (GRID_LEFT + col * (CELL + GAP)) * size
            y0 = (GRID_TOP + row * (CELL + GAP)) * size
            x1 = x0 + CELL * size
            y1 = y0 + CELL * size
            color = ACCENT if (row, col) == HIGHLIGHT else WHITE
            paint(x0, y0, x1, y1, color, RADIUS)

    return bytes(pixels)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, "android", "app", "src", "main", "res")

    for folder, size in DPI_SIZES:
        path = os.path.join(res, folder, "ic_launcher.png")
        write_png(path, size, size, draw_icon(size))
        print("wrote", os.path.relpath(path, root), f"{size}x{size}")

    # 额外导出一张 512 的大图，方便预览 / 以后做自适应图标
    preview = os.path.join(root, "tool", "icon_preview_512.png")
    write_png(preview, 512, 512, draw_icon(512))
    print("wrote", os.path.relpath(preview, root), "512x512")


if __name__ == "__main__":
    main()
