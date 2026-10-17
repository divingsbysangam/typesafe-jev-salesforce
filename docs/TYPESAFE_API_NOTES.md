# TypeSafe API — Build Cheat Sheet

Source: https://docs.typesafe.ai (raw pages mirrored in `docs/typesafe/`, pulled 2026-09-19)

## Endpoint
```
POST https://api.typesafe.ai/v1/systemone
Authorization: Bearer <API_KEY>
Content-Type: application/json
GET  https://api.typesafe.ai/v1/models        (cheap auth/latency probe)
```

## Request
```json
{
  "state": "string | object | array",
  "model": "jev-latest",
  "questions": {
    "<your_id>": { "type": "noul",   "instructions": "...", "criteria": { "true": "...", "false": "..." } },
    "<your_id>": { "type": "choice", "instructions": "...", "criteria": { "optA": "desc", "optB": null } },
    "<your_id>": { "type": "score",  "instructions": "...", "criteria": ["level 0", "level 1", "level 2"] }
  }
}
```

## Response
```json
{
  "model": "jev-1.13.0",
  "answers": {
    "is_x":  { "type": "noul",   "noul": 0.92 },
    "dept":  { "type": "choice", "choice": "technical", "probabilities": {"billing":0.08,"technical":0.85}, "confidence": 0.82 },
    "frust": { "type": "score",  "score": 1.6, "legend": {"0":"Calm","1":"Frustrated","2":"Very angry"},
               "probabilities": {"0":0.05,"1":0.3,"2":0.65}, "confidence": 0.78 }
  },
  "usage": { "input_tokens": 312, "output_tokens": 48 }
}
```

## Gotchas that shape the Apex design
- **Noul answers have NO `confidence`.** Only Choice/Score do. Gate Nouls on the probability itself
  (review band vs action band, e.g. 0.35 / 0.70 per the guardrails cookbook).
- Score `score` is a float (probability-weighted), can land between levels.
- Response `model` reports the versioned ID — log it; pin `jev-1.13.0` once thresholds are tuned.
- Answer-type keys are dynamic maps → parse with `JSON.deserializeUntyped`, not a fixed Apex class.
- Errors: 401 bad key, 422 validation, 429 rate limit, 529 overloaded → retry 429/529 with backoff
  (retry must be async in Salesforce — no sleep in Apex).
- Limits: 1,200 req/min, 250k tok/s (dynamic). Context 64k total; 32k for state + longest question.
- Price: input tokens only, $0.042 / Mtok. Output free.
- Text only. English best.

## Jev 1.13 weak spots (design around them)
- Literal reading → put exact conditions + boundary cases in criteria.
- No counting / math / date arithmetic → do it in Apex.
- Large irrelevant state hurts → send only the fields the question needs.
- Adversarial content → be explicit in criteria; test guardrails with real jailbreak prompts.
- Don't reuse a threshold tuned on a Noul for a Choice.

## Data handling
- Not trained on customer data. ZDR for enterprise only (privacy@typesafe.ai).
- No documented regions. API resolves to AWS us-west-2 (Boardman, Oregon), served via istio-envoy.
