@echo off
chcp 65001 >nul
title IRIS Portable Update
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0portable_update_by_zip.ps1"
rem NOTE: no trailing `pause` here - the .ps1 already pauses on error paths and
rem ends with the "launch now?" prompt on success; an extra pause forces two Enters.
