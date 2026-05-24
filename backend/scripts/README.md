# Backend scripts (dev / ops)

**DEV ONLY** — not for production deploy pipelines.

| Script | Purpose |
|--------|---------|
| `probe_deliverable_upload.py` | Smoke-test capstone deliverable upload (see `docs/AGENTS.md`) |
| `check_defense_tables.py` | Inspect defense-related DB tables |
| `check_grade_tables.py` | Inspect grading-related DB tables |
| `fix_defense_table_names.py` | One-off table rename helper (dev DB only) |

Run from `backend/`:

```powershell
python scripts/probe_deliverable_upload.py
```

One-off migration/refactor scripts from the app-consolidation phases were removed in Phase 3 hygiene.
