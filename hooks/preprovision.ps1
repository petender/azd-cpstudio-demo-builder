#Requires -Version 7.0
<#
.SYNOPSIS
    Pre-provision hook — validates prerequisites and authenticates to Power Platform.
.DESCRIPTION
    Runs before Azure infrastructure provisioning. Checks that pac CLI is installed,
    PowerShell 7+ is available, and authenticates to the target Power Platform environment.
    Supports both interactive (browser) and service principal authentication.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — Pre-provision Check  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ── Helper: read azd env var ──
function Get-AzdEnvValue {
    param([string]$Name)
    $val = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ([string]::IsNullOrEmpty($val)) { return $null }
    return $val.Trim('"')
}

# ── 1. Check PowerShell version ──
Write-Host "[1/4] Checking PowerShell version..." -ForegroundColor Yellow
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7+ is required. Current version: $($PSVersionTable.PSVersion). Install from https://aka.ms/powershell"
}
Write-Host "  ✓ PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green

# ── 2. Check pac CLI ──
Write-Host "[2/4] Checking pac CLI..." -ForegroundColor Yellow
$pacCmd = Get-Command pac -ErrorAction SilentlyContinue
if (-not $pacCmd) {
    Write-Error @"
pac CLI is not installed or not on PATH.
Install options:
  • dotnet tool install --global Microsoft.PowerApps.CLI
  • VS Code extension: ms-powerplatform.powerplatform-vscode
  • Windows MSI: https://aka.ms/PowerAppsCLI
"@
}
$pacVersion = (pac --version 2>$null) | Select-Object -First 1
Write-Host "  ✓ pac CLI $pacVersion" -ForegroundColor Green

# ── 3. Read environment configuration ──
Write-Host "[3/4] Reading environment configuration..." -ForegroundColor Yellow

$envUrl = Get-AzdEnvValue 'POWERPLATFORM_ENVIRONMENT_URL'
$tenantId = Get-AzdEnvValue 'POWERPLATFORM_TENANT_ID'
$appId = Get-AzdEnvValue 'POWERPLATFORM_APP_ID'
$clientSecret = Get-AzdEnvValue 'POWERPLATFORM_CLIENT_SECRET'
$deploymentMode = Get-AzdEnvValue 'DEPLOYMENT_MODE'
$solutionName = Get-AzdEnvValue 'POWERPLATFORM_SOLUTION_NAME'
$scenarioName = Get-AzdEnvValue 'SCENARIO_NAME'

# Resolve scenario root for auto-detection
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if ($scenarioName) {
    $scenarioRoot = Join-Path $projectRoot 'scenarios' $scenarioName
} else {
    $scenarioRoot = $projectRoot
}

# Validate required vars
$missing = @()
if (-not $envUrl) { $missing += 'POWERPLATFORM_ENVIRONMENT_URL' }
if (-not $solutionName) { $missing += 'POWERPLATFORM_SOLUTION_NAME' }
if (-not $deploymentMode) {
    # Auto-detect mode from folder presence (in scenario or root)
    if (Test-Path (Join-Path $scenarioRoot 'solution' '*.xml') -ErrorAction SilentlyContinue) {
        $deploymentMode = 'solution'
    }
    elseif (Test-Path (Join-Path $scenarioRoot 'template' '*.yaml') -ErrorAction SilentlyContinue) {
        $deploymentMode = 'template'
    }
    else {
        $missing += 'DEPLOYMENT_MODE (and no solution/ or template/ folder detected)'
    }

    if ($deploymentMode) {
        Write-Host "  Auto-detected deployment mode: $deploymentMode" -ForegroundColor Cyan
        azd env set DEPLOYMENT_MODE $deploymentMode
    }
}

if ($missing.Count -gt 0) {
    Write-Error @"
Missing required environment variables. Set them with:
  $(($missing | ForEach-Object { "azd env set $_ <value>" }) -join "`n  ")

See .env.sample for the full list of configuration variables.
"@
}

Write-Host "  ✓ Environment URL : $envUrl" -ForegroundColor Green
Write-Host "  ✓ Solution name   : $solutionName" -ForegroundColor Green
Write-Host "  ✓ Deployment mode : $deploymentMode" -ForegroundColor Green
if ($scenarioName) { Write-Host "  ✓ Scenario        : $scenarioName" -ForegroundColor Green }

# ── 4. Authenticate to Power Platform ──
Write-Host "[4/4] Authenticating to Power Platform..." -ForegroundColor Yellow

# Check if there's already an active auth profile for this environment
$existingAuth = pac auth list 2>$null
$alreadyAuth = $existingAuth | Select-String $envUrl

if ($alreadyAuth) {
    Write-Host "  ✓ Active auth profile found for $envUrl" -ForegroundColor Green
}
elseif ($appId -and $clientSecret -and $tenantId) {
    # Service principal authentication (non-interactive / CI-CD)
    Write-Host "  Authenticating with service principal..." -ForegroundColor Cyan
    pac auth create `
        --name "azd-cpstudio-$($env:AZURE_ENV_NAME)" `
        --environment $envUrl `
        --applicationId $appId `
        --clientSecret $clientSecret `
        --tenant $tenantId

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to authenticate to Power Platform with service principal."
    }
    Write-Host "  ✓ Authenticated via service principal" -ForegroundColor Green
}
else {
    # Interactive authentication (trainer use)
    Write-Host "  No service principal configured — launching interactive login..." -ForegroundColor Cyan
    Write-Host "  A browser window will open. Sign in with your Power Platform account." -ForegroundColor Cyan

    $authArgs = @('auth', 'create', '--name', "azd-cpstudio-$($env:AZURE_ENV_NAME)", '--environment', $envUrl)
    if ($tenantId) { $authArgs += '--tenant'; $authArgs += $tenantId }

    pac @authArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to authenticate to Power Platform interactively."
    }
    Write-Host "  ✓ Authenticated interactively" -ForegroundColor Green
}

# Verify environment is reachable
$envInfo = pac env who 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Cannot reach Power Platform environment at $envUrl. Check the URL and your permissions."
}

Write-Host "`n✅ All pre-provision checks passed. Ready to deploy.`n" -ForegroundColor Green
