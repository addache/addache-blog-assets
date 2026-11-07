@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
REM Edit ONLY a private downloaded copy. Never commit a real signed URL.
REM In BAT source, replace every percent sign in the URL with two percent signs.
set "URI=REPLACE_WITH_LOGIC_APPS_SIGNED_URL"
set "SECRET_FROM=COPY-FROM"
set "SECRET_TO=COPY-TO"

call :GetSecret "%SECRET_FROM%" COPY_FROM
if errorlevel 1 goto Failed
call :GetSecret "%SECRET_TO%" COPY_TO
if errorlevel 1 goto Failed
set "DESKTOP="
for /f "usebackq delims=" %%A in (`powershell.exe -NoProfile -NonInteractive -Command "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP=%%A"
setlocal EnableDelayedExpansion
set "COPY_FROM=!COPY_FROM:~1!"
set "COPY_TO=!COPY_TO:~1!"
echo [Key Vault] COPY-FROM = "!COPY_FROM!"
echo [Key Vault] COPY-TO   = "!COPY_TO!"

REM Accept only simple, distinct folder names directly under Desktop.
REM Reject traversal, absolute paths, Windows device names and reparse points.
powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; try { foreach ($n in @($env:COPY_FROM,$env:COPY_TO)) { if ($n -notmatch '^[a-zA-Z0-9_-]+$' -or $n -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$') { exit 1 } }; if ($env:COPY_FROM -ieq $env:COPY_TO -or [string]::IsNullOrWhiteSpace($env:DESKTOP) -or -not (Test-Path -LiteralPath $env:DESKTOP -PathType Container)) { exit 1 }; foreach ($n in @($env:COPY_FROM,$env:COPY_TO)) { $p=Join-Path $env:DESKTOP $n; if (Test-Path -LiteralPath $p) { $i=Get-Item -LiteralPath $p -Force; if (-not $i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) { exit 1 }; foreach ($c in @(Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction Stop)) { if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) { exit 1 } } } } } catch { exit 1 }"
if errorlevel 1 (
    echo Unsafe folder settings, unavailable Desktop, or a reparse point. Copy stopped.
    goto FailedExpanded
)
set "SOURCE=!DESKTOP!\!COPY_FROM!"
set "DEST=!DESKTOP!\!COPY_TO!"
echo Source      = "!SOURCE!"
echo Destination = "!DEST!"
if not exist "!SOURCE!\" (
    echo Create the source folder on Desktop and put sample files in it first.
    goto FailedExpanded
)
if exist "!DEST!\" (
    echo Destination exists. Reusing it.
) else (
    mkdir "!DEST!"
    if errorlevel 1 goto FailedExpanded
    echo Destination created.
)
REM /E includes empty subfolders. /Y overwrites files with the same name.
xcopy "!SOURCE!\*" "!DEST!\" /E /I /Y
set "COPY_RESULT=!errorlevel!"
echo XCOPY exit code = !COPY_RESULT!
if "!COPY_RESULT!"=="0" (
    echo Copy completed successfully.
    goto End
)
if "!COPY_RESULT!"=="1" echo No files were found to copy.
goto FailedExpanded

:Failed
setlocal EnableDelayedExpansion
echo Could not retrieve folder settings. No copy was attempted.
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

