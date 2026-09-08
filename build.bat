@echo off
setlocal
chcp 65001 >nul
echo [LOTM Diagnostics] Building LotmDiagnosticsTool.exe...

set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" (
    set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe
)

if not exist "%CSC%" (
    echo [ERROR] csc.exe not found!
    exit /b 1
)

if not exist "build" mkdir "build"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$template = [IO.File]::ReadAllText('src/Program.template.cs'); $bytes = [IO.File]::ReadAllBytes('src/LotmDiagnostics.lua'); $b64 = [Convert]::ToBase64String($bytes); $code = $template.Replace('__PAYLOAD_B64__', $b64); [IO.File]::WriteAllText('src/Program.cs', $code, [Text.Encoding]::UTF8);"

"%CSC%" /target:winexe /optimize+ /platform:anycpu /r:System.dll,System.Windows.Forms.dll,System.Drawing.dll /win32manifest:src\app.manifest /win32icon:src\app.ico /out:build\LotmDiagnosticsTool.exe src\Program.cs src\AssemblyInfo.cs

if %ERRORLEVEL% equ 0 (
    echo [SUCCESS] Build completed: build\LotmDiagnosticsTool.exe
) else (
    echo [ERROR] Build failed!
)
endlocal
