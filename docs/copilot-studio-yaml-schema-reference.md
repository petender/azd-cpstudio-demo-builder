# Copilot Studio Topic YAML Schema Reference

> **Sources**: Microsoft Learn docs, `pac copilot` CLI reference, `microsoft/CopilotStudioSamples` repo (Workday ESS topics, authoring snippets).  
> **Important**: Microsoft does **not** publish a formal YAML schema specification. This reference is compiled from official documentation examples, the code editor in Copilot Studio, exported topics, and the CopilotStudioSamples GitHub repo.

---

## 1. Agent Template YAML (`pac copilot extract-template / create`)

The **agent template** is a whole-agent export produced by:

```powershell
# Extract template from existing agent
pac copilot extract-template `
  --environment <env-guid> `
  --bot <bot-id-or-schema-name> `
  --templateFileName MyAgent.yaml

# Create new agent from template
pac copilot create `
  --displayName "My New Agent" `
  --schemaName my_new_agent `
  --solution MySolution `
  --templateFileName MyAgent.yaml
```

The template YAML contains the **entire agent definition** — all topics, entities, variables, knowledge sources, settings. Its internal schema is auto-generated and not documented for hand-authoring. Use `extract-template` from an existing agent to obtain one.

**Individual topic YAML** (below) is what you paste into the **code editor** within Copilot Studio (`Open code editor` in a topic).

---

## 2. Topic YAML Structure — `kind: AdaptiveDialog`

Every topic YAML has this root shape:

```yaml
kind: AdaptiveDialog
beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent:
    displayName: <Topic Display Name>
    triggerQueries:
      - <trigger phrase 1>
      - <trigger phrase 2>
      - <trigger phrase 3>

  actions:
    - kind: <NodeType>
      id: <unique-short-id>
      # ... node-specific properties
```

### Root Properties

| Property | Required | Description |
|---|---|---|
| `kind` | Yes | Always `AdaptiveDialog` |
| `beginDialog` | Yes | Contains the trigger and actions |
| `inputs` | No | Topic input parameters (for generative orchestration) |
| `inputType` | No | Typed input schema (properties with types) |
| `outputType` | No | Typed output schema |
| `modelDescription` | No | Description for generative orchestration to decide when to invoke this topic |

### Extended Root (Generative Orchestration)

```yaml
kind: AdaptiveDialog
inputs:
  - kind: AutomaticTaskInput
    propertyName: InputAction
    description: "Description for the AI to extract the value"
    entity: StringPrebuiltEntity
    shouldPromptUser: false

modelDescription: |-
  Describe when this topic should be triggered.
  Include example valid/invalid requests.

beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent: {}         # Empty intent = orchestrated by AI, not trigger phrases
  actions:
    - # ...
```

---

## 3. Node Type Reference

### 3.1 Trigger Node — `OnRecognizedIntent`

```yaml
beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent:
    displayName: "Order Products"
    triggerQueries:
      - Buy items
      - Buy online
      - Purchase item
      - Order product
```

For **generative orchestration** (no trigger phrases):
```yaml
beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent: {}
```

### 3.2 SendMessage Node

```yaml
- kind: SendMessage
  id: Sjghab
  message: I am happy to help you place your order.
```

With **variable interpolation**:
```yaml
- kind: SendMessage
  id: abc123
  message: Hello {Topic.customerName}, welcome back!
```

With **message variations** (agent randomly picks one):
```yaml
- kind: SendMessage
  id: def456
  message:
    - How can I help you today?
    - What can I do for you?
    - I'm here to help!
```

### 3.3 SendActivity Node

Used for richer messages (Adaptive Cards, attachments):

```yaml
- kind: SendActivity
  id: update_context_msg
  activity: "{Topic.updateContextText}"
```

With **Adaptive Card attachment**:
```yaml
- kind: SendActivity
  id: success_card
  activity:
    attachments:
      - kind: AdaptiveCardTemplate
        cardContent: |-
          ={
            type: "AdaptiveCard",
            '$schema': "http://adaptivecards.io/schemas/adaptive-card.json",
            version: "1.5",
            body: [
              {
                type: "TextBlock",
                text: "Success!",
                weight: "Bolder",
                size: "Medium",
                wrap: true
              }
            ]
          }
