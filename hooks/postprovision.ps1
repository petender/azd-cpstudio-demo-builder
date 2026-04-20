#Requires -Version 7.0
<#
.SYNOPSIS
    Post-provision hook — deploys the Copilot Studio agent to Power Platform.
.DESCRIPTION
    Runs after Azure infrastructure provisioning. Depending on DEPLOYMENT_MODE:
    - "solution": Packs and imports a Power Platform solution containing the agent.
    - "template": Creates a new agent from a YAML template.
    Then displays a reminder to publish the agent manually in Copilot Studio.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Copilot Studio Demo Builder — Agent Deployment     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# ── Helper: read azd env var ──
function Get-AzdEnvValue {
    param([string]$Name)
    $val = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ([string]::IsNullOrEmpty($val)) { return $null }
    return $val.Trim('"')
}

# ── Read configuration ──
$deploymentMode = Get-AzdEnvValue 'DEPLOYMENT_MODE'
$solutionName   = Get-AzdEnvValue 'POWERPLATFORM_SOLUTION_NAME'
$agentDisplayName = Get-AzdEnvValue 'AGENT_DISPLAY_NAME'
$agentSchemaName  = Get-AzdEnvValue 'AGENT_SCHEMA_NAME'
$scenarioName     = Get-AzdEnvValue 'SCENARIO_NAME'

# ── Resolve scenario folder ──
if ($scenarioName) {
    $scenarioRoot = Join-Path $projectRoot 'scenarios' $scenarioName
    if (-not (Test-Path $scenarioRoot)) {
        Write-Error "Scenario folder not found: $scenarioRoot. Create it under scenarios/ or check SCENARIO_NAME."
    }
} else {
    # Legacy: fall back to root-level template/ or solution/ if they exist
    $scenarioRoot = $projectRoot
}

Write-Host "Deployment mode : $deploymentMode" -ForegroundColor Cyan
Write-Host "Solution name   : $solutionName" -ForegroundColor Cyan
if ($scenarioName) { Write-Host "Scenario        : $scenarioName" -ForegroundColor Cyan }

