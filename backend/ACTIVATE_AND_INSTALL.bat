@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================
echo DefenSYS - Single Python environment
echo ========================================
echo.
echo Backend folder: %CD%
echo.

REM --- [1/4] Create venv if missing ---
if not exist "venv\Scripts\python.exe" (
    echo [1/4] Creating virtual environment in .\venv ...
    python -m venv venv
    if errorlevel 1 (
        echo.
        echo ERROR: "python -m venv venv" failed.
        echo Install Python 3.12+ and ensure "python" is on PATH, then run this script again.
        echo.
        pause
        exit /b 1
    )
    echo OK - venv created.
) else (
    echo [1/4] Existing venv found - reusing .\venv
)
echo.

REM --- [2/4] Activate ---
echo [2/4] Activating virtual environment...
call "%~dp0venv\Scripts\activate.bat"
if errorlevel 1 (
    echo.
    echo ERROR: Could not activate venv. Check that venv\Scripts\activate.bat exists.
    echo.
    pause
    exit /b 1
)
echo OK - venv active.
where python
echo.

REM --- [3/4] Install full stack from requirements.txt ---
echo [3/4] pip install -r requirements.txt ^(this may take a few minutes^)...
python -m pip install --upgrade pip
if errorlevel 1 (
    echo WARNING: pip self-upgrade reported an error; continuing anyway.
)
python -m pip install -r "%~dp0requirements.txt"
if errorlevel 1 (
    echo.
    echo ERROR: pip install -r requirements.txt failed.
    echo.
    pause
    exit /b 1
)
echo OK - dependencies installed.
echo.

REM --- [4/4] Quick import smoke test ---
echo [4/4] Verifying Django, DRF, dotenv, psycopg2...
python -c "import django; import rest_framework; import dotenv; import psycopg2; print('  Django', django.get_version()); print('  OK imports.')"
if errorlevel 1 (
    echo.
    echo ERROR: Import verification failed.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo Done - single env ready
echo ========================================
echo.
echo Next: copy .env.example to .env if you have not already, then:
echo   python manage.py runserver 0.0.0.0:8000
echo.
echo This window stays open with the venv activated.
echo.

cmd /k
