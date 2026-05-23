# Archived ad-hoc scripts

Manual scripts that duplicated app tests or targeted pre-consolidation module paths were moved here during the repository/defense/grading app merge cleanup.

**Do not run these against production.** Prefer:

```powershell
cd backend
python manage.py test repository.audit --keepdb
```

Use `--keepdb` to avoid interactive prompts when `test_defensys_db` already exists.
