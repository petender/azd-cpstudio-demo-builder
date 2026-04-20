---
applyTo: "**/template/**,**/agent-config.yaml"
---
# Knowledge Assets — Generation & Integration Guide

This document defines how the Creator Agent should generate knowledge assets for Copilot Studio agents and provide integration instructions.

## Overview

YAML templates (`pac copilot create`) cannot embed knowledge sources, uploaded documents, or connectors. To bridge this gap, the Creator Agent should **generate companion knowledge assets** alongside the YAML template and provide clear, beginner-friendly instructions on how to integrate them in Copilot Studio.

## Phase 4: Knowledge Assets (run after template generation)

After generating `bot-template.yaml`, `kickStartTemplate-1.0.0.json`, and `agent-config.yaml`, proceed with knowledge asset generation.

### Step 1: Ask the User

Present a brief offer — don't force it. Example:

> I've generated your agent template. I can also create **knowledge assets** to make your agent smarter:
>
> 1. **Sample data files** — realistic demo data your agent can reference (JSON, CSV, or content outlines for DOCX/XLSX)
> 2. **Suggested knowledge URLs** — public websites relevant to your agent's domain
> 3. **Integration guide** — step-by-step instructions for adding these to your agent in Copilot Studio
>
> Would you like me to generate any of these?

If the user declines, skip this phase entirely.

### Step 2: Generate Sample Data Files

Based on the agent's context (description, topics, instructions), generate realistic sample data.

#### File Format Guidelines

| Agent Context | Recommended Format | Example |
|---|---|---|
| Lookup/status checking (orders, tickets, prescriptions) | JSON | `sample-prescriptions.json`, `sample-tickets.json` |
| FAQ / policy reference | Markdown or TXT | `company-policies.md`, `faq.md` |
| Product catalog, inventory, schedule | JSON or CSV | `product-catalog.json`, `session-schedule.csv` |
| Training material, guides | Markdown (outline for DOCX) | `onboarding-guide.md` |
| Tabular data (employee directory, pricing) | CSV | `employee-directory.csv`, `pricing-tiers.csv` |

#### Quality Guidelines for Sample Data

- **Realistic but fictional** — use plausible names, dates, IDs, but never real PII
- **5-10 records minimum** — enough for demo variety, not so many it's overwhelming
- **Match the agent's topics** — if the agent has a "Check order status" topic, the sample data should have orders with various statuses (pending, shipped, delivered, cancelled)
- **Include edge cases** — at least one record that tests boundary conditions
- **Use current dates** — reference dates near the current date so demos feel fresh
- **Include field descriptions** — add a comment/header explaining the data structure

#### File Naming Convention

```
sample-<domain>.json        — e.g., sample-prescriptions.json, sample-tickets.json
sample-<domain>.csv         — e.g., sample-sessions.csv, sample-products.csv
<domain>-knowledge.md       — e.g., policies-knowledge.md, faq-knowledge.md
```

Save all generated files to `scenarios/<name>/template/`.

### Step 3: Suggest Knowledge Source URLs

Use your knowledge of the agent's domain to suggest relevant public websites that Copilot Studio can use as knowledge sources.

#### URL Suggestion Guidelines

- **Suggest 2-5 URLs** — enough to be useful, not overwhelming
- **Prioritize authoritative sources** — government sites, official documentation, well-known industry resources
- **Explain why each URL is useful** — one-line purpose description
- **Verify relevance** — the URL should contain information the agent's topics would actually need
- **Prefer stable URLs** — avoid pages that change frequently or require authentication

#### Example URL Suggestions by Domain

