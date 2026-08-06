# setup-windows.ps1
# One-time Windows setup: locates docker.exe wherever Docker Desktop installed
# it, adds it to PATH, and checks the daemon is reachable.
#
# Works for per-user AND system-wide installs. No hardcoded usernames.
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1

Write-Host "=== Docker Desktop setup check ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Locate docker.exe -----------------------------------------------------
# Docker Desktop installs to one of these depending on whether it was a
# per-user install (the default in recent versions) or system-wide.
$candidates = @(
    "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin",
    "$env:ProgramFiles\Docker\Docker\resources\bin",
    "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin",
    "$env:ProgramW6432\Docker\Docker\resources\bin"
)

$dockerBin = $candidates |
    Where-Object { $_ -and (Test-Path (Join-Path $_ "docker.exe")) } |
    Select-Object -First 1

# Fall back to a registry lookup if it landed somewhere unusual.
if (-not $dockerBin) {
    Write-Host "Not in standard locations, checking registry..." -ForegroundColor DarkGray
    $reg = Get-ItemProperty `
              HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, `
              HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* `
              -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -like "*Docker Desktop*" } |
           Select-Object -First 1

    if ($reg -and $reg.InstallLocation) {
        $guess = Join-Path $reg.InstallLocation "resources\bin"
        if (Test-Path (Join-Path $guess "docker.exe")) { $dockerBin = $guess }
    }
}

if (-not $dockerBin) {
    Write-Host "docker.exe NOT FOUND." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install Docker Desktop first:" -ForegroundColor Yellow
    Write-Host "  winget install -e --id Docker.DockerDesktop --force ``"
    Write-Host "    --accept-package-agreements --accept-source-agreements"
    Write-Host ""
    Write-Host "Then reboot and re-run this script."
    exit 1
}

Write-Host "Found: $dockerBin\docker.exe" -ForegroundColor Green

# --- 2. Add to PATH -----------------------------------------------------------
if ($env:Path -notlike "*$dockerBin*") {
    $env:Path += ";$dockerBin"
    Write-Host "Added to PATH for this session." -ForegroundColor Green
} else {
    Write-Host "Already on PATH for this session." -ForegroundColor DarkGray
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dockerBin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dockerBin", "User")
    Write-Host "Added to permanent user PATH." -ForegroundColor Green
} else {
    Write-Host "Already on permanent PATH." -ForegroundColor DarkGray
}

# --- 3. Is Docker Desktop running? -------------------------------------------
Write-Host ""
if (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue)) {
    Write-Host "Docker Desktop is not running. Starting it..." -ForegroundColor Yellow
    $exe = Join-Path (Split-Path (Split-Path $dockerBin)) "Docker Desktop.exe"
    if (Test-Path $exe) { Start-Process $exe }
    else { Write-Host "Launch it manually from the Start menu." -ForegroundColor Yellow }
    Write-Host "Wait for the whale icon to stop animating, then re-run this script."
}

# --- 4. Context check ---------------------------------------------------------
# Modern Docker Desktop listens on the 'desktop-linux' context. A CLI left on
# the legacy 'default' context looks for a named pipe that is never created.
Write-Host ""
Write-Host "Docker contexts:" -ForegroundColor Cyan
& docker context ls 2>&1 | Write-Host

$contexts = (& docker context ls --format "{{.Name}}" 2>$null)
$current  = (& docker context show 2>$null)
if ($contexts -contains "desktop-linux" -and $current -ne "desktop-linux") {
    Write-Host "Switching context to desktop-linux..." -ForegroundColor Yellow
    & docker context use desktop-linux | Out-Null
}

# --- 5. Verify ----------------------------------------------------------------
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
& docker version
Write-Host ""
& docker compose version

Write-Host ""
Write-Host "If both Client and Server blocks appeared above, you are ready:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File .\fix-line-endings.ps1"
Write-Host "  docker compose build"
Write-Host "  docker compose up -d"
