@echo off
REM Install dependencies for PDF generation feature

echo 📦 Installing PDF generation dependencies...
echo.

REM Check if virtual environment is activated
if "%VIRTUAL_ENV%"=="" (
    echo ⚠️  Warning: No virtual environment detected.
    echo    It's recommended to activate your virtual environment first.
    echo.
    set /p continue="Continue anyway? (y/n) "
    if /i not "%continue%"=="y" exit /b 1
)

REM Install reportlab
echo Installing reportlab...
pip install reportlab

REM Verify installation
echo.
echo ✅ Verifying installation...
python -c "import reportlab; print(f'ReportLab version: {reportlab.Version}')" 2>nul

if %errorlevel% equ 0 (
    echo.
    echo ✅ PDF generation dependencies installed successfully!
    echo.
    echo Next steps:
    echo 1. Run the test script: python test_pdf_generation.py
    echo 2. Start the Django server: python manage.py runserver
    echo 3. Test the feature in the frontend
) else (
    echo.
    echo ❌ Installation verification failed. Please check for errors above.
    exit /b 1
)
