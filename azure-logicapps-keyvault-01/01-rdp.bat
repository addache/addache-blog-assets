@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
REM Edit ONLY a private downloaded copy. Never commit a real signed URL.
REM In BAT source, replace every percent sign in the URL with two percent signs.
set "URI=REPLACE_WITH_LOGIC_APPS_SIGNED_URL"
set "SECRET_HOST=RDP-HOST"
set "SECRET_USER=RDP-USER"
set "SECRET_PASS=RDP-PASS"
set "CREDENTIAL_WAIT_SECONDS=10"

call :GetSecret "%SECRET_HOST%" RDP_HOST
call :GetSecret "%SECRET_USER%" RDP_USER
call :GetSecret "%SECRET_PASS%" RDP_PASS
setlocal EnableDelayedExpansion
if defined RDP_HOST set "RDP_HOST=!RDP_HOST:~1!"
if defined RDP_USER set "RDP_USER=!RDP_USER:~1!"
if defined RDP_PASS set "RDP_PASS=!RDP_PASS:~1!"

echo [Key Vault] HOST = "!RDP_HOST!"
echo [Key Vault] USER = "!RDP_USER!"
if defined RDP_PASS (echo [Key Vault] PASS = ********) else echo [Key Vault] PASS = [not retrieved]
if not defined RDP_HOST goto Manual
if not defined RDP_USER goto Manual
if not defined RDP_PASS goto Manual

REM Only a host name / IP address, optionally with a port, is accepted.
powershell.exe -NoProfile -NonInteractive -Command "if ($env:RDP_HOST -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.:-]*$') { exit 1 }"
if errorlevel 1 goto Manual
REM Do not overwrite or delete credentials that were already present.
powershell.exe -NoProfile -NonInteractive -Command "$t='TERMSRV/'+$env:RDP_HOST; $r=@(& cmdkey.exe ('/list:'+$t)); if ($LASTEXITCODE -ne 0 -or ($r -join [Environment]::NewLine).IndexOf($t,[StringComparison]::OrdinalIgnoreCase) -ge 0) { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo Existing credentials found, or credential check failed. Using manual login.
    goto Manual
)

cmdkey.exe /generic:TERMSRV/!RDP_HOST! /user:"!RDP_USER!" /pass:"!RDP_PASS!" >nul 2>&1
set "RDP_PASS="
if errorlevel 1 (
    echo Credential registration failed. Using manual login.
    goto Manual
)
echo Temporary credentials registered. Starting Remote Desktop...
start "" "%SystemRoot%\System32\mstsc.exe" /v:"!RDP_HOST!"
echo Removing temporary credentials after !CREDENTIAL_WAIT_SECONDS! seconds.
timeout /t !CREDENTIAL_WAIT_SECONDS! /nobreak >nul
REM A redirected console can make TIMEOUT fail; retain the ten-second wait.
if errorlevel 1 powershell.exe -NoProfile -NonInteractive -Command "Start-Sleep -Seconds ([int]$env:CREDENTIAL_WAIT_SECONDS)"
cmdkey.exe /delete:TERMSRV/!RDP_HOST! >nul 2>&1
if errorlevel 1 (
    echo WARNING: Credential deletion failed. Remove TERMSRV/!RDP_HOST! in Credential Manager.
    goto Failed
)
echo Temporary credentials deleted. Enter credentials in the RDP window if prompted.
goto End

:Manual
set "RDP_PASS="
echo Automatic login is unavailable. Enter the computer and credentials manually.
start "" "%SystemRoot%\System32\mstsc.exe"
goto End

:Failed
pause
endlocal
endlocal
exit /b 1

:End
set "RDP_PASS="
echo.
pause
endlocal
endlocal
exit /b 0

REM Shared implementation, copied into each BAT so every sample is standalone.
REM Returns a colon-prefixed value; the caller removes it after enabling delayed expansion.
REM No temporary secret file, verbose curl output, URL logging, or CALL with secret values.
:GetSecret
set "%~2="
set "SECRET_NAME=%~1"
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); try { if ($env:URI -eq 'REPLACE_WITH_LOGIC_APPS_SIGNED_URL' -or ([uri]$env:URI).Scheme -ne 'https') { exit 1 }; $r=@(& curl.exe --disable --fail --silent --proto '=https' --connect-timeout 10 --max-time 30 --max-filesize 4096 --get --data-urlencode ('secret_name='+$env:SECRET_NAME) --url $env:URI 2>$null); if ($LASTEXITCODE -ne 0 -or $r.Count -ne 1) { exit 1 }; $v=[string]$r[0]; if ([string]::IsNullOrWhiteSpace($v) -or $v.Length -gt 1024 -or $v -match '[\x00-\x1f\x7f]' -or $v.Contains([char]34) -or $v.EndsWith('\')) { exit 1 }; [Console]::WriteLine(':'+$v) } catch { exit 1 }"`) do set "%~2=%%A"
set "SECRET_NAME="
if not defined %~2 exit /b 1
exit /b 0

