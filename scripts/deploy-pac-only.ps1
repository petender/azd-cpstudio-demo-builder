#Requires -Version 7.0
<#
.SYNOPSIS
    Deploy a Copilot Studio agent using pac CLI only (no Azure subscription required).
.DESCRIPTION
    Standalone deployment script for users who don't have an Azure subscription.
    Performs the same agent deployment as the azd postprovision hook but without
    requiring azd or Azure resources.

    Supports both deployment modes:
    - "solution": Packs and imports a Power Platform solution
    - "template": Creates a new agent from a BotDefinition YAML template

.PARAMETER EnvironmentUrl
    The Power Platform environment URL (e.g., https://org123.crm.dynamics.com).

.PARAMETER SolutionName
    Unique name for the Power Platform solution.

.PARAMETER DeploymentMode
    Either "solution" or "template". Auto-detected from folder structure if omitted.

.PARAMETER AgentDisplayName
    Display name for the agent (required for template mode).

.PARAMETER ScenarioName
    Name of the scenario folder under scenarios/ (e.g., "it-helpdesk").
    If omitted, looks for template/ and solution/ in the project root (legacy layout).

.EXAMPLE
    ./scripts/deploy-pac-only.ps1 -EnvironmentUrl "https://org123.crm.dynamics.com" -SolutionName "MyDemo" -DeploymentMode "template" -AgentDisplayName "My Demo Agent" -ScenarioName "it-helpdesk"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$SolutionName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('solution', 'template')]
    [string]$DeploymentMode,

    [Parameter(Mandatory = $false)]
    [string]$AgentDisplayName,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# ── Resolve scenario folder ──
if ($ScenarioName) {
    $scenarioRoot = Join-Path $projectRoot 'scenarios' $ScenarioName
    if (-not (Test-Path $scenarioRoot)) {
        Write-Error "Scenario folder not found: $scenarioRoot. Create it under scenarios/ or check -ScenarioName."
    }
} else {
    $scenarioRoot = $projectRoot
}

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — pac-only Deploy       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ── Auto-detect deployment mode ──
if (-not $DeploymentMode) {
    $solutionFolder = Join-Path $scenarioRoot 'solution'
    $templateFolder = Join-Path $scenarioRoot 'template'
    $hasSolution = (Test-Path (Join-Path $solutionFolder '*.xml')) -or (Test-Path (Join-Path $solutionFolder '*.yml'))
    $hasTemplate = Get-ChildItem -Path $templateFolder -Filter '*.yaml' -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content $_.FullName -First 1) -match 'kind:\s*BotDefinition' }

    if ($hasSolution) { $DeploymentMode = 'solution' }
    elseif ($hasTemplate) { $DeploymentMode = 'template' }
    else { Write-Error "Cannot auto-detect deployment mode. No solution files in solution/ or BotDefinition YAML in template/. Use -DeploymentMode." }
    Write-Host "Auto-detected deployment mode: $DeploymentMode" -ForegroundColor Cyan
}

# ── Validate pac CLI ──
Write-Host "[1/5] Checking pac CLI..." -ForegroundColor Yellow
$pacCmd = Get-Command pac -ErrorAction SilentlyContinue
if (-not $pacCmd) {
    Write-Error "pac CLI is not installed. Install with: dotnet tool install --global Microsoft.PowerApps.CLI"
}
Write-Host "  ✓ pac CLI found" -ForegroundColor Green

# ── Authenticate to Power Platform ──
Write-Host "[2/5] Checking Power Platform authentication..." -ForegroundColor Yellow
$existingAuth = pac auth list 2>$null
$alreadyAuth = $existingAuth | Select-String ([regex]::Escape($EnvironmentUrl))

if ($alreadyAuth) {
    Write-Host "  ✓ Already authenticated to $EnvironmentUrl" -ForegroundColor Green
} else {
    Write-Host "  Launching interactive login for $EnvironmentUrl..." -ForegroundColor Cyan
    pac auth create --name "cpstudio-pac-only" --environment $EnvironmentUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to authenticate. Ensure you have Maker permissions on this environment."
    }
    Write-Host "  ✓ Authenticated" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODE A: Solution Import