```

### 3.4 Question Node

```yaml
- kind: Question
  id: eRH3BJ
  alwaysPrompt: false
  variable: init:Topic.State
  prompt: To what state will you be shipping?
  entity: StatePrebuiltEntity
```

**Key properties:**

| Property | Description |
|---|---|
| `variable` | `init:Topic.VarName` (creates new) or `Topic.VarName` (reuses existing) |
| `prompt` | The question text shown to the user |
| `entity` | Entity type for parsing response (see §4) |
| `alwaysPrompt` | `true` = always ask; `false` = skip if variable already has a value |

**Multiple-choice Question:**
```yaml
- kind: Question
  id: mc01
  alwaysPrompt: false
  variable: init:Topic.Choice
  prompt: Which department do you need?
  entity:
    kind: EmbeddedEntity
    definition:
      kind: ClosedListEntity
      items:
        - id: sales
          displayName: Sales
        - id: support
          displayName: Support
        - id: billing
          displayName: Billing
```

**Boolean Question:**
```yaml
- kind: Question
  id: 6lyBi8
  alwaysPrompt: false
  variable: init:Topic.ShippingRateAccepted
  prompt: Is that acceptable?
  entity: BooleanPrebuiltEntity
```

### 3.5 AdaptiveCardPrompt Node

Interactive Adaptive Card that collects user input:

```yaml
- kind: AdaptiveCardPrompt
  id: emergency_contact_form
  displayName: Emergency contact form
  card: |-
    ={
      type: "AdaptiveCard",
      '$schema': "http://adaptivecards.io/schemas/adaptive-card.json",
      version: "1.5",
      body: [
        {
          type: "Input.Text",
          id: "firstName",
          label: "First name",
          isRequired: true,
          errorMessage: "First name is required.",
          value: If(Topic.isUpdateMode, Topic.existingFirstName, "")
        },
        {
          type: "Input.ChoiceSet",
          id: "department",
          label: "Department",
          style: "compact",
          choices: [
            { title: "Sales", value: "sales" },
            { title: "Support", value: "support" }
          ]
        }
      ],
      actions: [
        { type: "Action.Submit", title: "Submit", id: "Submit",
          data: { actionSubmitId: "Submit" } },
        { type: "Action.Submit", title: "Cancel", id: "Cancel",
          data: { actionSubmitId: "Cancel" }, associatedInputs: "none" }
      ]
    }
  output:
    binding:
      actionSubmitId: Topic.formActionId
      firstName: Topic.firstName
      department: Topic.department
  outputType:
    properties:
      actionSubmitId: String
      firstName: String
      department: String
```

### 3.6 ConditionGroup / Condition Nodes

```yaml
- kind: ConditionGroup
  id: sEzulE
  conditions:
    - id: pbR5LO
      condition: =Topic.State = "California" || Topic.State = "Washington" || Topic.State = "Oregon"
      displayName: West Coast states
      actions:
        - kind: SendMessage
          id: msg01
          message: No additional charge for shipping!

  elseActions:
    - kind: SendMessage
      id: X7BFUC
      message: There will be an additional shipping charge of $27.50.
```

**Nested conditions:**
```yaml
- kind: ConditionGroup
  id: outer
  conditions:
    - id: cond1
      condition: =Topic.ShippingRateAccepted = true
      actions:
        - kind: SendMessage
          id: msg02
          message: Great, proceeding with order.

  elseActions:
    - kind: ConditionGroup
      id: inner
      conditions:
        - id: cond2
          condition: =Topic.WantsToCancel = true
          actions:
            - kind: SendMessage
              id: msg03
              message: Order cancelled.
```

**Condition syntax** uses Power Fx preceded by `=`:
```yaml
condition: =Topic.Score > 80
condition: =Topic.Status = "Active"
condition: =IsBlank(Topic.Name)
condition: =CountRows(Topic.Items) > 0
condition: =!IsBlank(Topic.InputAction) && "add" in Lower(Topic.InputAction)
```

### 3.7 SetVariable Node

```yaml
- kind: SetVariable
  id: setVar01
  variable: Topic.isUpdateMode
  value: =true

