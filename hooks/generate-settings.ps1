#Requires -Version 7.0
<#
.SYNOPSIS
    Generates a deployment-settings.json file from Azure resource outputs.
.DESCRIPTION
    Reads Bicep output values from azd environment variables and produces a
    deployment-settings.json compatible with pac solution import --settings-file.
    This wires Azure resource endpoints/keys into Power Platform environment
    variables and connection references in the solution.

    Add mappings below for each Azure output your agent's solution needs.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$settingsPath = Join-Path $projectRoot '.tmp' 'deployment-settings.json'

# ── Helper: read azd env var ──
function Get-AzdEnvValue {
    param([string]$Name)
    $val = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ([string]::IsNullOrEmpty($val)) { return $null }
    return $val.Trim('"')
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Environment Variable Mappings                                          ║
# ║                                                                         ║
# ║  Map azd env vars (from Bicep outputs) to Power Platform environment   ║
# ║  variable schema names in your solution.                                ║
# ║                                                                         ║
# ║  Example: If your Bicep outputs AZURE_OPENAI_ENDPOINT and your         ║
# ║  solution has an env var named cr_AzureOpenAIEndpoint, add:            ║
# ║                                                                         ║
# ║    @{                                                                   ║
# ║        AzdVariable = 'AZURE_OPENAI_ENDPOINT'                           ║
# ║        PPVariable  = 'cr_AzureOpenAIEndpoint'                          ║
# ║    }                                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════╝
$envVarMappings = @(
    # Uncomment and customize these mappings for your agent:
    #
    # @{ AzdVariable = 'AZURE_OPENAI_ENDPOINT';  PPVariable = 'cr_AzureOpenAIEndpoint' }
    # @{ AzdVariable = 'AZURE_OPENAI_KEY';       PPVariable = 'cr_AzureOpenAIKey' }
    # @{ AzdVariable = 'AZURE_SEARCH_ENDPOINT';  PPVariable = 'cr_AzureSearchEndpoint' }
    # @{ AzdVariable = 'AZURE_SEARCH_KEY';       PPVariable = 'cr_AzureSearchKey' }
    # @{ AzdVariable = 'AZURE_FUNCTION_URL';     PPVariable = 'cr_AzureFunctionUrl' }
)

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Connection Reference Mappings                                          ║
# ║                                                                         ║
# ║  Map solution connection references to existing connection IDs in the  ║
# ║  target environment. The connection ID must already exist.             ║
# ║                                                                         ║
# ║  Example:                                                               ║
# ║    @{                                                                   ║
# ║        ConnectionRef = 'cr_sharedazureopenai_XXXXX'                    ║
# ║        ConnectionId  = '<guid-of-existing-connection>'                 ║
# ║    }                                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════╝
$connectionMappings = @(
    # Uncomment and customize:
    #
    # @{ ConnectionRef = 'cr_sharedazureopenai_XXXXX'; ConnectionId = 'AZURE_OPENAI_CONNECTION_ID' }
)

# ── Build the settings object ──
$envVars = @{}
foreach ($mapping in $envVarMappings) {
    $value = Get-AzdEnvValue $mapping.AzdVariable
    if ($value) {
        $envVars[$mapping.PPVariable] = $value
    }
    else {
        Write-Host "  ⚠ No value found for $($mapping.AzdVariable) — skipping" -ForegroundColor Yellow
    }
}

$connRefs = @{}
foreach ($mapping in $connectionMappings) {
    $connId = Get-AzdEnvValue $mapping.ConnectionId
    if (-not $connId) { $connId = $mapping.ConnectionId }
    if ($connId) {
        $connRefs[$mapping.ConnectionRef] = @{ ConnectionId = $connId }
    }
}

# Only write the file if there are actual mappings
if ($envVars.Count -eq 0 -and $connRefs.Count -eq 0) {
    Write-Host "  No Azure-to-Power Platform mappings configured. Skipping settings file." -ForegroundColor Cyan
    exit 0
}

$settings = @{
    EnvironmentVariables = $envVars
    ConnectionReferences = $connRefs
}

$tmpDir = Split-Path $settingsPath -Parent
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

$settings | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding utf8

Write-Host "  ✓ Deployment settings written to $settingsPath" -ForegroundColor Green
Write-Host "    Environment variables: $($envVars.Count)" -ForegroundColor Cyan
Write-Host "    Connection references: $($connRefs.Count)" -ForegroundColor Cyan
