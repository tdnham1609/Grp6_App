@echo off
setlocal
cd /d "%~dp0"

echo Starting Firebase Emulator Suite for project sinhtuapp...
echo Keep this window open while testing the app.
echo Press Ctrl+C here to stop the emulators and save their data.
echo.

call npm.cmd --prefix functions run build
if errorlevel 1 (
    echo.
    echo Functions build failed. Emulators were not started.
    exit /b 1
)

call firebase.cmd emulators:start --only auth,firestore,functions,pubsub --project sinhtuapp --import=.firebase-demo-data --export-on-exit=.firebase-demo-data

echo.
echo Firebase Emulator Suite has stopped.
