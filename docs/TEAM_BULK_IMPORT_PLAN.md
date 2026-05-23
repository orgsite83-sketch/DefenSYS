# Team bulk import — implemented

## Features

- **Full-name matching** (case-insensitive) for `member_ids`, `leader_id`, `adviser_id`
- **Preflight** with `row`, `sheet_row`, `team_name`, `issues[]`, `ready`
- **Editable review table** — fix rows in-app without Excel
- **Import ready rows only**
- **Persistent draft** (`shared_preferences`) with Resume / Discard banner
- **Partial import** — successful rows removed; failed rows stay in draft

## CSV example

```csv
team_name,project_title,level,year_level,member_ids,leader_id,adviser_id
Team VaultSync,Cloud File Sync,3rd Year Capstone,3rd Year,Juan Dela Cruz|Maria Santos,Juan Dela Cruz,Ada Lovelace
```

## Key files

- `backend/modules/student_teams/bulk_import.py`
- `frontend/lib/screens/web/admin/student_teams_screen.dart`
- `frontend/lib/screens/web/admin/widgets/team_bulk_import_review_table.dart`
- `frontend/lib/utils/team_bulk_import_draft.dart`
- `frontend/lib/utils/team_bulk_import_csv.dart`
