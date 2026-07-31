#!/usr/bin/env python3
"""Конвертер старых (русских) txt-каталогов в новый английский формат.

Переименовывает заголовки секций и служебные строки, не трогая содержимое
описаний. Порядок секций не важен — приложение переупорядочит их при следующем
сохранении.

Использование:
    python3 convert_catalog.py path/to/catalog.txt [more.txt ...]

Рядом с каждым файлом создаётся резервная копия <имя>.ru.bak, а сам файл
перезаписывается в новом формате.
"""
import re
import sys
import shutil

# Заголовки секций (каждый — на отдельной строке): русский -> английский.
SECTION_HEADERS = {
    "Категории и теги": "Categories & tags",
    "Дата публикации": "Publication date",
    "Дата изменения": "Modification date",
    "Краткое описание": "Short description",
    "Полное описание": "Full description",
    # Старые синонимы из ранних версий.
    "Описание": "Description",
    "Содержимое": "Content",
}

# Заголовки каталога (первая строка файла) и строка счётчика.
PLAIN = {
    "SubliminalClub — содержимое страниц продуктов": "SubliminalClub — product page contents",
    "Quintessence (q.subliminalclub.com) — содержимое страниц продуктов":
        "Quintessence (q.subliminalclub.com) — product page contents",
    "Количество найденных товаров:": "Products found:",
}


def convert(text: str) -> str:
    # Заголовки секций — только когда занимают строку целиком (^...$),
    # чтобы не задеть те же слова внутри описаний.
    for ru, en in SECTION_HEADERS.items():
        text = re.sub(rf"(?m)^{re.escape(ru)}$", en, text)
    # Служебные строки — обычная замена (строки достаточно уникальны).
    for ru, en in PLAIN.items():
        text = text.replace(ru, en)
    return text


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    for path in argv:
        try:
            with open(path, encoding="utf-8") as f:
                original = f.read()
        except OSError as e:
            print(f"✗ {path}: {e}")
            continue
        converted = convert(original)
        if converted == original:
            print(f"• {path}: уже в новом формате (без изменений)")
            continue
        shutil.copyfile(path, path + ".ru.bak")
        with open(path, "w", encoding="utf-8") as f:
            f.write(converted)
        print(f"✓ {path}: сконвертирован (бэкап: {path}.ru.bak)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
