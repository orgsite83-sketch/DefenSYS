# DefenSYS sample import files

Demo CSV files for bulk import. Default password for imported users is the same as **id_number** (e.g. student `4081`, faculty `206`).

## Files

| File | Purpose |
|------|---------|
| `demo_faculty_import.csv` | 10 faculty accounts |
| `demo_students_1st_year_import.csv` | 4 first-year students (one team cohort) |
| `demo_students_2nd_year_import.csv` | 4 second-year students |
| `demo_students_3rd_year_import.csv` | 4 third-year students |
| `demo_students_4th_year_import.csv` | 4 fourth-year students |
| `demo_teams_1st_year_import.csv` | 1 PIT team (4 members) — **1st Year** PIT Lead |
| `demo_teams_2nd_year_import.csv` | 1 PIT team (4 members) — **2nd Year** PIT Lead |
| `demo_teams_3rd_year_import.csv` | 1 PIT team (4 members) — **3rd Year** PIT Lead |
| `demo_teams_4th_year_import.csv` | 1 capstone team (4 members) — **Admin** (4th Year) |
| `demo_teams_capstone_import.csv` | Same 3rd-year cohort as capstone — **Admin** in 2nd semester |

## Student id_number ranges

| Year | IDs | Leader (first in team CSV) |
|------|-----|----------------------------|
| 1st Year | 4011–4014 | James Rivera |
| 2nd Year | 4021–4024 | Darren Kim |
| 3rd Year | 4081–4084 | Carlos Reyes |
| 4th Year | 4091–4094 | Marcus Villar |

## If you already imported 12 students

Trim the database to the 4-student demo cohort:

```bash
cd backend
python manage.py remove_extra_demo_students --dry-run   # preview
python manage.py remove_extra_demo_students             # delete 4085-4092
```

Keeps: **4081** Carlos Reyes, **4082** Maria Santos, **4083** Juan Dela Cruz, **4084** Ana Mendoza.

## Recommended import order

1. **Academic Periods** — active school year and semester (e.g. 1st Semester ON).
2. **Users** → Bulk import `demo_faculty_import.csv` (Faculty / General Users).
3. **Role Assignment** — assign **Project Adviser** and **PIT Lead** per year (e.g. **Ricardo Fontanilla** for 3rd Year PIT Lead).
4. **Users** → Bulk import the student file for each year you need as **Student Batch** with the matching year level (fresh install only; skips duplicates if already imported).
5. **1st semester (PIT)** — log in as the **PIT Lead** for that year → **Student Teams** → bulk import the matching `demo_teams_*_year_import.csv` (or use **CSV Template** in the app to download a sample for that year).
6. **2nd semester (Capstone)** — log in as **admin** → **Student Teams** → bulk import `demo_teams_capstone_import.csv` or the 4th-year capstone file as appropriate.

## Team import notes

- CSV columns: `team_name`, `project_title`, `member_ids`, `leader_id`, `adviser_id` (optional: `year_level` for power users).
- No `level` column — the app derives **PIT vs Capstone** from your role.
- **PIT Lead:** program year comes from your PIT Lead assignment (e.g. 3rd Year PIT).
- **Admin capstone:** `year_level` is inferred from members’ academic records on the active semester (defaults to 3rd Year if members are not resolved yet). After rollover, a 4th-year cohort becomes **4th Year Capstone** automatically.
- Members, leader, and adviser use **First Last** names matching User Management (or numeric **id_number** / username, e.g. `4083`, to avoid duplicate-name errors).
- If team import fails with “multiple users match that name”, delete leftover test accounts: `python manage.py dev_remove_leftover_test_users --dry-run` then run without `--dry-run` in `backend/`.
- Adviser in capstone team files: **Ricardo Fontanilla** (faculty id `206`). PIT year samples leave `adviser_id` blank.

## In-app download

On **Student Teams**, **CSV Template** opens a year-level picker (admin) or downloads the sample for your PIT Lead year. Files match the `demo_teams_*` samples in this folder.
