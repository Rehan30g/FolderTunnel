@echo off
title Folder Tunnel
cd /d "%~dp0"
powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0GUI.ps1"