- kind: SetVariable
  id: setVar02
  variable: Topic.greeting
  value: ="Hello, " & Topic.customerName & "!"

- kind: SetVariable
  id: setVar03
  variable: Topic.contactList
  value: |
    =ForAll(
      Topic.rawData.Contacts,
      {
        Name: ThisRecord.FirstName & " " & ThisRecord.LastName,
        Phone: ThisRecord.Phone
      }
    )
```

### 3.8 ParseValue Node

```yaml
- kind: ParseValue
  id: parse_contacts
  displayName: Parse emergency contacts response
  variable: Topic.parsedContacts
  valueType:
    kind: Record
    properties:
      EmergencyContacts:
        type:
          kind: Table
          properties:
            Name: String
            Phone: String
            Address: String
  value: =Topic.rawJsonResponse
```

### 3.9 Topic Management Nodes

**Redirect to another topic (BeginDialog):**
```yaml
- kind: BeginDialog
  id: redirect01
  displayName: Redirect to Workday System
  input:
    binding:
      parameters: ="some value"
      scenarioName: msdyn_SomeScenario
  dialog: msdyn_copilotforhr.topic.WorkdaySystemExecution
  output:
    binding:
      errorResponse: Topic.errorResponse
      isSuccess: Topic.isSuccess
```

**GoTo action (jump within same topic):**
```yaml
- kind: GotoAction
  id: goto01
  actionId: emergency_contact_form    # references the `id` of another node
```

**Cancel all dialogs (end conversation):**
```yaml
- kind: CancelAllDialogs
  id: end01
```

**End conversation:**
```yaml
- kind: EndConversation
  id: endConvo01
```

### 3.10 HTTP Request Node

```yaml
- kind: HttpRequest
  id: http01
  method: POST
  url: ="https://api.contoso.com/orders"
  headers:
    Content-Type: application/json
    Authorization: ="Bearer " & Topic.AccessToken
  body: |-
    ={
      orderId: Topic.OrderId,
      quantity: Topic.Quantity
    }
  responseType:
    kind: Record
    properties:
      status: String
      orderId: String
  resultVariable: Topic.apiResponse
```

### 3.11 Generative Answers Node

```yaml
- kind: SearchAndSummarizeContent
  id: genAnswers01
  userMessage: =System.Activity.Text
  moderationLevel: Medium     # Low, Medium, High
```

> Note: The generative answers node kind name may vary based on agent version. It can also appear as `GenerativeAnswer` in some exports.

---

## 4. Entity Types

### 4.1 Prebuilt Entities

| Entity Name | Captures |
|---|---|
| `StringPrebuiltEntity` | Free-form text string |
| `BooleanPrebuiltEntity` | Yes/No, True/False |
| `NumberPrebuiltEntity` | Numeric values |
| `DateTimePrebuiltEntity` | Dates and times |
| `AgePrebuiltEntity` | Age references ("5 years old") |
| `CurrencyPrebuiltEntity` | Money amounts ("$50") |
| `DimensionPrebuiltEntity` | Measurements ("5 meters") |
| `EmailPrebuiltEntity` | Email addresses |
| `MoneyPrebuiltEntity` | Money amounts (alternate) |
| `OrdinalPrebuiltEntity` | Ordinal numbers ("first", "2nd") |
| `PercentagePrebuiltEntity` | Percentage values ("50%") |
| `PhoneNumberPrebuiltEntity` | Phone numbers |
| `TemperaturePrebuiltEntity` | Temperature values |
| `UrlPrebuiltEntity` | URLs |
| `PersonNamePrebuiltEntity` | Person names |
| `StatePrebuiltEntity` | US states |
| `CityPrebuiltEntity` | City names |
| `CountryPrebuiltEntity` | Country names |
| `ZipCodePrebuiltEntity` | Zip/postal codes |
| `ColorPrebuiltEntity` | Color names |
| `SpeedPrebuiltEntity` | Speed measurements |

### 4.2 Custom Entity Types (Embedded)

**Closed List (Choice) Entity:**
```yaml
entity:
  kind: EmbeddedEntity
  definition:
    kind: ClosedListEntity
    items:
      - id: option1
        displayName: Option One
        synonyms:
          - opt 1
          - first option
      - id: option2
        displayName: Option Two
