#Requires -Version 7.0
<#
.SYNOPSIS
    Post-down hook — removes the Copilot Studio agent and solution from Power Platform.
.DESCRIPTION
    Runs after azd down tears down Azure resources. Deletes the deployed Power Platform
    solution (which removes the agent and all its components).
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — Agent Teardown       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ── Helper: read azd env var ──
function Get-AzdEnvValue {
    param([string]$Name)
    $val = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ([string]::IsNullOrEmpty($val)) { return $null }
    return $val.Trim('"')
}

$solutionName = Get-AzdEnvValue 'DEPLOYED_SOLUTION_NAME'

if (-not $solutionName) {
    $solutionName = Get-AzdEnvValue 'POWERPLATFORM_SOLUTION_NAME'
}

if (-not $solutionName) {
    Write-Host "  ⚠ No solution name found in environment. Nothing to tear down on Power Platform side." -ForegroundColor Yellow
    exit 0
}

# ── Verify pac auth is still valid ──
Write-Host "[1/2] Verifying Power Platform authentication..." -ForegroundColor Yellow
$envInfo = pac env who 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ⚠ Not authenticated to Power Platform. Skipping agent teardown." -ForegroundColor Yellow
    Write-Host "  You may need to manually delete solution '$solutionName' from Copilot Studio." -ForegroundColor Yellow
    exit 0
}
Write-Host "  ✓ Authenticated" -ForegroundColor Green

# ── Delete the solution ──
Write-Host "[2/2] Deleting solution '$solutionName' from Power Platform..." -ForegroundColor Yellow

# Check if solution exists first
$solutionList = pac solution list 2>$null
$solutionExists = $solutionList | Select-String $solutionName

if (-not $solutionExists) {
    Write-Host "  Solution '$solutionName' not found in environment. Already removed or never deployed." -ForegroundColor Yellow
    exit 0
}

pac solution delete --solution-name $solutionName

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ⚠ Failed to delete solution. You may need to delete it manually from Power Platform admin center." -ForegroundColor Yellow
    Write-Host "  Solution name: $solutionName" -ForegroundColor Yellow
}
else {
    Write-Host "  ✓ Solution deleted — agent and all components removed" -ForegroundColor Green
}

# Clean up stored identifiers
azd env set DEPLOYED_SOLUTION_NAME '' 2>$null
azd env set DEPLOYED_BOT_ID '' 2>$null
azd env set DEPLOYED_BOT_SCHEMA '' 2>$null

Write-Host "`n✅ Teardown complete.`n" -ForegroundColor Green
