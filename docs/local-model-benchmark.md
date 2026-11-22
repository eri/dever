# Local model benchmark

Five language models that run on a Mac, put to the six jobs Dever has or wants, to decide what
on-device intelligence is built on. First measured on 11 November 2026 on battery; measured again on
mains power on 20 and 23 November, with Gemma 4 E4B and Gemma 4 E2B added. Background and the rules every
generated text follows: [on-device-ai.md](on-device-ai.md). No code in the app comes with this document.

Contents: [answer](#1-the-answer-in-short) · [candidates](#2-candidates) · [method](#3-method) ·
[results](#4-results) · [raw outputs](#5-a-few-raw-outputs-side-by-side) · [machine cost](#6-what-each-model-costs-the-machine) ·
[product](#7-for-the-product) · [options](#8-options) · [recommendation](#9-recommendation) ·
[not measured](#10-what-was-not-measured)

---

## 1. The answer in short

| | Apple system model | Qwen3.5-4B | Gemma 4 E2B | Gemma 4 E4B | Gemma 4 12B |
| --- | --- | --- | --- | --- | --- |
| Cases fully useful (of 31) | 4 | 13 | 10 | 22 | **25** |
| Cases with a false statement in two runs of three (of 31) | 9 | 5 | 6 | 2 | **0** |
| Median time for an answer, mains power | not measured | 1.8 s | **0.7 s** | 1.5 s | 5.5 s |
| Median time for an answer, battery and Low Power Mode | 2.4 s | 3.5 s | not measured | not measured | 9.7 s |
| Download | none | 3.0 GB | 3.6 GB | 5.1 GB | 6.6 GB |
| Memory while loaded | not in the app | 2.7 to 3.9 GB | 2.9 to 3.4 GB | 4.4 to 4.8 GB | 6.8 to 7.9 GB |

Gemma 4 E4B, the small Gemma, is the find of the second pass. It is right where Apple's model invents
(pipeline failures, issue summaries, priorities), writes better one-message summaries than Apple's model,
and answers faster than Apple's model did. Its one weak job is the channel catch-up: in a channel where
nothing is asked of the reader it hands the reader someone else's task, as Apple's model does. Only the
12-billion-parameter Gemma gets the catch-up right, at three to four times the time and one and a half
times the memory. One step down, Gemma 4 E2B, is twice as fast as E4B but falls to 10 useful cases of
31: it gets priorities wrong, says a log shows a cause it does not, and swaps expected and actual values.
E4B is the smallest model that holds. No model writes a useful reply under the "commit the user to
nothing" rule.

**Recommendation:** an opt-in "Local Intelligence" download of **Gemma 4 E4B** (5.1 GB), run through MLX,
on Macs with 16 GB or more, for issue summaries, pipeline failures and issues from a message, and for
long-message summaries when it is installed. Apple's model keeps the long-message summaries where Local
Intelligence is off or cannot run. The catch-up stays dropped unless it is worth the 12B (section 9).

## 2. Candidates

| | Apple system model | Qwen3.5-4B | Gemma 4 E2B | Gemma 4 E4B | Gemma 4 12B |
| --- | --- | --- | --- | --- | --- |
| Maker | Apple | Alibaba (Qwen team) | Google DeepMind | Google DeepMind | Google DeepMind |
| Parameters | about 3 billion | 4 billion | 2 billion effective, about 5 with embeddings | 4.5 billion effective, 8 billion with embeddings | 12 billion |
| Build measured | macOS 27.2, Foundation Models | `mlx-community/Qwen3.5-4B-MLX-4bit` | `mlx-community/gemma-4-e2b-it-4bit` | `mlx-community/gemma-4-e4b-it-4bit` | `lmstudio-community/gemma-4-12B-it-MLX-4bit` |
| Quantisation | Apple's | 4-bit (5.3 bits per weight) | 4-bit | 4-bit | 4-bit |
| Size on disk | system asset, not readable | 2.99 GB | 3.3 GB | 5.06 GB | 6.61 GB |
| Context | 4,096 tokens | 262,144 tokens | 128,000 tokens | 128,000 tokens | 256,000 tokens |
| Languages claimed | 15, French and English among them | 201 | 140 in training, 35 supported | 140 in training, 35 supported | 140 in training, 35 supported |
| Licence | none needed, part of macOS 26 and later | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 |
| Released | with macOS 26 | March 2026 | April 2026 | April 2026 | about June 2026 |

**Why these.** Looked up on the day, not from memory: among MLX builds on Hugging Face, the Qwen3.5 and
Gemma 4 families lead the downloads of general-purpose models under 15 billion parameters. The first pass
took Qwen3.5-4B and Gemma 4 12B, two families at two sizes. Gemma 4 E4B was passed over then because its
MLX build weighs 5 GB, more than a 4-billion text model should: it carries audio and vision encoders that
Dever does not use. After the first pass showed the Gemma family well ahead, it was added to see whether a
smaller Gemma would do, and Gemma 4 E2B, the smallest of the family, to see how the answers degrade one
step further down. The newer Qwen 3.6 and 3.8 start at 27 billion parameters, too large for an app
that shares a 16 GB Mac. Mistral's current small models are 3 billion (Ministral 3) or 24 billion.

**What the licences require.** Apache 2.0 for all four open models, with no extra use policy attached to
the weights (Gemma 4 left the "Gemma Terms of Use" of Gemma 3). An app may download, run and redistribute
them, for commercial use too. Redistribution, which is what hosting a copy for users would be, requires
giving a copy of the licence, keeping the copyright and attribution notices, and stating changes if the
files were changed (a quantised build is a changed file). There is no obligation to publish Dever's code
and no trademark right: Dever may say "Gemma 4 by Google" as a fact, not as an endorsement. An
acknowledgements entry in Settings with the licence covers it. One trap: the cards of the E2B and E4B
builds measured say `license: gemma`, a leftover of Gemma 3, while Google's own model page says Apache 2.0. The
build Dever ships should be one whose card carries Apache 2.0, or one Dever converts itself.

**Runtime.** MLX, Apple's array framework for Apple Silicon, through its Swift package
[`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm) (3.32.3, September 2026). It was chosen over
llama.cpp because it is a Swift package Dever can depend on directly, it supports macOS 14 like the app,
the models have an implementation in it (`Qwen35.swift`, `Gemma4.swift`), and it ships two things Dever
needs: `MLXGuidedGeneration` (output forced to a JSON Schema on any model, macOS 14 and later) and
`MLXFoundationModels` (an MLX model behind Apple's `LanguageModelSession` on macOS 27, so the
`@Generable` code Dever already has would drive it). llama.cpp remains the fallback: its models (GGUF)
exist for every candidate and it has grammars too, at the price of a C++ XCFramework and a bridging layer.

**Measured with** `mlx-lm` 0.32.2 on MLX 0.32.4, the Python twin of the Swift package: same framework,
same model files, same Metal kernels. The Swift package itself was not built or run here. Apple's model
was measured through a small Swift program that calls Foundation Models the way Dever does.

## 3. Method

**Machine.** MacBook Pro, Apple M1 Max (10 CPU cores, 32 GPU cores), 32 GB, macOS 27.2, with the usual
applications open. **Two power states:**

- *First pass, 11 November:* Apple, Qwen3.5-4B and Gemma 4 12B, **on battery,
  Low Power Mode on**.
- *Second pass, 20 and 23 November:* **on mains power, Low Power Mode off**: Gemma 4 12B and Qwen3.5-4B
  again, Gemma 4 E4B and Gemma 4 E2B for the first time. Apple's model could not be run again: the system
  reported it not ready (`modelNotReady`), because Siri's language had gone back to French while the Mac
  is in English, the cause already described in on-device-ai.md section 2.

Times are only compared within one power state.

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
Jobs e and f were never built here when this ran: their instructions are written in the same manner. Two
extra reply cases (c5, c6) reuse two threads with bolder instructions that let the model use what the
thread holds; they are not Dever's and are reported apart. Every model gets the same instructions and input.

**Format, the one difference.** Apple's model is called with guided generation (`@Generable`), as in the
app. The open models get the same field descriptions as text at the end of the instructions and are
asked for one JSON object, **without** a grammar forcing it: whether the answer is the asked shape is
therefore a real measurement for them, and a lower bound on what `MLXGuidedGeneration` would give.
Thinking is switched off for the open models. Sampling: Apple's default; temperature 0.4 and top-p 0.9
for the open models; 400 tokens at most.

**Runs.** Each case three times per model and pass, a fresh session each time: 744 generations in all.

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
   Graded by the author of this benchmark (an AI agent), one grader, not blind to the model. Apple,
   Qwen3.5-4B and Gemma 4 12B are graded on the first pass; the second-pass answers of Qwen and the 12B
   were read and match those grades (the 12B's one broken answer did not recur). Gemma 4 E4B and E2B are
   graded on the second pass. Every grade has its reason in `grades.json`, and every answer is in `outputs.md`.

Scripts, the test set, every raw answer and the grades are outside the repository, in the shared notes
folder of the sessions that did this work, under `local-model-benchmark/` (first-pass answers in
`raw/battery-lowpower/`), with a note on how to rerun them.

## 4. Results

Columns: **shape** and **checks** are shares of the runs; **faithful** and **useful** count the cases
graded 2; **false** counts the cases graded 0 for faithfulness. **Time** is the median total in seconds,
on mains power, the battery figure in brackets where there is one; Apple's only on battery.

### a. One long message (8 cases)

| Model | Shape | Checks | Faithful | Useful | False | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 42% | 5/8 | 1/8 | 0/8 | (2.0) |
| Qwen3.5-4B | 100% | 58% | 7/8 | 4/8 | 1/8 | 1.8 (3.4) |
| Gemma 4 E2B | 100% | 88% | 8/8 | 3/8 | 0/8 | **0.6** |
| Gemma 4 E4B | 100% | 62% | 7/8 | 6/8 | 0/8 | 1.3 |
| Gemma 4 12B | 100% | 83% | 8/8 | 7/8 | 0/8 | 5.7 (9.6) |

The job Dever runs on Apple's model today, and on these harder messages Apple's model is the weakest: it
rarely says anything false, but it drops who is asked, files an incident that is over as a Problem, and
gave three different readings of a question of opinion. Qwen wrote "21/21 criteria pass" of a report
that says 21 of 24. Gemma E4B writes sentences as good as the 12B's but files a reported risk and a
request for a decision as Update, so they would show muted. Gemma E2B gets the kinds right but answers
in English two times in three where French was asked, and drops what the outcome was.

### b. Catch-up of 15 messages (4 cases)

| Model | Shape | Checks | Faithful | Useful | False | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 50% | 2/4 | 0/4 | 2/4 | (4.2) |
| Qwen3.5-4B | 100% | 42% | 0/4 | 0/4 | 1/4 | 3.3 (5.7) |
| Gemma 4 E2B | 100% | 50% | 2/4 | 1/4 | 2/4 | **1.1** |
| Gemma 4 E4B | 100% | 50% | 2/4 | 2/4 | 2/4 | 2.3 |
| Gemma 4 12B | 100% | 100% | 4/4 | 4/4 | 0/4 | 7.9 (13.4) |

The job dropped after four forms. Every model finds the request made to the reader in the third person,
and the request made with an @. The difference is in the channels where nothing is asked of the reader:
Apple's model and Gemma E4B give the reader a task asked of someone else ("Send the old plan school
list", asked of Robin), and so does Gemma E2B; Qwen invents open matters; only Gemma 12B returns two empty lists, six runs
out of six, and never lists a fixed problem as open.

### c. Reply draft (4 cases with Dever's instructions, 2 with bolder ones)

| Model | Shape | Checks | Faithful | Useful | False | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 100% | 4/6 | 2/6 | 1/6 | (1.4) |
| Qwen3.5-4B | 94% | 83% | 5/6 | 1/6 | 1/6 | 1.0 (1.8) |
| Gemma 4 E2B | 100% | 100% | 5/6 | 2/6 | 0/6 | **0.3** |
| Gemma 4 E4B | 100% | 100% | 5/6 | 2/6 | 0/6 | 0.9 |
| Gemma 4 12B | 100% | 100% | 5/6 | 2/6 | 0/6 | 2.8 (4.9) |

With Dever's instructions the size of the model changes nothing: asked for an opinion, all four answer
"I'll look into both options and get back to you". The three Gemma and Apple's model answer from the thread
when the answer is in it ("Yes, it included the fix for the offline books"); Qwen says it will check.
With the bolder instructions Gemma 12B takes the side the thread supports, with its reason, every run, and
gives no date; Gemma E4B says "the thread suggests…" and gets the reason wrong twice; Apple's model
reverses the reasoning; Qwen promises Friday twice.

### d. Issue from a message (5 cases)

| Model | Shape | Checks | Faithful | Useful | False | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | 80% | 60% | 2/5 | 0/5 | 1/5 | (2.7) |
| Qwen3.5-4B | 100% | 73% | 3/5 | 3/5 | 2/5 | 2.1 (3.5) |
| Gemma 4 E2B | 100% | 60% | 1/5 | 0/5 | 2/5 | **0.9** |
| Gemma 4 E4B | 100% | 100% | 5/5 | 5/5 | 0/5 | 1.9 |
| Gemma 4 12B | 100% | 100% | 5/5 | 4/5 | 0/5 | 5.6 (10.3) |

The message that sounds pressing without being urgent: Apple's model says urgent three times, Qwen high,
high, urgent, Gemma E2B high three times, and it gives medium to a plain bug report; E4B and 12B none
every time. Apple's descriptions are the message copied, "I" included; the
others rewrite it. Apple's guardrail refused one message three times out of three ("May contain unsafe
content"): it mentions that a screenshot shows a child's full name. On the two-tasks message, E4B picks
the one that holds the approval; the 12B names both under a vague title.

### e. CI failure explained (5 cases)

| Model | Shape | Checks | Faithful | Useful | False | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 60% | 1/5 | 1/5 | 4/5 | (2.7) |
| Qwen3.5-4B | 100% | 100% | 4/5 | 3/5 | 0/5 | 1.8 (3.4) |
| Gemma 4 E2B | 100% | 80% | 3/5 | 3/5 | 2/5 | **0.7** |
| Gemma 4 E4B | 100% | 93% | 4/5 | 4/5 | 0/5 | 1.5 |
| Gemma 4 12B | 100% | 93% | 4/5 | 5/5 | 0/5 | 4.9 (8.5) |

Not a job for Apple's model: given a log that only waits and exits, it says the log shows the cause and
invents one, three different ways; it blames a test that passed for a job killed by its time limit; it
invents command lines. Gemma E2B says the log shows the cause and gives the exit code, three runs of
three, and states the test's expected and actual values the wrong way round. Qwen, E4B and the 12B say
the log does not say why (E4B gave the exit code as the cause once in three), name the time limit, and see that the lint job failed on the network during
`npm ci`. Since the first pass, Dever has built this feature on Apple's model with checks in code that make
up for these faults (the mentions-and-ci work, `FailureExplanation.swift`); these results are for the
model alone.

### f. Issue summary (3 cases)

| Model | Shape | Checks | Faithful | Useful | False | Time |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | 100% | 89% | 1/3 | 0/3 | 1/3 | (3.6) |
| Qwen3.5-4B | 100% | 100% | 2/3 | 2/3 | 0/3 | 3.0 (5.9) |
| Gemma 4 E2B | 100% | 89% | 1/3 | 1/3 | 0/3 | **1.0** |
| Gemma 4 E4B | 100% | 100% | 2/3 | 3/3 | 0/3 | 2.4 |
| Gemma 4 12B | 100% | 100% | 3/3 | 3/3 | 0/3 | 9.0 (15.8) |

Apple's model pastes the last comments instead of summing up, and on the issue with two approaches it
states the reverse of where the comments end. Qwen writes "the team decided" of a choice still waiting for
objections. E4B and the 12B write "leans toward" and who confirms by when; E4B once adds a detail that
belongs to the other approach; E2B once gives, for the reversed decision, the option that was rejected.
The 50-comment issue (8,600 characters, about 2,500 tokens) took, on mains power, Gemma E2B 1.4 s, Gemma
E4B 4.5 s, Qwen 6.0 s and Gemma 12B 20.6 s.

### All jobs

| Model | Shape | Checks | Faithful | Useful | Unusable | False | Time, median | 9 in 10 under |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple | 97% | 65% | 15/31 | 4/31 | 11/31 | 9/31 | (2.4 s) | (4.5 s) |
| Qwen3.5-4B | 99% | 73% | 21/31 | 13/31 | 5/31 | 5/31 | 1.8 s (3.5 s) | 3.5 s (5.9 s) |
| Gemma 4 E2B | 100% | 80% | 20/31 | 10/31 | 3/31 | 6/31 | **0.7 s** | **1.1 s** |
| Gemma 4 E4B | 100% | 83% | 25/31 | 22/31 | 3/31 | 2/31 | 1.5 s | 2.6 s |
| Gemma 4 12B | 100% | 95% | 29/31 | 25/31 | 1/31 | 0/31 | 5.5 s (9.7 s) | 9.3 s (15.9 s) |

**Where E4B and 12B differ:** the two catch-ups where nothing is asked (b2, b4), the bolder reply (c5),
the kind of a risk and of a request for a decision (a3, a7), and four single-run slips. Everywhere else
they give the same answer.

**Where E2B falls from E4B:** priorities (medium for a plain bug, high for a message with no word on
urgency), the CI log that does not say why, the expected and actual values of a test, the language of
the answer (English for French messages in a6 and a8), and issue titles that read the wrong way ("Block
school subscription renewal", "Reject screenshot number three"). It is no worse at the replies and is
better than E4B at the kind of a message (a3, a7). The fall is not gradual: from E4B to E2B the useful
cases halve, from 22 to 10, while from the 12B to E4B they go from 25 to 22.

**Shape.** Apple's three malformed answers are the three guardrail refusals. without any grammar, Qwen
produced two answers in 186 that were not the asked object, Gemma 12B one in 186, Gemma E4B and E2B none. Both Gemma often wrap their JSON in a code fence, which a parser strips and guided generation
would prevent.

**Repeating the instructions.** None of the models repeated an example or a phrase of the instructions as
if the input had said it; the instructions hold no example sentence, which is the lesson of the first day.

**French and English.** No model is clearly worse in one language. Apple's weakest summaries are French
(a4, a5, a8); Qwen answered one French case in English once; Gemma 12B misspelt one French word once.

**Stability.** The three Gemma gave the same answer, nearly word for word, in the three runs of most cases;
Apple's model and Qwen changed their reading of a message from one run to the next (a3, a8, e1, f1).

## 5. A few raw outputs, side by side

**a2, a QA report: "21 criteria pass, 3 fail… APP-612 should be fixed before the release; the other two can follow."**

- Apple: *Problem* — "APP-612: the streak counter is not refreshed after the device changes time zone; it should be fixed before the release."
- Qwen: *Update* — "QA-41 report shows 21/21 criteria pass, with APP-612 fixed before release and APP-615, APP-618 following."
- Gemma E2B: *Problem* — "The final QA report for QA-41 shows three failures related to reading streaks, and APP-612 should be fixed before the release."
- Gemma E4B: *Update* — "QA-41 shows APP-612 needs fixing before release, while APP-615 and APP-618 can follow."
- Gemma 12B: *Update* — "QA-41 report shows three failures, with APP-612 needing a fix before the release."

**b2, fifteen messages in which nothing is asked of the reader (one message asks Robin for a list, and Robin says yes).**

- Apple: asked: "send [6]" · open: "The retry fix for the sync queue is not merged. [2]"; "The changelog with the three fixes of this week is not updated. [10]"
- Qwen: asked: nothing · open: "Robin needs to send Priya the list of schools on the old plan. [6]"; "The team must confirm the sprint review schedule with the new time. [4]"
- Gemma E2B: asked: "Send list of schools on the old plan [6]" · open: "The list of schools on the old plan is pending [7]"
- Gemma E4B: asked: "Send the old plan school list [6]" · open: "The pilot schools confirmed the demo for Thursday at 11am. [12]"
- Gemma 12B: asked: nothing · open: nothing

**d2, « Alors là il faut vraiment qu'on s'en occupe !!! … Ce serait bien de corriger ça avant la release si on peut. »**

- Apple: "Corriger le bouton exporter sur Résultats" — **urgent** — the message copied as the description
- Qwen: "Corriger le bouton Exporter invisible sur l'écran Résultats" — **high** (urgent in one run)
- Gemma E2B: "Corriger bouton Exporter gris clair" — **high**, three times
- Gemma E4B: "Rendre bouton Exporter visible sur écran Résultats" — **none** — "Sur la console des enseignants, le bouton « Exporter » de l'écran Résultats est difficilement visible. Il est écrit en gris clair sur fond blanc. Trois enseignants en ont parlé pendant la démo."
- Gemma 12B: "Modifier la couleur du bouton Exporter" — **none** — "Le bouton « Exporter » de l'écran Résultats sur la console des enseignants est écrit en gris clair sur fond blanc. Il est difficile à voir et a été signalé par trois enseignants."

**e3, a deploy log that uploads, waits four times, then "Process completed with exit code 1".**

- Apple: log shows the cause — "The test `./scripts/deploy-preview.sh pr-2207` on file `pr-2207` failed with `upload` command: `Uploading 214 files to preview storage`"
- Qwen: log does not show the cause — (no explanation)
- Gemma E2B: log shows the cause, three times — "The job failed because the process completed with exit code 1 during the step "Waiting for environment to become ready"."
- Gemma E4B: log does not show the cause, two runs of three; the third: "The job failed during the deployment process because the script exited with code 1."
- Gemma 12B: log does not show the cause — "The log does not say why."

**f1, an issue with two fixes debated; the last comment: "I lean towards A in 3.4.1… any objection? If none by Wednesday noon I confirm."**

- Apple: "B is selected for 3.4; A is planned for 3.5." · to settle: "Schools are closed next week (holidays), so a night window is easy to get then, but that is after the 3.4 release on the 28th."
- Qwen: "The team decided to fix the streak counter in 3.4.1 by storing UTC timestamps and converting to local time zones." · to settle: "The decision to ship fix A in 3.4.1 needs confirmation by Wednesday noon to inform Noor."
- Gemma E4B: "The team leans toward implementing fix A (UTC timestamp) in version 3.4.1, rather than fix B in 3.4, to avoid doing the work twice." · to settle: "Sam and Malo must confirm their agreement on using fix A in 3.4.1 by Wednesday noon."
- Gemma 12B: "The team is leaning toward implementing fix A in version 3.4.1 to avoid doing work twice." · to settle: "Inès will confirm the decision if Sam and Malo have no objections by Wednesday noon."

**c2 and c5, "Sam, what do you think: faster sync before the release, or document the delay?" (the thread says the cache layer is not to be changed before 3.4).**

- Dever's instructions, all five models: "I'll look into both options and get back to you."
- Bolder instructions, Apple: "Making the sync faster is less risky than documenting the delay, because the cache layer is involved."
- Bolder instructions, Qwen: one run of three takes the side; another: "I'll look at both options."
- Bolder instructions, Gemma E2B: "Documenting the delay is the current plan because changing the cache layer is not something we are changing before the 3.4 release."
- Bolder instructions, Gemma E4B: "The thread suggests documenting the delay in the help page, as changing the sync speed requires touching the cache layer, which is reserved for the 3.4 release."
- Bolder instructions, Gemma 12B: "We should document the delay since we agreed not to touch the cache layer before the 3.4 release."

## 6. What each model costs the machine

Open models on mains power, battery figures in brackets; Apple on battery and Low Power Mode.

| | Apple system model | Qwen3.5-4B | Gemma 4 E2B | Gemma 4 E4B | Gemma 4 12B |
| --- | --- | --- | --- | --- | --- |
| Disk | system asset, shared with macOS | 2.99 GB | 3.3 GB | 5.06 GB | 6.61 GB |
| Download (here, fast line) | none | 43 s | 50 s | 69 s | 77 s |
| Load into memory | none in the app | 1.5 s | 2.2 to 2.5 s | 2.6 to 2.9 s | 3.7 to 3.9 s |
| First answer after a load | (2.5 s) | 1.5 s | 0.9 s | 1.1 s | 4.8 s |
| Memory after load (process footprint) | 11 to 23 MB in the calling process | 2.76 GB | 2.90 GB | 4.42 GB | 6.81 GB |
| Peak while generating | not measurable | 3.3 GB typical, 3.9 GB longest | 3.1 GB typical, 3.4 GB longest | 4.7 GB typical, 4.8 GB longest | 7.1 GB typical, 7.9 GB longest |
| Held when idle for 30 s | nothing in the app | 2.72 GB, all of it | 2.96 GB, all of it | 4.51 GB, all of it | 7.21 GB, all of it |
| After unloading | — | 0.17 GB | 0.27 GB | 0.26 GB | 0.27 GB |
| Load again, then answer | — | 1.7 s, then 1.9 s | 2.5 s, then 1.0 s | 2.9 s, then 1.7 s | 3.9 s, then 6.9 s |
| Reading the input | — | 460 tokens/s (270) | 2,900 tokens/s | 780 tokens/s | 146 tokens/s (91) |
| Writing the answer | (about 65 tokens/s, estimate) | 77 tokens/s (40) | 105 tokens/s | 61 tokens/s | 28 tokens/s (14) |
| Context | 4,096 tokens | 262,144 | 128,000 | 128,000 | 256,000 |

- **Mains power doubles the speed** of the two models measured both ways: Qwen from 40 to 77 tokens/s
  written, the 12B from 14 to 28. Apple's model probably gains too; not measured.
- **Gemma E2B and E4B are fast for their size** because they compute with about 2 and 4.5 billion
  parameters while their files hold about 5 and 8 billion (per-layer embeddings looked up, not
  multiplied). Their memory follows the file: E4B takes 4.4 to 4.8 GB, more than Qwen3.5-4B; E2B about
  as much as Qwen, 2.9 to 3.4 GB.
- **Apple's model does not live in the app.** It runs in a system service
  (`TGOnDeviceInferenceProviderService`), which `top` showed at about 0.7 GB over two processes while
  generating and at 17 MB each a few minutes after the run: the system loads and unloads it itself.
  Those figures probably leave out weights mapped from disk; its true memory could not be measured.
- **An MLX model lives in Dever's process** and holds its memory until it is unloaded. Unloading works
  and gives the memory back at once; loading again costs 3 to 4 s once the file is in the system's file
  cache. The first load after a restart reads the whole file from disk and was not measured.
- **Time before the first token is what the user waits for.** The fixed instructions are 250 to 350 tokens
  of every prompt and were read again each time. Keeping them in a prompt cache would take about 0.1 s
  (E2B) to 2 s (12B) off each answer; not measured.
- **Context.** Apple's 4,096 tokens were enough for every case here, the 50-comment issue included
  (2,462 tokens by Apple's count). Past roughly 13,000 characters of issue they would not be. For the
  open models the limit is time, not room.
- **Energy and heat** were not measured.

## 7. For the product

**Download for a user who says yes in onboarding.** 5.1 GB for E4B, 6.6 GB for the 12B. At 50 Mbit/s:
14 and 18 minutes; at 20 Mbit/s: 34 and 44 minutes (computed). The first attempt of the second pass, on a
shared phone connection, broke after three hours with 1.4 of 6.6 GB received; the files already complete
were kept and the rest came in 77 s on a good line. So the download must resume where it stopped, run in
the background, and never hold the onboarding: the question is asked, the app goes on, the features
appear when the model is ready, as they do today when Apple's model becomes ready.

**Memory on a Mac with 8 GB.** Neither E4B nor the 12B should run: E4B's 4.4 to 4.8 GB is more than half
the machine, the 12B is the whole of it. E2B (about 3 GB) would fit if loaded only for an answer, but its
answers are not good enough to justify it (section 4). Apple's model is the only one that costs such a Mac
nothing.
*Inferred from the memory measured here; no 8 GB Mac was tested.*

**Memory on a Mac with 16 GB.** E4B is workable: 4.5 GB while loaded, released after an idle time. The
12B takes half of the machine and would need to be loaded for each use and unloaded right after; with a
simulator or containers running, the system will compress and swap during a generation. *Inferred.*

**Speed on an older or smaller Mac.** The test Mac has 32 GPU cores; a MacBook Air M1 or M2 has 7 to 10
and a sixth to a quarter of the memory bandwidth. Generation speed on Apple Silicon follows those two.
*Inferred:* on an M1 or M2 Air, E4B near 12 to 20 tokens/s (an answer in 3 to 6 s), the 12B near 5 to
8 tokens/s if it fits at all (an issue summary in 40 to 90 s). On an M3 Pro or later, both should be at
or above what this Mac gave. None of this was measured.

**Shipping and updating the model.** The weights are not in the app. On a yes, Dever downloads a pinned
revision (a commit hash, with the files' checksums) either from Hugging Face directly or from a copy Dever
hosts; both are allowed by the licence, and the copy removes a dependency on a third party's repository
staying up and unchanged. A Dever-made conversion could also drop E4B's audio and vision weights, which
Dever does not use (how much that saves was not measured). Files go under Application Support, excluded
from backups, checked before use, removable from Settings. A model update is a new pinned revision shipped
with an app release: download the new one, check it, switch, delete the old one, and rerun the prompts'
tests, because a new model is a new behaviour. The runtime (`mlx-swift-lm`) updates with the app.

**What the user must be told,** before the download and in Settings › Intelligence: the size and where
it comes from; that it runs on this Mac and nothing leaves it (the download itself is the only request,
and it sends none of their data); that it uses about 4.5 GB of memory while working and releases it when
idle; that it draws power while it writes; that it can be removed at any time; that what it writes may
be wrong, as the mark already says. Rule 3 of on-device-ai.md ("Only the system model") has to be
reworded: the promise that holds is "nothing leaves the Mac".

**What stays impossible whatever the model.**

- *Speaking for the user.* Under "commit to nothing" every model writes "I'll look and come back". A
  bolder instruction gives a useful draft with the 12B, and that draft takes a position in the user's
  name: whether Dever should do that is a product decision, not a matter of model size.
- *Knowing what the text does not say:* whether a request was already handled elsewhere, who owns a
  screen, how urgent something is for the business. Gemma gets priority right by answering "none"
  unless the message says otherwise, which is the instruction, not judgement.
- *Being right every time.* The best model made a slip in about one answer in fifty. The mark, the link
  to the source, the checks in code and "never in place of facts" stay.
- *Telling who a request is for, below 12 billion parameters.* E4B, like Apple's model, takes a task asked
  of someone else in the channel for the reader's. Dever already does this in code
  (`MessageSummary.isForReader`), and should keep doing so whatever the model.

## 8. Options

**A. Keep Apple's model only.**

- For: no download, no memory in the app, no new dependency, already built, runs on 8 GB Macs, Apple
  updates it.
- Against: 4 cases of 31 fully useful and 9 with false statements; the long-message summaries it does
  today are the weakest of the five models on hard messages; issue summary is out of its reach (0 of 3);
  pipeline failure needs checks in code to hide its inventions; a guardrail that refuses ordinary work
  messages; Apple Intelligence required, with states such as `modelNotReady` that come back by themselves
  (it did during this benchmark); a model that changes with system updates without notice.

**B. Qwen3.5-4B or Gemma 4 E2B, the small open models.** Both take about 3 GB of memory and would fit an
8 GB Mac loaded for one answer at a time. Both are superseded by Gemma 4 E4B: Qwen is slower (1.8 s
against 1.5 s), less faithful (5 false cases against 2) and less useful (13 against 22); E2B is twice as
fast as E4B but useful in 10 cases of 31 and false in 6, with priorities and CI explanations that cannot
be trusted. For 2 GB more disk and 1.5 GB more memory, E4B is the better buy. Not considered further.

**C. Gemma 4 E4B, opt-in, beside Apple's model (recommended).**

- For: 22 of 31 fully useful, 2 with false statements, both in the catch-up; issue summary, pipeline
  failure and issue from a message all work; better one-message summaries than Apple's model; the smallest
  model measured whose answers hold (one step down, E2B halves the useful cases); fast (1.5 s median, 2.6 s for nine answers in ten, 4.5 s on a 50-comment issue); 4.5 GB of
  memory, which a 16 GB Mac can spare; no guardrail; macOS 14, no Apple Intelligence needed.
- Against: 5 GB to download, 4.5 GB of memory while loaded, so not for 8 GB Macs; the catch-up still
  fails on channels where nothing is asked; a second model to test prompts against; the build measured
  carries a wrong licence label (section 2).

**D. Gemma 4 12B, opt-in, beside Apple's model.**

- For: the best answers: 25 of 31 fully useful, no false case; the only model that gets the catch-up
  right, which would bring back a dropped feature.
- Against: 6.6 GB and 7 to 8 GB of memory, so only comfortable from 24 GB; three to four times slower
  than E4B (5.5 s median, 21 s on the long issue on mains power; twice that on battery); for every job
  but the catch-up, the gain over E4B is a few single-run slips.

**E. E4B and 12B, the user choosing.** E4B by default, the 12B offered on Macs with 24 GB or more, for the
catch-up. It doubles the download paths, the tests and the wording in Settings for one feature that was
dropped; worth it only if the catch-up becomes a priority again.

## 9. Recommendation

**Option C: Gemma 4 E4B through `mlx-swift-lm`, opt-in, on Macs with 16 GB or more, beside Apple's model.**

1. "Local Intelligence" is a question in onboarding and a row in Settings › Intelligence: it downloads
   Gemma 4 E4B (5.1 GB) in the background, resumable. Not offered under 16 GB of memory.
2. On it, in this order: **issue summary** (3 of 3 useful here, out of reach of Apple's model);
   **pipeline failure**, moved from Apple's model, keeping the checks in code; **long messages**, moved
   from Apple's model when Local Intelligence is installed (6 of 8 useful against 1 of 8, and faster);
   then **issue from a message** again, on real channels (5 of 5 here).
3. Where Local Intelligence is off or cannot run, Apple's model keeps the long messages and the pipeline
   failure as today.
4. The catch-up stays dropped. If it becomes a priority again, it needs the 12B (option E), on Macs with
   24 GB or more. The reply draft stays dropped whatever the model.
5. The model is loaded on first use and unloaded after a short idle time; one generation at a time, as today.

**What it would cost to build** (estimates, not measured):

| Piece | Work | Estimate |
| --- | --- | --- |
| Build | `mlx-swift-lm` as a dependency; MLX's Metal shaders are not built by `swift build`, which `scripts/build-app.sh` uses: an `xcodebuild` step or a prebuilt shader library; app size, signing | 1 to 2 days, the main unknown |
| Model client | a second `LanguageModel` behind the existing protocol; output forced to a JSON Schema with `MLXGuidedGeneration` (or `MLXFoundationModels` on macOS 27, reusing the `@Generable` types); load, unload on idle, prompt cache for the instructions; routing per feature | 2 to 3 days |
| Model store | download with progress and resume, pinned revision and checksums, disk-space and memory checks, removal; its states in Settings › Intelligence and the onboarding question; rows in data-freshness.md | 3 to 4 days |
| Issue summary | feature 5.5 of on-device-ai.md on the new client | 2 days |
| Long messages and pipeline failure | routing the two built features to the new client, and their prompts tested on it | 1 to 2 days |
| Tests | this test set turned into real-model tests for the new client; a rerun at every model update | 1 to 2 days |

About two and a half to three weeks. **Before building,** one cheap check removes the main doubt: a
50-line Swift command-line tool on `mlx-swift-lm` with guided generation and Gemma 4 E4B, to confirm the
Swift package loads this model and gives what the Python one gave.

## 10. What was not measured

- **Apple's model on mains power.** It was not ready on the days of the second pass (Siri's language).
  Its times are from battery and Low Power Mode, where the open models ran at half their mains speed.
- **The Swift package.** Measured with `mlx-lm` (Python). Same framework and model files; the Swift
  package, its guided generation and its Foundation Models bridge were read about, not run. Open reports
  mention load errors for some Gemma 4 E4B builds in MLX; the build measured here loaded and ran in Python.
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
- **One grader, 31 cases, three runs each.** The gaps between Apple, Qwen and the Gemma models are wide
  enough to survive a second grader; the gap between E4B and the 12B (22 against 25) is not, outside the
  catch-up.
- **Other candidates.** Qwen3.5-9B, and 6- or 8-bit builds (which might lift E2B), were not run.
