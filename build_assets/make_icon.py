#!/usr/bin/env python3
"""Генерирует иконку приложения (мозг) в стиле светлой темы и собирает
AppIcon.icns. Мозг строится программно как «цветная капуста» из бугров-извилин
на кремовом squircle-фоне; фиолетовый акцент — как в светлой теме приложения.

Запуск (из .venv Qt-версии, где есть PySide6):
    QT_QPA_PLATFORM=offscreen python3 build_assets/make_icon.py
"""

import math
import os
import subprocess
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QByteArray, QRectF, Qt
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

HERE = Path(__file__).resolve().parent
ICONSET = HERE / "AppIcon.iconset"
ICNS = HERE / "AppIcon.icns"

# Палитра светлой темы приложения
CREAM_TOP = "#fdfaf2"
CREAM_BOTTOM = "#f1ead9"
BORDER = "#e2dac8"
BRAIN_TOP = "#8a7fe0"
BRAIN_BOTTOM = "#6a5cc4"
BRAIN_OUTLINE = "#4a3f97"
GYRI = "#d8d2f4"


def scalloped_outline(cx: float, cy: float, r: float, bumps: int, bump_r: float) -> str:
    """Замкнутый контур-«капуста»: точки на окружности, соединённые дугами
    наружу, дают ряд округлых бугров (извилин)."""
    pts = [
        (cx + r * math.cos(-math.pi / 2 + 2 * math.pi * i / bumps),
         cy + r * math.sin(-math.pi / 2 + 2 * math.pi * i / bumps))
        for i in range(bumps)
    ]
    d = f"M {pts[0][0]:.1f} {pts[0][1]:.1f} "
    for i in range(1, bumps + 1):
        x, y = pts[i % bumps]
        d += f"A {bump_r:.0f} {bump_r:.0f} 0 0 1 {x:.1f} {y:.1f} "
    return d + "Z"


def build_svg() -> str:
    cx, cy = 512, 512
    outline = scalloped_outline(cx, cy, r=190, bumps=11, bump_r=64)

    # Внутренние борозды (светлые линии-извилины) и центральная щель.
    fissure = "M 512 340 C 486 400 540 440 508 500 C 480 552 540 592 512 672"
    left_folds = [
        "M 470 400 C 420 420 430 470 392 476",
        "M 452 500 C 402 508 420 560 372 566",
        "M 470 600 C 430 606 442 636 404 648",
    ]
    right_folds = [
        "M 554 400 C 604 420 594 470 632 476",
        "M 572 500 C 622 508 604 560 652 566",
        "M 554 600 C 594 606 582 636 620 648",
    ]
    folds = "".join(
        f'<path d="{p}" fill="none" stroke="{GYRI}" stroke-width="15" '
        f'stroke-linecap="round"/>' for p in ([fissure] + left_folds + right_folds)
    )

    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="cream" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{CREAM_TOP}"/>
      <stop offset="1" stop-color="{CREAM_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="brain" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BRAIN_TOP}"/>
      <stop offset="1" stop-color="{BRAIN_BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect x="64" y="64" width="896" height="896" rx="224"
        fill="url(#cream)" stroke="{BORDER}" stroke-width="6"/>
  <g transform="translate(512 512) scale(1.32) translate(-512 -512)">
    <path d="{outline}" fill="url(#brain)" stroke="{BRAIN_OUTLINE}"
          stroke-width="9" stroke-linejoin="round"/>
    {folds}
  </g>
</svg>'''


SIZES = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def main() -> None:
    QGuiApplication([])
    svg = build_svg()
    (HERE / "AppIcon.svg").write_text(svg, encoding="utf-8")
    renderer = QSvgRenderer(QByteArray(svg.encode("utf-8")))

    ICONSET.mkdir(exist_ok=True)
    for name, px in SIZES:
        image = QImage(px, px, QImage.Format_ARGB32)
        image.fill(Qt.transparent)
        painter = QPainter(image)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        renderer.render(painter, QRectF(0, 0, px, px))
        painter.end()
        image.save(str(ICONSET / name))

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"OK: {ICNS}")


if __name__ == "__main__":
    main()