# ═══════════════════════════════════════════════════════════════════════════
if ($DeploymentMode -eq 'solution') {
    $solutionFolder = Join-Path $scenarioRoot 'solution'
    $tempZip = Join-Path $projectRoot '.tmp' 'solution-import.zip'

    $solutionXml = Get-ChildItem -Path $solutionFolder -Filter 'Solution.xml' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $solutionYml = Get-ChildItem -Path $solutionFolder -Filter 'solution.yml' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $solutionXml -and -not $solutionYml) {
        Write-Error "No Solution.xml or solution.yml found in $solutionFolder."
    }

    # Pack
    Write-Host "`n[3/5] Packing solution..." -ForegroundColor Yellow
    $tmpDir = Split-Path $tempZip -Parent
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

    $packArgs = @('solution', 'pack', '--zipfile', $tempZip, '--folder', $solutionFolder, '--packagetype', 'Unmanaged')
    if ($solutionYml) { $packArgs += '--processCanvasApps' }
    pac @packArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to pack solution." }
    Write-Host "  ✓ Solution packed" -ForegroundColor Green

    # Import
    Write-Host "`n[4/5] Importing solution..." -ForegroundColor Yellow
    pac solution import --path $tempZip --publish-changes --activate-plugins
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to import solution." }
    Write-Host "  ✓ Solution imported" -ForegroundColor Green

    # Publish
    Write-Host "`n[5/5] Publishing agent..." -ForegroundColor Yellow
    $copilots = pac copilot list 2>$null
    $botLine = $copilots | Select-String $AgentDisplayName | Select-Object -First 1
    if (-not $botLine) { $botLine = $copilots | Select-String $SolutionName | Select-Object -First 1 }
    if ($botLine) {
        $botId = ($botLine -split '\s{2,}')[0].Trim()
        pac copilot publish --bot $botId 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Agent published" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Could not auto-publish. Publish manually in Copilot Studio." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠ Could not locate agent. Publish manually in Copilot Studio." -ForegroundColor Yellow
    }

    # Clean up
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODE B: YAML Template
# ═══════════════════════════════════════════════════════════════════════════
elseif ($DeploymentMode -eq 'template') {
    if (-not $AgentDisplayName) {
        Write-Error "AgentDisplayName is required for template mode. Use -AgentDisplayName 'My Agent'."
    }

    $templateFolder = Join-Path $scenarioRoot 'template'
    $templateFile = Get-ChildItem -Path $templateFolder -Filter '*.yaml' -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content $_.FullName -First 1) -match 'kind:\s*BotDefinition' } |
        Select-Object -First 1

    if (-not $templateFile) {
        Write-Error "No BotDefinition YAML template found in $templateFolder."
    }

    $agentSchemaName = 'cr_' + ($AgentDisplayName -replace '[^a-zA-Z0-9]', '').ToLower()

    # Ensure solution exists
    Write-Host "`n[3/5] Checking target solution..." -ForegroundColor Yellow
    $solutionList = pac solution list 2>$null
    $solutionExists = $solutionList | Select-String $SolutionName

    if (-not $solutionExists) {
        Write-Host "  Creating solution '$SolutionName'..." -ForegroundColor Cyan

        $tmpSolDir = Join-Path $projectRoot '.tmp' $SolutionName
        if (Test-Path $tmpSolDir) { Remove-Item $tmpSolDir -Recurse -Force }

        $publisherPrefix = ($SolutionName -replace '[^a-zA-Z]', '').ToLower()
        if ($publisherPrefix.Length -gt 5) { $publisherPrefix = $publisherPrefix.Substring(0, 5) }
        if ($publisherPrefix.Length -lt 2) { $publisherPrefix = 'demo' }
        $publisherName = "${publisherPrefix}publisher"

        pac solution init --publisher-name $publisherName --publisher-prefix $publisherPrefix --outputDirectory $tmpSolDir
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to init solution." }

        $tmpSolZip = Join-Path $projectRoot '.tmp' "$SolutionName.zip"
        if (Test-Path $tmpSolZip) { Remove-Item $tmpSolZip -Force }
        pac solution pack --zipfile $tmpSolZip --folder (Join-Path $tmpSolDir 'src') --packagetype Unmanaged
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to pack solution." }

        pac solution import --path $tmpSolZip --publish-changes
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to import solution." }

        Remove-Item $tmpSolDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpSolZip -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ Solution '$SolutionName' created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Solution '$SolutionName' exists" -ForegroundColor Green
    }

    # Create agent
    Write-Host "`n[4/5] Creating agent from template..." -ForegroundColor Yellow
    Write-Host "  Template: $($templateFile.Name)" -ForegroundColor Cyan

    $createOutput = pac copilot create `
        --displayName $AgentDisplayName `
        --schemaName $agentSchemaName `
        --solution $SolutionName `
        --templateFileName $templateFile.FullName 2>&1
    $createOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create agent." }

    $botIdMatch = ($createOutput | Out-String) -match 'with id ([0-9a-f\-]{36})'
    $botId = if ($botIdMatch) { $Matches[1] } else { $null }
    Write-Host "  ✓ Agent created" -ForegroundColor Green

    # Publish
    Write-Host "`n[5/5] Publishing agent..." -ForegroundColor Yellow
    $publishTarget = if ($botId) { $botId } else { $agentSchemaName }
    pac copilot publish --bot $publishTarget 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Agent published" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Could not auto-publish. Publish manually in Copilot Studio." -ForegroundColor Yellow
    }

    # Store info for teardown
    Write-Host "`nFor teardown, run:" -ForegroundColor Cyan
    Write-Host "  ./scripts/teardown-pac-only.ps1 -EnvironmentUrl '$EnvironmentUrl' -SolutionName '$SolutionName'" -ForegroundColor White
    if ($botId) {
        Write-Host "  Bot ID: $botId" -ForegroundColor Cyan
    }
}

Write-Host "`n✅ Deployment complete.`n" -ForegroundColor Green
Write-Host "Open Copilot Studio to verify: https://copilotstudio.microsoft.com" -ForegroundColor Cyan
Write-Host ""
