@echo off
rem Runs the automated tests headless on Windows.
rem Set GODOT to your Godot 4.7.2 console executable if "godot" is not on PATH, e.g.
rem   set GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe
setlocal
if "%GODOT%"=="" set GODOT=godot
cd /d "%~dp0"
"%GODOT%" --headless --path . --import >NUL 2>&1
"%GODOT%" --headless --path . --script res://tests/run_tests.gd -- %*
exit /b %ERRORLEVEL%