| Agent Domain | Suggested URLs | Purpose |
|---|---|---|
| Pharmacy / Health | `https://medlineplus.gov`, `https://www.drugs.com` | Drug info, health topics |
| IT Help Desk | `https://support.microsoft.com`, `https://learn.microsoft.com` | Microsoft product support |
| Weather | `https://www.weather.gov`, `https://www.accuweather.com` | Weather forecasts, alerts |
| Travel | `https://www.tsa.gov`, `https://travel.state.gov` | Travel rules, advisories |
| HR / Onboarding | Company intranet (suggest placeholder) | Policies, benefits |
| Conference | Conference website (suggest placeholder) | Schedule, speakers |
| Finance | `https://www.investor.gov`, `https://www.sec.gov` | Financial literacy, regulations |
| Education | `https://learn.microsoft.com`, `https://www.khanacademy.org` | Learning resources |
| Customer Service | Company support site (suggest placeholder) | Product docs, FAQs |

**Present suggestions and ask for approval before adding them to the agent-config.yaml and kickStartTemplate JSON.**

After approval, update:
1. `agent-config.yaml` → `knowledgeSources` section
2. `kickStartTemplate-1.0.0.json` → `spec.knowledgeSources.publicSites` array

### Step 4: Generate Integration Guide

Create a `KNOWLEDGE-ASSETS.md` file in `scenarios/<name>/template/` with beginner-friendly integration instructions.

#### Integration Guide Structure

The guide must follow this structure:

```markdown
# Knowledge Assets Integration Guide — <Agent Name>

## What Are Knowledge Assets?

Brief explanation that knowledge sources let the agent look up real information
instead of relying only on scripted responses.

## Assets Included

Table listing each file, its format, and purpose.

## Step-by-Step: Adding Knowledge Sources in Copilot Studio

### Adding Public Website Sources
1. Open your agent in Copilot Studio (https://copilotstudio.microsoft.com)
2. Select your agent from the list
3. Click **Knowledge** in the left sidebar (or the Knowledge tab at the top)
4. Click **+ Add knowledge**
5. Select **Public websites**
6. Enter the URL (e.g., `https://medlineplus.gov`)
7. Give it a name and description
8. Click **Add** → **Save**
9. Repeat for each URL

### Uploading Document Knowledge Sources
1. In the Knowledge panel, click **+ Add knowledge**
2. Select **Files**
3. Click **Upload** and select the file from `scenarios/<name>/template/`
4. Supported formats: PDF, DOCX, XLSX, PPTX, TXT, JSON, CSV, MD
5. Give it a name and description
6. Click **Add** → **Save**

### Verifying Knowledge Sources Work
1. Open the **Test** panel (bottom-left corner)
2. Ask a question that requires knowledge lookup
3. Check that the agent references the knowledge source in its response
4. If not working, verify the knowledge source status shows "Ready"

## After Integration: Export for Reuse

Once you've added knowledge sources and tested the agent:
1. Go to **Settings** → **Advanced** → note the Solution name
2. In Power Platform maker portal, find the solution
3. Click "Add required objects" to capture all dependencies
4. Run the export script:
   ```powershell
   ./scripts/export-agent.ps1 -SolutionName "<solution>" -ScenarioName "<name>"
   ```
5. This captures everything (including knowledge sources) for repeatable deployment
```

### Step 5: Update agent-config.yaml

Add the knowledge sources and post-deployment steps to the agent-config.yaml:

```yaml
knowledgeSources:
  - type: Public website
    url: <url>
    purpose: "<one-line description>"
  - type: Uploaded document
    file: <filename>
    purpose: "<one-line description>"

postDeploymentSteps:
  - "Add knowledge source: <url> (public website)"
  - "Upload <filename> as a document knowledge source"
  - "Test knowledge-backed topics in the Test panel"
  - "Optionally export enriched agent as solution for repeatable demos"
```

## Summary of Generated Files

After Phase 4, the scenario folder should contain:

```
scenarios/<name>/template/
├── bot-template.yaml              ← agent topics (Phase 3)
├── kickStartTemplate-1.0.0.json   ← agent metadata + knowledge URLs (Phase 3 + 4)
├── agent-config.yaml              ← reference config + knowledge sources (Phase 3 + 4)
├── KNOWLEDGE-ASSETS.md            ← integration guide (Phase 4)
├── sample-<domain>.json           ← sample data file(s) (Phase 4)
└── (other sample files as needed)
```
