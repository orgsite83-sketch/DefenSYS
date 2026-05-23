"""Rewrite imports after Phase 3 app consolidation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / 'modules'

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
    ("'rubric_engine.RubricCriterion'", "'grading.RubricCriterion'"),
    ("'grade_center.TeamGrade'", "'grading.TeamGrade'"),
    ("'grade_center.teamgrade'", "'grading.teamgrade'"),
    ("to='rubric_engine.rubric'", "to='grading.rubric'"),
    ("to='grade_center.teamgrade'", "to='grading.teamgrade'"),
]

DIRS = [ROOT / 'grading', ROOT / 'repository']


def main():
    for base in DIRS:
        for path in base.rglob('*.py'):
            text = path.read_text(encoding='utf-8')
            original = text
            for old, new in REPLACEMENTS:
                text = text.replace(old, new)
            if text != original:
                path.write_text(text, encoding='utf-8')
                print(f'updated {path.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
