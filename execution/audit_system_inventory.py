"""Read-only static inventory for system-flow audits; never initializes Django.

Usage: python execution/audit_system_inventory.py
Writes regenerable JSON under .tmp/system-flow-audit/.
"""
import ast
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.tmp' / 'system-flow-audit'


def source(node):
    return ast.unparse(node) if node is not None else ''


def inventory():
    result = {'models': [], 'views': [], 'urls': [], 'functions': [], 'tests': [], 'frontend': []}
    for path in sorted((ROOT / 'backend' / 'modules').rglob('*.py')):
        if {'migrations', '__pycache__'} & set(path.parts):
            continue
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding='utf-8-sig')
        try:
            tree = ast.parse(text)
        except SyntaxError as exc:
            result.setdefault('parse_errors', []).append({'file': rel, 'error': str(exc)})
            continue
        if 'management' not in path.parts and (path.name.startswith('test') or path.stem.endswith('_tests')):
            result['tests'].append({'file': rel, 'cases': sum(isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith('test') for n in ast.walk(tree))})
            continue
        for node in tree.body:
            if isinstance(node, ast.ClassDef):
                item = {'file': rel, 'line': node.lineno, 'name': node.name, 'bases': [source(b) for b in node.bases], 'methods': [], 'attributes': {}}
                for child in node.body:
                    if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        item['methods'].append({'name': child.name, 'line': child.lineno, 'doc': ast.get_docstring(child)})
                    if isinstance(child, ast.Assign):
                        for target in child.targets:
                            if isinstance(target, ast.Name):
                                value = source(child.value)
                                if len(value) < 1600:
                                    item['attributes'][target.id] = value
                if any('models.Model' in b or 'AbstractUser' in b for b in item['bases']):
                    result['models'].append(item)
                if path.name == 'views.py':
                    result['views'].append(item)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                result['functions'].append({'file': rel, 'line': node.lineno, 'name': node.name, 'doc': ast.get_docstring(node)})
        if path.name == 'urls.py':
            result['urls'].append({'file': rel, 'source': text})
    for path in sorted((ROOT / 'frontend' / 'lib').rglob('*.dart')):
        rel = path.relative_to(ROOT).as_posix()
        if '/navigation/' in rel or '/services/' in rel or '/notifications/' in rel:
            text = path.read_text(encoding='utf-8-sig')
            result['frontend'].append({'file': rel, 'api_lines': [{'line': i, 'text': line.strip()} for i, line in enumerate(text.splitlines(), 1) if any(marker in line for marker in ('ApiConfig.', 'baseUrl', 'path:', 'static const ', 'export '))]})
    if '--resolve-routes' in sys.argv:
        # Import configuration and URL declarations only. No queries, writes,
        # migrations, seed commands, or application HTTP calls are performed.
        sys.path.insert(0, str(ROOT / 'backend'))
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
        import django
        django.setup()
        from django.urls import URLResolver, get_resolver
        result['resolved_routes'] = []

        def walk(patterns, prefix=''):
            for pattern in patterns:
                route = prefix + str(pattern.pattern)
                if isinstance(pattern, URLResolver):
                    walk(pattern.url_patterns, route)
                elif route.startswith('api/'):
                    cls = getattr(pattern.callback, 'view_class', None) or getattr(pattern.callback, 'cls', None)
                    methods = [m.upper() for m in ('get', 'post', 'put', 'patch', 'delete') if cls and hasattr(cls, m)]
                    result['resolved_routes'].append({'route': '/' + route, 'view': f'{cls.__module__}.{cls.__name__}' if cls else str(pattern.callback), 'methods': methods, 'name': pattern.name})

        walk(get_resolver().url_patterns)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'inventory.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'output': str(OUT / 'inventory.json'), 'models': len(result['models']), 'view_classes': len(result['views']), 'url_files': len(result['urls']), 'backend_test_files': len(result['tests']), 'backend_test_cases_static': sum(t['cases'] for t in result['tests']), 'frontend_service_navigation_files': len(result['frontend']), 'parse_errors': result.get('parse_errors', [])}))


if __name__ == '__main__':
    inventory()
