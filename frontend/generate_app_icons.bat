@echo off
echo ========================================
echo DefenSYS App Icon Generator
echo ========================================
echo.

echo Step 1: Getting dependencies...
call flutter pub get
echo.

echo Step 2: Generating launcher icons...
call flutter pub run flutter_launcher_icons
echo.

echo ========================================
echo Done! App icons generated successfully.
echo ========================================
echo.
echo Next steps:
echo 1. Hot restart your Flutter app (press 'R')
echo 2. Or rebuild: flutter build apk --release
echo.
pause
