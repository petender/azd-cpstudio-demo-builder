---
applyTo: "**/template/**/*.yaml"
---
# Copilot Studio Agent YAML Schema Reference

This document describes the YAML formats used by Copilot Studio for defining agents and topics.

## Two YAML Formats

### 1. BotDefinition Format (for `pac copilot create`)

This is the format required by `pac copilot create --templateFileName`. It bundles all topics into a single file. **Use this format for automated deployment.**

```yaml
kind: BotDefinition
entity:
  accessControlPolicy: ChatbotReaders
  authenticationMode: Integrated
  authenticationTrigger: Always
  configuration: {}
  template: kickStartTemplate-1.0.0

components:
  - kind: DialogComponent
    displayName: <Topic Name>
    schemaName: template-content.topic.<TopicNameNoSpaces>
    description: <Description>
    shareContext: {}
    state: Active
    status: Active
    dialog:
      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent:
          displayName: <Topic Name>
          includeInOnSelectIntent: false
          triggerQueries:
            - <phrase>
        actions:
          - kind: SendActivity
            id: <id>
            activity: <message text>
```

**Key differences from topic-level format:**
- Root is `kind: BotDefinition` (not `AdaptiveDialog`)
- Topics are `kind: DialogComponent` items in `components:` array
- Use `SendActivity` with `activity:` (not `SendMessage` with `message:`)
- Schema names: `template-content.topic.<TopicNameNoSpaces>`
- Cross-topic refs: `template-content.topic.Escalate` (not `cr_escalate`)
- Requires companion `kickStartTemplate-1.0.0.json` with metadata

### 2. Topic-Level Format (for Copilot Studio code editor)

This format is used when pasting individual topics into the Copilot Studio UI code editor. Each file defines one topic.

```yaml
kind: AdaptiveDialog
beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent:
    displayName: <Topic Name>
    triggerQueries:
      - <phrase>
  actions:
    - kind: SendMessage
      id: <id>
      message: <text>
```

## Important Constraints

- Topic names must **NOT contain periods (`.`)** — this breaks solution export.
- Node `id` values must be unique alphanumeric strings (e.g., `Sjghab`, `eRH3BJ`).
- Variable names use dot notation: `Topic.VarName` (topic-scoped), `Global.VarName` (agent-wide), `System.Activity.Text` (system).
- Use `init:Topic.VarName` when first declaring/initializing a variable in a Question or SetVariable node.
- Conditions use Power Fx expressions prefixed with `=` (e.g., `=Topic.State = "California"`).
- **Colon-in-string values**: If a YAML value contains a colon followed by a space (`: `) inside a quoted string (e.g., in a `Concatenate()` expression), the entire value must be wrapped in outer double quotes with inner quotes escaped. Otherwise YAML interprets `": "` as a nested mapping and throws `"Nested mappings are not allowed in compact mappings"`.
  - **Bad**: `userInput: =Concatenate("advice for symptoms: ", Topic.Var)`
  - **Good**: `userInput: "=Concatenate(\"advice for symptoms: \", Topic.Var)"`

## System Topic Kinds

When using BotDefinition format, system topics use specific `beginDialog.kind` values:
| Kind | Used For |
|---|---|
| `OnRecognizedIntent` | Custom topics, Greeting, Thank you, Goodbye, Start Over |
| `OnUnknownIntent` | Conversational boosting, Fallback |
| `OnConversationStart` | Conversation Start |
| `OnEscalate` | Escalate |
| `OnError` | On Error |
| `OnSystemRedirect` | End of Conversation, Reset Conversation |
| `OnSignIn` | Sign in |
| `OnSelectIntent` | Multiple Topics Matched |

## Node Types Reference

### SendActivity — Send a message (BotDefinition format)

In the `kind: BotDefinition` format used by `pac copilot create`, use `SendActivity`:

```yaml
- kind: SendActivity
  id: Sjghab
  activity: I am happy to help you place your order.
```

Multi-line:

```yaml
- kind: SendActivity
  id: abc123
  activity: |-
    Welcome to Contoso support!
    I can help you with orders, returns, and account questions.
```

With variable interpolation:

```yaml
- kind: SendActivity
  id: def456
  activity: Thank you, {Topic.CustomerName}! Your order is confirmed.
```

