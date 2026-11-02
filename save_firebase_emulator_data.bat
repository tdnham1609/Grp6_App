@echo off
setlocal
cd /d "%~dp0"

echo Saving Firebase Emulator data to .firebase-demo-data...
call firebase.cmd emulators:export .firebase-demo-data --force --project sinhtuapp
if errorlevel 1 (
    echo.
    echo Export failed. Make sure the Firebase Emulator Suite is running.
    exit /b 1
)

echo.
echo Firebase Emulator data saved successfully.
