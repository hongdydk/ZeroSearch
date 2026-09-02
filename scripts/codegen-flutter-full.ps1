# Full Flutter API codegen: OpenAPI generate (Docker) + build_runner + app pub get.
# Prerequisite: Docker. Flutter/Dart on PATH optional (build_runner uses Docker when missing).
param(
    [string]$SpecFile = "$PSScriptRoot\openapi.json"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..").Path
$generated = Join-Path $root "apps\flutter\lib\api\generated"

if (-not (Test-Path $SpecFile)) {
    Write-Error "OpenAPI spec not found at $SpecFile. Run: python scripts/export_openapi.py"
}

& "$PSScriptRoot\generate-flutter-api.ps1" -SpecFile $SpecFile

function Invoke-BuildRunner {
    param([string]$WorkDir)
    Push-Location $WorkDir
    try {
        $flutter = Get-Command flutter -ErrorAction SilentlyContinue
        if ($flutter) {
            flutter pub get
            dart run build_runner build
            return
        }
        $dart = Get-Command dart -ErrorAction SilentlyContinue
        if ($dart) {
            dart pub get
            dart run build_runner build
            return
        }
        docker run --rm `
            -v "${root}:/local" `
            -w "/local/apps/flutter/lib/api/generated" `
            ghcr.io/cirruslabs/flutter:stable `
            bash -lc "dart pub get && dart run build_runner build"
    } finally {
        Pop-Location
    }
}

Write-Host "Building generated serializers..."
Invoke-BuildRunner -WorkDir $generated

$fixPs = Join-Path $PSScriptRoot "fix-generated-dart-parts.ps1"
$fixSh = Join-Path $PSScriptRoot "fix-generated-dart-parts.sh"
if (Test-Path $fixPs) {
    & $fixPs -GeneratedDir $generated
} elseif (Test-Path $fixSh) {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
        & bash $fixSh
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "bash fix script failed (exit $LASTEXITCODE); run scripts/fix-generated-dart-parts.ps1"
        }
    } else {
        Write-Warning "bash not found — run scripts/fix-generated-dart-parts.ps1"
    }
}

Write-Host "Refreshing app dependencies..."
Push-Location (Join-Path $root "apps\flutter")
try {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutter) {
        flutter pub get
    } else {
        Write-Warning "flutter not on PATH — run: cd apps/flutter && flutter pub get"
    }
} finally {
    Pop-Location
}

Write-Host "Done. Generated client at apps/flutter/lib/api/generated"
