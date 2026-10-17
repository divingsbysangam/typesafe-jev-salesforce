# TypeSafe (Jev) × Salesforce — the typed decision layer

A working Salesforce DX project that puts a **typed decision model** inside Apex, instead of a
generative LLM, and uses it for two jobs where a free-text answer is a liability:

1. **Service Cloud case triage** — every new case is classified, scored and routed by a model that
   returns numbers, not prose.
2. **An Agentforce guardrail** — every guest message to a live Agent Script agent is screened
   before the agent is allowed to take an action.

Built live, deployed to a Developer Edition org, and run end to end on camera for
**Deep Dives by Sangam**. The slide deck is in [`video/`](video/).

---

## Why a typed model and not an LLM

A generative model answers a question by writing text. You then have to parse that text, hope the
shape is stable, and you get no calibrated measure of how sure it was. TypeSafe's **Jev** is a
"System One" model — trained with RLCD, deliberately fast and non-deliberative — and it answers in
three fixed shapes only:

| Primitive | Returns | Confidence? | Use it for |
|---|---|---|---|
| **Choice** | one option from your list + per-option probabilities | yes | routing, classification |
| **Score** | a float on a ladder you define + probabilities | yes | severity, sentiment, risk |
| **Noul** | a probability that a statement is true | **no** | yes/no signals |

The whole design of this project falls out of that table. Because a Choice carries a confidence,
low-confidence routing can be escalated to a human. Because a **Noul carries no confidence**, you
gate it on the probability itself with two bands — a review band and an action band. Reusing a
Choice threshold on a Noul is the single easiest way to get this wrong.

Every threshold lives in custom metadata (`TypeSafe_Setting__mdt`), so tuning the business
behaviour is a metadata edit, not a code change and not a prompt change.

```
Case created
   │
   ├─ CaseTrigger ─→ CaseTriggerHandler ─→ marks Pending, enqueues
   │                                           │
   │                              CaseTriageQueueable (Database.AllowsCallouts)
   │                                           │
   │                              CaseTriageService ──→ IDecisionProvider ──→ TypeSafe /v1/systemone
   │                                           │                               (or OpenAI /v1/decisions)
   │                                           │
   │                              callouts first, then DML:
   │                              TS_* fields + Priority + one TypeSafe_Log__c per call
   │                                           │
   └─ TypeSafe_Case_Routing (Flow) ─→ queue assignment from the typed fields

Guest message ─→ Agent Script agent ─→ TypeSafeGuardrail (@InvocableMethod)
                       │                      │
                       │              one call: a Noul per hazard + a severity Score
                       │                      │
                       └── create_support_case  available when guard_action == "pass"
```

---

## What's in here

| Path | What it is |
|---|---|
| `force-app/main/default/classes/` | 33 Apex classes — the client, provider abstraction, triage service, guardrail, latency probe, mocks and 11 test classes |
| `force-app/main/default/triggers/` | `CaseTrigger` — thin, delegates to a handler |
| `force-app/main/default/objects/` | `TypeSafe_Log__c` (the audit object), `TypeSafe_Setting__mdt` (thresholds), 13 `TS_*` fields on Case |
| `force-app/main/default/aiAuthoringBundles/` | **`Coral_Cloud_Guarded_Concierge.agent`** — the Agent Script agent, with the guardrail gate |
| `force-app/main/default/namedCredentials/`, `externalCredentials/` | Named + External Credential for both APIs. **No keys** — the key lives in the org's named principal |
| `force-app/main/default/flows/` | `TypeSafe_Case_Routing` — branches on the typed fields to pick a queue |
| `force-app/main/default/queues/` | The nine queues triage can route to |
| `force-app/main/default/permissionsets/` | `TypeSafe_User` — FLS on the new fields, access to the API principal |
| `scripts/apex/` | Every demo and probe script, runnable with the Salesforce CLI |
| `docs/` | The TypeSafe API cheat sheet and the Agent Script agent spec |
| `video/` | `Deep-Dives-TypeSafe-x-Salesforce-slides.pdf` — the deck |

---

## Use case 1 — Service Cloud case triage

`CaseTriageService` asks **five questions in one request**, evaluated in parallel:

| Question | Primitive | Why |
|---|---|---|
| Which team owns this? | Choice (5 departments) | routing |
| Is it time-sensitive? | Noul | priority |
| Did they ask for money back? | Noul | catches refunds routed away from Billing |
| How frustrated are they? | Score (Calm → Furious) | priority + escalation |
| How likely are they to leave? | Score (None → Explicit) | priority |

The answers decide `Priority`, and whether the case is `Auto_Routed` or `Needs_Review`. A case goes
to review when any confidence falls below `Confidence_Min__c`, **or** when a refund was requested
but the case was routed somewhere other than Billing — a cross-check the model was never asked to
make. That last rule is the point: the typed output is cheap enough to reason about in Apex.

Three implementation details that matter in Salesforce specifically:

- **All callouts complete before any DML.** `TypeSafeClient` never throws on an HTTP failure; it
  returns a result carrying an *unsaved* `TypeSafe_Log__c`. The caller does every callout, then
  saves logs and updates records once.
