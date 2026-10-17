# Deep Dives: TypeSafe (Jev) × Salesforce · Script

~1,450 spoken words ≈ 9:30 at 150 wpm. `[ON SCREEN]` = cue. `[YOUR MOMENT]` = a slot for a real
memory only you can supply; leave it out if nothing fits. Every fact below traces to TypeSafe's docs,
their manifesto, or what ran in the `jev` org on 19 Sep 2026.

---

## 0:00 · Slide 01 · Hook
[ON SCREEN: slide 01, cam right]

This AI will never write you a sentence. It won't chat, and it won't draft your email. It comes from a
company whose co-founder co-invented RLHF, the training method that turned language models into
ChatGPT. So why would someone who helped teach AI to talk build one that doesn't? I wired it into a
Salesforce dev org to find out. Here's what held up, and what didn't.

## 0:30 · Slide 02 · What TypeSafe is
[ON SCREEN: slide 02]

The company is TypeSafe, and the model is called Jev. Their manifesto puts the whole idea in five
words: we're building prod, not God. They aren't chasing one model that does everything. Their bet is that
almost all AI traffic will be software talking to software, roughly ninety-nine percent machine to
machine and one percent human. If they're right, a chat window is the wrong interface, because software
doesn't want a paragraph. It wants something it can branch on.

## 1:10 · Slide 03 · LLM vs System One
[ON SCREEN: slide 03]

That's the whole difference. An LLM writes text for a person to read; it's great in a chat window and
awkward inside an if statement. Jev returns a typed decision with probabilities attached, and your code
reads it directly. TypeSafe calls this a System One model, after Daniel Kahneman's *Thinking, Fast and
Slow*, where System 1 is fast and intuitive and System 2 is slow and deliberate. Jev is built for the
first kind of thinking: quick, narrow judgments.

## 1:45 · Slide 04 · How Jev is trained
[ON SCREEN: slide 04]

So how do you train that? After pre-training there have been two big ways to shape a model. RLHF taught
models to chat by rewarding the answers people prefer. RLVR taught them to reason, which is strong but
slower and more expensive. TypeSafe adds a third, RLCD, reinforcement learning for calibrated decisions.
There's no text at all, just an answer and how sure it is. And the RLHF link isn't marketing: Diogo
Almeida, one of TypeSafe's co-founders, co-invented it.

## 2:20 · Slide 05 · Calibration
[ON SCREEN: slide 05]

Calibrated is the word doing the work. If Jev says 0.8, it should be right about eighty percent of the
time. That's measured across many answers; it isn't a promise about any single one. What it gives you
is a model that can tell your code, in a number, that it isn't sure. For automation I think that's the
most useful sentence a model can say, even though it's a number, because now code decides when to act
and when to hand over to a person.

## 2:50 · Slide 06 · The primitives
[ON SCREEN: slide 06]

You ask Jev questions in three shapes. A Choice picks one option from a list, like which team owns a
case. A Score rates something on levels you define, like how frustrated a guest is from zero to three.
A Noul is a yes or no question that comes back as a probability. These are real answers from a case I
filed in my org: Billing, 2.06 out of 3, and a 0.98 chance the guest wanted a refund.

## 3:20 · Slide 07 · One request
[ON SCREEN: slide 07]

And you don't pay for them one at a time. This is a single request carrying five questions, and all
five answers come back together. One detail matters here. Choice and Score answers carry a confidence
value, but Nouls don't; for a Noul the probability itself is the signal. So in my code a Noul gets two
bands instead of one threshold: one for review and one for action.

## 3:50 · Slide 08 · What people are building
[ON SCREEN: slide 08]

What are people building with it? TypeSafe hasn't named customers, so I'll stick to what their own
cookbooks show. Batching thirteen questions into one call came out about twelve times cheaper.
Re-ranking legal search results lifted top-1 accuracy from five percent to eighteen. Another cookbook
picks the right skill for an agent out of a catalogue of a hundred and eighty-two. Their use-case map
goes on into moderation, insurance claims and financial crime, and every item on it is a judgment, not
a paragraph.

## 4:25 · Slide 09 · Why Salesforce
[ON SCREEN: slide 09]

That's why this lands so naturally in Salesforce. Apex and Flow already branch on bits, a checkbox or a
picklist value. The manifesto says it better than I can: imagine if they could also branch on common
sense. So I built two things. The first is case triage, where a case goes to Jev and comes back as typed
fields that a Flow routes to a queue. The second is a guardrail for Agentforce, where every message
comes back as pass, review, block or support. Jev is the judgment layer. It isn't the agent.

