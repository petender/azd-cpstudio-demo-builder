---
applyTo: "**/hooks/**,**/scripts/**,**/azure.yaml"
---
# Copilot Studio Demo Builder — Deployment Instructions

## Overview

This project deploys Copilot Studio agents using `azd` with Power Platform CLI (`pac`) hooks.
Two deployment modes are supported: **solution** (complex agents) and **template** (simple agents).

## Template Mode Deployment Flow

For YAML-template-based agents (simple agents created from scratch):

### Prerequisites
1. `pac` CLI installed and on PATH
2. `azd` CLI installed
3. PowerShell 7+
4. A Power Platform environment URL (Dataverse org URL)
5. A YAML template file in `template/` folder

### Environment Variables Required
```
POWERPLATFORM_ENVIRONMENT_URL  — e.g., https://org123.crm.dynamics.com
POWERPLATFORM_SOLUTION_NAME    — unique name for the solution (no spaces)
DEPLOYMENT_MODE                — "template"
AGENT_DISPLAY_NAME             — display name for the agent
AGENT_SCHEMA_NAME              — (optional) auto-generated from display name
SCENARIO_NAME                  — name of the scenario folder under scenarios/ (e.g., it-helpdesk)
```

### Deployment Steps
```powershell
# 1. Initialize azd environment (if not done)
azd init

# 2. Set required variables
azd env set POWERPLATFORM_ENVIRONMENT_URL "https://yourorg.crm.dynamics.com"
azd env set POWERPLATFORM_SOLUTION_NAME "MyDemoAgent"
azd env set DEPLOYMENT_MODE "template"
azd env set AGENT_DISPLAY_NAME "My Demo Agent"
azd env set SCENARIO_NAME "it-helpdesk"

# 3. Deploy
azd up

# 4. Teardown when done
azd down
```

### What `azd up` Does
1. **preprovision hook**: Validates pac CLI, authenticates to Power Platform (interactive or SPN)
2. **provision**: Runs Bicep (no-op if no Azure resources defined)
3. **postprovision hook**: Creates agent from YAML template in `scenarios/<name>/template/`, publishes it

### What `azd down` Does
1. Removes Azure resources (if any)
2. **postdown hook**: Deletes the Power Platform solution and agent

## Solution Mode Deployment Flow

For complex agents built in the Copilot Studio UI and exported as Power Platform solutions.

### When to Use Solution Mode
- Agent has knowledge sources, connectors, tools, MCP servers, or Power Automate flows
- Agent was built/customized in the Copilot Studio UI and you want to preserve it exactly
- You need an exact replica of a production agent for training demos

### Preparing the Agent for Export

Before exporting, the agent **must be in a solution** with all required objects:

1. **Open make.powerapps.com** → Solutions
2. **Create a new solution** (or use an existing one) with a publisher that has a prefix you'll recognize
3. **Add the agent** to the solution: Add existing → Chatbot/Agent → select your agent
4. **Add required objects**: Select the agent in the solution → click "Add required objects" in the toolbar. This pulls in all topics, bot components, AI plugins, custom APIs, environment variable definitions, etc.
5. **Verify**: The solution should show multiple components (bot, botcomponents, aipluginoperations, etc.)

**Alternative — add agent via CLI:**
```powershell
# Find your agent's bot ID
pac copilot list

# Add it to a solution (use component type name "bot", NOT numeric code)
pac solution add-solution-component `
    --solutionUniqueName "YourSolution" `
    --component "<bot-guid>" `
    --componentType "bot" `
    --AddRequiredComponents true
```

> **Critical**: The `--componentType` parameter accepts the **name** `"bot"` for auto-resolution. Numeric type codes (like `10162`) are rejected with "not known". Always use the string name.

### Export to Scenario Folder

```powershell
# Authenticate to the environment that has the agent
pac auth create --environment https://yourorg.crm.dynamics.com

# Export to a scenario folder
./scripts/export-agent.ps1 -SolutionName "YourSolutionName" -ScenarioName "your-scenario"
```

This exports the solution zip, unpacks it into `scenarios/<name>/solution/`, and cleans up.

### Deployment
```powershell
azd env set SCENARIO_NAME "your-scenario"
azd env set POWERPLATFORM_SOLUTION_NAME "YourSolutionName"
azd env set DEPLOYMENT_MODE "solution"
azd up
```

### What Happens During Solution Import
1. `preprovision` validates tools, authenticates, detects `solution` mode from the scenario folder
2. `postprovision` packs the `scenarios/<name>/solution/` folder into a zip
3. `pac solution import --publish-changes --activate-plugins` imports and publishes in one step
4. The `--publish-changes` flag publishes all customizations, so no separate publish step is needed

### Re-export After Changes

If you modify the agent in Copilot Studio and want to capture the changes:
```powershell
# Re-run the export script — it clears old files and re-exports
./scripts/export-agent.ps1 -SolutionName "YourSolutionName" -ScenarioName "your-scenario"

# Commit the updated files
git add scenarios/your-scenario/solution/
git commit -m "Updated agent export"
```

### Teardown
```powershell
azd down    # removes the solution from Power Platform (and Azure resources if any)
```

Or standalone:
```powershell
pac solution delete --solution-name "YourSolutionName"
```

> **Note**: `pac solution delete` uses `--solution-name` (not `--name`). Deleting a solution removes the agent and all components that were part of the solution.

## Error Handling
- If `pac auth` fails, the preprovision hook will attempt interactive login
- If solution import fails, check that custom connectors were imported first
- Solution delete during teardown is best-effort — manual cleanup may be needed
- Ghost schema records can linger after solution delete — use a new `AGENT_SCHEMA_NAME` if re-creating with the same name fails

## Cross-Environment Deployment

Solution export/import is designed to move agents across environments. However, some features carry environment-specific bindings.

### Same-environment re-imports (teardown → redeploy)
No manual steps needed. All references resolve correctly because they point to resources that still exist (or are re-created) in the same environment.

### Different-environment imports
These features need manual reconfiguration after import:
- **Knowledge sources** (SharePoint, uploaded docs) — re-link in Copilot Studio UI
- **Connection references** — reconfigure credentials in the maker portal
- **Environment variables** — update values (endpoints, API keys) via maker portal or deployment settings
- **Custom connectors** — must exist in the target environment before the agent solution imports
- **AI Builder models** — may need re-creation in the target
- **Authentication settings** — reconfigure SSO/identity provider for the new environment

### Deployment settings for environment-specific values
When deploying across environments, use deployment settings to override environment variables:
```powershell
# Pack and import with settings override
pac solution import --path ./solution.zip --publish-changes --settings-file deployment-settings.json
```
The `generate-settings.ps1` hook can map azd/Bicep outputs to a settings file automatically.
