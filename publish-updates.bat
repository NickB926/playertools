@echo off
cd /d "%~dp0"
echo.
echo  PlayerTools publish (like discord-lite)
echo  Bumps version, copies from Potassium scripts, pushes GitHub.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-PlayerTools.ps1" %*
set ERR=%ERRORLEVEL%
echo.
if %ERR% NEQ 0 (
  echo FAILED exit %ERR%
) else (
  echo Done.
)
pause
exit /b %ERR%