[YOUR MOMENT: optional. Why this caught your eye in the first place, if there's a real moment.]

---

## 5:00 · Slide 10 → Demo 1 · Case triage
[ON SCREEN: slide 10 for 3 s, then the Cases list]

Three guests at a resort. One's air conditioning died overnight, one got charged twice for a spa
package, and one wants to move dinner by an hour. I'll create all three cases.
[ON SCREEN: create the cases or run `demo-create-cases.apex`, then refresh]

The trigger queues one call per case, and a few seconds later... every field on the right is Jev's
answer. The dinner change is Reservations, low priority. The double charge is Billing and high
priority, with a 0.98 refund signal and a churn score close to the top of the scale.
[ON SCREEN: open the AC case]

Now the AC case. Jev is certain it's Facilities, confidence 1.0, and it's urgent. It still went to
human review, because Jev wasn't sure how frustrated the guest was: about 0.53, against a floor of 0.7.
One answer was unsure, so a person looks. I could change the rule so only the department decides
routing. I kept it, because for a demo about trust I'd rather over-review than under-review.
[ON SCREEN: Flow Builder, then TypeSafe Setting]

The routing lives in a Flow with no AI in it at all, and the thresholds sit in custom metadata, so
changing them is a config edit rather than a prompt rewrite.

## 6:15 · Slide 11 → Demo 2 · Guardrail
[ON SCREEN: slide 11 for 3 s, then VS Code, run `demo-guardrail.apex`]

The second build is a guardrail. I sent eight messages through it in one bulk call: five from users and
three written as if an LLM had replied. The clean ones pass. The jailbreak is blocked at 0.99, and so is
someone asking how to get into an ex's account. A message showing signs of self-harm goes to support,
and support outranks block, so a person in crisis is never simply refused.

This pair is the one to watch. A customer pastes their own card number, and the answer is review: mask
it and keep helping. The assistant's reply leaks a card number, and the answer is block. Jev said 0.99
both times. The difference is a small map in my Apex class that decides what each hazard means in each
direction; the model judges and the code decides.
[ON SCREEN: `HAZARD_ACTION` in `TypeSafeGuardrail.cls`, then TypeSafe Logs]

Every one of these is in the log with its scores and its latency.

## 7:15 · Slide 12 → Demo 3 · Guarded agent
[ON SCREEN: slide 12 for 3 s, then Agentforce Builder]

The last build is where it gets interesting. This is an Agentforce agent written in Agent Script. It
files a guest's issue as a case, and the tool that files the case carries one line: it's only available
when the latest screen returned pass.
[ON SCREEN: the `available when` line, then type the Wi-Fi message]

The Wi-Fi in villa 7 keeps dropping. The agent screens the message, and only after the pass does the
case tool even appear in the trace. The case is filed, and the reply is screened on the way out. The
model can't skip the check and still act, because until the check passes the tool isn't there.
[ON SCREEN: type the card-number message, open the trace]

Next, a card number. I get a generic refusal, and when I open the trace, Jev never ran.
[ON SCREEN: type the self-harm message, open the trace]

It's the same with this one: the same refusal, word for word, and no crisis line.

## 8:20 · Slide 13 · The twist
[ON SCREEN: slide 13, cam]

Salesforce got there first. Its built-in layer classified all three as inappropriate content and dealt
with them before my agent saw anything. That's good; the obvious stuff should stop early. But it gave a
card number, a stalking question and a person in crisis the same canned reply, and that's where a layer
like Jev earns its place, because it can tell review, block and support apart. I don't know yet whether
that platform layer can be tuned, and I'd rather say so than guess.

## 8:45 · Slide 14 · The numbers
[ON SCREEN: slide 14, cam]

Here are the numbers. A typical call took 209 milliseconds from inside the org, on Salesforce instance
NA232. I'm in Hyderabad and that didn't matter, because Apex calls out from Salesforce's data centre,
not from my laptop. Eight out of eight guardrail decisions were right, and sixty-nine tests pass after
three real bugs. The worst one was a Named Credential setting, Allow Formulas in HTTP Header, that was
switched off, so my API key never left the org and every call came back 403.

## 9:10 · Slide 15 · Where it fits
[ON SCREEN: slide 15, cam]

So where does Jev fit? Narrow, repeatable judgments your code branches on, in about two hundred
milliseconds. Where doesn't it? Anything whose output is a paragraph. And if you need data kept in
India, that isn't documented yet, so ask them before you build. It won't replace Agentforce; it's the
judgment inside it. The full notes and the code are in the newsletter.

[YOUR SIGN-OFF]

---

## Humanize pass (checked)
- [x] No banned words, openers or phrases; contractions throughout
- [x] No em dashes; one ellipsis (Demo 1); no exclamation marks
- [x] Direct opinions: "the most useful sentence a model can say", "I'd rather over-review than under-review"
- [x] Real numbers from the build: 0.98, 0.53, 209 ms, 8/8, 69 tests, 403
- [x] Admitted limits: platform layer tunability unknown; India residency undocumented; no named customers
- [x] Nothing invented: no scenes, feelings or anecdotes beyond what happened in the build

## Before recording
- Opinions confirmed and kept (20 Sep 2026); the "keep coming back to" line on slide 02 was cut.
- **The two `[YOUR MOMENT]` slots** are optional. If there's a real moment (what made you look at
  TypeSafe, what surprised you first), add it; otherwise skip them.
