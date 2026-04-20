targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (used for resource naming)')
param environmentName string

@minLength(1)
@description('Primary Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object = {}

@description('Power Platform solution name for the Copilot Studio agent')
param solutionName string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  Resource Group                                                         ║
// ╚══════════════════════════════════════════════════════════════════════════╝
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: union(tags, {
    'azd-env-name': environmentName
    purpose: 'Copilot Studio demo deployment'
    'copilot-studio-solution': solutionName
  })
}

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  Add Azure backend modules below when your Copilot Studio agent needs  ║
// ║  Azure resources (Azure OpenAI, AI Search, Azure Functions, etc.)      ║
// ║                                                                         ║
// ║  Example:                                                               ║
// ║    module openai './modules/openai.bicep' = {                           ║
// ║      name: 'openai'                                                     ║
// ║      scope: rg                                                          ║
// ║      params: {                                                          ║
// ║        name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'       ║
// ║        location: location                                               ║
// ║        tags: tags                                                       ║
// ║      }                                                                  ║
// ║    }                                                                    ║
// ╚══════════════════════════════════════════════════════════════════════════╝

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  Outputs — these become azd env vars, available in hook scripts        ║
// ║  Example:                                                               ║
// ║    output AZURE_OPENAI_ENDPOINT string = openai.outputs.endpoint       ║
// ║    output AZURE_OPENAI_KEY string = openai.outputs.key                 ║
// ╚══════════════════════════════════════════════════════════════════════════╝
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location
