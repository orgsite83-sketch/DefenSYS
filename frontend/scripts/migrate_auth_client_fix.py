import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

for p in (ROOT / 'lib').rglob('*.dart'):
    text = p.read_text(encoding='utf-8')
    orig = text
    text = text.replace(', headers: await _headers()', '')
    text = text.replace('headers: await _headers(),', '')
    text = re.sub(
        r"final prefs = await SharedPreferences\.getInstance\(\);\s*"
        r"final token = prefs\.getString\('jwt_token'\);\s*"
        r"if \(token == null[^}]*\}\s*"
        r"return \{[^}]*\};\s*",
        '',
        text,
        flags=re.DOTALL,
    )
    if text != orig:
        p.write_text(text, encoding='utf-8')
        print('fixed', p.relative_to(ROOT))