- **`without sharing` + `SYSTEM_MODE`, on purpose and documented.** Triage is back-end automation
  started by a trigger, and the user who created a case frequently cannot see it afterwards
  (Email-to-Case, Web-to-Case, assignment rules). No user input selects records — the job only
  reads Subject/Description/Origin on the exact Ids the trigger handed over, and it is not exposed
  to Flow, LWC or the API.
- **Rate limits are retried, not swallowed.** 429/529 are retryable; the case is left untouched and
  re-queued rather than marked in error. There is no sleep in Apex, so the backoff has to be async.

## Use case 2 — the Agentforce guardrail

`TypeSafeGuardrail` is an `@InvocableMethod(callout=true)` that screens one message in a single
request: **one Noul per hazard, plus a severity Score**.

| Hazard | Action when it crosses the threshold |
|---|---|
| `jailbreak` / `broke_policy` | **block** |
| `harmful_request` | **block** |
| `pii_shared` (the guest's own details) | **review** — mask, don't refuse |
| `pii_leak` (someone else's details) | **block** |
| `self_harm` | **support** — stop the task, point to a crisis line |

Precedence is `support > block > review > pass`. If TypeSafe cannot be reached, or the model
refuses, the result is **review** — it fails closed.

The agent side is the interesting half. In `Coral_Cloud_Guarded_Concierge.agent`, the screen writes
its verdict into a variable and case filing is gated on it:

```
create_support_case: @actions.create_support_case
    available when @variables.guard_action == "pass"

after_reasoning:
    set @variables.guard_action = ""
```

`available when` is enforced by the runtime, not by the agent's instructions, so the agent cannot
talk itself past the gate. Resetting the variable `after_reasoning` means a pass earned on one turn
cannot be spent on the next.

**What the live runs showed.** The guardrail separated review / block / support correctly across the
battery. They also showed something the deck now opens with: Salesforce's own platform safety layer
(the `Prompt_Injection` and `Inappropriate_Content` system topics) intercepts the riskiest messages
*before* any custom agent logic runs, and returns one canned refusal. That is a sane default — but
it leaves no audit trail, no severity, and no distinction between "block this" and "this person
needs help". The typed layer is what gives you the row in `TypeSafe_Log__c` and the four-way
decision. Layered defence, with Salesforce's layer first.

## Switchable providers, and one image check

`IDecisionProvider` / `DecisionProviders` put a seam behind the primitives, so the same five triage
questions can run against either API and be compared on the same inputs:

- **TypeSafe Jev** — `POST https://api.typesafe.ai/v1/systemone`, text only.
- **OpenAI Decisions** (`gpt-6-luna`) — `POST https://api.openai.com/v1/decisions`, and it takes
  **images**, which Jev does not. `OpenAIImageCheck` sends the newest photo on a case inline as
  base64 and asks two questions about it (damage visible? how serious?), writing
  `TS_Visible_Damage__c` / `TS_Damage_Severity__c`.

Each profile is its own `TypeSafe_Setting__mdt` record with its **own thresholds**, because
probabilities from two different models need separately calibrated cut-offs.
`Default.Active_Profile__c` picks the one everything uses. Run
`scripts/apex/demo-compare-providers.apex` to put them side by side.

---

## Setup

Prerequisites: Salesforce CLI (`sf`), a Developer Edition or scratch org, and a TypeSafe API key
(plus an OpenAI key if you want that profile).

```bash
# 1. authorise an org
sf org login web --alias jev --set-default

# 2. deploy
sf project deploy start --source-dir force-app

# 3. give yourself access
sf org assign permset --name TypeSafe_User
```

**4. Add the API key.** The key is *not* in this repo and must not be. In Setup → Named Credentials
→ External Credentials → `TypeSafe`, open the `ApiKeyPrincipal` named principal and set the
`ApiKey` authentication parameter to your key.

The Named Credential sends it with a formula header:

```
Authorization: {!'Bearer ' & $Credential.TypeSafe.ApiKey}
```

> **The one setting that will cost you an hour.** A formula in an HTTP header is only evaluated if
> **Allow Formulas in HTTP Header** is enabled on the Named Credential
> (`allowMergeFieldsInHeader=true` in the metadata). With it off, the formula is sent as literal
> text and the API answers `403 Must supply an API key` — which reads exactly like a bad key. It is
> already `true` in this repo's metadata; if you build one by hand, check it first.

Then prove the connection works by running `scripts/apex/latency-probe.apex` as Anonymous Apex.

**If you are deploying the agent too**, change the agent user to one that exists in your org. It
appears in two places and is specific to the org this was built in:

- `Coral_Cloud_Guarded_Concierge.agent` → `access.default_agent_user`
- `Coral_Cloud_Guarded_Concierge.bot-meta.xml` → `<botUser>`

The Apex, metadata and triage half of the project deploy without it.

## Demo scripts

All of these are plain Anonymous Apex and print a single parseable line to the debug log.

| Script | What it does |
|---|---|
| `demo-create-cases.apex` | Creates three guest cases; the trigger queues live triage |
| `demo-show-triage.apex` | Prints what the model decided for each case, with confidences |
| `demo-guardrail.apex` | Runs the hazard battery through `TypeSafeGuardrail` |
| `demo-show-guardrail-logs.apex` | The audit rows those screens produced |
| `demo-show-agent-run.apex` | The TypeSafe calls made by a live agent conversation |
| `demo-show-recent-logs.apex` | Every call in the last few minutes, whoever made it |
| `demo-compare-providers.apex` | The same five questions on Jev and on `gpt-6-luna` |
| `demo-image-check.apex` | Image damage check via OpenAI Decisions |
| `latency-probe.apex` | 20 sequential calls, cold vs warm percentiles |
| `demo-reset.apex` | Clears demo cases and logs |

Tip: set `FORCE_COLOR=0` before any Salesforce CLI command with `--json`, or ANSI escape codes end
up inside the JSON and break the parse.

## Tests

**116 test methods across 11 test classes**, all callouts mocked (`TypeSafeMock`,
`OpenAIDecisionsMock`), with `TestDataFactory` for data setup. Run them with the Salesforce CLI at
the `RunLocalTests` level.

Two things in `TestDataFactory` are worth borrowing:

- `prepareDemoOrgCaseAutomation()` — Salesforce demo orgs (SDO) ship a Case-on-create process whose
  Einstein demo flow fails when no active helper record exists, which is always true inside a test.
  It creates one inert helper that can never match a case, and **does nothing in orgs without the
  SDO object**, so the project stays portable. This one turned 18 red tests green.
- `grantTypeSafePermissionsToRunningUser()` wraps the permission-set assignment in
  `System.runAs(new User(Id = UserInfo.getUserId()))`, because a setup-object insert alongside
  record DML is a mixed-DML error.

The bulk test deliberately asserts **two** trigger chunks for 251 cases, not one: 200 + 51 records,
and only 100 callouts are permitted per transaction.

## Measured latency

Measured from *inside* the org with `TypeSafeLatencyProbe`, which is the only number that means
anything — Apex callouts leave from the org's instance (NA232 here), not from your laptop, so the
developer's location is irrelevant. 20 sequential calls per run, three typed questions each, first
call reported separately because it includes TLS setup.

| Run | Cold | Warm min | **Warm p50** | Warm p95 | Success |
|---|---|---|---|---|---|
| 1 | 648 ms | 169 ms | 209 ms | 261 ms | 20/20 |
| 2 | 404 ms | 154 ms | 170 ms | 316 ms | 20/20 |
| 3 | 294 ms | 139 ms | **153 ms** | 204 ms | 20/20 |

Sept–Oct 2026, `jev-1.13.0`. Roughly 150–210 ms for a typed judgement is fast enough to sit inside
a synchronous transaction without a user noticing.

**Residency is still an open question** and worth saying out loud: the API runs in AWS `us-west-2`,
no region pinning is documented, and zero-data-retention is enterprise-only. For a regulated
Salesforce tenant that matters more than the latency does.

---

## Design notes worth keeping

Collected while building this against Jev 1.13:

- **The model reads instructions literally.** Spell out boundary cases in the criteria. "Anything
  broken in the room, villa or grounds" routes well; "facilities issues" does not.
- **No counting, no maths, no date arithmetic.** Do all of it in Apex.
- **Send only the fields the question needs.** Large irrelevant state measurably lowers accuracy.
- **Answer-type keys are dynamic**, so parse with `JSON.deserializeUntyped`, not a fixed class.
- **Log the versioned model id** (`jev-1.13.0`, not `jev-latest`) and pin it once thresholds are
  tuned, because thresholds are calibrated against a specific version.
- Split a complex judgement into one question per factor and combine them in code with weights you
  control, rather than asking one broad question.

## Deck and reference

| Resource | Where |
|---|---|
| Slide deck (15 slides, PDF) | [`video/Deep-Dives-TypeSafe-x-Salesforce-slides.pdf`](video/Deep-Dives-TypeSafe-x-Salesforce-slides.pdf) |
| TypeSafe API cheat sheet — endpoint, request/response shapes, the gotchas that shaped the Apex | [`docs/TYPESAFE_API_NOTES.md`](docs/TYPESAFE_API_NOTES.md) |
| Agent spec for the guarded concierge | [`docs/Coral_Cloud_Guarded_Concierge-AgentSpec.md`](docs/Coral_Cloud_Guarded_Concierge-AgentSpec.md) |

## Notes

- This is a demo project on a Developer Edition org, not a managed package and not hardened for
  production. Calibrate the thresholds against your own data before trusting them.
- TypeSafe's own product documentation is **not** mirrored here; see
  [docs.typesafe.ai](https://docs.typesafe.ai). The cheat sheets in `docs/` are my own build notes.
- No API keys, org credentials or customer data are in this repository.

Built with [Claude Code](https://claude.com/claude-code).

— **Deep Dives by Sangam**

## License

[MIT](LICENSE)