# ═══════════════════════════════════════════════════════════════════════════
#  MODE A: Solution Import (complex agents)
# ═══════════════════════════════════════════════════════════════════════════
if ($deploymentMode -eq 'solution') {
    $solutionFolder = Join-Path $scenarioRoot 'solution'
    $tempZip = Join-Path $projectRoot '.tmp' 'solution-import.zip'

    if (-not (Test-Path $solutionFolder)) {
        Write-Error "Solution folder not found at $solutionFolder. Run scripts/export-agent.ps1 first."
    }

    # Check if the unpacked solution has content
    $solutionXml = Get-ChildItem -Path $solutionFolder -Filter 'Solution.xml' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $solutionYml = Get-ChildItem -Path $solutionFolder -Filter 'solution.yml' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $solutionXml -and -not $solutionYml) {
        Write-Error "No Solution.xml or solution.yml found in $solutionFolder. Is this a valid unpacked solution?"
    }

    # Step 1: Pack the solution
    Write-Host "`n[1/2] Packing solution from source files..." -ForegroundColor Yellow
    $tmpDir = Split-Path $tempZip -Parent
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

    $packArgs = @('solution', 'pack', '--zipfile', $tempZip, '--folder', $solutionFolder, '--packagetype', 'Unmanaged')

    # Use YAML format if solution.yml is present
    if ($solutionYml) {
        $packArgs += '--processCanvasApps'
    }

    pac @packArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to pack solution. Check the solution folder contents."
    }
    Write-Host "  ✓ Solution packed to $tempZip" -ForegroundColor Green

    # Step 2: Generate deployment settings if Azure backend outputs exist
    $settingsFile = Join-Path $projectRoot '.tmp' 'deployment-settings.json'
    $generateSettings = Join-Path $PSScriptRoot 'generate-settings.ps1'

    if (Test-Path $generateSettings) {
        Write-Host "`n[1.5/2] Generating deployment settings from Azure outputs..." -ForegroundColor Yellow
        & $generateSettings
        if (Test-Path $settingsFile) {
            Write-Host "  ✓ Deployment settings generated" -ForegroundColor Green
        }
    }

    # Step 3: Import the solution
    Write-Host "`n[2/2] Importing solution into Power Platform..." -ForegroundColor Yellow

    $importArgs = @('solution', 'import', '--path', $tempZip, '--publish-changes', '--activate-plugins')

    if (Test-Path $settingsFile) {
        $importArgs += '--settings-file'
        $importArgs += $settingsFile
    }

    pac @importArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to import solution. Check pac CLI output above for details."
    }
    Write-Host "  ✓ Solution imported successfully" -ForegroundColor Green

    # Store bot ID for teardown (if we can find it)
    $copilots = pac copilot list 2>$null
    if ($agentSchemaName) {
        $botLine = $copilots | Select-String $agentSchemaName | Select-Object -First 1
    }
    elseif ($agentDisplayName) {
        $botLine = $copilots | Select-String $agentDisplayName | Select-Object -First 1
    }
    if ($botLine) {
        $botId = ($botLine -split '\s{2,}')[0].Trim()
        azd env set DEPLOYED_BOT_ID $botId
    }

    # Store solution name for teardown
    azd env set DEPLOYED_SOLUTION_NAME $solutionName

    # Clean up temp files
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    if (Test-Path $settingsFile) { Remove-Item $settingsFile -Force }
    $tmpDir = Join-Path $projectRoot '.tmp'
    if ((Test-Path $tmpDir) -and (Get-ChildItem $tmpDir | Measure-Object).Count -eq 0) {
        Remove-Item $tmpDir -Force
    }
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODE B: YAML Template (simple agents)
# ═══════════════════════════════════════════════════════════════════════════
elseif ($deploymentMode -eq 'template') {
    $templateFolder = Join-Path $scenarioRoot 'template'

    # Find YAML files that start with 'kind: BotDefinition' (pac copilot create format)
    $templateFile = Get-ChildItem -Path $templateFolder -Filter '*.yaml' -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content $_.FullName -First 1) -match 'kind:\s*BotDefinition' } |
        Select-Object -First 1

    if (-not $templateFile) {
        Write-Error "No BotDefinition YAML template found in $templateFolder. The template must start with 'kind: BotDefinition'. Use 'pac copilot extract-template' or the creator agent to generate one."
    }

    if (-not $agentDisplayName) {
        Write-Error "AGENT_DISPLAY_NAME is required for template mode. Set with: azd env set AGENT_DISPLAY_NAME '<name>'"
    }
    if (-not $agentSchemaName) {
        # Auto-generate schema name from display name (remove spaces, prefix with cr_)
        $agentSchemaName = 'cr_' + ($agentDisplayName -replace '[^a-zA-Z0-9]', '').ToLower()
        Write-Host "  Auto-generated schema name: $agentSchemaName" -ForegroundColor Cyan
        azd env set AGENT_SCHEMA_NAME $agentSchemaName
    }

    # Step 1: Ensure the target solution exists
    Write-Host "`n[1/2] Checking target solution..." -ForegroundColor Yellow

    $solutionList = pac solution list 2>$null
    $solutionExists = $solutionList | Select-String $solutionName

    if (-not $solutionExists) {
        Write-Host "  Solution '$solutionName' not found. Creating it..." -ForegroundColor Cyan

        # Create a minimal solution: init → pack → import
        # Use the solution name as directory name so pac uses it as the UniqueName
        $tmpSolDir = Join-Path $projectRoot '.tmp' $solutionName
        if (Test-Path $tmpSolDir) { Remove-Item $tmpSolDir -Recurse -Force }

        # Derive a publisher prefix from the solution name (max 5 chars, lowercase alpha)
        $publisherPrefix = ($solutionName -replace '[^a-zA-Z]', '').ToLower()
        if ($publisherPrefix.Length -gt 5) { $publisherPrefix = $publisherPrefix.Substring(0, 5) }
        if ($publisherPrefix.Length -lt 2) { $publisherPrefix = 'demo' }
        $publisherName = "${publisherPrefix}publisher"

        pac solution init --publisher-name $publisherName --publisher-prefix $publisherPrefix --outputDirectory $tmpSolDir

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to initialize solution project."
        }

        $tmpSolZip = Join-Path $projectRoot '.tmp' "$solutionName.zip"
        if (Test-Path $tmpSolZip) { Remove-Item $tmpSolZip -Force }
        pac solution pack --zipfile $tmpSolZip --folder (Join-Path $tmpSolDir 'src') --packagetype Unmanaged

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to pack empty solution."
        }

        pac solution import --path $tmpSolZip --publish-changes
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to import empty solution."
        }

        # Clean up temp files
        Remove-Item $tmpSolDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpSolZip -Force -ErrorAction SilentlyContinue

        Write-Host "  ✓ Solution '$solutionName' created" -ForegroundColor Green
    }
    else {
        Write-Host "  ✓ Solution '$solutionName' exists" -ForegroundColor Green
    }

    # Step 2: Create agent from template
    Write-Host "`n[2/2] Creating agent from YAML template..." -ForegroundColor Yellow
    Write-Host "  Template: $($templateFile.FullName)" -ForegroundColor Cyan

    $createOutput = pac copilot create `
        --displayName $agentDisplayName `
        --schemaName $agentSchemaName `
        --solution $solutionName `
        --templateFileName $templateFile.FullName 2>&1

    $createOutput | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create agent from template. Check pac CLI output above."
    }

    # Extract bot ID from output (e.g., "with id 0c17906c-...")
    $botIdMatch = ($createOutput | Out-String) -match 'with id ([0-9a-f\-]{36})'
    $botId = if ($botIdMatch) { $Matches[1] } else { $null }
    Write-Host "  ✓ Agent created" -ForegroundColor Green

    # Store identifiers for teardown
    azd env set DEPLOYED_SOLUTION_NAME $solutionName
    azd env set DEPLOYED_BOT_SCHEMA $agentSchemaName
    if ($botId) { azd env set DEPLOYED_BOT_ID $botId }
}
else {
    Write-Error "Unknown DEPLOYMENT_MODE: '$deploymentMode'. Must be 'solution' or 'template'."
}

Write-Host "`n✅ Agent deployment complete.`n" -ForegroundColor Green
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  ⚠  IMPORTANT: Open Copilot Studio and publish the agent   ║" -ForegroundColor Yellow
Write-Host "║     before testing. The agent won't respond until published.║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host "`nOpen Copilot Studio: https://copilotstudio.microsoft.com" -ForegroundColor Cyan
Write-Host ""
