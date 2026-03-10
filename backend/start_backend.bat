@echo off
REM Neo Optimize AI Backend Startup Script
REM Run this to start the backend FastAPI server

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Neo Optimize AI Backend Startup Script
echo ============================================================
echo.

REM Check Python installation
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.10+ from https://www.python.org
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
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment
        pause
        exit /b 1
    )
)

REM Activate venv
call venv\Scripts\activate.bat

REM Install/update requirements
echo Installing Python dependencies...
pip install --upgrade pip
pip install -r requirements-neoai.txt
if errorlevel 1 (
    echo ERROR: Failed to install requirements
    pause
    exit /b 1
)

REM Check for .env file
if not exist .env (
    echo WARNING: .env file not found
    echo Creating .env with placeholder values...
    (
        echo HF_TOKEN=hf_placeholder_token_for_testing
        echo HF_MODEL_ID=Qwen/Qwen2.5-7B-Instruct
        echo SUPABASE_URL=https://placeholder.supabase.co
        echo SUPABASE_KEY=placeholder_key
        echo CLIENT_API_KEY=dev_key_12345
        echo APP_ENV=development
    ) > .env
    echo.
    echo Created .env file - UPDATE with your actual credentials!
)

REM Start backend
echo.
echo ============================================================
echo Starting Neo Optimize AI Backend Server...
echo ============================================================
echo.
echo Backend will run on: http://localhost:7860
echo API endpoint: http://localhost:7860/docs
echo.
echo Press Ctrl+C to stop the server
echo.

python neoai_backend.py

pause
