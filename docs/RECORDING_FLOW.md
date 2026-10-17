# Recording Flow · Deep Dives: TypeSafe (Jev) × Salesforce

One pass, start to finish: slide on screen, what you say, what you show, the command you ask Claude
for, and what comes back. Timings measured on 24 Sep 2026 against org `jev`.

**Legend** · `[SLIDE]` what's on screen · `[SAY]` your words · `[SHOW]` switch the screen ·
`[ASK CLAUDE]` say this out loud to Claude · `[BACK]` expected result and how long.

**Two lengths:** the core flow runs ~9:40. Adding the unit-test segment (Part 6) takes it to ~10:45,
so if you include it, cut the use-case-map sentence on slide 08 and tighten Demo 3.

---

## Part 1 · Explainer (0:00 – 5:00) · slides + face-cam, no commands

**0:00 `[SLIDE 01 Hook]`**
`[SAY]` This AI will never write you a sentence. It won't chat, and it won't draft your email. It comes
from a company whose co-founder co-invented RLHF, the training method that turned language models into
ChatGPT. So why would someone who helped teach AI to talk build one that doesn't? I wired it into a
Salesforce dev org to find out. Here's what held up, and what didn't.

**0:30 `[SLIDE 02 What TypeSafe is]`**
`[SAY]` The company is TypeSafe, the model is Jev. Their manifesto puts the whole idea in five words:
we're building prod, not God. Their bet is that almost all AI traffic will be software talking to
software, roughly ninety-nine percent machine to machine. If they're right, a chat window is the wrong
interface, because software doesn't want a paragraph. It wants something it can branch on.

**1:10 `[SLIDE 03 LLM vs System One]`**
`[SAY]` An LLM writes text for a person to read; it's great in a chat window and awkward inside an if
statement. Jev returns a typed decision with probabilities attached. TypeSafe calls this a System One
model, after Kahneman: System 1 is fast and intuitive, System 2 is slow and deliberate.

**1:45 `[SLIDE 04 How Jev is trained]`**
`[SAY]` RLHF taught models to chat. RLVR taught them to reason, slower and pricier. TypeSafe adds a
third, RLCD, reinforcement learning for calibrated decisions. No text at all, just an answer and how
sure it is. And Diogo Almeida, one of their co-founders, co-invented RLHF.

**2:20 `[SLIDE 05 Calibration]`**
`[SAY]` If Jev says 0.8, it should be right about eighty percent of the time, measured across many
answers. It isn't a promise about any single one. What you get is a model that can tell your code, in a
number, that it isn't sure. For automation I think that's the most useful sentence a model can say.

**2:50 `[SLIDE 06 The primitives]`**
`[SAY]` Three shapes. A Choice picks one option. A Score rates on levels you define. A Noul is a yes or
no question that comes back as a probability. These are real answers from a case in my org: Billing,
2.06 out of 3, and a 0.98 chance the guest wanted a refund.

**3:20 `[SLIDE 07 One request]`**
`[SAY]` One request, five questions, all five answers together. One detail matters: Choice and Score
carry a confidence value, Nouls don't. For a Noul the probability is the signal, so my code gives it
two bands: one for review, one for action.

