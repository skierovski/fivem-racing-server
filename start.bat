@echo off
title BlackList Racing - Server Launcher
echo ============================================
echo  BlackList Racing - Starting Server
echo ============================================
echo.

:: Run tests before starting
echo [1/3] Running test suite...
cd /d "%~dp0"
call node tests/run.js
if errorlevel 1 (
    echo.
    echo ============================================
    echo  TESTS FAILED - Server will NOT start.
    echo  Fix the failing tests and try again.
    echo ============================================
    pause
    exit /b 1
)
echo       All tests passed.
echo.

:: Start MariaDB if not already running
echo [2/3] Starting MariaDB...
tasklist /FI "IMAGENAME eq mysqld.exe" | find "mysqld.exe" >nul 2>&1
if errorlevel 1 (
    start "" /B "%~dp0mariadb\mariadb-11.4.4-winx64\bin\mysqld.exe" --datadir="%~dp0mariadb\mariadb-11.4.4-winx64\data" --port=3306
    echo       MariaDB started.
    timeout /t 3 /nobreak >nul
) else (
    echo       MariaDB already running.
)

:: Start FXServer
echo [3/3] Starting FXServer...
echo.
cd /d "%~dp0"
"%~dp0server\FXServer.exe" +exec "%~dp0server.cfg"