### SendMessage — Send a message (topic-level format)

In the `kind: AdaptiveDialog` format (Copilot Studio code editor), use `SendMessage`:

```yaml
- kind: SendMessage
  id: Sjghab
  message: I am happy to help you place your order.
```

### Question — Ask the user a question and store the response

```yaml
- kind: Question
  id: eRH3BJ
  alwaysPrompt: false
  variable: init:Topic.State
  prompt: To what state will you be shipping?
  entity: StatePrebuiltEntity
```

**Key properties:**
- `variable`: Use `init:Topic.VarName` to declare a new variable, or `Topic.VarName` to reuse existing.
- `alwaysPrompt`: `false` = skip if variable already has a value; `true` = always ask.
- `entity`: The entity type for parsing the response (see Entity Types below).
- `prompt`: The question text shown to the user.

### ConditionGroup — Branch logic based on conditions

```yaml
- kind: ConditionGroup
  id: sEzulE
  conditions:
    - id: pbR5LO
      condition: =Topic.State = "California" || Topic.State = "Washington" || Topic.State = "Oregon"
      actions:
        - kind: SendMessage
          id: msg001
          message: Great news — free shipping is available to {Topic.State}!
  elseActions:
    - kind: SendMessage
      id: X7BFUC
      message: There will be an additional shipping charge of $27.50.
```

**Conditions use Power Fx syntax:**
- Equality: `=Topic.Var = "value"`
- Boolean: `=Topic.Confirmed = true`
- OR: `=Topic.State = "CA" || Topic.State = "WA"`
- AND: `=Topic.Age > 18 && Topic.HasAccount = true`
- Comparison: `=Topic.Amount > 100`

Multiple conditions (else-if pattern):

```yaml
- kind: ConditionGroup
  id: grp001
  conditions:
    - id: c001
      condition: =Topic.Priority = "high"
      actions:
        - kind: SendMessage
          id: m001
          message: Escalating to priority support immediately.
    - id: c002
      condition: =Topic.Priority = "medium"
      actions:
        - kind: SendMessage
          id: m002
          message: Adding to the support queue. Expected wait is 15 minutes.
  elseActions:
    - kind: SendMessage
      id: m003
      message: Your request has been logged. We'll get back to you within 24 hours.
```

### SetVariable — Set or compute a variable value

```yaml
- kind: SetVariable
  id: sv001
  variable: init:Topic.FullName
  value: =Concatenate(Topic.FirstName, " ", Topic.LastName)
```

### ParseValue — Parse a value from one type to another

```yaml
- kind: ParseValue
  id: pv001
  variable: init:Topic.OrderTotal
  valueType: Number
  value: =Topic.RawInput
```

### BeginDialog — Redirect to another topic

```yaml
- kind: BeginDialog
  id: bd001
  dialog: cr_orderConfirmation
```

With input parameters:

```yaml
- kind: BeginDialog
  id: bd002
  dialog: cr_orderConfirmation
  input:
    binding:
      - dialogVariable: Topic.OrderId
        sourceVariable: Topic.CurrentOrderId
```

### CancelAllDialogs — End the conversation

```yaml
- kind: CancelAllDialogs
  id: end01
```

### GotoAction — Jump to a specific node in the current topic

```yaml
- kind: GotoAction
  id: gt001
  actionId: eRH3BJ
```

### EndDialog — End the current topic

```yaml
- kind: EndDialog
  id: end01
  clearTopicQueue: true
```

### EndConversation — End the entire conversation

```yaml
- kind: EndConversation
  id: ec01
```

### AdaptiveCardPrompt — Show an Adaptive Card

```yaml
- kind: AdaptiveCardPrompt
  id: acp01
  card: |-
    {
      "type": "AdaptiveCard",
      "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
      "version": "1.5",
      "body": [
        {
          "type": "TextBlock",
          "text": "Order Summary",
          "weight": "Bolder",
          "size": "Medium"
        },
        {
          "type": "TextBlock",
          "text": "Item: {Topic.ItemName}"
        },
        {
          "type": "TextBlock",
          "text": "Total: ${Topic.Total}"
        }
      ],
      "actions": [
        {
          "type": "Action.Submit",
          "title": "Confirm Order",
          "data": { "action": "confirm" }
        },
        {
          "type": "Action.Submit",
          "title": "Cancel",
          "data": { "action": "cancel" }
        }
      ]
    }
  variable: init:Topic.CardResponse
```

