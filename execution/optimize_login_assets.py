"""Encode the existing login photos for desktop and phone displays.

Run with backend/venv/Scripts/python.exe. Requires Pillow, already available in
the backend environment. Original PNGs stay intact as the source assets.
"""

from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'frontend' / 'assets'
OUTPUT = ASSETS / 'login'


def main() -> None:
    sources = [ASSETS / f'login_hero_{index}.png' for index in range(1, 8)]
    for source in sources:
        if not source.is_file():
            raise FileNotFoundError(source)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source_bytes = sum(source.stat().st_size for source in sources)
    for variant, max_size, quality in (
        ('desktop', 2048, 85), ('mobile', 1280, 82),
    ):
        total = 0
        for index, source in enumerate(sources, start=1):
            with Image.open(source) as original:
                photo = ImageOps.exif_transpose(original).convert('RGB')
                photo.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
                target = OUTPUT / f'hero_{variant}_{index}.webp'
                photo.save(target, format='WEBP', quality=quality, method=6)
                total += target.stat().st_size
        print(f'{variant}: {source_bytes:,} -> {total:,} bytes '
              f'({100 * (1 - total / source_bytes):.1f}% smaller)')


if __name__ == '__main__':
    main()
