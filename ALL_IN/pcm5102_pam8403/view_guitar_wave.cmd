@echo off
if not exist "%~dp0sim\build\guitar_wave.png" (
    echo Waveform image not found in sim\build.
    pause
    exit /b 1
)
start "" "%~dp0sim\build\guitar_wave.png"
