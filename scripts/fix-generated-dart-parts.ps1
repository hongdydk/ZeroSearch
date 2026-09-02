# Ensure all generated Dart library/part files share the same // @dart= version.
param(
    [string]$GeneratedDir = "$PSScriptRoot\..\apps\flutter\lib\api\generated",
    [string]$DartVersion = ""
)

$ErrorActionPreference = "Stop"
$lib = Join-Path $GeneratedDir "lib"
if (-not (Test-Path $lib)) {
    Write-Host "No generated lib at $lib — skipping @dart fix"
    exit 0
}

$version = $DartVersion
if (-not $version) {
    $version = "3.8"
    $dart = Get-Command dart -ErrorAction SilentlyContinue
    if ($dart) {
        $dartVer = & dart --version 2>&1 | Out-String
        if ($dartVer -match 'Dart SDK version: ([0-9]+\.[0-9]+)') {
            $version = $Matches[1]
        }
    }
}

$count = 0
Get-ChildItem -Path $lib -Recurse -Filter "*.dart" | ForEach-Object {
    $lines = @(Get-Content $_.FullName | Where-Object { $_ -notmatch '^// @dart=' })
    @("// @dart=$version") + $lines | Set-Content $_.FullName -Encoding utf8
    $count++
}

Write-Host "Set // @dart=$version on $count generated Dart files under lib/"
