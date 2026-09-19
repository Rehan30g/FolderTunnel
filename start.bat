@echo off
cd /d "%~dp0"
attrib +h "%~dp0.gitignore" >nul 2>&1
attrib +h "%~dp0.git" >nul 2>&1
start "" wscript.exe "%~dp0app\WinTunnel.vbs"
exit /b
