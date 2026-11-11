# Local model benchmark

Three language models that run on a Mac, put to the six jobs Dever has or wants, to decide what
on-device intelligence is built on. Measured on 11 November 2026. Background and the rules every
generated text follows: [on-device-ai.md](on-device-ai.md). No code in the app comes with this document.

Contents: [answer](#1-the-answer-in-short) · [candidates](#2-candidates) · [method](#3-method) ·
[results](#4-results) · [raw outputs](#5-a-few-raw-outputs-side-by-side) · [machine cost](#6-what-each-model-costs-the-machine) ·
[product](#7-for-the-product) · [options](#8-options) · [recommendation](#9-recommendation) ·
[not measured](#10-what-was-not-measured)

---

## 1. The answer in short

| | Apple system model | Qwen3.5-4B | Gemma 4 12B |
| --- | --- | --- | --- |
| Cases fully useful (of 31) | 4 | 13 | **25** |
| Cases with a false statement in two runs of three (of 31) | 9 | 5 | **0** |
| Median time for an answer | **2.4 s** | 3.5 s | 9.7 s |
| Download | none | 3.0 GB | 6.6 GB |
| Memory while loaded | not in the app | 2.8 to 3.9 GB | 6.8 to 7.9 GB |

Times were taken on battery in Low Power Mode (section 10): they compare the models fairly and are
slower than a plugged-in Mac would give.

A 12-billion-parameter model does what Apple's model could not: it weighs fifteen messages, says "nothing
is asked of you" when nothing is, leaves a fixed problem out of the open matters, reads a reversed
decision in an issue's comments, and says "the log does not say why" instead of inventing a cause. A
4-billion-parameter model sits in between and still invents. No model writes a useful reply under the
"commit the user to nothing" rule.

**Recommendation:** keep Apple's model for the one automatic job it does (long messages), and add an
opt-in "Local Intelligence" download of Gemma 4 12B, run through MLX, for the jobs done on demand or
rarely: issue summary and pipeline failure first, then the catch-up and the issue from a message again.
Offer it on Macs with 16 GB or more only (section 9).

## 2. Candidates

| | Apple system model | Qwen3.5-4B | Gemma 4 12B |
| --- | --- | --- | --- |
| Maker | Apple | Alibaba (Qwen team) | Google DeepMind |
| Parameters | about 3 billion | 4 billion | 12 billion |
| Build measured | macOS 27.2, Foundation Models | `mlx-community/Qwen3.5-4B-MLX-4bit` | `lmstudio-community/gemma-4-12B-it-MLX-4bit` |
| Quantisation | Apple's | 4-bit (5.3 bits per weight) | 4-bit |
| Size on disk | system asset, not readable | 2.99 GB | 6.63 GB |
| Context | 4,096 tokens | 262,144 tokens | 256,000 tokens |
| Languages claimed | 15, French and English among them | 201 | 140 in training, 35 supported |
| Licence | none needed, part of macOS 26 and later | Apache 2.0 | Apache 2.0 |
| Released | with macOS 26 | March 2026 | about June 2026 (family: April 2026) |

**Why these two.** Looked up on the day, not from memory: among MLX builds on Hugging Face, the Qwen3.5
and Gemma 4 families lead the downloads of general-purpose models under 15 billion parameters, and
Qwen3.5-4B and Gemma 4 12B are the current members of each at the two sizes wanted. Two families were preferred to two sizes of one, so that a weakness of one
family would show. Both are trained for many languages, French included. The newer Qwen 3.6 and 3.8
start at 27 billion parameters, which is too large for an app that shares a 16 GB Mac. Gemma 4 E4B, the
"small" Gemma, weighs 5.2 to 6.9 GB in MLX because it carries audio and vision encoders, more than a
4-billion text model should: it was passed over for Qwen3.5-4B. Mistral's current small models are 3 billion (Ministral 3, late 2025) or 24 billion.

**What the licences require.** Apache 2.0 for both, with no extra use policy attached to the weights
(Gemma 4 left the "Gemma Terms of Use" of Gemma 3). An app may download, run and redistribute them, for
commercial use too. Redistribution, which is what hosting a copy for users would be, requires giving a
copy of the licence, keeping the copyright and attribution notices, and stating changes if the files
were changed (a quantised build is a changed file: the model card says so). There is no obligation to
publish Dever's code and no trademark right: Dever may say "Gemma 4 by Google" as a fact, not as an
endorsement. An acknowledgements entry in Settings with the two licences covers it.

**Runtime.** MLX, Apple's array framework for Apple Silicon, through its Swift package
[`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm) (3.32.3, September 2026). It was chosen over
llama.cpp because it is a Swift package Dever can depend on directly, it supports macOS 14 like the app,
both models have an implementation in it (`Qwen35.swift`, `Gemma4.swift`), and it ships two things Dever
needs: `MLXGuidedGeneration` (output forced to a JSON Schema on any model, macOS 14 and later) and
`MLXFoundationModels` (an MLX model behind Apple's `LanguageModelSession` on macOS 27, so the
`@Generable` code Dever already has would drive it). llama.cpp remains the fallback: its models (GGUF)
exist for both candidates and it has grammars too, at the price of a C++ XCFramework and a bridging layer.

**Measured with** `mlx-lm` 0.32.2 on MLX 0.32.4, the Python twin of the Swift package: same framework,
same model files, same Metal kernels. The Swift package itself was not built or run here. Apple's model
was measured through a small Swift program that calls Foundation Models the way Dever does.

## 3. Method

**Machine.** MacBook Pro, Apple M1 Max (10 CPU cores, 32 GPU cores), 32 GB, macOS 27.2, 56 GB of free
disk before the downloads. **On battery, Low Power Mode on**, with the usual applications open.

**Test set.** 31 cases written for this benchmark, all invented (people, product, tickets, logs), 13 in
French and 18 in English, the reader being "Sam":

| Job | Cases | The hard ones |
| --- | --- | --- |
| a. One long message to a sentence and a kind | 8 | a QA report to boil down; "not a bug strictly speaking"; an incident that is over; a risk that blocks nothing today |
| b. Catch-up of 15 unread messages: what is asked of the reader, then the open matters | 4 | a request in the third person without an @; a channel where nothing is asked; a problem later said to be fixed |
| c. A reply drafted from a thread | 4 + 2 | a question of opinion; an answer already in the thread; a date the thread proposes |
| d. An issue from a message: title, description, priority | 5 | a message that sounds pressing without a word on urgency; two pieces of work in one message |
| e. A CI failure from a job name and a log tail | 5 | a log that does not say why; a job killed by its time limit; a lint job that never linted |
| f. A Linear issue summed up in two lines: where it stands, what is left to settle | 3 | a decision reversed in the comments; 50 comments with nothing left to decide |

**Instructions.** The ones Dever used, word for word, for jobs a to d (`MessageSummary.swift`, and
`CatchUp.swift`, `IssueDraft.swift`, `ReplyDraft.swift` from the git history; the catch-up without the
example sentences, and with "the matters still open" in place of "the most important other things").
Jobs e and f were never built: their instructions are written in the same manner. Two extra reply cases
(c5, c6) reuse two threads with bolder instructions that let the model use what the thread holds; they
are not Dever's and are reported apart. Every model gets the same instructions and the same input.

**Format, the one difference.** Apple's model is called with guided generation (`@Generable`), as in the
app. The open models get the same field descriptions as text at the end of the instructions and are
asked for one JSON object, **without** a grammar forcing it: whether the answer is the asked shape is
therefore a real measurement for them, and a lower bound on what `MLXGuidedGeneration` would give.
Thinking is switched off for both open models. Sampling: Apple's default; temperature 0.4 and top-p 0.9
for the open models; 400 tokens at most.

**Runs.** Each case three times per model, a fresh session each time: 279 generations.

**What was recorded:** the answer; time to the first token and total time; tokens per second; prompt
size; load time; memory after load, at peak, after 30 s idle and after unload; disk size.

**Grading.** Three levels, kept apart:

1. *Shape*: the answer is the asked object, with its fields, types and allowed values. By program.
2. *Automatic checks*: what a program can verify per case: the expected kind or priority, the number of
   the message that asks the reader, no closed matter among the open ones, words that must or must not
   appear. They catch gross errors and miss subtle ones.
3. *Hand grades*, per case and model, over the three runs:
   **faithful** 2 = nothing invented, overstated or reversed in any run; 1 = a slip, a misleading
   omission or one run of three wrong; 0 = false or overstated in two runs or more.
   **useful** 2 = could be shown as it is and saves the reading; 1 = acceptable but vague, too long, a
   copy of the input, bland or missing the main point; 0 = misleading, beside the point, refused or unusable.
   Graded by the author of this benchmark (an AI agent), one grader, not blind to the model. Every
   grade has its reason in `grades.json`, and every answer is in `outputs.md`, so each can be contested.

Scripts, the test set, every raw answer and the grades are outside the repository, in the shared notes
folder of the sessions that did this work, under `local-model-benchmark/`, with a note on how to rerun them.

## 4. Results

Columns: **shape** and **checks** are shares of the runs; **faithful** and **useful** count the cases
graded 2; **false** counts the cases graded 0 for faithfulness; times are medians in seconds (total, and
to the first token), speeds in tokens per second.

### a. One long message (8 cases, 24 runs per model)

| Model | Shape | Checks | Faithful | Useful | False | Total | First token | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 42% | 5/8 | 1/8 | 0/8 | 2.0 | 1.9 | not measurable |
| Qwen3.5-4B | 100% | 58% | 7/8 | 4/8 | 1/8 | 3.4 | 2.2 | 40 |
| Gemma 4 12B | 100% | 79% | 8/8 | 7/8 | 0/8 | 9.6 | 6.5 | 14 |

This is the job Apple's model keeps in the app, and on these harder messages it is the weakest of the
three: it rarely says anything false, but it drops who is asked, files an incident that is over as a
Problem, and gave three different readings of a question of opinion. Qwen wrote "21/21 criteria pass"
and "APP-612 fixed" of a report that says 21 of 24 and "should be fixed", in all three runs.

### b. Catch-up of 15 messages (4 cases, 12 runs per model)

| Model | Shape | Checks | Faithful | Useful | False | Total | First token | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 50% | 2/4 | 0/4 | 2/4 | 4.2 | 2.5 | about 31 |
| Qwen3.5-4B | 100% | 42% | 0/4 | 0/4 | 1/4 | 5.7 | 2.9 | 38 |
| Gemma 4 12B | 100% | 100% | 4/4 | 4/4 | 0/4 | 13.4 | 8.9 | 13 |

The job dropped after four forms. All three models find the request made to the reader in the third
person. The difference is in the channels where nothing is asked: Apple's model gives the reader someone
else's task and states that a merged fix "is not merged"; Qwen invents open matters; Gemma returns two
empty lists, six runs out of six, and never lists the fixed problem as open.

### c. Reply draft (4 cases with Dever's instructions, 2 with bolder ones; 18 runs per model)

| Model | Shape | Checks | Faithful | Useful | False | Total | First token | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 100% | 4/6 | 2/6 | 1/6 | 1.4 | 1.4 | not measurable |
| Qwen3.5-4B | 94% | 83% | 5/6 | 1/6 | 1/6 | 1.8 | 1.3 | 45 |
| Gemma 4 12B | 94% | 94% | 5/6 | 2/6 | 0/6 | 4.9 | 3.9 | 14 |

With Dever's instructions the size of the model changes nothing: asked for an opinion, all three answer
"I'll look into both options and get back to you". Gemma and Apple's model do answer from the thread
when the answer is in it ("Yes, it included the fix for the offline books"); Qwen says it will check.
With the bolder instructions Gemma takes the side the thread supports, with its reason, three runs out
of three, and still gives no date; Apple's model reverses the reasoning; Qwen promises Friday twice.
One Gemma run broke down (stray tokens, then one syllable repeated to the limit): the one malformed
answer of its 93.

### d. Issue from a message (5 cases, 15 runs per model)

| Model | Shape | Checks | Faithful | Useful | False | Total | First token | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 80% | 60% | 2/5 | 0/5 | 1/5 | 2.7 | 1.5 | about 66 |
| Qwen3.5-4B | 100% | 73% | 3/5 | 3/5 | 2/5 | 3.5 | 1.4 | 39 |
| Gemma 4 12B | 100% | 100% | 5/5 | 4/5 | 0/5 | 10.3 | 4.2 | 14 |

The message that sounds pressing without being urgent: Apple's model says urgent three times, Qwen high,
high, urgent, Gemma none three times. Apple's descriptions are the message copied, "I" included; the
other two rewrite it. Apple's guardrail refused one message three times out of three ("May contain
unsafe content"): it mentions that a screenshot shows a child's full name.

### e. CI failure explained (5 cases, 15 runs per model)

| Model | Shape | Checks | Faithful | Useful | False | Total | First token | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 60% | 1/5 | 1/5 | 4/5 | 2.7 | 1.9 | about 65 |
| Qwen3.5-4B | 100% | 100% | 4/5 | 3/5 | 0/5 | 3.4 | 1.6 | 40 |
| Gemma 4 12B | 100% | 93% | 4/5 | 5/5 | 0/5 | 8.5 | 5.0 | 14 |

Not a job for Apple's model: given a log that only waits and exits, it says the log shows the cause and
invents one, three different ways; it blames a test that passed for a job killed by its time limit; it
invents command lines. Both open models say the log does not say why, name the time limit, and see that
the lint job failed on the network during `npm ci`. Qwen is as good as Gemma here, three times faster.

### f. Issue summary (3 cases, 9 runs per model)

| Model | Shape | Checks | Faithful | Useful | False | Total | First token | Speed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 89% | 1/3 | 0/3 | 1/3 | 3.6 | 3.1 | about 63 |
| Qwen3.5-4B | 100% | 100% | 2/3 | 2/3 | 0/3 | 5.9 | 3.6 | 39 |
| Gemma 4 12B | 100% | 100% | 3/3 | 3/3 | 0/3 | 15.8 | 10.6 | 13 |

Apple's model pastes the last comments instead of summing up, and on the issue with two approaches it
states the reverse of where the comments end. Qwen follows the reversed decision but writes "the team
decided" of a choice still waiting for objections. Gemma writes "leaning toward" and who confirms by
when. The 50-comment issue (8,600 characters, about 2,500 tokens) took Apple's model 7 s, Qwen 11 s and
Gemma 31 to 34 s, of which 26 to 29 s before the first token.

### All jobs

| Model | Shape | Checks | Faithful | Useful | Unusable | False | Total, median | Total, 9 in 10 under |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 97% | 65% | 15/31 | 4/31 | 11/31 | 9/31 | 2.4 s | 4.5 s |
| Qwen3.5-4B | 99% | 74% | 21/31 | 13/31 | 5/31 | 5/31 | 3.5 s | 5.9 s |
| Gemma 4 12B | 99% | 92% | 29/31 | 25/31 | 1/31 | 0/31 | 9.7 s | 15.9 s |

**Shape.** Apple's three malformed answers are the three guardrail refusals. Each open model produced
one answer in 93 that was not the asked object, without any grammar. Gemma wraps its JSON in a code
fence four times in five, which a parser strips and guided generation would prevent.

**Repeating the instructions.** None of the three repeated an example or a phrase of the instructions as
if the input had said it; the instructions hold no example sentence, which is the lesson of the first day.

**French and English.** No model is clearly worse in one language. Apple's weakest summaries are French
(a4, a5, a8); Qwen answered one French case in English once; Gemma misspelt one French word once.

**Stability.** Gemma gave the same answer, nearly word for word, in the three runs of most cases; Apple's
model and Qwen changed their reading of a message from one run to the next (a3, a8, e1, f1).

## 5. A few raw outputs, side by side

**a2, a QA report: "21 criteria pass, 3 fail… APP-612 should be fixed before the release; the other two can follow."**

- Apple: *Problem* — "APP-612: the streak counter is not refreshed after the device changes time zone; it should be fixed before the release."
- Qwen: *Update* — "QA-41 report shows 21/21 criteria pass, with APP-612 fixed before release and APP-615, APP-618 following."
- Gemma: *Update* — "QA-41 report shows three failures, with APP-612 needing a fix before the release."

**b2, fifteen messages in which nothing is asked of the reader (one message asks Robin for a list, and Robin says yes).**

- Apple: asked: "send [6]" · open: "The retry fix for the sync queue is not merged. [2]"; "The changelog with the three fixes of this week is not updated. [10]"
- Qwen: asked: nothing · open: "Robin needs to send Priya the list of schools on the old plan. [6]"; "The team must confirm the sprint review schedule with the new time. [4]"
- Gemma: asked: nothing · open: nothing

**d2, « Alors là il faut vraiment qu'on s'en occupe !!! … Ce serait bien de corriger ça avant la release si on peut. »**

- Apple: "Corriger le bouton exporter sur Résultats" — **urgent** — the message copied as the description
- Qwen: "Corriger le bouton Exporter invisible sur l'écran Résultats" — **high** (urgent in one run)
- Gemma: "Modifier la couleur du bouton Exporter" — **none** — "Le bouton « Exporter » de l'écran Résultats sur la console des enseignants est écrit en gris clair sur fond blanc. Il est difficile à voir et a été signalé par trois enseignants."

**e3, a deploy log that uploads, waits four times, then "Process completed with exit code 1".**

- Apple: log shows the cause — "The test `./scripts/deploy-preview.sh pr-2207` on file `pr-2207` failed with `upload` command: `Uploading 214 files to preview storage`"
- Qwen: log does not show the cause — (no explanation)
- Gemma: log does not show the cause — "The log does not say why."

**f1, an issue with two fixes debated; the last comment: "I lean towards A in 3.4.1… any objection? If none by Wednesday noon I confirm."**

- Apple: "B is selected for 3.4; A is planned for 3.5." · to settle: "Schools are closed next week (holidays), so a night window is easy to get then, but that is after the 3.4 release on the 28th."
- Qwen: "The team decided to fix the streak counter in 3.4.1 by storing UTC timestamps and converting to local time zones." · to settle: "The decision to ship fix A in 3.4.1 needs confirmation by Wednesday noon to inform Noor."
- Gemma: "The team is leaning toward implementing fix A in version 3.4.1 to avoid doing work twice." · to settle: "Inès will confirm the decision if Sam and Malo have no objections by Wednesday noon."

**c2 and c5, "Sam, what do you think: faster sync before the release, or document the delay?" (the thread says the cache layer is not to be changed before 3.4).**

- Dever's instructions, all three models: "I'll look into both options and get back to you."
- Bolder instructions, Apple: "Making the sync faster is less risky than documenting the delay, because the cache layer is involved."
- Bolder instructions, Qwen: one run of three takes the side; another: "I'll look at both options."
- Bolder instructions, Gemma: "We should document the delay since we agreed not to touch the cache layer before the 3.4 release."

## 6. What each model costs the machine

| | Apple system model | Qwen3.5-4B | Gemma 4 12B |
| --- | --- | --- | --- |
| Disk | system asset, shared with macOS | 2.99 GB | 6.63 GB |
| Download here (about 170 Mbit/s) | none | 2 min 24 s | 4 min 56 s |
| Load into memory | none in the app | 1.6 to 2.6 s | 4.3 to 4.7 s |
| First answer after a load | 2.5 s | 3.0 s | 10.6 s |
| Memory after load (process footprint) | 11 to 23 MB in the calling process | 2.75 GB | 6.81 GB |
| Peak while generating | not measurable | 3.3 GB typical, 3.9 GB on the 50-comment issue | 7.1 GB typical, 7.9 GB on the 50-comment issue |
| Held when idle for 30 s | nothing in the app | 2.95 GB, all of it | 7.21 GB, all of it |
| After unloading | — | 0.15 GB | 0.27 GB |
| Load again, then answer | — | 1.7 s, then 3.1 s | 4.7 s, then 11.9 s |
| Reading the input | — | 270 tokens/s | 90 tokens/s |
| Writing the answer | about 65 tokens/s (estimate) | 40 tokens/s | 14 tokens/s |
| Context | 4,096 tokens | 262,144 | 256,000 |

- **Apple's model does not live in the app.** It runs in a system service
  (`TGOnDeviceInferenceProviderService`), which `top` showed at about 0.7 GB over two processes while
  generating and at 17 MB each a few minutes after the run: the system loads and unloads it itself.
  Those figures probably leave out weights mapped from disk; its true memory could not be measured.
- **An MLX model lives in Dever's process** and holds its memory until it is unloaded. Unloading works
  and gives the memory back at once; loading again costs 2 s (Qwen) or 5 s (Gemma) once the file is in
  the system's file cache. The first load after a restart reads the whole file from disk and was not measured.
- **Time before the first token is what the user waits for.** The fixed instructions are 250 to 350 tokens
  of every prompt and were read again each time. Keeping them in a prompt cache would take about
  1 s (Qwen) to 3 s (Gemma) off each answer; not measured.
- **Context.** Apple's 4,096 tokens were enough for every case here, the 50-comment issue included
  (2,462 tokens by Apple's count), so the rule "the description and the newest comments that fit" was not
  put to work. Past roughly 13,000 characters of issue it would be. For the open models the limit is
  time, not room: Gemma took 26 to 29 s to read 2,600 tokens in Low Power Mode.
- **Energy and heat** were not measured. The whole run was on battery, in Low Power Mode.

## 7. For the product

**Download for a user who says yes in onboarding.** 3.0 GB or 6.6 GB. Here: 2.5 and 5 minutes. On a
50 Mbit/s line: 8 and 18 minutes; at 20 Mbit/s: 20 and 44 minutes (computed). It has to run in the
background, resume after an interruption, and never hold the onboarding: the question is asked, the app
goes on, the features appear when the model is ready, as they do today when Apple's model becomes ready.

**Memory on a Mac with 8 GB.** Gemma 4 12B cannot run: 7 to 8 GB is the whole machine. Qwen3.5-4B fits
(3 to 4 GB) only if nothing heavy is open, which is not the Mac of someone who runs Slack, a browser and
an editor; it would have to load for one answer and unload right after. Apple's model is the only one
that costs such a Mac nothing. *Inferred from the memory measured here; no 8 GB Mac was tested.*

**Memory on a Mac with 16 GB.** Gemma takes half of it while loaded. Workable if the model is loaded on
demand and unloaded after a minute or two without use, not if it stays resident; with a simulator or
containers running, the system will compress and swap during a generation. Qwen is comfortable. *Inferred.*

**Speed on an older or smaller Mac.** The test Mac has 32 GPU cores; a MacBook Air M1 or M2 has 7 to 10
and a sixth to a quarter of the memory bandwidth. Generation speed on Apple Silicon follows those two, so expect a
third to a quarter of the plugged-in speed of this Mac. Published MLX figures put Qwen3.5-4B near
87 tokens/s on an M1 Max at full power, about twice what Low Power Mode gave here. *Inferred:* on an
M1 or M2 Air, Qwen near 20 to 30 tokens/s (an answer in 4 to 8 s), Gemma near 6 to 9 tokens/s if it
fits at all (an issue summary in 30 to 60 s). On an M3 Pro or later, Gemma should be at or above what
this Mac gave. None of this was measured.

**Shipping and updating the model.** The weights are not in the app. On a yes, Dever downloads a pinned
revision (a commit hash, with the files' checksums) either from Hugging Face directly or from a copy Dever
hosts; both are allowed by the licence, and the copy removes a dependency on a third party's repository
staying up and unchanged. Files go under Application Support, excluded from backups, checked before use,
removable from Settings. A model update is a new pinned revision shipped with an app release: download
the new one, check it, switch, delete the old one, and rerun the prompts' tests, because a new model is a
new behaviour. The runtime (`mlx-swift-lm`) is a build dependency and updates with the app.

**What the user must be told,** before the download and in Settings › Intelligence: the size and where
it comes from; that it runs on this Mac and nothing leaves it (the download itself is the only request,
and it sends none of their data); that it uses 7 to 8 GB of memory while working and is released when
idle; that it draws power and warms the Mac while it writes; that it can be removed at any time; that
what it writes may be wrong, as the mark already says. Rule 3 of on-device-ai.md ("Only the system
model") has to be reworded: the promise that holds is "nothing leaves the Mac".

**What stays impossible whatever the model.**

- *Speaking for the user.* Under "commit to nothing" every model writes "I'll look and come back". A
  bolder instruction gives a useful draft with the 12B model, and that draft takes a position in the
  user's name: whether Dever should do that is a product decision, not a matter of model size.
- *Knowing what the text does not say:* whether a request was already handled elsewhere, who owns a
  screen, how urgent something is for the business. Gemma gets priority right by answering "none"
  unless the message says otherwise, which is the instruction, not judgement.
- *Being right every time.* Gemma made two slips in 93 answers (one broken answer, one test name
  altered). The mark, the link to the source, the checks in code and "never in place of facts" stay.
- *Reading everything at once at reading speed.* Nearly 30 s before the first word on a 50-comment issue is a
  wait that needs a skeleton and a reason to exist; automatic use on every message of a busy channel is
  out of reach of a 12B model on battery.

## 8. Options

**A. Keep Apple's model only.**

- For: no download, no memory in the app, no new dependency, fastest (2.4 s), already built, runs on
  8 GB Macs, Apple updates it.
- Against: 4 cases of 31 fully useful and 9 with false statements; issue summary and pipeline failure,
  the two jobs still planned, are not within its reach (0 of 3 and 1 of 5 useful, false on 4 of 5 logs);
  a guardrail that refuses ordinary work messages; macOS 26 and Apple Intelligence required; a model that
  changes with system updates without notice. The product stays where it is today.

**B. Replace it with Qwen3.5-4B for everything.**

- For: 3 GB, runs wherever MLX runs from macOS 14, with or without Apple Intelligence; fast (3.5 s);
  good on logs (as good as Gemma) and on issue summaries; no guardrail refusals.
- Against: still invents (false in 5 of 31, "21/21 criteria pass"); the catch-up is no better than
  Apple's (0 of 4 faithful); priorities wrong; unstable from run to run. It does not bring back the
  dropped jobs, and it asks 3 GB of disk and memory for a gain limited to two jobs.

**C. Replace it with Gemma 4 12B for everything.**

- For: 25 of 31 fully useful, no case with a false statement in two runs; every job but the reply draft
  works, the dropped catch-up and issue-from-a-message included; stable; no guardrail; macOS 14.
- Against: 6.6 GB to download, 7 to 8 GB of memory, so no 8 GB Mac and care on 16 GB; 10 s per answer in
  Low Power Mode, 16 s for one in ten; too slow and too power-hungry to summarise every long message of a
  rail automatically; Macs without it would lose the long-message summaries they have today.

**D. Apple's model for the small job, a larger model for the rest (recommended).**

- For: each model where it fits. The automatic, high-volume, low-stakes job (long messages: one text in,
  one sentence out, original one click away) stays on the model that is free, fast and already there.
  The jobs done on demand or once per issue, where a wrong answer costs more and a 10-second wait is
  acceptable, go to the model that gets them right. Nothing is taken from users who say no or whose Mac
  is too small. The service already hides the model behind a protocol (`LanguageModel`).
- Against: two models to test prompts against; two sets of states in Settings (Apple's availability, the
  download); the weaker model stays on the most visible feature unless the larger one takes it over when
  loaded and on power, which is a later decision that needs its own measurement.

## 9. Recommendation

**Option D, with Gemma 4 12B through `mlx-swift-lm`, opt-in, on Macs with 16 GB or more.**

1. Long messages stay on Apple's model, unchanged.
2. "Local Intelligence" is a question in onboarding and a row in Settings › Intelligence: it downloads
   Gemma 4 12B (6.6 GB) in the background. Not offered under 16 GB of memory.
3. First features on it, in this order: **issue summary** (data already loaded, 3 of 3 here) and
   **pipeline failure explained** (5 of 5 useful here), both in the plan and both out of reach of
   Apple's model. Then the **catch-up** and the **issue from a message** again, on real channels, since
   this benchmark says the reason they were dropped is gone (4 of 4 and 4 of 5). The reply draft stays dropped.
4. The model is loaded on first use and unloaded after a short idle time; one generation at a time, as today.
5. Macs with 8 GB keep what they have. Qwen3.5-4B for the pipeline explanation alone is possible later
   (it matched Gemma on that job) but is a second model to maintain for one feature: not now.

**What it would cost to build** (estimates, not measured):

| Piece | Work | Estimate |
| --- | --- | --- |
| Build | `mlx-swift-lm` as a dependency; MLX's Metal shaders are not built by `swift build`, which `scripts/build-app.sh` uses: an `xcodebuild` step or a prebuilt shader library; app size, signing | 1 to 2 days, the main unknown |
| Model client | a second `LanguageModel` behind the existing protocol; output forced to a JSON Schema with `MLXGuidedGeneration` (or `MLXFoundationModels` on macOS 27, reusing the `@Generable` types); load, unload on idle, prompt cache for the instructions; routing per feature | 2 to 3 days |
| Model store | download with progress and resume, pinned revision and checksums, disk-space and memory checks, removal; its states in Settings › Intelligence and the onboarding question; rows in data-freshness.md | 3 to 4 days |
| Issue summary | feature 5.5 of on-device-ai.md on the new client | 2 days |
| Pipeline failure | two GitHub reads (jobs of a run, log tail), then feature 5.6 | 3 days |
| Tests | this test set turned into real-model tests for the new client; a rerun at every model update | 1 to 2 days |

About two and a half to three weeks for the ground and the two planned features; the catch-up and the
issue from a message would then mostly be their old code on the new client.

**Before building,** two cheap checks would remove the main doubts: run the timing pass again plugged in
with Low Power Mode off, and build a 50-line Swift command-line tool on `mlx-swift-lm` with guided
generation to confirm the Swift package gives what the Python one gave.

## 10. What was not measured

- **Speed at full power.** Every time and speed here was taken on battery with Low Power Mode on. The
  three models were measured in the same state, so the comparison holds; absolute speeds are probably
  near half of a plugged-in Mac's for the open models.
- **The Swift package.** Measured with `mlx-lm` (Python). Same framework and model files; the Swift
  package, its guided generation and its Foundation Models bridge were read about, not run.
- **Guided generation on the open models.** They were asked for JSON without a grammar. Shape results
  for them are a lower bound.
- **Apple's model's memory, disk size and exact token speed.** It runs in a system service; `top` gives
  a partial figure, the asset is not readable, and the speed is the answer's token count over the time
  after the first partial result, which guided generation delivers late.
- **A cold load from disk,** right after a restart, for the open models.
- **Energy and heat.**
- **8 GB and 16 GB Macs, and older chips.** Everything said about them is inferred from a 32 GB M1 Max.
- **The context limit of Apple's model in action.** The longest case fit.
- **Real channels.** The cases are invented and written by the same author who graded them; real
  messages are messier (pasted logs, links, emoji, mixed languages). The first day on real channels is
  what dropped four features, and the same test awaits these results.
- **One grader, 31 cases, three runs each.** The gaps between the models are wide enough to survive a
  second grader; the exact counts are not.
- **Other candidates.** Qwen3.5-9B, Gemma 4 E4B and a 6- or 8-bit build of either model were not run.
