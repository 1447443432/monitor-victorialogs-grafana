@echo off
setlocal

cd /d "%~dp0"
echo ================================================
echo Download offline packages
echo Proxy: configured in packages\package-manifest.yaml
echo ================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\download-packages.ps1"
if errorlevel 1 (
    echo.
    echo [ERROR] Download or SHA256 verification failed.
) else (
    echo.
    echo [OK] All packages downloaded and verified.
)

echo.
pause
