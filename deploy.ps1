# Assembles dist/ for Firebase Hosting: the landing page at the root and the
# Flutter app under /app/. This script only builds. It never deploys anything.
#
#   .\deploy.ps1            strict: fails on placeholder text or unknown hosts
#   .\deploy.ps1 -Preview   the same checks, reported as warnings
param([switch]$Preview)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Stop-Build([string]$Message) {
    Write-Host "FAILED: $Message" -ForegroundColor Red
    exit 1
}

function Assert-Exists([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Build "$Path is missing"
    }
}

Write-Host 'Building the Flutter app for /app/ ...'
flutter build web --release --base-href /app/
if ($LASTEXITCODE -ne 0) { Stop-Build "flutter build failed with exit code $LASTEXITCODE" }

Write-Host 'Assembling dist/ ...'
if (Test-Path -LiteralPath 'dist') { Remove-Item -LiteralPath 'dist' -Recurse -Force }
New-Item -ItemType Directory -Path 'dist' | Out-Null
Copy-Item -Path 'landing\*' -Destination 'dist' -Recurse
Copy-Item -Path 'build\web' -Destination 'dist\app' -Recurse

Assert-Exists 'dist\index.html'
Assert-Exists 'dist\app\index.html'
Assert-Exists 'dist\flutter_service_worker.js'

# Flutter ships a self-removing worker too, so its behaviour can't tell the two
# apart. Only the marker can.
$worker = Get-Content -LiteralPath 'dist\flutter_service_worker.js' -Raw
if ($worker -notmatch 'FULL-STAR-QR-KILL-SWITCH') {
    Stop-Build 'dist\flutter_service_worker.js is not the kill-switch'
}

$problems = New-Object System.Collections.ArrayList
$textExtensions = '.html', '.css', '.js', '.json', '.txt', '.xml', '.svg'
$codeExtensions = '.html', '.css', '.js'
$allowedHosts = 'fullstarqr.com', 'wa.me', 'www.w3.org'
$bannedText = 'TODO-COPY', 'example\.com', 'lorem', 'admin@fullstarqr\.com'

$landingFiles = Get-ChildItem -LiteralPath 'landing' -Recurse -File
foreach ($file in $landingFiles) {
    if ($textExtensions -notcontains $file.Extension.ToLower()) { continue }
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($null -eq $content) { continue }

    foreach ($pattern in $bannedText) {
        if ($content -match $pattern) {
            [void]$problems.Add("$($file.Name) contains banned text: $pattern")
        }
    }

    if ($codeExtensions -contains $file.Extension.ToLower()) {
        foreach ($match in [regex]::Matches($content, 'https?://([A-Za-z0-9.-]+)')) {
            $hostName = $match.Groups[1].Value.ToLower()
            if ($allowedHosts -notcontains $hostName) {
                [void]$problems.Add("$($file.Name) references an unknown host: $hostName")
            }
        }
    }
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        if ($Preview) { Write-Warning $problem } else { Write-Host $problem -ForegroundColor Red }
    }
    if (-not $Preview) { Stop-Build "$($problems.Count) problem(s) found in landing/" }
}

$distFiles = Get-ChildItem -LiteralPath 'dist' -Recurse -File
$totalBytes = ($distFiles | Measure-Object -Property Length -Sum).Sum
$appFiles = Get-ChildItem -LiteralPath 'dist\app' -Recurse -File
Write-Host ''
Write-Host "dist/ is ready: $($distFiles.Count) files, $([math]::Round($totalBytes / 1MB, 1)) MB"
Write-Host "  landing: $($distFiles.Count - $appFiles.Count) files"
Write-Host "  app:     $($appFiles.Count) files"
if ($Preview) { Write-Host 'Preview build: problems above were warnings only.' }
Write-Host 'Nothing has been deployed.'