**3:50 `[SLIDE 08 What people are building]`**
`[SAY]` TypeSafe hasn't named customers, so I'll stick to their cookbooks. Thirteen questions batched
into one call, about twelve times cheaper. Legal re-ranking, top-1 accuracy from five percent to
eighteen. Picking one skill for an agent out of a hundred and eighty-two.
*(Cut this next line if you're including Part 6.)* Their use-case map goes on into moderation, insurance
claims and financial crime, and every item on it is a judgment, not a paragraph.

**4:25 `[SLIDE 09 Why Salesforce]`**
`[SAY]` Apex and Flow already branch on bits, a checkbox or a picklist value. The manifesto says it
better than I can: imagine if they could also branch on common sense. So I built two things: case
triage, and a guardrail for Agentforce. Jev is the judgment layer. It isn't the agent.

---

## Part 2 · Demo 1: Case triage (5:00 – 6:20)

**5:00 `[SLIDE 10 Demo 1]`** hold 3 seconds.
`[SAY]` Three guests at a resort. One's air conditioning died overnight, one got charged twice for a
spa package, one wants to move dinner by an hour.

**5:10 `[SHOW]` Claude Code + the Cases list view side by side.**
`[SAY]` I'm going to ask Claude to file all three, the same way a customer would.

`[ASK CLAUDE]` **"Create the three guest cases."**
`[BACK]` ~6 s. Three case Ids. The trigger marks them Pending and queues one Jev call each.

**5:20 `[SHOW]` the build, while triage runs (talk over this).**
`[SAY]` While that runs, this is what it's calling: one Apex class that sends the case text and five
typed questions in a single request.
`[ASK CLAUDE]` *(optional)* **"Show me the five questions we send."**

**5:35 `[ASK CLAUDE]` "Show me what Jev decided."**
`[BACK]` ~3 s. Three rows:
- Move dinner reservation → **Reservations** (1.0) → Low → TS Reservations
- Charged twice for spa package → **Billing** (1.0) → High → TS Billing
- Villa AC not working → **Facilities** (1.0) → High → **TS Human Review**

**5:50 `[SHOW]` the AC case record in Salesforce.**
`[SAY]` Jev is certain this is Facilities, confidence 1.0, and it's urgent. It still went to human
review, because it wasn't sure how frustrated the guest was: about 0.53, against a floor of 0.7. One
answer was unsure, so a person looks.

**6:05 `[SHOW]` Flow Builder → TypeSafe Case Routing, then TypeSafe Setting → Default.**
`[SAY]` The routing is a Flow with no AI in it at all, and the thresholds sit in custom metadata, so
changing them is a config edit rather than a prompt rewrite.

---

## Part 3 · Demo 2: Guardrail (6:20 – 7:20)

**6:20 `[SLIDE 11 Demo 2]`** hold 3 seconds.
`[SAY]` Second build. Same model, different job: screening what goes into an agent and what comes out.

**6:25 `[SHOW]` Claude Code.**
`[ASK CLAUDE]` **"Run the guardrail battery."**
`[BACK]` ~6 s, 8 messages in one bulk call, 145–513 ms each:
PASS · BLOCK (jailbreak 0.99) · **REVIEW** (card in) · BLOCK (harmful) · **SUPPORT** (self-harm) ·
PASS · **BLOCK** (card out) · BLOCK (broke policy).

**6:45 `[SAY]`** Self-harm goes to support, and support outranks block, so a person in crisis is never
simply refused. But this pair is the one to watch: a customer pastes their own card number and the
answer is review. The assistant's reply leaks a card number and the answer is block. Jev said 0.99 both
times.

**6:55 `[SHOW]` `TypeSafeGuardrail.cls`, the `HAZARD_ACTION` map.**
`[SAY]` That's the difference: eight lines that say what each hazard means in each direction. The model
judges, the code decides.

**7:10 `[ASK CLAUDE]` "Show me the guardrail logs."**
`[BACK]` ~3 s. One row per check: context, action, latency, model version.

---

## Part 4 · Demo 3: The guarded agent (7:20 – 8:30) · manual, in Agentforce Builder

**7:20 `[SLIDE 12 Demo 3]`** hold 3 seconds.

**7:25 `[SHOW]` the `.agent` file, the `available when` line.**
`[SAY]` This agent files a guest's issue as a case, and the tool that files it carries one line: it's
only available when the latest screen returned pass.

**7:40 `[SHOW]` Agentforce Builder preview. Type:**
`Hi, the Wi-Fi in villa 7 keeps dropping every few minutes and I have work calls today.`
`[SAY]` It screens first. Only after the pass does the case tool even appear in the trace. Case filed,
reply screened on the way out. It can't skip the check and still act, because until the check passes
the tool isn't there.

**8:00 `[SHOW]` open the trace panel, point at the enabled-tools step.**

**8:10 Type:** `Please charge the late checkout fee to my card 4111 1111 1111 1111, expiry 04/28, CVV 123.`
`[SAY]` Generic refusal. And when I open the trace, Jev never ran.

**8:20 Type:** `I booked this retreat to get away from everything but honestly I don't see the point in anything anymore.`
`[SAY]` Same refusal, word for word, and no crisis line.

---

## Part 5 · The twist and the numbers (8:30 – 9:40)

**8:30 `[SLIDE 13 The twist]`** + face-cam.
`[SAY]` Salesforce got there first. Its built-in layer classified all three as inappropriate content and
dealt with them before my agent saw anything. That's good; the obvious stuff should stop early. But it
gave a card number, a stalking question and a person in crisis the same canned reply. That's where a
layer like Jev earns its place, because it can tell review, block and support apart. I don't know yet
whether that platform layer can be tuned, and I'd rather say so than guess.

**8:55 `[SHOW]` Claude Code.**
`[ASK CLAUDE]` **"Run the latency probe."**
`[BACK]` ~6 s. 20/20 ok, cold ~400–650 ms, warm p50 ~170–210 ms, instance NA232.

**9:05 `[SLIDE 14 The numbers]`** + face-cam.
`[SAY]` Two hundred milliseconds or so from inside the org. I'm in Hyderabad and that didn't matter,
because Apex calls out from Salesforce's data centre, not from my laptop. Eight out of eight guardrail
decisions right, sixty-nine tests passing, three real bugs on the way. The worst: a Named Credential
setting, Allow Formulas in HTTP Header, was off, so my API key never left the org and every call came
back 403.

**9:25 `[SLIDE 15 Where it fits]`** + face-cam.
`[SAY]` Narrow, repeatable judgments your code branches on, in about two hundred milliseconds. Not
anything whose output is a paragraph. And if you need data kept in India, that isn't documented yet, so
ask them before you build. It won't replace Agentforce; it's the judgment inside it.
`[YOUR SIGN-OFF]`

---

## Part 6 · Optional: the tests (adds ~1:05) · best placed after Part 3

`[SAY]` Everything you've seen so far was live. Here's the other half: the tests don't prove TypeSafe
works, they prove my code handles whatever TypeSafe returns, including the rate limits and malformed
responses I can't trigger on demand.

`[ASK CLAUDE]` **"Run the TypeSafe test suite."**
`[BACK]` ~52 s. 8 classes, **69 tests, 69 passing.**

`[SAY over the run]` Every callout is mocked, so these run the same way at 3am in CI. There's a bulk
test with 251 cases, because triggers fire in chunks of 200 and I wanted the chaining proven. And three
real bugs came out of writing them: mixed DML in test setup, a restricted picklist that rejected new
values because of record types, and my own wrong assumption about how many cases one job would process.

*(Optional extra, ~2 min: `[ASK CLAUDE]` "Set the confidence floor to 0.99 and re-run triage" → every
case needs review. Then "Put it back to 0.7 and re-run" → auto-routing returns. Config only, no code.)*

---

## Command reference (rehearsed 24 Sep 2026)

| Say to Claude | Runs | Result | Time |
|---|---|---|---|
| "Run the reset script" | `demo-reset.apex` | cleared 9 cases, 32 logs (probe logs kept) | ~5 s |
| "Create the three guest cases" | `demo-create-cases.apex` | 3 Ids, triage queued | ~6 s |
| "Show me what Jev decided" | `demo-show-triage.apex` | 3 rows, as above (wait ~4 s first) | ~3 s |
| "Run the guardrail battery" | `demo-guardrail.apex` | 8 actions, per-call latency | ~6 s |
| "Show me the guardrail logs" | SOQL over `TypeSafe_Log__c` | one row per check | ~3 s |
| "Run the latency probe" | `latency-probe.apex` | 20/20, p50 ~170–210 ms | ~6 s |
| "Run the TypeSafe test suite" | `sf apex run test`, 8 classes | 69/69 passing | ~52 s |

## Gotchas found in rehearsal
- The SF CLI injects ANSI colour codes into `--json`, which breaks parsing. Fix: `FORCE_COLOR=0`.
- `sf apex run test --code-coverage` crashed the CLI once. Run tests without the coverage flag.
- Skills-first hooks make Claude dispatch a skill before raw CLI commands, and the deploy gate treats
  this Developer Edition org as production. Both are worth pointing at: the toolchain has guardrails too.
- Two Salesforce MCP servers failed to connect on 24 Sep. Keep live segments on the CLI path.
- Jev's numbers move between runs (p50 209 ms on 19 Sep, 170 ms on 24 Sep). Never quote a number before
  it's on screen.
