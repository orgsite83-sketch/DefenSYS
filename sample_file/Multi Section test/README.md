# DefenSYS Multi-Section Test Data Suite

Sample import CSV files configured for testing **multi-section** cohorts and team management across all year levels and semesters.

## Structure Overview

Each academic year level contains **3 sections** (e.g. Sections A, B, and C) with **1 team per section** (4 members per team, 12 students total per year level).

```text
Multi Section test/
├── 1st_Year/
│   ├── 1st_Sem/
│   │   ├── students_section_1A_import.csv   (BSIT-1A: 4 students -> Team NovaPath)
│   │   ├── students_section_1B_import.csv   (BSIT-1B: 4 students -> Team ByteForce)
│   │   ├── students_section_1C_import.csv   (BSIT-1C: 4 students -> Team NexGen)
│   │   ├── teams_import.csv                 (All 3 teams: 1 from each section)
│   │   └── defense_schedule_import.csv      (Defense schedule for all 3 teams)
│   └── 2nd_Sem/
│       ├── students_section_1A_import.csv
│       ├── students_section_1B_import.csv
│       ├── students_section_1C_import.csv
│       ├── teams_import.csv
│       └── defense_schedule_import.csv
├── 2nd_Year/
│   ├── 1st_Sem/
│   │   ├── students_section_2A_import.csv   (BSIT-2A: 4 students -> Team Quantum)
│   │   ├── students_section_2B_import.csv   (BSIT-2B: 4 students -> Team ByteForce)
│   │   ├── students_section_2C_import.csv   (BSIT-2C: 4 students -> Team NexGen)
│   │   ├── teams_import.csv                 (All 3 teams: 1 from each section)
│   │   └── defense_schedule_import.csv
│   └── 2nd_Sem/
│       ├── students_section_2A_import.csv
│       ├── students_section_2B_import.csv
│       ├── students_section_2C_import.csv
│       ├── teams_import.csv
│       └── defense_schedule_import.csv
├── 3rd_Year/
│   ├── PIT/                                 (1st Semester PIT)
│   │   ├── students_section_3A_import.csv   (BSIT-3A: 4 students -> Team CodeLearners)
│   │   ├── students_section_3B_import.csv   (BSIT-3B: 4 students -> Team ByteForce)
│   │   ├── students_section_3C_import.csv   (BSIT-3C: 4 students -> Team NexGen)
│   │   ├── teams_import.csv
│   │   └── defense_schedule_import.csv
│   └── Capstone/                            (2nd Semester Capstone)
│       ├── students_section_3A_import.csv   (BSIT-3A: 4 students -> Team Site Avengers)
│       ├── students_section_3B_import.csv   (BSIT-3B: 4 students -> Team ByteForce)
│       ├── students_section_3C_import.csv   (BSIT-3C: 4 students -> Team NexGen)
│       ├── capstone_teams_import.csv
│       └── defense_schedule_import.csv
└── 4th_Year_Capstone/
    ├── students_section_4A_import.csv       (BSIT-4A: 4 students -> Team SkyLedger)
    ├── students_section_4B_import.csv       (BSIT-4B: 4 students -> Team ByteForce)
    ├── students_section_4C_import.csv       (BSIT-4C: 4 students -> Team NexGen)
    ├── teams_import.csv
    └── defense_schedule_import.csv
```

## Section, Student, and Team Matrix

| Year Level | Section | Instructor | Student IDs | Team Name | Project Name (PIT / Capstone) |
|---|---|---|---|---|---|
| **1st Year** | BSIT-1A | Maricel Suarez | 1011 - 1014 | Team NovaPath | Campus Wayfinder App / Unified Campus Gateway |
| | BSIT-1B | Jonathan Beltran | 1015 - 1018 | Team ByteForce | Smart Locker System / Cloud Locker Network |
| | BSIT-1C | Analiza Corpuz | 1019 - 1022 | Team NexGen | Interactive Map / Autonomous Map Guide |
| **2nd Year** | BSIT-2A | Jonathan Beltran | 2011 - 2014 | Team Quantum | Automated Grade Calculator / Academic Analytics Portal |
| | BSIT-2B | Analiza Corpuz | 2015 - 2018 | Team ByteForce | Library Seat Reservation / Smart Library Ecosystem |
| | BSIT-2C | Renato Villanueva | 2019 - 2022 | Team NexGen | Student Health Tracker / Campus Health Ledger |
| **3rd Year** | BSIT-3A | Maricel Suarez | 4081 - 4084 | Team CodeLearners / Team Site Avengers | Smart Campus Navigator / DefenSYS |
| | BSIT-3B | Jonathan Beltran | 4085 - 4088 | Team ByteForce | IoT-Based Smart Classroom Monitor / AI-Powered Attendance System |
| | BSIT-3C | Analiza Corpuz | 4089 - 4092 | Team NexGen | Online Complaint Management System / Campus Lost and Found Portal |
| **4th Year** | BSIT-4A | Ricardo Fontanilla | 4011 - 4014 | Team SkyLedger | Alumni Career Tracker |
| | BSIT-4B | Analiza Corpuz | 4015 - 4018 | Team ByteForce | AI-Powered Attendance System |
| | BSIT-4C | Renato Villanueva | 4019 - 4022 | Team NexGen | Campus Lost and Found Portal |

## Recommended Import Workflow

1. **Faculty Users**: Import `sample_file/faculty_user/demo_faculty_import.csv` in **User Management** so instructors, chairs, and panelists (`206` to `215`) exist.
2. **Student Sections**: In **PIT Lead -> Cohort** (or **Admin -> User Management / Student Batch**), import the section CSV files one-by-one:
   - `students_section_XA_import.csv`
   - `students_section_XB_import.csv`
   - `students_section_XC_import.csv`
   This automatically creates student accounts and establishes the section-instructor assignments (`BSIT-XA`, `BSIT-XB`, `BSIT-XC`).
3. **Student Teams**: In **Student Teams**, import `teams_import.csv` (or `capstone_teams_import.csv` for Capstone) to form the 3 teams across the 3 sections.
4. **Defense Scheduler**: In **Defense Scheduler -> Import Schedule**, import `defense_schedule_import.csv` to schedule the 3 defense slots with chair, panelists, and documenter assigned.