### SearchAndSummarizeContent — Generative answers from knowledge

```yaml
- kind: SearchAndSummarizeContent
  id: gen01
  userMessage: =System.Activity.Text
```

### HttpRequest — Make an HTTP call

```yaml
- kind: HttpRequest
  id: http1
  method: GET
  url: ="https://api.contoso.com/orders/" & Topic.OrderId
  headers:
    Content-Type: application/json
  responseVariable: init:Topic.ApiResponse
  responseStatusCodeVariable: init:Topic.StatusCode
```

## Entity Types

### Prebuilt Entities
| Entity | Captures |
|---|---|
| `StringPrebuiltEntity` | Free-form text |
| `BooleanPrebuiltEntity` | Yes/no, true/false |
| `NumberPrebuiltEntity` | Numeric values |
| `DateTimePrebuiltEntity` | Dates and times |
| `StatePrebuiltEntity` | US states |
| `CityPrebuiltEntity` | City names |
| `CountryPrebuiltEntity` | Country names |
| `PersonNamePrebuiltEntity` | Person names |
| `EmailPrebuiltEntity` | Email addresses |
| `PhoneNumberPrebuiltEntity` | Phone numbers |
| `URLPrebuiltEntity` | URLs |
| `MoneyPrebuiltEntity` | Currency amounts |
| `AgePrebuiltEntity` | Age values |
| `PercentagePrebuiltEntity` | Percentage values |
| `OrdinalPrebuiltEntity` | Ordinal numbers (1st, 2nd, etc.) |
| `ZipCodePrebuiltEntity` | ZIP/postal codes |
| `TemperaturePrebuiltEntity` | Temperature values |

### Custom Choice Entity (inline)

```yaml
- kind: Question
  id: q001
  variable: init:Topic.ProductCategory
  prompt: What category are you interested in?
  entity:
    kind: ClosedListEntity
    items:
      - id: opt1
        displayName: Electronics
      - id: opt2
        displayName: Clothing
      - id: opt3
        displayName: Home & Garden
```

## Complete Example — Order Tracking Topic

```yaml
kind: AdaptiveDialog
beginDialog:
  kind: OnRecognizedIntent
  id: main
  intent:
    displayName: Track Order
    triggerQueries:
      - Track my order
      - Where is my order
      - Order status
      - Check order status
      - When will my order arrive
      - Track package
      - Order tracking
  actions:
    - kind: SendMessage
      id: greet1
      message: I'd be happy to help you track your order!

    - kind: Question
      id: askOrd
      alwaysPrompt: false
      variable: init:Topic.OrderNumber
      prompt: What is your order number?
      entity: StringPrebuiltEntity

    - kind: Question
      id: askEml
      alwaysPrompt: false
      variable: init:Topic.Email
      prompt: And what email address is associated with this order?
      entity: EmailPrebuiltEntity

    - kind: SendMessage
      id: look1
      message: Looking up order {Topic.OrderNumber} for {Topic.Email}...

    - kind: ConditionGroup
      id: chkOrd
      conditions:
        - id: found
          condition: =Topic.OrderNumber <> ""
          actions:
            - kind: SendMessage
              id: status
              message: |-
                Here's what I found for order {Topic.OrderNumber}:
                Status: In Transit
                Estimated delivery: 3-5 business days

                Is there anything else I can help with?
      elseActions:
        - kind: SendMessage
          id: notFnd
          message: I wasn't able to find that order. Please double-check the order number and try again.

        - kind: GotoAction
          id: retry
          actionId: askOrd
```

## Tips for Generating Good Topics

1. **Use 5-10 trigger phrases** that cover natural variations of how users might express their intent.
2. **Keep topics focused** — one intent per topic. If the topic is getting long, split into sub-topics and use `BeginDialog` to redirect.
3. **Always validate input** with ConditionGroup after Question nodes when the answer matters for branching.
4. **Use descriptive variable names** — `Topic.CustomerEmail` not `Topic.x`.
5. **Generate unique 6-char IDs** for every node — use random alphanumeric strings.
6. **End conversations gracefully** — always have a closing message or a redirect to a follow-up topic.
