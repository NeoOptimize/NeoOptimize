@echo off
REM Neo Optimize AI Gradio UI Startup Script
REM Run this to start the Gradio web interface

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Neo Optimize AI Gradio UI Startup Script
echo ============================================================
echo.

REM Check Python installation
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    pause
    exit /b 1
)

REM Get script directory
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

REM Check if venv exists
if not exist venv (
    echo Creating Python virtual environment...
    python -m venv venv
)

REM Activate venv
call venv\Scripts\activate.bat

REM Install requirements if needed
python -c "import gradio" >nul 2>&1
if errorlevel 1 (
    echo Installing Python dependencies...
    pip install --upgrade pip
    pip install -r requirements-neoai.txt
)

REM Start UI
echo.
echo ============================================================
echo Starting Neo Optimize AI Gradio Interface...
echo ============================================================
echo.
echo Web interface will open at: http://localhost:7861
echo Backend API should be running on: http://localhost:7860
echo.
echo Press Ctrl+C to stop
echo.

python gradio_ui.py

pause
