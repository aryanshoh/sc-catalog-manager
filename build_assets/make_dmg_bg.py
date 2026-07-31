#!/usr/bin/env python3
"""Рисует фон окна .dmg в стиле светлой (кремовой) темы: заголовок,
подсказка и стрелка от приложения к папке Applications. Рендерит PNG в 2×
(для Retina). Позиции иконок в build_app.sh согласованы с этой картинкой.

Запуск:  QT_QPA_PLATFORM=offscreen python3 build_assets/make_dmg_bg.py
"""

import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QByteArray, QRectF, Qt
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

HERE = Path(__file__).resolve().parent
OUT = HERE / "dmg_background.png"

# Окно 560×400 точек → картинка 1120×800 px (2×).
W, H = 1120, 800

CREAM_TOP = "#fdfaf2"
CREAM_BOTTOM = "#f3ecdd"
TITLE = "#2b2a28"
SUBTITLE = "#625c4f"
ARROW = "#7166c9"


def build_svg() -> str:
    # Стрелка между центрами иконок (app ≈ x300, Applications ≈ x820).
    ay = 470
    x1, x2 = 430, 690
    arrow = (
        f'<line x1="{x1}" y1="{ay}" x2="{x2 - 26}" y2="{ay}" stroke="{ARROW}" '
        f'stroke-width="12" stroke-linecap="round"/>'
        f'<path d="M {x2} {ay} L {x2 - 34} {ay - 22} L {x2 - 34} {ay + 22} Z" fill="{ARROW}"/>'
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="cream" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{CREAM_TOP}"/>
      <stop offset="1" stop-color="{CREAM_BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{W}" height="{H}" fill="url(#cream)"/>
  <text x="560" y="150" text-anchor="middle" font-family="Helvetica Neue, Helvetica, Arial"
        font-size="46" font-weight="500" fill="{TITLE}">Менеджер каталога</text>
  <text x="560" y="215" text-anchor="middle" font-family="Helvetica Neue, Helvetica, Arial"
        font-size="27" fill="{SUBTITLE}">Перетащите иконку в папку Applications</text>
  {arrow}
</svg>'''


def main() -> None:
    QGuiApplication([])
    svg = build_svg()
    renderer = QSvgRenderer(QByteArray(svg.encode("utf-8")))
    image = QImage(W, H, QImage.Format_ARGB32)
    image.fill(Qt.white)
    painter = QPainter(image)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setRenderHint(QPainter.TextAntialiasing)
    renderer.render(painter, QRectF(0, 0, W, H))
    painter.end()
    image.save(str(OUT))
    print(f"OK: {OUT}")


if __name__ == "__main__":
    main()
