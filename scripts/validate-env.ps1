#Requires -Version 7.0
<#
.SYNOPSIS
    Validates that all prerequisites are met for using the Copilot Studio Demo Builder.
.DESCRIPTION
    Checks for required tools (pac, azd, pwsh), environment variable configuration,
    and connectivity to Power Platform.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — Environment Check    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$allPassed = $true

# ── 1. Tools ──
Write-Host "Tools:" -ForegroundColor Yellow

# PowerShell
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Host "  ✓ pwsh $($PSVersionTable.PSVersion)" -ForegroundColor Green
}
else {
    Write-Host "  ✗ PowerShell 7+ required (current: $($PSVersionTable.PSVersion))" -ForegroundColor Red
    $allPassed = $false
}

# azd
$azdCmd = Get-Command azd -ErrorAction SilentlyContinue
if ($azdCmd) {
    $azdVer = (azd version 2>$null) | Select-Object -First 1
    Write-Host "  ✓ azd $azdVer" -ForegroundColor Green
}
else {
    Write-Host "  ✗ azd not found — install from https://aka.ms/azd" -ForegroundColor Red
    $allPassed = $false
}

# pac
$pacCmd = Get-Command pac -ErrorAction SilentlyContinue
if ($pacCmd) {
    $pacVer = (pac --version 2>$null) | Select-Object -First 1
    Write-Host "  ✓ pac $pacVer" -ForegroundColor Green
}
else {
    Write-Host "  ✗ pac not found — install: dotnet tool install --global Microsoft.PowerApps.CLI" -ForegroundColor Red
    $allPassed = $false
}

# ── 2. azd Environment ──
Write-Host "`nazd Environment:" -ForegroundColor Yellow

function Test-AzdVar {
    param([string]$Name, [bool]$Required = $true)
    $val = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $val) {
        if ($Required) {
            Write-Host "  ✗ $Name — not set (required)" -ForegroundColor Red
            return $false
        }
        else {
            Write-Host "  - $Name — not set (optional)" -ForegroundColor DarkGray
            return $true
        }
    }
    $display = $val.Trim('"')
    # Mask secrets
    if ($Name -match 'SECRET|KEY|PASSWORD') {
        $display = $display.Substring(0, [Math]::Min(4, $display.Length)) + '****'
    }
    Write-Host "  ✓ $Name = $display" -ForegroundColor Green
    return $true
}

$envOk = $true
$envOk = (Test-AzdVar 'POWERPLATFORM_ENVIRONMENT_URL') -and $envOk
$envOk = (Test-AzdVar 'POWERPLATFORM_SOLUTION_NAME') -and $envOk
$envOk = (Test-AzdVar 'DEPLOYMENT_MODE') -and $envOk
Test-AzdVar 'AGENT_DISPLAY_NAME' -Required $false | Out-Null
Test-AzdVar 'AGENT_SCHEMA_NAME' -Required $false | Out-Null
Test-AzdVar 'POWERPLATFORM_TENANT_ID' -Required $false | Out-Null
Test-AzdVar 'POWERPLATFORM_APP_ID' -Required $false | Out-Null
Test-AzdVar 'POWERPLATFORM_CLIENT_SECRET' -Required $false | Out-Null

if (-not $envOk) { $allPassed = $false }

# ── 3. Project structure ──
Write-Host "`nProject Structure:" -ForegroundColor Yellow

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$mode = azd env get-value DEPLOYMENT_MODE 2>$null
if ($mode) { $mode = $mode.Trim('"') }

if ($mode -eq 'solution') {
    $solPath = Join-Path $projectRoot 'solution'
    $hasSolution = (Test-Path (Join-Path $solPath '*.xml') -ErrorAction SilentlyContinue) -or
    (Test-Path (Join-Path $solPath '**' 'Solution.xml') -ErrorAction SilentlyContinue) -or
    (Test-Path (Join-Path $solPath '**' 'solution.yml') -ErrorAction SilentlyContinue)

    if ($hasSolution) {
        $fileCount = (Get-ChildItem -Path $solPath -Recurse -File -Exclude '.gitkeep' | Measure-Object).Count
        Write-Host "  ✓ solution/ folder — $fileCount files" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ solution/ folder is empty — run scripts/export-agent.ps1" -ForegroundColor Red
        $allPassed = $false
    }
}
elseif ($mode -eq 'template') {
    $tmplPath = Join-Path $projectRoot 'template'
    $hasTemplate = Get-ChildItem -Path $tmplPath -Filter '*.yaml' -ErrorAction SilentlyContinue

    if ($hasTemplate) {
        Write-Host "  ✓ template/ folder — $($hasTemplate.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ template/ folder has no .yaml files" -ForegroundColor Red
        $allPassed = $false
    }
}

# ── 4. Power Platform connectivity ──
Write-Host "`nPower Platform Connectivity:" -ForegroundColor Yellow

if ($pacCmd) {
    $authList = pac auth list 2>$null
    if ($authList -and ($authList | Select-String '\*')) {
        Write-Host "  ✓ Active pac auth profile found" -ForegroundColor Green

        $envInfo = pac env who 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Environment reachable" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Cannot reach Power Platform environment" -ForegroundColor Red
            $allPassed = $false
        }
    }
    else {
        Write-Host "  - No active pac auth profile (will be created during azd up)" -ForegroundColor DarkGray
    }
}

# ── Summary ──
Write-Host ""
if ($allPassed) {
    Write-Host "✅ All checks passed. Ready to run 'azd up'." -ForegroundColor Green
}
else {
    Write-Host "❌ Some checks failed. Fix the issues above before running 'azd up'." -ForegroundColor Red
}
Write-Host ""
