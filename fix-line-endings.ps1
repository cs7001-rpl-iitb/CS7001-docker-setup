# fix-line-endings.ps1
# Converts CRLF -> LF and strips any UTF-8 BOM from shell scripts.
# Pure PowerShell, no WSL, no Git, no dos2unix required.
#
# Usage:   powershell -ExecutionPolicy Bypass -File .\fix-line-endings.ps1

$targets = @("entrypoint.sh", "diagnose.sh")
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

foreach ($f in $targets) {
    if (-not (Test-Path $f)) {
        Write-Host "skip (not found): $f" -ForegroundColor DarkGray
        continue
    }

    $path  = (Resolve-Path $f).Path
    $bytes = [IO.File]::ReadAllBytes($path)
    $crlf  = 0
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) { $crlf++ }
    }

    $text = [IO.File]::ReadAllText($path)
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    $text = $text.TrimStart([char]0xFEFF)   # strip BOM if present

    [IO.File]::WriteAllText($path, $text, $utf8NoBom)

    Write-Host "fixed: $f  ($crlf CRLF pairs removed)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Verifying shebangs..." -ForegroundColor Cyan
foreach ($f in $targets) {
    if (-not (Test-Path $f)) { continue }
    $first = (Get-Content $f -TotalCount 1)
    $ok = $first -eq "#!/usr/bin/env bash"
    $colour = if ($ok) { "Green" } else { "Red" }
    Write-Host ("  {0}: '{1}' {2}" -f $f, $first, $(if ($ok) { "OK" } else { "STILL WRONG" })) -ForegroundColor $colour
}

Write-Host ""
Write-Host "Now run:  docker compose build; docker compose up -d" -ForegroundColor Yellow
