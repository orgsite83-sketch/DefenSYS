# DefenSYS sample import files

Demo CSV files for bulk import. Default password for imported users is the same as **id_number** (for example student `4081`, faculty `206`).

## Files

| File | Purpose |
|------|---------|
| `demo_faculty_import.csv` | 10 faculty accounts |
| `demo_students_1st_year_import.csv` | 1st-year official class list for admin Student Batch import |
| `demo_students_2nd_year_import.csv` | 2nd-year official class list for admin Student Batch import |
| `demo_students_3rd_year_import.csv` | 3rd-year official class list for admin Student Batch import |
| `demo_students_4th_year_import.csv` | 4th-year official class list for admin Student Batch import |
| `demo_pit_lead_official_class_list_import.csv` | PIT Lead Cohort import sample using the official class list template |
| `demo_teams_1st_year_import.csv` | 1 PIT team, 4 members, for 1st Year PIT Lead |
| `demo_teams_2nd_year_import.csv` | 1 PIT team, 4 members, for 2nd Year PIT Lead |
| `demo_teams_3rd_year_import.csv` | 1 PIT team, 4 members, for 3rd Year PIT Lead |
| `demo_teams_4th_year_import.csv` | 1 capstone team, 4 members, for Admin 4th Year |
| `demo_teams_capstone_import.csv` | Same 3rd-year cohort as capstone, for Admin in 2nd semester |
| `demo_admin_defense_schedule_import.csv` | Defense Scheduler import sample matching the 3rd-year capstone demo team |

## Student Id Number Ranges

| Year | IDs | Leader in team CSV |
|------|-----|--------------------|
| 1st Year | 4011-4014 | James Rivera |
| 2nd Year | 4021-4024 | Darren Kim |
| 3rd Year | 4081-4084 | Carlos Reyes |
| 4th Year | 4091-4094 | Marcus Villar |

## PIT Lead Official Class List

Use `demo_pit_lead_official_class_list_import.csv` from:

```text
PIT Lead -> User Management -> Cohort -> Import Official Class List
```

This file follows the current Cohort template:

```text
OFFICIAL LIST OF ENROLLED STUDENTS
Subject Code
Subject Title
Instructor
Class Section
Year Level
#, Student Number, Full Name, Program, Gender, Level, OR No., Validation Date, Email, Contact
```

The sample uses:

```text
Instructor: Maricel Suarez
Section: BSIT-3A
Year Level: 3rd Year
Students: 4081-4084
```

Import `demo_faculty_import.csv` first so the official class list instructor can match `Maricel Suarez` to an existing faculty account and create the PIT Instructor assignment automatically.

## If You Already Imported 12 Students

Trim the database to the 4-student demo cohort:

```bash
cd backend
python manage.py remove_extra_demo_students --dry-run
python manage.py remove_extra_demo_students
```

Keeps: **4081** Carlos Reyes, **4082** Maria Santos, **4083** Juan Dela Cruz, **4084** Ana Mendoza.

## Recommended Import Order

1. **Academic Periods** - create or activate the school year and semester, for example 1st Semester ON.
2. **Users** - bulk import `demo_faculty_import.csv` as Faculty / General Users.
3. **Role Assignment** - assign **Project Adviser** and **PIT Lead** per year, for example Ricardo Fontanilla for 3rd Year PIT Lead.
4. **Admin student setup** - if admin is seeding students directly, bulk import the matching `demo_students_*_year_import.csv` as **Student Batch**. These files use the official class list shape and include section/year metadata.
5. **PIT Lead student setup** - log in as the PIT Lead, open **Cohort**, then import `demo_pit_lead_official_class_list_import.csv` with **Import Official Class List**.
6. **1st semester PIT teams** - log in as the PIT Lead for that year, open **Student Teams**, then bulk import the matching `demo_teams_*_year_import.csv`.
7. **2nd semester Capstone teams** - log in as admin, open **Student Teams**, then bulk import `demo_teams_capstone_import.csv` or the 4th-year capstone file as appropriate.
8. **Defense Scheduler import** - configure the `Concept Proposal` stage and its published panel/adviser/peer rubrics, mark faculty `207`, `208`, `209`, and `210` as Defense Panelists, then use **Defense Scheduler -> Import Schedule** with `demo_admin_defense_schedule_import.csv`.

## Team Import Notes

- CSV columns: `team_name`, `project_title`, `member_ids`, `leader_id`, `adviser_id`.
- Optional column for power users: `year_level`.
- No `level` column. The app derives PIT vs Capstone from your role.
- PIT Lead program year comes from the PIT Lead assignment.
- Admin capstone `year_level` is inferred from members' academic records on the active semester.
- Members, leader, and adviser can use First Last names matching User Management, or numeric id numbers like `4083`.
- If team import fails with multiple matching users, delete leftover test accounts with `python manage.py dev_remove_leftover_test_users --dry-run`, then run without `--dry-run` in `backend/`.
- Adviser in capstone team files is Ricardo Fontanilla, faculty id `206`. PIT year samples leave `adviser_id` blank.

## In-App Download

On **Cohort**, **CSV Template** downloads the PIT Lead official class list shape. Use `demo_pit_lead_official_class_list_import.csv` as the matching sample file.

On **Student Teams**, **CSV Template** opens a year-level picker for admin or downloads the sample for the PIT Lead year. Files match the `demo_teams_*` samples in this folder.

On **Defense Scheduler**, use `demo_admin_defense_schedule_import.csv` after importing:

```text
demo_faculty_import.csv
demo_students_3rd_year_import.csv
demo_teams_capstone_import.csv
```

The schedule sample uses:

```text
Team: Team Site Avengers
Project: DefenSYS
Adviser: 206 Ricardo Fontanilla
Chair: 207 Maricel Suarez
Panelists: 208 Jonathan Beltran, 209 Analiza Corpuz, 210 Renato Villanueva
Documenter: 211 Cecilia Magbanua
```

The documenter is parsed and shown in preview only. The current system does not assign documenters to schedules yet.

## PIT Imports Folder (`pit_imports/`)

A dedicated folder containing separated CSV templates for PIT import matching the current **Team CodeLearners** in the database:

1. [user_students_import.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/pit_imports/user_students_import.csv): Student cohort class list using the official enrollments template. Imports the four student members (`4081-4084`) and sets the instructor to `Maricel Suarez`.
2. [user_faculty_import.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/pit_imports/user_faculty_import.csv): Faculty account bulk import file. Sets up adviser/panelists `206-211`.
3. [team_import.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/pit_imports/team_import.csv): PIT team creation file for **Team CodeLearners** and project **Smart Campus Navigator**.
4. [schedule_import.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/pit_imports/schedule_import.csv): PIT defense schedule import file using the three-row header in-app template.

