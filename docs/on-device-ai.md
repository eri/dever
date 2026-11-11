# On-device intelligence

How Dever uses the language model that ships with macOS (Apple Intelligence, the Foundation Models
framework): what was decided, what was checked on a real Mac, the rules every generated text follows,
and the order of work. Nothing here is built yet.

Contents: [scope](#1-scope) · [feasibility](#2-feasibility) · [rules](#3-rules) ·
[the mark](#4-the-mark-and-the-source) · [features](#5-features) · [settings](#6-settings--intelligence) ·
[unavailable, slow, failing](#7-unavailable-slow-failing) · [architecture](#8-architecture) ·
[plan](#9-plan) · [open points](#10-open-points)

---

## 1. Scope

The time lost today is in three places: **catching up on Slack**, **writing** (a reply, an issue), and
**understanding an issue or a failed pipeline**. "Knowing where to start" is not a problem: the Delivery
board already answers it.

| Kept | Where | Trigger |
| --- | --- | --- |
| Slack catch-up | Slack rail of the project page, above the unread messages | automatic, from a threshold of unread |
| Detected mentions | the catch-up, and the "for you" items of the Overview | automatic |
| Issue from a message | ⋯ menu of a Slack message | on demand |
| Draft a reply | thread composer | on demand, one click |
| Issue summary | top of the Linear issue page | automatic, from a threshold of length |
| Explain a pipeline failure | "Start here" tile, pull request chip of the issue page | on demand |

Cut, and not to be brought back without a new decision: morning brief across projects, one sentence per
project in the Overview table, the reason of the "Start here" pick in generated words, "since your last
visit", blockers said in Slack but absent from Linear, thread summary in the thread pane, acceptance
criteria, pull request summary, pull request against issue comparison, semantic matching in project
creation, suggested channel names, grouped notifications, natural-language search, Siri and Shortcuts,
one-click translation.

## 2. Feasibility

Checked on the development Mac (Apple M1 Max, macOS 27.2, SDK 26.5) with a throwaway probe outside the
repository.

| Question | Finding |
| --- | --- |
| Is the framework there? | Yes. `FoundationModels` is in the SDK; `SystemLanguageModel`, `LanguageModelSession`, guided generation (`@Generable`), streaming. Introduced in macOS 26.0; `tokenCount(for:)` in 26.4; `contextSize` back-deployed to 26.0. |
| Is the model usable on this Mac? | Yes, once Siri's language matched the Mac's. It first answered `.unavailable(.modelNotReady)` with no model asset on disk: Siri was in French and the Mac in English, which the system reports as `selectedSiriLanguageIneligible`, and it then asks for no asset at all. Setting Siri to English started the download; the model was ready about 90 minutes later. So `modelNotReady` does not always mean "downloading". |
| Languages | `supportedLanguages` lists French (France and Canada), English, German, Spanish, Italian, Portuguese, Dutch, Danish, Norwegian, Swedish, Turkish, Vietnamese, Japanese, Korean, Chinese. `supportsLocale` is true for `fr_FR` and `en_US`. |
| Context size | `contextSize` is 4,096 tokens, instructions and answer included. A 16-message French thread (1,348 characters) counts 446 tokens: about 3 characters a token, the estimate `TextBudget` uses before macOS 26.4. |
| Speed | On that thread: two-sentence summary 2.4 s (first token after 1.9 s), one line of 12 words 1.3 s, reply draft 2.0 s, guided generation (a digest, an issue draft) 4.6 s, a pipeline log explained 1.2 s. Input size costs: 892 tokens 3.1 s, 1,784 tokens 4.8 s, 2,676 tokens 7.1 s, 3,568 tokens 8.3 s for one sentence out. The catch-up as built (six messages, guided) takes 4 to 5 s. |
| Following a format | Free text in two labelled lines ("YOU: … REST: …") failed one time in two: labels translated or dropped, never "NONE", five sentences where two were asked. Guided generation (`@Generable`) gave the asked shape every time, found a request made in the third person once the instructions spelt that case out, and answered "nothing asked" when nothing was. Structured output is the rule for every feature. |
| Language | Summaries follow the language asked for, French included. Forced translation works but bends jargon ("staging deploy" became "déploiement de la phase de préparation"): only "English" is offered as a forced language. |
| Other frameworks | `NaturalLanguage` (language detection, macOS 14 compatible) is used. `Translation`, `AppIntents` and Writing Tools are not needed by the kept scope. The composer is an `NSTextView`, so the system Writing Tools already work in it with no code. |

Consequences for the design, true whatever the measurements say:

- The app targets macOS 14. Every use is behind `#if canImport(FoundationModels)` and
  `if #available(macOS 26.0, *)`, and behind `availability == .available` at run time. `modelNotReady`
  is a real, lasting state on real Macs (this one), not an edge case.
- 4,096 tokens is small: a catch-up of a few dozen messages fits, a long channel day or an issue with
  fifty comments does not. Each feature states what it does when the input does not fit (section 5).
- One generation at a time: the framework refuses concurrent requests on a session and the chip is shared
  with the system. Requests are queued, the one on screen first.


## 3. Rules

1. **Nothing leaves without you.** A generated text is never sent, created or saved to Slack, Linear or
   GitHub without an explicit act (Return in the composer, "Create" in a sheet). Once sent it is the
   user's text and carries no mark.
2. **Never in place of facts.** Pipeline, review, deploy and preview states, counts, dates, names and
   priorities shown as data are always the raw value. The model may explain beside a fact; it never
   replaces, recolours or reorders one. An explanation of a pipeline failure sits next to the link to
   the real log, never instead of it.
3. **Everything stays on the Mac.** Only the system model. No online AI service, no Slack, Linear or
   GitHub content sent anywhere else, no generated text written to disk (memory only). The wording in
   the app: "Runs on this Mac. Nothing leaves it."
4. **Silent rather than inventive.** Too little material, input too long for the model, a refusal, a
   guardrail or an error: no generated text at all and no error message; the screen is the one of today.
   No system notification is ever built from generated text or triggered by a model's judgement.
5. **Always marked, always traceable** (section 4).
6. **Raw data first.** A generated text is added above or beside what it describes; the messages, the
   description and the comments stay where they are, readable at once, and never wait for the model.
7. **Skeletons, not spinners,** and a generated text never makes content move when it arrives: its
   place is reserved.

## 4. The mark and the source

One sparkle glyph (`sparkles`) before every generated text, the same everywhere, in the muted ink of
secondary text. No tinted block, no "AI" word. Its tooltip and accessible label: "Generated on this Mac.
May be wrong."

Every generated sentence that speaks of a message leads to it: a click opens the room on that message
and lights it, the way arriving from an Overview item does today. A sentence that cannot be tied to a
message is not clickable.

A detected mention uses `@` with the sparkle, where a Slack mention uses `@` alone.

```
✦ → Your answer on the front end is awaited before noon.   ↗
  The migration breaks billing; the CSV export leaves the release.
```

## 5. Features

Each feature gives its data contract when it is implemented (the template of
[data-freshness.md, section 7](data-freshness.md#7-checklist-for-every-feature)); the lines below are
the parts already decided.

### 5.1 Slack catch-up

- **Where:** top of the Slack rail of the project page, above the unread messages.
- **When:** by itself when the channel holds at least 6 unread messages (`CatchUp.threshold`). Below
  that, nothing: reading three messages is faster than reading about them. Replies inside threads are
  not counted and not read by the catch-up yet (open point).
- **Content:** first, only if something asks an action of the user, one line "for you" that leads to the
  message. Then one or two sentences on the rest. No headings, no lists.
- **Language:** the language of the messages (detected with `NaturalLanguage` over the unread), or
  English when Settings says so.
- **Loading:** two skeleton lines beside the sparkle, then the whole text fades in. No word-by-word
  streaming. While newer messages are being summarised the previous text stays.
- **Too long:** no catch-up (rule 4) when the unread messages do not all fit the context, or when some
  of them are older than what `SlackStore` has loaded (20 messages): a catch-up of a part would pass for
  one of the whole. One message counts for at most 600 characters. Chunked summarising is an open point.
- **How:** the unread messages go to the model numbered, with the reader's name; guided generation
  holds the answer to a shape (`CatchUpAnswer`: whether something is asked, what and in which message,
  then one or two other points with their message). `CatchUp.text(from:)` ties the sentences to their
  messages. `DEVER_TEST_REAL_MODEL=1 swift test --filter RealModel` runs it on the real model.
- **Reads:** `SlackStore` messages of the channel, `lastRead` / `seenUpTo`, opened threads, user names.
  **New derived data:** the catch-up, keyed by channel and by the timestamps of the first and last unread
  message, held in an app-lifetime store, memory only. A new message invalidates it; "Mark as read"
  and reading up to the end remove it. No network request.

### 5.2 Detected mentions

Someone speaks of the user, or asks something of them, without a Slack mention.

- **Where:** as the "for you" line of the catch-up, and as a "for you" item of the project in the
  Overview, with the `@✦` glyph and the message one click away. It counts in the "N for you" chip.
- **Never** a system notification (rule 4), and never mixed with real mentions: a different glyph, a
  tooltip that says it is detected.
- **How:** unread messages not written by the user and without an explicit mention are classified
  (guided generation, a boolean and the message it rests on), a few at a time with the thread around
  them, each message once (result kept by timestamp, in memory). The model is given the user's display
  name.
- **Cost:** no network; one short generation per batch of new unread messages, in the background queue
  behind anything on screen.
- **Rule 2 holds:** the count of Slack mentions is unchanged; detected ones are added beside it.

### 5.3 Issue from a message

- **Where:** "Create an issue" in the ⋯ menu of a Slack message.
- **What:** a sheet with title, description and priority filled from the message and its thread, a line
  "✦ Filled from the message of <author>", every field editable. "Create" creates the issue in the
  project's Linear project and puts a link to the Slack message in it; the mark does not go to Linear.
- **Needs first:** issue creation in `LinearClient` (`issueCreate`; team, state and priority from the
  team context `IssueStore` already holds). Today Dever only updates issues.
- **Without the model:** the menu item stays and the sheet opens with the message text as description
  and an empty title: the feature is a write path of its own, the model only fills it.
- **Write:** optimistic row in `IssueStore`, reconciled with the answer, removed on refusal; invalidates
  the project's issue list, the Delivery plan and the Overview counts.
- **Language:** the language of the project's existing issue titles.

### 5.4 Draft a reply

- **Where:** the thread composer. A sparkle button, shown when the field is empty.
- **What:** one click writes a reply in the field from the thread alone, in the thread's language and
  tone. The field shows "✦ draft" until the first edit; ⌘Z empties it. Nothing is sent before Return.
- **Known risk, accepted:** the model takes a position for the user ("yes, I'll look at it"). The draft
  must stay visibly a draft, and the prompt keeps it short and commits to nothing the thread does not
  support.
- **Too long:** the parent and the newest replies that fit.

### 5.5 Issue summary

- **Where:** top of the reading column of the Linear issue page, above the description.
- **When:** by itself when description and comments are long (threshold set after measuring; starting
  point: 1,500 characters or 6 comments). Two lines: where the issue stands, what is left to settle.
- **Reads:** `IssueStore.details`, already loaded. Derived data keyed by issue and `updatedAt`, memory only.
- **Too long:** the description and the newest comments that fit; if the description alone does not
  fit, no summary.
- **Language:** as 5.1.

### 5.6 Explain a pipeline failure

- **Where:** a "✦ Why?" link beside "CI failed on #N" on the "Start here" tile, and on the pull request
  chip of the issue page.
- **When:** on click only. No log is downloaded without it.
- **What:** Dever loads the failed job's name and the tail of its log, then shows the job name (raw),
  one generated sentence, and "Open log ↗". When the log does not say: "The log does not say." The
  red state, the count and the word "failed" are GitHub's (rule 2).
- **Needs first:** two GitHub reads Dever does not make today: the jobs of a run and the log of a job
  (tail only, capped in bytes). Budget and cost rows in data-freshness.md section 4.
- **Kept:** per run id, in memory; a new run drops it. The explanation carries the run's age like any
  pipeline state.

## 6. Settings › Intelligence

A new page between Notifications and Launch, built like the others (`SectionHead`, `SettingRows`,
`SettingRow` with a switch). No master switch: one per use, all on by default.

```
Intelligence
Runs on this Mac. Nothing leaves it.

Summaries
  Slack catch-up                        [on]
  Detected mentions  @✦                 [on]
  Issue summary                         [on]
  Language            [ Source | English ]
Writing
  Draft a reply                         [on]
  Issue from a message                  [on]
Pipelines
  Explain a failure                     [on]
```

- **Language** applies to summaries only: "Source" (default) keeps the language of what is summarised,
  "English" forces English. A segment picker, not a system dropdown.
- A switch turned off removes the feature's interface entirely, and drops what it had generated.
- "Issue from a message" off removes only the filling; the menu item stays.

## 7. Unavailable, slow, failing

| State | Pages | Settings › Intelligence |
| --- | --- | --- |
| macOS before 26, or a Mac that can never run it (`deviceNotEligible`) | nothing | the page does not exist |
| Apple Intelligence off (`appleIntelligenceNotEnabled`) | nothing, plus the invitation once | the reason in one sentence, "Open System Settings ↗" |
| Model not there (`modelNotReady`: downloading, or held back by the system, for instance when Siri's language and the Mac's differ) | nothing, plus the invitation once | "Apple Intelligence is not ready on this Mac yet. Dever will use it when it is.", "Open System Settings ↗". Never "downloading": the API does not say why. |
| Available | features on | as section 6 |

- **The invitation:** one quiet line at the top of the Slack rail, the first time only, when the Mac
  could run the model but it is off or not ready: what Dever would do here and a link to System
  Settings. Dismissed once, never shown again.
- **Slow:** skeleton lines in the reserved place; the content under it is usable at once.
- **Failing** (refusal, guardrail, context exceeded, rate limit, unsupported language): rule 4. The
  place closes without a message; the next change of the input may try again, the same input does not.
- Availability is observed (`SystemLanguageModel` is `Observable`): features appear when the model
  becomes ready, without a relaunch.

## 8. Architecture

- `Services/Intelligence.swift`: the only file that imports `FoundationModels`. Availability as a small
  enum the rest of the app can read on macOS 14; a serial queue with two priorities (on screen,
  background); one function per use, each with its instructions, its `@Generable` output and its input
  budget. Token counts with `tokenCount(for:)` where it exists, a character estimate before 26.4.
- `Model/IntelligenceStore.swift`: app-lifetime, memory only. Holds catch-ups, detected mentions, issue
  summaries and failure explanations by key; views read it, never call the model (rule 1 of CLAUDE.md).
- Prompts are English instructions that name the output language; inputs are plain text
  (`SlackPlain.text`), with authors' display names, never ids.
- Views: one `GeneratedMark` and one `GeneratedText` component (sparkle, tooltip, skeleton, fade through
  `Motion`), links through the existing button roles.
- Tests in `Tests/DeverTests`: thresholds, keys and invalidation, input budgeting and truncation, what
  each failure does. The model itself is behind a protocol so tests run without it.
- Snapshots: `DEVER_SNAPSHOT_INTELLIGENCE=available|notReady|off|unsupported` stands in for the system's
  answer and shows every feature's interface, built or not, so captures need neither the model nor the
  network. With `DEVER_SNAPSHOT_GALLERY=1` it also writes `generated-{dark,light}.png`: the marks, a
  text being written, a written one, the invitation.
- `IntelligenceFeature.built` lists the features that exist. A feature not in it has no switch, no
  interface and no invitation, and Settings › Intelligence is not listed while the set is empty: the
  ground can ship before any feature does.

## 9. Plan

| Phase | Content | Depends on |
| --- | --- | --- |
| 0. Ground | **Done.** `Intelligence` service and availability gating, `IntelligenceStore`, the mark and the generated block, Settings › Intelligence, the one-time invitation, snapshot states, tests, measurements (section 2). | |
| 1. Slack catch-up | **Built:** 5.1 in the rail, with its "for you" line (the first form of 5.2), tuned on the real model. **Left:** look at it on real channels; 5.2 as `@✦` items in the Overview. | 0 |
| 2. Writing | `issueCreate` and the sheet (useful without the model), its filling (5.3), then the reply draft (5.4). | 0; the sheet itself depends on nothing |
| 3. Issue summary | 5.5. | 0 |
| 4. Pipeline failure | job and log reads, then 5.6. | 0 |

Each phase updates data-freshness.md (a budget row for each new kind of data in section 4, the new exits
in section 5) in the same change.

## 10. Open points

- **Thresholds.** 6 unread messages and 1,500 characters are starting points, to adjust on real channels.
- **Long catch-ups.** The days with the most unread are the ones where a catch-up helps most and the
  ones least likely to fit 4,096 tokens. Summarising in chunks and then summarising the chunks is
  possible but multiplies the time; decide after measuring.
- **Threads.** The catch-up reads the channel's unread messages, not the new replies inside threads
  (only opened threads are loaded). A busy thread is where decisions are made; loading unread replies
  for the catch-up costs one request per thread and needs its own budget row.
- **Detected mentions with no name.** "He wrote that screen, he should look" needs the thread around
  it and will produce false positives; the rate has to be looked at on real channels before 5.2 reaches
  the Overview.
- **Onboarding wording.** A tooltip says Dever "never posts on your behalf" while thread replies post
  as the user; issue creation adds a second write. To be reworded with phase 2.
