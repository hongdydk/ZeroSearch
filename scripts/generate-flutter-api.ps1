# Generate Flutter API client from OpenAPI spec (default: scripts/openapi.json).
# Prerequisite: openapi-generator-cli on PATH, or use Docker image openapi-generator-cli.
param(
    [string]$SpecFile = "$PSScriptRoot\openapi.json",
    [string]$ApiBase = "http://localhost:8000",
    [string]$OutDir = "$PSScriptRoot\..\apps\flutter\lib\api",
    [switch]$FetchFromApi
)

$ErrorActionPreference = "Stop"
$specInput = $SpecFile

if ($FetchFromApi) {
    Write-Host "Fetching OpenAPI from $ApiBase/openapi.json"
    $tempSpec = Join-Path $env:TEMP "shopping-mall-openapi.json"
    try {
        Invoke-WebRequest -Uri "$ApiBase/openapi.json" -OutFile $tempSpec -UseBasicParsing
        $specInput = $tempSpec
    } catch {
        Write-Error "Failed to fetch OpenAPI from $ApiBase. Start API (pnpm dev:api) or run: python scripts/export_openapi.py"
    }
} elseif (-not (Test-Path $SpecFile)) {
    Write-Error "OpenAPI spec not found at $SpecFile. Run: python scripts/export_openapi.py"
} else {
    Write-Host "Using spec: $SpecFile"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$generator = Get-Command openapi-generator-cli -ErrorAction SilentlyContinue
if ($generator) {
    & openapi-generator-cli generate `
        -i $specInput `
        -g dart-dio `
        -o $OutDir/generated `
        --additional-properties=pubName=shopping_mall_api,pubAuthor=shopping_mall
    Write-Host "Generated client at $OutDir/generated"
    exit 0
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($docker) {
    $root = (Resolve-Path "$PSScriptRoot\..").Path
    docker run --rm `
        -v "${root}:/local" `
        openapitools/openapi-generator-cli:v7.11.0 generate `
        -i /local/scripts/openapi.json `
        -g dart-dio `
        -o /local/apps/flutter/lib/api/generated `
        --additional-properties=pubName=shopping_mall_api,pubAuthor=shopping_mall
    Write-Host "Generated client at $OutDir/generated (via Docker)"
    exit 0
}

Write-Warning @"
openapi-generator-cli and docker not found.
Install openapi-generator-cli: https://openapi-generator.tech/docs/installation
Or install Docker and re-run this script / pnpm codegen:flutter
On Linux/macOS/CI: bash scripts/generate-flutter-api.sh
Spec input: $specInput
"@
exit 1
