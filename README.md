# Copilot Studio Demo Builder

Automate the deployment and teardown of **Microsoft Copilot Studio agents** for repeatable training demos. Supports two deployment paths:

| Path | Azure subscription | Power Platform | CLI tools |
|---|---|---|---|
| **Full (`azd up`)** | ✅ Required | ✅ Required | `azd` + `pac` |
| **pac-only** | ❌ Not needed | ✅ Required | `pac` only |

> **Different credentials, different platforms.** Azure Developer CLI (`azd`) authenticates against your Azure subscription (Entra ID). Power Platform CLI (`pac`) authenticates against your Power Platform / Dataverse environment. These are independent — you can use different accounts for each.

---

## Prerequisites

### 1. Install Tools

| Tool | Required for | Install command |
|---|---|---|
| **PowerShell 7+** | Both paths | [https://aka.ms/powershell](https://aka.ms/powershell) |
| **.NET SDK 8.0+** | Installing pac | [https://dot.net/download](https://dot.net/download) |
| **Power Platform CLI (`pac`)** | Both paths | `dotnet tool install --global Microsoft.PowerApps.CLI` |
| **Azure Developer CLI (`azd`)** | Full path only | [https://aka.ms/azd](https://aka.ms/azd) |

Verify your installs:

```powershell
pwsh --version          # Should be 7.x
pac --version           # Should show version
azd version             # Only needed for full path
```

### 2. Get a Power Platform Environment

You need a Power Platform environment with **Maker** permissions. Options:

- **Microsoft 365 Developer Program** — free, includes Power Platform ([https://developer.microsoft.com/microsoft-365/dev-program](https://developer.microsoft.com/microsoft-365/dev-program))
- **Power Apps Developer Plan** — free, standalone ([https://powerapps.microsoft.com/developerplan](https://powerapps.microsoft.com/developerplan))
- **Existing org** — any environment where you have Maker role

Find your environment URL using either method:

- **Power Platform Admin Center** — [https://admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com) → Environments → your env → Environment URL
- **Copilot Studio** — open [https://copilotstudio.microsoft.com](https://copilotstudio.microsoft.com) → click the ⚙️ gear icon (Settings) → **Session details** → look for **Instance url** under "Power Platform Environment details"

The URL looks like `https://org12345.crm.dynamics.com`.

### 3. Authenticate

#### Power Platform authentication (`pac`)

```powershell
# Interactive login — opens a browser window
pac auth create --environment https://org12345.crm.dynamics.com

# Verify
pac env who
```

> **Corporate accounts (WAM):** If your organization enforces Web Account Manager (WAM), `pac auth create` will use the Windows account picker instead of a browser. This is automatic.

#### Azure authentication (`azd`) — only for full path

```powershell
# Interactive login
azd auth login

# Verify
azd auth login --check-status
```

> **Key point:** `azd auth login` uses your Azure / Entra ID credentials. `pac auth create` uses your Power Platform credentials. These can be **different accounts** on different tenants.

---

## How It Works

### Full Path (`azd up`)

```
azd up
  ├─ preprovision hook  → validates pac CLI, authenticates to Power Platform
  ├─ provision           → deploys Azure resources via Bicep (optional, can be no-op)
  └─ postprovision hook → imports solution or creates agent from YAML template

azd down
  ├─ infra delete       → removes Azure resources
  └─ postdown hook      → deletes solution/agent from Power Platform
```

### pac-only Path

```
deploy-pac-only.ps1    → authenticates, creates solution, creates agent, publishes
teardown-pac-only.ps1  → authenticates, deletes solution and agent
```

### Two Deployment Modes

| Mode | Use Case | Agent Definition |
|---|---|---|
| **solution** | Complex agents with topics, tools, MCP, connectors, knowledge, flows | Unpacked Power Platform solution in `solution/` |
| **template** | Simple agents with topics and instructions only | YAML template in `template/` |

### Understanding Template vs Solution Mode

Choosing the right mode depends on **which Copilot Studio capabilities your agent uses**. The table below maps every major capability to the mode(s) that support it.

#### Capability Comparison

| Copilot Studio Capability | Template (YAML) | Solution (exported) | Notes |
|---|:---:|:---:|---|
| **Custom topics** (trigger phrases, messages, branching) | ✅ | ✅ | Core building block of both modes |
| **System topics** (Greeting, Fallback, Escalate, On Error, etc.) | ✅ | ✅ | Template supports all system topic kinds |
| **Questions** (capture user input with entities) | ✅ | ✅ | Use `StringPrebuiltEntity`, `BooleanPrebuiltEntity`, etc. |
| **Conditions / branching logic** (Power Fx) | ✅ | ✅ | `ConditionGroup` with Power Fx expressions |
| **Variables** (topic-scoped, global) | ✅ | ✅ | `Topic.Var`, `Global.Var` syntax in both |
| **Adaptive Cards** | ✅ | ✅ | Inline JSON in `SendActivity` / message nodes |
| **Generative AI instructions** (system prompt) | ⚠️ Limited | ✅ | Template can set basic instructions; solution preserves full GPT configuration |
| **Generative orchestration** (AI selects topics) | ❌ | ✅ | Requires `modelDescription`, orchestrator config stored in solution metadata |
| **Knowledge sources** (websites, SharePoint, Dataverse, files) | ❌ | ✅ | Stored as bot components; need re-linking when importing cross-environment |
| **AI plugins / plugin actions** | ❌ | ✅ | Exported as `aipluginoperations/` and `aiplugins/` in the solution |
| **Custom connectors** | ❌ | ✅ | Must exist in target environment before import |
| **Connection references** | ❌ | ✅ | Credentials need reconfiguration on cross-environment import |
| **Power Automate cloud flows** | ❌ | ✅ | Flows are solution-aware components; included in export |
| **MCP server tools** | ❌ | ✅ | Tool registrations live in solution metadata |
| **HTTP request actions** | ❌ | ✅ | Not available in template YAML schema |
| **Environment variables** | ❌ | ✅ | Can be overridden via `deployment-settings.json` on import |
| **Authentication (SSO, Entra ID)** | ⚠️ Basic | ✅ | Template sets `authenticationMode`; solution preserves full SSO/OAuth config |
| **Custom entities (closed lists, regex)** | ❌ | ✅ | `ClosedListEntity` causes errors in template mode |
| **Multi-channel publishing** (Teams, web, etc.) | ❌ | ✅ | Channel configuration is environment-specific metadata |
| **Security / access control policies** | ⚠️ Basic | ✅ | Template sets `accessControlPolicy`; solution preserves full RBAC |

#### When to Use Each Mode

**Choose Template mode when:**
- Your agent is **topic-driven** — scripted conversations with trigger phrases, messages, questions, and branching logic
- You want to **author the agent as code** (YAML) and version-control it directly
- The agent does **not** need external data sources, connectors, or flows
- You want the **fastest possible deploy** (no prior Copilot Studio setup needed)
- You're building **training demos** that focus on conversational design, not integrations

**Choose Solution mode when:**
- Your agent uses **knowledge sources** (website search, SharePoint, uploaded documents, Dataverse)
- Your agent calls **external services** via connectors, AI plugins, HTTP actions, or MCP tools
- Your agent triggers **Power Automate flows** (e.g., send email, create ticket, call an API)
- You need **generative orchestration** (AI dynamically selects which topic to run)
- You need **full authentication** (SSO, OAuth, Entra ID token exchange)
- You built and tested the agent **in the Copilot Studio UI** and want an exact replica

#### Hybrid Workflow (Start Template → Graduate to Solution)

Many agents start simple and grow. The recommended hybrid workflow is:

1. **Start with a YAML template** — use the `@creator` agent or hand-author topics
2. **Deploy with template mode** — `azd up` (or `deploy-pac-only.ps1`)
3. **Enhance in Copilot Studio UI** — add knowledge sources, connectors, flows, AI plugins
4. **Export as a solution** — `./scripts/export-agent.ps1 -SolutionName "..." -ScenarioName "..."`
5. **Switch to solution mode** — set `DEPLOYMENT_MODE "solution"` and redeploy from the exported files

This gives you the speed of YAML authoring for the conversational skeleton, plus the full power of the Copilot Studio UI for integrations that YAML can't express.

---

## Quick Start: Full Path (azd + pac)

Best when you have an Azure subscription and want one-command deploy/teardown.

### Option A: Deploy a Complex Agent (Solution Mode)

Solution mode lets you export a fully-configured agent from Copilot Studio (with topics, knowledge sources, connectors, flows, tools, etc.) and redeploy it reliably.

#### Step 1: Build your agent in Copilot Studio

Create and configure your agent in the Copilot Studio UI. Add topics, knowledge sources, connectors — everything you need for the demo.

#### Step 2: Add the agent to a solution

The agent must be in a Power Platform solution before you can export it.

**Option A — via the maker portal:**
1. Open [make.powerapps.com](https://make.powerapps.com) → **Solutions**
2. Create a new solution (e.g., `IgniteAssistant`) with a publisher
3. Open the solution → **Add existing** → **Chatbot** → select your agent
4. Select the agent → click **Add required objects** to pull in all topics, bot components, AI plugins, etc.

**Option B — via CLI:**
```powershell
# If you need to create the solution first, import a minimal solution zip
# (the export script handles this for you — see below)

# Or add your agent to an existing solution:
pac copilot list                                     # find your agent's bot ID
pac solution add-solution-component `
    --solutionUniqueName "IgniteAssistant" `
    --component "<bot-guid>" `
    --componentType "bot" `
    --AddRequiredComponents true
```

> **Important**: Use `--componentType "bot"` (the string name). Numeric type codes like `10162` are rejected by the CLI. The `--AddRequiredComponents true` flag automatically includes all topics, AI plugins, custom APIs, and other dependencies.

#### Step 3: Export to a scenario folder

```powershell
pac auth create --environment https://yourorg.crm.dynamics.com
./scripts/export-agent.ps1 -SolutionName "IgniteAssistant" -ScenarioName "ignite-assistant"
```

This exports the solution, unpacks it into `scenarios/ignite-assistant/solution/`, and shows you the file count. Commit the results to git.

#### Step 4: Deploy

```powershell
azd init
azd env set POWERPLATFORM_ENVIRONMENT_URL "https://yourorg.crm.dynamics.com"
azd env set POWERPLATFORM_SOLUTION_NAME "IgniteAssistant"
azd env set DEPLOYMENT_MODE "solution"
azd env set SCENARIO_NAME "ignite-assistant"
azd up
```

#### Step 5: Teardown after training

```powershell
azd down
```

#### Step 6: Redeploy for the next session

```powershell
azd up      # fresh import from the local solution files
```

#### Re-export after editing

If you update the agent in Copilot Studio and want to capture changes:

```powershell
./scripts/export-agent.ps1 -SolutionName "IgniteAssistant" -ScenarioName "ignite-assistant"
git add scenarios/ignite-assistant/solution/
git commit -m "Updated ignite-assistant export"
```

> **What you get**: The exported `scenarios/ignite-assistant/solution/` folder contains the full unpacked solution — bot definitions, bot components, AI plugins, custom APIs, and metadata. Running `azd up` packs it back into a zip and imports it into the target environment.

### Option B: Deploy a Simple Agent (Template Mode)

**1. Create a YAML template** — either extract from an existing agent:

```powershell
pac copilot extract-template --bot <botSchemaName> --outputDirectory ./scenarios/my-scenario/template
```

Or use the **VS Code Creator Agent** (see below) to generate one from a natural language description.

**2. Configure:**

```powershell
azd init
azd env set POWERPLATFORM_ENVIRONMENT_URL "https://yourorg.crm.dynamics.com"
azd env set POWERPLATFORM_SOLUTION_NAME "SimpleDemoAgent"
azd env set DEPLOYMENT_MODE "template"
azd env set AGENT_DISPLAY_NAME "My Demo Agent"
azd env set SCENARIO_NAME "my-scenario"
```

**3. Deploy and teardown:**

```powershell
azd up      # creates solution, creates agent from template, publishes
azd down    # removes everything
```

---

## Quick Start: pac-only Path (no Azure subscription)

Use this when you only have Power Platform access and don't need Azure backend resources.

### Deploy

```powershell
# Template mode (simple agent from YAML)
./scripts/deploy-pac-only.ps1 `
    -EnvironmentUrl "https://yourorg.crm.dynamics.com" `
    -SolutionName "MyDemoAgent" `
    -DeploymentMode "template" `
    -AgentDisplayName "My Demo Agent" `
    -ScenarioName "it-helpdesk"

# Solution mode (complex agent from exported solution)
./scripts/deploy-pac-only.ps1 `
    -EnvironmentUrl "https://yourorg.crm.dynamics.com" `
    -SolutionName "MyDemoAgent" `
    -DeploymentMode "solution" `
    -ScenarioName "it-helpdesk"
```

### Teardown

```powershell
./scripts/teardown-pac-only.ps1 `
    -EnvironmentUrl "https://yourorg.crm.dynamics.com" `
    -SolutionName "MyDemoAgent"
```

### Manual pac Commands (step-by-step)

If you prefer to run the pac commands yourself instead of using the scripts:

```powershell
# 1. Authenticate
pac auth create --environment https://yourorg.crm.dynamics.com

# 2a. For solution mode — pack and import
pac solution pack `
    --zipfile ./.tmp/solution.zip `
    --folder ./scenarios/ignite-assistant/solution `
    --packagetype Unmanaged
pac solution import --path ./.tmp/solution.zip --publish-changes --activate-plugins

# 2b. For template mode — create solution, then create agent
#     Create an empty solution first (pac copilot create needs one)
pac solution init --publisher-name demopublisher --publisher-prefix demo --outputDirectory ./.tmp/MySolution
pac solution pack --zipfile ./.tmp/MySolution.zip --folder ./.tmp/MySolution/src --packagetype Unmanaged
pac solution import --path ./.tmp/MySolution.zip --publish-changes

#     Create the agent from template
pac copilot create `
    --displayName "My Demo Agent" `
    --schemaName "cr_mydemoagent" `
    --solution "MySolution" `
    --templateFileName ./scenarios/it-helpdesk/template/bot-template.yaml

# 3. Teardown when done
pac solution delete --solution-name MySolution
```

> **Notes:**
> - `pac solution delete` uses `--solution-name` (not `--name`)
> - `pac copilot publish` is not needed when using `--publish-changes` on solution import
> - `pac copilot publish` may crash with some pac CLI versions (FaultException) — publish manually in Copilot Studio if this happens

---

## VS Code Agents

This project includes two VS Code agents (`.github/agents/`) for an agentic workflow:

### @creator — Scenario Advisor + Agent Generator

Describe what your agent should do. The creator acts as a **scenario advisor** — it asks targeted questions about your requirements and then recommends the best approach:

| Approach | When | What the creator does |
|----------|------|----------------------|
| **A: Template** | Topics + scripted messages only | Generates YAML template, saves to `scenarios/<name>/template/` |
| **B: Hybrid** | Mix of scripted topics + knowledge/connectors/tools | Generates template, deploys, tells you what to configure in UI, then helps export as solution |
| **C: Solution** | Existing agent already in Copilot Studio | Guides you through export to `scenarios/<name>/solution/` |

```
@creator I want an agent that handles session lookup and speaker info
for Microsoft Ignite, with a knowledge source pulling from the Ignite website
```

The creator will ask follow-up questions to determine whether template mode covers the scenario or if knowledge sources push it toward hybrid/solution mode. It then executes the appropriate workflow.

Examples of what drives the recommendation:
- "Just topics and messages" → **Approach A** (template)
- "Needs to search SharePoint for answers" → **Approach B** (hybrid) or **C** (solution)
- "I already built the agent, just want to capture it" → **Approach C** (solution export)

### @deploy — Deploy and Manage

Deploy, teardown, or validate your agent:

```
@deploy deploy
@deploy teardown
@deploy validate
```

The deploy agent detects whether you have `azd` + `pac` or just `pac` and uses the appropriate path. It reads `SCENARIO_NAME` to find the right scenario folder.

### Full Agentic Workflow

1. `@creator` → describe your agent → generates template files in `scenarios/<name>/`
2. Set `SCENARIO_NAME`: `azd env set SCENARIO_NAME "<name>"`
3. `@deploy deploy` → deploys to Power Platform
4. Demo your agent in Copilot Studio
5. `@deploy teardown` → clean up
6. Repeat with a different scenario

---

## Adding Azure Backend Resources

When your demo agent needs Azure services (Azure OpenAI, AI Search, Functions), add Bicep modules under `infra/`:

1. Add your modules to `infra/main.bicep`.
2. Define Bicep outputs for values the agent needs (endpoints, keys).
3. Edit `hooks/generate-settings.ps1` to map Bicep outputs → Power Platform environment variables.

```
Bicep outputs → azd env vars → generate-settings.ps1 → deployment-settings.json
→ pac solution import --settings-file → agent's env vars get wired
```

> This requires the full `azd` path. Azure backend resources are not available with pac-only deployment.

---

## Environment Variables Reference

Set via `azd env set <KEY> <VALUE>` (full path) or as script parameters (pac-only path).

| Variable | Required | Description |
|---|---|---|
| `POWERPLATFORM_ENVIRONMENT_URL` | Yes | Dataverse org URL (e.g., `https://org123.crm.dynamics.com`) |
| `POWERPLATFORM_SOLUTION_NAME` | Yes | Unique name of the Power Platform solution |
| `SCENARIO_NAME` | Yes | Scenario folder name under `scenarios/` (e.g., `it-helpdesk`) |
| `DEPLOYMENT_MODE` | Auto | `solution` or `template` (auto-detected from scenario folder structure) |
| `AGENT_DISPLAY_NAME` | Template mode | Display name for the agent |
| `AGENT_SCHEMA_NAME` | No | Schema name (auto-generated from display name) |
| `POWERPLATFORM_TENANT_ID` | No | Entra ID tenant (for SPN auth or to scope interactive login) |
| `POWERPLATFORM_APP_ID` | No | Service principal app ID (for CI/CD) |
| `POWERPLATFORM_CLIENT_SECRET` | No | Service principal secret (for CI/CD) |

## Project Structure

```
├── azure.yaml                 # azd project definition with hooks
├── infra/
│   ├── main.bicep             # Azure resource definitions (optional)
│   ├── main.parameters.json   # Parameter bindings
│   └── abbreviations.json     # Resource naming abbreviations
├── scenarios/                 # One folder per demo scenario
│   ├── it-helpdesk/           # Example: template-mode scenario
│   │   └── template/          # YAML agent template (template mode)
│   │       ├── bot-template.yaml
│   │       ├── kickStartTemplate-1.0.0.json
│   │       └── agent-config.yaml
│   ├── ignite-assistant/      # Example: solution-mode scenario
│   │   └── solution/          # Exported from Copilot Studio (54 files)
│   └── .../                   # Add as many as you need
├── hooks/                     # Generic azd hooks (scenario-independent)
│   ├── preprovision.ps1       # Validates tools, authenticates to Power Platform
│   ├── postprovision.ps1      # Deploys agent (solution import or template create)
│   ├── postdown.ps1           # Deletes agent/solution on teardown
│   └── generate-settings.ps1  # Wires Azure outputs to Power Platform env vars
├── scripts/                   # Standalone scripts (scenario-independent)
│   ├── deploy-pac-only.ps1    # Standalone deploy without azd
│   ├── teardown-pac-only.ps1  # Standalone teardown without azd
│   ├── export-agent.ps1       # One-time: exports agent to solution/ folder
│   └── validate-env.ps1       # Pre-flight environment check
├── .github/
│   ├── agents/
│   │   ├── creator.agent.md   # VS Code agent: generate templates (any scenario)
│   │   └── deploy.agent.md    # VS Code agent: deploy/teardown
│   └── instructions/
│       ├── copilot-studio-yaml.instructions.md
│       └── deployment.instructions.md
├── .env.sample                # Environment variable reference
└── .gitignore
```

## Troubleshooting

### "pac CLI is not installed"

```powershell
dotnet tool install --global Microsoft.PowerApps.CLI
```

If `dotnet` is not found, install the [.NET SDK](https://dot.net/download) first.

### Authentication failures

- **`pac auth create` fails with WAM error** — This happens with corporate Microsoft accounts. Use a non-corporate Power Platform environment, or ensure WAM is working on your Windows machine.
- **`azd auth login` fails** — Run `azd auth login --use-device-code` as a fallback.
- **Different tenants** — `azd` and `pac` can authenticate to different tenants. This is expected if your Azure subscription and Power Platform environment are on different Entra ID tenants.
- **Service principal** — Set `POWERPLATFORM_TENANT_ID`, `POWERPLATFORM_APP_ID`, and `POWERPLATFORM_CLIENT_SECRET`. The app registration needs Maker permissions on the target environment.

### Solution import fails

- Ensure all required objects were added before export (topics, flows, environment variables, connection references).
- Topic names must **not contain periods (`.`)**.
- Custom connectors must be imported separately, before the agent solution.

### Template create fails

- The YAML file must start with `kind: BotDefinition` (not `kind: AdaptiveDialog`).
- A companion `kickStartTemplate-1.0.0.json` must exist in the same directory as the YAML.
- The target solution must exist before `pac copilot create` runs (the scripts handle this automatically).

### Knowledge sources missing after import

Knowledge sources linked to SharePoint or uploaded documents need to be re-linked manually in Copilot Studio after import. This is a known Power Platform limitation.

---

## Cross-Environment Deployment Notes

Solution export/import is designed for cross-environment portability — that's the core Power Platform ALM pattern. However, some features carry environment-specific bindings:

| Feature | Same environment | Different environment |
|---------|-----------------|----------------------|
| Topics, bot components | ✅ Works | ✅ Works |
| AI plugins, custom APIs | ✅ Works | ✅ Works |
| Knowledge sources (SharePoint, docs) | ✅ Works | ⚠️ Re-link in Copilot Studio UI |
| Connection references | ✅ Works | ⚠️ Reconfigure credentials |
| Environment variables | ✅ Works | ⚠️ Update values (endpoints, keys) |
| Custom connectors | ✅ Works | ⚠️ Must exist in target first |
| AI Builder models | ✅ Works | ⚠️ May need re-creation |
| Publisher prefix | ✅ Works | ✅ Auto-created if missing |

**For repeatable demos on the same environment** (the primary use case of this tool), teardown → redeploy cycles work seamlessly — no manual steps needed.

**For cross-environment scenarios** (e.g., dev → staging → production), plan for manual reconfiguration of knowledge sources and connections after the first import. Subsequent re-imports on the same target environment preserve the configuration.

### 429 (Rate Limit) errors

The Power Platform API throttles heavy usage. Wait a few minutes and retry.

## Validation

Run the pre-flight check anytime:

```powershell
./scripts/validate-env.ps1
```

This verifies tools, environment variables, project structure, and Power Platform connectivity.
