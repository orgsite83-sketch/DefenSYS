"""Rewrite imports project-wide after Phase 3 consolidation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [
    ROOT / 'modules',
    ROOT / 'tests',
    ROOT.parent / 'frontend' / 'lib',
]

REPLACEMENTS = [
    ('from rubric_engine.', 'from grading.rubrics.'),
    ('import rubric_engine.', 'import grading.rubrics.'),
    ('from grade_center.', 'from grading.grades.'),
    ('import grade_center.', 'import grading.grades.'),
    ('from digital_vault.', 'from repository.vault.'),
    ('import digital_vault.', 'import repository.vault.'),
    ('from capstone_deliverables.', 'from repository.deliverables.'),
    ('import capstone_deliverables.', 'import repository.deliverables.'),
    ('from repository_audit.', 'from repository.audit.'),
    ('import repository_audit.', 'import repository.audit.'),
    ("'rubric_engine.Rubric'", "'grading.Rubric'"),
    ("'rubric_engine.rubric'", "'grading.rubric'"),
    ("to='rubric_engine.rubric'", "to='grading.rubric'"),
    ("'/api/rubrics/", "'/api/grading/rubrics/"),
    ("'/api/grade-center/", "'/api/grading/grades/"),
    ("'/api/digital-vault/", "'/api/repository/vault/"),
    ("'/api/capstone-deliverables/", "'/api/repository/deliverables/"),
    ("'/api/repository-audit/", "'/api/repository/audit/"),
    ("$baseUrl/rubrics", "$baseUrl/grading/rubrics"),
    ("$baseUrl/grade-center", "$baseUrl/grading/grades"),
    ("$baseUrl/digital-vault", "$baseUrl/repository/vault"),
    ("$baseUrl/capstone-deliverables", "$baseUrl/repository/deliverables"),
    ("$baseUrl/repository-audit", "$baseUrl/repository/audit"),
]

SKIP_DIRS = {
    'rubric_engine', 'grade_center', 'digital_vault',
    'capstone_deliverables', 'repository_audit',
}


def main():
    for base in TARGETS:
        if not base.is_dir():
            continue
        for path in base.rglob('*'):
            if path.suffix not in {'.py', '.dart'}:
                continue
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            text = path.read_text(encoding='utf-8')
            original = text
            for old, new in REPLACEMENTS:
                text = text.replace(old, new)
            if text != original:
                path.write_text(text, encoding='utf-8')
                print(f'updated {path.relative_to(ROOT.parent)}')


if __name__ == '__main__':
    main()
