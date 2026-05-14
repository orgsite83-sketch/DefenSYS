# DefenSYS - create/use one venv under backend\venv and install requirements.txt
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File .\backend\setup_venv.ps1
# Or from backend:     .\setup_venv.ps1

$ErrorActionPreference = 'Stop'
$BackendRoot = $PSScriptRoot
Set-Location $BackendRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DefenSYS - Single Python environment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Backend: $BackendRoot`n"

$venvPython = Join-Path $BackendRoot 'venv\Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    Write-Host '[1/4] Creating venv\ ...' -ForegroundColor Yellow
    & python -m venv (Join-Path $BackendRoot 'venv')
    if (-not (Test-Path $venvPython)) {
        throw 'python -m venv failed. Install Python 3.12+ and ensure python is on PATH.'
    }
    Write-Host "OK - venv created.`n"
} else {
    Write-Host "[1/4] Using existing venv\`n"
}

Write-Host '[2/4] Using venv Python:' -ForegroundColor Yellow
& $venvPython -c "import sys; print(sys.executable)"
Write-Host ''

Write-Host '[3/4] pip install -r requirements.txt ...' -ForegroundColor Yellow
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $BackendRoot 'requirements.txt')
Write-Host "OK - dependencies installed.`n"

Write-Host '[4/4] Verifying imports...' -ForegroundColor Yellow
& $venvPython -c @"
import django
import rest_framework
import dotenv
import psycopg2
print('  Django', django.get_version())
print('  OK imports.')
"@

Write-Host "`n========================================" -ForegroundColor Green
Write-Host 'Done. Activate in this shell:' -ForegroundColor Green
Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor White
Write-Host "Then: python manage.py runserver 0.0.0.0:8000`n" -ForegroundColor White
