# Brain App (Flutter) — build & run
# Usage: .\start.ps1 [-Target <android|web|apk>] [-Release]
#
# Quick one-liners:
#   .\start.ps1 -Target apk -Release   # Release APK for sideloading
#   .\start.ps1 -Target apk            # Debug APK
#   .\start.ps1                         # Run on Android device (debug)
#   .\start.ps1 -Release               # Run on Android device (release)
#   .\start.ps1 -Target web            # Run in Chrome
#
# Targets:
#   android  — Run on connected Android device/emulator (default)
#   web      — Run in Chrome (hot reload)
#   apk      — Build APK for sideloading
#
# Prerequisites:
#   - Flutter SDK 3.x
#   - For Android: Android SDK, connected device or emulator
#   - .env file with IBECOME_TOKEN and IBECOME_URL
param(
    [ValidateSet('android', 'web', 'apk')]
    [string]$Target = 'android',
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot

Write-Host "`n  Brain App (Flutter)" -ForegroundColor Cyan
Write-Host "  ===================`n"

# Ensure dependencies are up to date
Write-Host "  Resolving dependencies..." -ForegroundColor Yellow
Push-Location $base
flutter pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "flutter pub get failed" }

switch ($Target) {
    'apk' {
        $mode = if ($Release) { '--release' } else { '--debug' }
        Write-Host "  Building APK ($mode)..." -ForegroundColor Yellow
        flutter build apk $mode
        if ($LASTEXITCODE -ne 0) { Pop-Location; throw "APK build failed" }

        $apkPath = if ($Release) {
            "$base\build\app\outputs\flutter-apk\app-release.apk"
        } else {
            "$base\build\app\outputs\flutter-apk\app-debug.apk"
        }
        Write-Host "`n  APK built: $apkPath" -ForegroundColor Green
        Write-Host "  Install: adb install $apkPath`n" -ForegroundColor DarkGray
    }
    'web' {
        Write-Host "  Running in Chrome..." -ForegroundColor Green
        Write-Host "  Press 'r' for hot restart, 'q' to quit`n" -ForegroundColor DarkGray
        flutter run -d chrome
    }
    default {
        $mode = if ($Release) { '--release' } else { '' }
        Write-Host "  Running on Android device..." -ForegroundColor Green
        Write-Host "  Press 'r' for hot restart, 'q' to quit`n" -ForegroundColor DarkGray
        flutter run $mode
    }
}

Pop-Location
