# Application modules

Django apps for DefenSYS live here (each subfolder is one `INSTALLED_APPS` entry).

The project package stays at `backend/defensys_backend/`; `manage.py` stays at `backend/`.
`defensys_backend/settings.py` prepends this directory to `sys.path` so imports stay
short (`from student_teams.models import …`, app labels unchanged for migrations).

Do **not** rename app folders without updating `INSTALLED_APPS` and migration history.
