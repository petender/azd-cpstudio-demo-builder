#Requires -Version 7.0
<#
.SYNOPSIS
    Exports an existing Copilot Studio agent as an unpacked Power Platform solution.
.DESCRIPTION
    One-time helper to capture a "golden" agent from Copilot Studio into source-controlled
    solution files. Run this after building your demo agent in the Copilot Studio UI.

    The exported solution is unpacked into the solution/ folder, ready for git commit.

.PARAMETER SolutionName
    The unique name of the Power Platform solution containing your agent.

.PARAMETER ScenarioName
    Scenario folder name under scenarios/. The solution is exported to
    scenarios/<ScenarioName>/solution/. If not provided, falls back to OutputFolder.

.PARAMETER OutputFolder
    Path to the output folder. Defaults to scenarios/<ScenarioName>/solution/
    or ./solution if no scenario is specified.

.EXAMPLE
    ./scripts/export-agent.ps1 -SolutionName "CopilotDemoAgent" -ScenarioName "ignite-assistant"
    ./scripts/export-agent.ps1 -SolutionName "CopilotDemoAgent" -OutputFolder "./solution"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionName,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioName,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

if (-not $OutputFolder) {
    if ($ScenarioName) {
        $OutputFolder = Join-Path $projectRoot 'scenarios' $ScenarioName 'solution'
    } else {
        $OutputFolder = Join-Path $projectRoot 'solution'
    }
}

# Ensure scenario directory structure exists
if ($ScenarioName) {
    $scenarioDir = Join-Path $projectRoot 'scenarios' $ScenarioName
    if (-not (Test-Path $scenarioDir)) {
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
    }
}

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — Export Agent          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ── Verify pac auth ──
Write-Host "[1/4] Verifying Power Platform authentication..." -ForegroundColor Yellow
pac env who 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not authenticated to Power Platform. Run: pac auth create --environment <url>"
}
Write-Host "  ✓ Authenticated" -ForegroundColor Green

# ── Verify solution exists ──
Write-Host "[2/4] Checking solution '$SolutionName'..." -ForegroundColor Yellow
$solutionList = pac solution list 2>$null
$found = $solutionList | Select-String $SolutionName
if (-not $found) {
    Write-Error @"
Solution '$SolutionName' not found in the current environment.
Available solutions:
$solutionList

Make sure:
1. Your agent is added to a solution in Power Platform.
2. You used 'Add required objects' to include all topics, flows, and dependencies.
3. Topic names do NOT contain periods (.).
"@
}
Write-Host "  ✓ Solution found" -ForegroundColor Green

# ── Export solution ──
Write-Host "[3/4] Exporting solution..." -ForegroundColor Yellow
$tempZip = Join-Path $projectRoot '.tmp' 'export-temp.zip'
$tmpDir = Split-Path $tempZip -Parent
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

pac solution export --name $SolutionName --path $tempZip

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to export solution. Check pac CLI output above."
}
Write-Host "  ✓ Solution exported to temp zip" -ForegroundColor Green

# ── Unpack solution ──
Write-Host "[4/4] Unpacking solution to $OutputFolder..." -ForegroundColor Yellow

# Clear existing solution folder contents (but keep the folder)
if (Test-Path $OutputFolder) {
    Get-ChildItem -Path $OutputFolder -Exclude '.gitkeep' | Remove-Item -Recurse -Force
}
else {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

pac solution unpack --zipfile $tempZip --folder $OutputFolder --packagetype Unmanaged --allowDelete --allowWrite

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to unpack solution. Check pac CLI output above."
}

# Clean up temp
Remove-Item $tempZip -Force
if ((Get-ChildItem $tmpDir | Measure-Object).Count -eq 0) {
    Remove-Item $tmpDir -Force
}

# ── Summary ──
$fileCount = (Get-ChildItem -Path $OutputFolder -Recurse -File | Measure-Object).Count
Write-Host "`n✅ Export complete." -ForegroundColor Green
Write-Host "   Files unpacked: $fileCount" -ForegroundColor Cyan
Write-Host "   Output folder : $OutputFolder" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review the exported files in $OutputFolder" -ForegroundColor White
Write-Host "  2. Set the azd environment variables:" -ForegroundColor White
if ($ScenarioName) {
    Write-Host "       azd env set SCENARIO_NAME '$ScenarioName'" -ForegroundColor White
}
Write-Host "       azd env set POWERPLATFORM_SOLUTION_NAME '$SolutionName'" -ForegroundColor White
Write-Host "       azd env set DEPLOYMENT_MODE 'solution'" -ForegroundColor White
Write-Host "  3. Commit the solution folder to git" -ForegroundColor White
Write-Host "  4. Use 'azd up' to redeploy and 'azd down' to tear down" -ForegroundColor White
Write-Host ""
Write-Host "⚠  Important reminders:" -ForegroundColor Yellow
Write-Host "  • Ensure you ran 'Add required objects' on the agent in the solution before exporting" -ForegroundColor White
Write-Host "  • Knowledge sources (SharePoint, uploaded docs) may need re-linking after import" -ForegroundColor White
Write-Host "  • Authentication settings need reconfiguration after import" -ForegroundColor White
Write-Host "  • Custom connectors must be imported separately, before the agent solution" -ForegroundColor White
