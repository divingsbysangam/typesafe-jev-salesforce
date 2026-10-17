# OpenAI Decisions API: Build Cheat Sheet

Source: https://developers.openai.com/api/docs/guides/decisions (public beta, pulled 2026-10-15)

## Endpoint
```
POST https://api.openai.com/v1/decisions
Authorization: Bearer <OPENAI_API_KEY>
Content-Type: application/json
model: gpt-6-luna   (only supported model)
```

## Request
```json
{
  "model": "gpt-6-luna",
  "input": "text"  |  [{ "role": "user", "content": [
                        { "type": "input_text",  "text": "..." },
                        { "type": "input_image", "image_url": "data:image/png;base64,..." } ] }],
  "questions": [
    { "type": "predicate", "name": "visible_damage", "instructions": "..." },
    { "type": "choice",    "name": "department", "instructions": "...",
      "choices": [{ "value": "billing", "description": "..." }, ...] },
    { "type": "score",     "name": "severity", "instructions": "...",
      "levels":  [{ "label": "Cosmetic", "description": "..." }, ...] }   // lowest first
  ]
}
```

## Response
```json
{ "answers": [
  { "type": "predicate", "name": "visible_damage", "probability": 0.92 },
  { "type": "choice", "name": "department", "choice": "billing",
    "probabilities": [{ "value": "billing", "probability": 0.95 }, ...], "confidence": 0.93 },
  { "type": "score", "name": "severity", "score": 1.1,
    "probabilities": [{ "value": 0, "label": "Cosmetic", "probability": 0.1 }, ...], "confidence": 0.55 },
  { "type": "refusal", "name": "..." }
] }
```

## Jev to OpenAI Decisions mapping (what `OpenAIDecisionsClient` translates)
| Jev (TypeSafe)                          | OpenAI Decisions                                  |
|-----------------------------------------|---------------------------------------------------|
| `POST /v1/systemone`, `jev-latest`      | `POST /v1/decisions`, `gpt-6-luna`                |
| `state` (string/object)                 | `input` (text, or a user message with images)     |
| questions: **map** keyed by id          | questions: **array**, each with a `name`          |
| `noul` + `criteria.true/false`          | `predicate`; criteria folded into `instructions`  |
| `choice` + `criteria {opt: desc}`       | `choice` + `choices [{value, description}]`       |
| `score` + `criteria ["Label: desc"]`    | `score` + `levels [{label, description}]`         |
| answers: map; probabilities: map        | answers: array; probabilities: array              |
| no refusals                             | `refusal` answer type → `getAnswer()` throws       |
| text only                               | text + inline base64 images (no URLs, no file ids) |
| billed in + out ($0.042 / Mtok in)      | billed **input only**, $0.10 / Mtok               |
| model id in response                    | not shown in the guide → we log the requested model |

## Gotchas that shape the Apex design
- Predicates, like Nouls, have **no confidence**: gate on the probability itself (review band / action band).
- Thresholds must be set "from labeled examples" per model, so each provider gets its **own profile**
  (`TypeSafe_Setting__mdt` record) and its own cut-offs. The OpenAI profile starts as a copy of
  Jev's (0.35 / 0.70 / 0.7 / 2.0). Recalibrate with `demo-compare-providers.apex` before trusting it.
- Independent questions share one request; questions that depend on each other need separate requests.
- `refusal` can appear for any question. `TypeSafeResult.getAnswer()` throws on it, so triage marks
  the case Error and the guardrail fails closed to review. Nothing auto-routes on a refusal.
- Images must be inline `data:` URLs. Apex heap (6 MB sync) and callout size are the real limits, so
  `OpenAIImageCheck` caps each image at 2 MB and each transaction at 3 MB. Image bytes are left out of
  `TypeSafe_Log__c.Request__c`.
- Errors/limits aren't documented in the guide yet (beta). The client treats non-2xx as failure and
  retries 429/503 like Jev.
- ZDR + HIPAA for eligible customers; US and EU (EEA + CH) data residency.

## How it plugs into this project
| Piece | What changed |
|---|---|
| `IDecisionProvider` | New interface; `TypeSafeClient` and `OpenAIDecisionsClient` implement it |
| `DecisionProviders.forConfig()` | Picks the client from the profile's `Provider__c` |
| `TypeSafeConfig` | Profiles: `current()` follows `Default.Active_Profile__c`; `forProfile(name)` loads any one |
| `CaseTriageService`, `TypeSafeGuardrail`, `TypeSafeLatencyProbe` | Use the factory; otherwise unchanged |
| Agentforce agent | Unchanged; its guardrail action follows the active profile |
| `OpenAIImageCheck` | New invocable (Flow/agent): newest photo on a case → damage probability + severity |
| Metadata | `OpenAI` Named + External Credential, `Provider__c` / `Active_Profile__c`, `OpenAI` profile record, `TS_Visible_Damage__c`, `TS_Damage_Severity__c`, `Image_Check` log context |

## Setup (once per org)
1. Deploy. The Default profile stays on Jev, so nothing changes yet.
2. Setup > Named Credentials > External Credentials > **OpenAI** > Principals > ApiKeyPrincipal:
   add parameter `ApiKey` = your OpenAI key.
3. Run `scripts/apex/demo-compare-providers.apex` and compare rows; tune the `OpenAI` profile thresholds.
4. Switch everything to OpenAI: set **Default → Active Profile = `OpenAI`** (Setup > Custom Metadata
   Types > TypeSafe Setting). Clear it to switch back to Jev.
