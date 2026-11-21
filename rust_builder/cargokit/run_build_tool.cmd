@echo off
setlocal
set "SOURCE=%~dp0build_tool"
set "WORK=%CARGOKIT_TOOL_TEMP_DIR%\locked_tool"
set "DART=%FLUTTER_ROOT%\bin\cache\dart-sdk\bin\dart.exe"
if not exist "%WORK%" mkdir "%WORK%" || exit /b 1
cd /d "%WORK%" || exit /b 1
copy /y "%SOURCE%\pubspec.yaml" . >nul || exit /b 1
copy /y "%SOURCE%\pubspec.lock" . >nul || exit /b 1
xcopy /q /i /e /y "%SOURCE%\lib" lib >nul || exit /b 1
xcopy /q /i /e /y "%SOURCE%\bin" bin >nul || exit /b 1
"%DART%" pub get --offline --enforce-lockfile --no-precompile
if errorlevel 1 (
    "%DART%" pub get --enforce-lockfile --no-precompile
    if errorlevel 1 exit /b 1
)
"%DART%" bin\build_tool.dart %*
exit /b %ERRORLEVEL%
