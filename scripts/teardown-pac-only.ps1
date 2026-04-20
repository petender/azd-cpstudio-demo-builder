#Requires -Version 7.0
<#
.SYNOPSIS
    Tear down a Copilot Studio agent using pac CLI only (no Azure subscription required).
.DESCRIPTION
    Standalone teardown script for users who don't have an Azure subscription.
    Deletes the Power Platform solution (and its contained agent) from the environment.

.PARAMETER EnvironmentUrl
    The Power Platform environment URL (e.g., https://org123.crm.dynamics.com).

.PARAMETER SolutionName
    Unique name of the Power Platform solution to delete.

.EXAMPLE
    ./scripts/teardown-pac-only.ps1 -EnvironmentUrl "https://org123.crm.dynamics.com" -SolutionName "MyDemo"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$SolutionName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — pac-only Teardown     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ── Verify pac CLI ──
Write-Host "[1/3] Checking pac CLI..." -ForegroundColor Yellow
$pacCmd = Get-Command pac -ErrorAction SilentlyContinue
if (-not $pacCmd) {
    Write-Error "pac CLI is not installed. Install with: dotnet tool install --global Microsoft.PowerApps.CLI"
}
Write-Host "  ✓ pac CLI found" -ForegroundColor Green

# ── Verify authentication ──
Write-Host "[2/3] Verifying Power Platform authentication..." -ForegroundColor Yellow
$existingAuth = pac auth list 2>$null
$alreadyAuth = $existingAuth | Select-String ([regex]::Escape($EnvironmentUrl))

if (-not $alreadyAuth) {
    Write-Host "  Not authenticated to $EnvironmentUrl. Launching login..." -ForegroundColor Cyan
    pac auth create --name "cpstudio-pac-only" --environment $EnvironmentUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to authenticate."
    }
}
Write-Host "  ✓ Authenticated" -ForegroundColor Green

# ── Delete solution ──
Write-Host "[3/3] Deleting solution '$SolutionName'..." -ForegroundColor Yellow

$solutionList = pac solution list 2>$null
$solutionExists = $solutionList | Select-String $SolutionName

if (-not $solutionExists) {
    Write-Host "  Solution '$SolutionName' not found. Already removed or never deployed." -ForegroundColor Yellow
    exit 0
}

pac solution delete --solution-name $SolutionName

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ⚠ Failed to delete solution. Delete manually from Power Platform admin center." -ForegroundColor Yellow
    Write-Host "  Solution: $SolutionName" -ForegroundColor Yellow
} else {
    Write-Host "  ✓ Solution deleted — agent and all components removed" -ForegroundColor Green
}

Write-Host "`n✅ Teardown complete.`n" -ForegroundColor Green
