# Starts everything needed to try the app on THIS computer, with no connection
# to the live project: the Firebase emulators (a fake, empty Auth + database),
# test data, and a copy of the app built to talk to them.
#
#   .\tools\local-dev\start-local.ps1              build and start everything
#   .\tools\local-dev\start-local.ps1 -SkipBuild   reuse the last build
#
# Then open http://127.0.0.1:8081/ and sign in as  admin@local.test / localadmin1
# Close the two windows it opens to stop.
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$jdk = 'C:\Program Files\Android\Android Studio\jbr'

if (-not (Test-Path (Join-Path $jdk 'bin\java.exe'))) {
    throw "The emulators need Java 21. Expected Android Studio's bundled JDK at: $jdk"
}
# True if something is already accepting connections on the port.
function Test-PortOpen([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        return ($pending.AsyncWaitHandle.WaitOne(500) -and $client.Connected)
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

foreach ($port in 9099, 8089, 8081) {
    if (Test-PortOpen $port) {
        throw "Port $port is already in use. If the local copy is already running, just open http://127.0.0.1:8081/ . Otherwise close whatever is using that port (maybe an earlier run) and try again."
    }
}

$env:JAVA_HOME = $jdk
$env:Path = "$jdk\bin;$env:Path"

Set-Location $PSScriptRoot
if (-not (Test-Path 'node_modules')) {
    Write-Host 'Installing test tools (first run only)...'
    npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }
}

Write-Host 'Starting the Firebase emulators...'
Start-Process powershell -ArgumentList '-NoExit', '-Command',
    "`$Host.UI.RawUI.WindowTitle = 'Firebase emulators (local)'; Set-Location '$PSScriptRoot'; firebase emulators:start --only auth,firestore --project qrcode-16b68"

$deadline = (Get-Date).AddSeconds(120)
while (-not (Test-PortOpen 8089)) {
    if ((Get-Date) -gt $deadline) { throw 'The emulators did not start within 2 minutes.' }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 3

Write-Host 'Adding test data...'
$env:FIRESTORE_EMULATOR_HOST = 'localhost:8089'
$env:FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099'
node seed.mjs
if ($LASTEXITCODE -ne 0) { throw 'Seeding the test data failed.' }

$web = Join-Path $root 'build\web_local'
if (-not $SkipBuild -or -not (Test-Path (Join-Path $web 'index.html'))) {
    Write-Host 'Building the app for local testing (a few minutes)...'
    Set-Location $root
    flutter build web --release --base-href / --dart-define=USE_EMULATOR=true --output build/web_local
    if ($LASTEXITCODE -ne 0) { throw 'The app build failed.' }
}

# Local copy only: keep Auth calls on the emulator across page reloads (see the
# comment in emulator-shim.js). Safe to repeat: the tag is added once.
Copy-Item (Join-Path $PSScriptRoot 'emulator-shim.js') (Join-Path $web 'emulator-shim.js') -Force
$indexPath = Join-Path $web 'index.html'
$indexHtml = Get-Content $indexPath -Raw
if ($indexHtml -notmatch 'emulator-shim\.js') {
    $indexHtml = $indexHtml -replace '<head>', '<head><script src="emulator-shim.js"></script>'
    [System.IO.File]::WriteAllText($indexPath, $indexHtml, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host 'Starting the local web server...'
Start-Process powershell -ArgumentList '-NoExit', '-Command',
    "`$Host.UI.RawUI.WindowTitle = 'Local app server'; python -m http.server 8081 --bind 127.0.0.1 --directory '$web'"
Start-Sleep -Seconds 3

Write-Host ''
Write-Host 'Ready. Open  http://127.0.0.1:8081/' -ForegroundColor Green
Write-Host 'Admin sign-in:  admin@local.test  /  localadmin1'
Write-Host 'This is a local copy: nothing here touches your live website or data.'