```

**Regex Entity:**
```yaml
entity:
  kind: EmbeddedEntity
  definition:
    kind: RegexEntity
    pattern: "[A-Z]{2}-\\d{4}"
```

---

## 5. Variable Declarations and Scoping

### 5.1 Variable Prefixes

| Prefix | Scope | Description |
|---|---|---|
| `Topic.VarName` | Topic | Local to the current topic |
| `Global.VarName` | Global | Shared across all topics in the agent |
| `System.Activity.Text` | System | Current user message text |
| `System.Activity.ChannelData` | System | Channel-specific metadata |

### 5.2 Creating Variables

Variables are **implicitly created** when first assigned:

```yaml
# init: prefix creates + initializes a new topic variable
variable: init:Topic.CustomerName

# Without init:, references existing variable
variable: Topic.CustomerName
```

### 5.3 Input/Output Parameters

For topics that receive/return values:

```yaml
inputType:
  properties:
    InputAction:
      displayName: InputAction
      description: The action the user wants to perform
      type: String

outputType:
  properties:
    Result:
      type: String
    IsSuccess:
      type: Boolean
```

### 5.4 Complex Variable Types

```yaml
valueType:
  kind: Record
  properties:
    Name: String
    Items:
      type:
        kind: Table
        properties:
          ItemName: String
          Quantity: Number
          Nested:
            type:
              kind: Record
              properties:
                Detail: String
```

---

## 6. Complete Working Examples

### Example 1: Simple Order Topic (from Microsoft Learn)

```yaml
kind: AdaptiveDialog
beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent:
    displayName: Lesson 3 - A topic with a condition, variables and a prebuilt entity
    triggerQueries:
      - Buy items
      - Buy online
      - Buy product
      - Purchase item
      - Order product

  actions:
    - kind: SendMessage
      id: Sjghab
      message: I am happy to help you place your order.

    - kind: Question
      id: eRH3BJ
      alwaysPrompt: false
      variable: init:Topic.State
      prompt: To what state will you be shipping?
      entity: StatePrebuiltEntity

    - kind: ConditionGroup
      id: sEzulE
      conditions:
        - id: pbR5LO
          condition: =Topic.State = "California" || Topic.State = "Washington" || Topic.State = "Oregon"

      elseActions:
        - kind: SendMessage
          id: X7BFUC
          message: There will be an additional shipping charge of $27.50.

        - kind: Question
          id: 6lyBi8
          alwaysPrompt: false
          variable: init:Topic.ShippingRateAccepted
          prompt: Is that acceptable?
          entity: BooleanPrebuiltEntity

        - kind: ConditionGroup
          id: 9BR57P
          conditions:
            - id: BW47C4
              condition: =Topic.ShippingRateAccepted = true

          elseActions:
            - kind: SendMessage
              id: LMwySU
              message: Thank you and please come again.
```

### Example 2: Generative Orchestration Topic with Adaptive Card & BeginDialog

```yaml
kind: AdaptiveDialog
inputs:
  - kind: AutomaticTaskInput
    propertyName: InputAction
    description: "Look for 'add', 'new', or 'create' keywords. Extract 'add' if found, otherwise 'manage'."
    entity: StringPrebuiltEntity
    shouldPromptUser: false

modelDescription: |-
  Respond to requests about managing emergency contacts.
  Example valid: "Manage my emergency contacts", "Add a new emergency contact"
  Example invalid: "Manage contacts for my manager"

beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent: {}
  actions:
    - kind: SetVariable
      id: set_icon
      variable: Topic.IconUrl
      value: "https://example.com/icon.png"

    - kind: ConditionGroup
      id: check_direct_add
      conditions:
        - id: user_wants_add
          condition: =(!IsBlank(Topic.InputAction) && "add" in Lower(Topic.InputAction))
          displayName: User wants to add directly
          actions:
            - kind: SetVariable
              id: set_add_mode
              variable: Topic.isUpdateMode
              value: =false
            - kind: SendActivity
              id: add_msg
              activity: Sure, let's add a new contact.
            - kind: GotoAction
              id: goto_form
              actionId: contact_form

    - kind: BeginDialog
      id: fetch_data
      displayName: Fetch existing contacts
      input:
        binding:
          parameters: ="some params"
      dialog: myagent.topic.FetchContacts
      output:
        binding:
          isSuccess: Topic.fetchIsSuccess
          response: Topic.contactsResponse

    - kind: AdaptiveCardPrompt
      id: contact_form
      displayName: Contact form
      card: |-
        ={
          type: "AdaptiveCard",
          '$schema': "http://adaptivecards.io/schemas/adaptive-card.json",
          version: "1.5",
          body: [
            { type: "Input.Text", id: "name", label: "Name", isRequired: true }
          ],
          actions: [
            { type: "Action.Submit", title: "Submit", id: "Submit",
              data: { actionSubmitId: "Submit" } },
            { type: "Action.Submit", title: "Cancel", id: "Cancel",
              data: { actionSubmitId: "Cancel" }, associatedInputs: "none" }
          ]
        }
      output:
        binding:
          actionSubmitId: Topic.formAction
          name: Topic.contactName
      outputType:
        properties:
          actionSubmitId: String
          name: String

    - kind: ConditionGroup
      id: handle_cancel
      conditions:
        - id: cancelled
          condition: =Topic.formAction = "Cancel"
          actions:
            - kind: SendActivity
              id: cancel_msg
              activity: Request cancelled.
            - kind: CancelAllDialogs
              id: cancel_all

    - kind: SendActivity
      id: success
      activity: Contact {Topic.contactName} saved successfully!

    - kind: CancelAllDialogs
      id: end

inputType:
  properties:
    InputAction:
      displayName: InputAction
      description: The action to perform
      type: String

outputType: {}
```

---

## 7. Complete Node Kind Reference Table

| `kind` Value | Purpose |
|---|---|
| `AdaptiveDialog` | Root of every topic YAML |
| `OnRecognizedIntent` | Trigger node (beginDialog) |
| `SendMessage` | Send a text message to user |
| `SendActivity` | Send rich message (cards, attachments) |
| `Question` | Ask user a question, store in variable |
| `AdaptiveCardPrompt` | Show interactive Adaptive Card, collect input |
| `ConditionGroup` | Branch based on conditions (if/else) |
| `SetVariable` | Set a variable value |
| `ParseValue` | Parse JSON/data into typed variable |
| `BeginDialog` | Redirect to another topic |
| `GotoAction` | Jump to another node in same topic |
| `CancelAllDialogs` | End all dialogs / end conversation |
| `EndConversation` | End the conversation |
| `HttpRequest` | Make an HTTP request |
| `SearchAndSummarizeContent` | Generative answers from knowledge |
| `AdaptiveCardTemplate` | Attachment kind for Adaptive Cards |
| `EmbeddedEntity` | Inline entity definition in a Question |
| `ClosedListEntity` | Multiple-choice entity definition |
| `RegexEntity` | Regex-based entity definition |
| `AutomaticTaskInput` | Input auto-filled by generative orchestration |

---

## 8. Key Syntax Rules

1. **IDs must be unique** within a topic (short alphanumeric strings like `Sjghab`, `eRH3BJ`)
2. **Power Fx expressions** are prefixed with `=` (e.g., `value: =Topic.X + 1`)
3. **String interpolation** uses `{Topic.VarName}` inside messages/activities
4. **Adaptive Cards** use Power Fx expressions inside `|-` block scalars, prefixed with `=`
5. **`init:` prefix** on variables creates a new variable; without it, references existing
6. **`displayName`** on conditions/nodes is optional documentation
7. **No periods (`.`)** in topic names — breaks solution export
8. **YAML indentation** is 2 spaces throughout
