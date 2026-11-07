@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
REM Edit ONLY a private downloaded copy. Never commit a real signed URL.
REM In BAT source, replace every percent sign in the URL with two percent signs.
set "URI=REPLACE_WITH_LOGIC_APPS_SIGNED_URL"
set "SECRET_ENABLED=APP-ENABLED"

call :GetSecret "%SECRET_ENABLED%" APP_ENABLED
if errorlevel 1 goto Failed
setlocal EnableDelayedExpansion
set "APP_ENABLED=!APP_ENABLED:~1!"
echo [Key Vault] APP-ENABLED = "!APP_ENABLED!"
if /i "!APP_ENABLED!"=="ON" goto Enabled
if /i "!APP_ENABLED!"=="OFF" (
    echo OFF: hostname was skipped.
    goto End
)
echo Invalid value. Expected ON or OFF. Nothing was executed.
goto FailedExpanded

:Enabled
echo ON: running hostname...
hostname
if errorlevel 1 goto FailedExpanded
echo hostname completed successfully.
goto End

:Failed
setlocal EnableDelayedExpansion
echo Could not retrieve APP-ENABLED. Nothing was executed.
:FailedExpanded
pause
endlocal
endlocal
exit /b 1

:End
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
for /f "usebackq delims=" %%A in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); try { if ($env:URI -eq 'REPLACE_WITH_LOGIC_APPS_SIGNED_URL' -or ([uri]$env:URI).Scheme -ne 'https') { exit 1 }; $r=@(& curl.exe --disable --fail --silent --proto '=https' --connect-timeout 10 --max-time 30 --max-filesize 4096 --write-out ('\n__BAT_HTTP_STATUS__:'+[char]37+'{http_code}') --get --data-urlencode ('secret_name='+$env:SECRET_NAME) --url $env:URI 2>$null); if ($LASTEXITCODE -ne 0 -or $r.Count -lt 2 -or $r[-1] -cne '__BAT_HTTP_STATUS__:200') { exit 1 }; $v=($r[0..($r.Count-2)] -join [Environment]::NewLine) -replace '\r?\n$',''; if ([string]::IsNullOrWhiteSpace($v) -or $v.Length -gt 1024 -or $v -match '[\x00-\x1f\x7f]' -or $v.Contains([char]34) -or $v.EndsWith('\')) { exit 1 }; [Console]::WriteLine(':'+$v) } catch { exit 1 }"`) do set "%~2=%%A"
set "SECRET_NAME="
if not defined %~2 exit /b 1
exit /b 0

