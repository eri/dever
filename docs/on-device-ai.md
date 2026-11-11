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
| Long messages as summaries | Slack rail, in the place of each message the rail cuts | automatic, newest first |
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
4. **Silent rather than inventive.** Too little material, a refusal, a guardrail or an error: no generated text at all and no error message; the screen is the one of today.
   No system notification is ever built from generated text or triggered by a model's judgement.
   An input too long to read whole is read in part only where the feature says which part and the
   text says what it covers; otherwise it is silence too.
5. **Always marked, always traceable** (section 4).
6. **Raw data first.** A generated text is added above or beside what it describes; the messages, the
   description and the comments stay where they are, readable at once, and never wait for the model.
   One exception, decided on the first real use: in the rail, where a long message is already cut at
   four lines, its summary takes the place of the cut (5.7). The message shows first and is replaced
   when the summary is ready; "Show original" brings it back in full; the room always shows messages.
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

A summary that stands in the place of a message (5.7) is the one generated text in a block of its own
(`SummarisedMessage`: ground tone, hairline edge, the sparkle and the kind of message), so that it is
never taken for the message.

```
✦ → Your answer on the front end is awaited before noon.   ↗
  The migration breaks billing; the CSV export leaves the release.
```

## 5. Features

Each feature gives its data contract when it is implemented (the template of
[data-freshness.md, section 7](data-freshness.md#7-checklist-for-every-feature)); the lines below are
the parts already decided.

### 5.1 Slack catch-up (dropped)

A block above the unread messages of the rail that sums up the channel. Built four ways, tried on real
channels, and removed:

1. Free text in two labelled lines: malformed one time in two.
2. Guided generation over the raw messages: vague or false sentences, an example of the instructions
   repeated as if the channel had said it, the author of a request taken for its target.
3. The same over the summaries of the messages: better, still not trusted.
4. A list put together by Dever from the message summaries, with no writing of its own: reliable, but
   it said again what the summaries under it already said.

What stays of it: the summaries message by message (5.7), which is where the model does well, and the
arrow on a summarised message that asks something of the user. Lessons kept for the next features: one
small task at a time, guided generation, no example in the instructions (the model repeats it), and a
check in code for anything the model gets wrong in a known way.

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

- **Where:** "Create an issue" in the ⋯ menu of a Slack message, when the project has a Linear project.
- **What:** a sheet with title, description and priority, every field editable. It opens at once with
  the message as its description; when the model is there, "Reading <author>'s message" shows while it
  writes, then the fields are filled and the line reads "✦ Filled from <author>'s message". The mark goes
  as soon as the user types over the text. If the user has started to type before the model answers,
  the proposal is dropped.
- **"Create"** creates the issue in the project's Linear project, in the team's default state, with a
  link to the Slack message at the end of the description. The mark does not go to Linear.
- **Title:** an action that starts with a verb, ten words at most (`IssueDraft`, guided generation).
- **Priority is checked, not trusted:** the model read "to fix before the release" as Urgent. Its
  priority is kept only when the message has a word for urgency (`IssueDraft.saysHowUrgent`: urgent,
  blocking, bloquant, critical…); otherwise None, for the user to set.
- **Without the model** (or with its switch off): the same sheet, the message as description, an empty
  title. The feature is a write path of its own; the model only fills it.
- **Write:** `IssueStore.create` → `issueCreate`. Not optimistic: an issue has no identifier to show
  before Linear answers, so the button reads "Creating" and the sheet stays until it does. On success
  Linear's row is put first in the project's list (`IssueStore.insert`), so the Delivery board follows at
  once; on refusal the sheet stays, with the reason, nothing changed.
- **Language:** the language of the project's issue titles, detected on the Mac; English when unknown.
- **Measured:** 2.4 to 3.7 s for a draft.

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

### 5.7 Long messages as summaries

- **Where:** the Slack rail, in the place of each message it would cut ("Show more", over 240
  characters). Not in the room, not for short messages.
- **When:** by itself, for the messages the rail shows, the newest first, one at a time. The original shows until the summary is ready, with a line under it ("Summarising", the
  sparkle breathing) so that the swap is expected; then the block takes its place.
- **What:** the kind of message at the head of the block and one sentence of at most 20 words that
  stands on its own: who or what it is about, then what is asked, wrong, decided or announced. Names,
  numbers and ticket identifiers kept. Guided generation; the kind is chosen after the sentence.
- **Asked of the user:** a lime arrow before the kind when the message is a Request or a Question and
  names the user, with an @ or by a word of their name (`MessageSummary.isForReader`). Read from the
  message, not asked of the model.
- **Kinds,** by what the message expects of its readers: **Request** (someone is asked to do, send,
  check, fix or decide), **Question** (an answer or an opinion is asked for), **Problem** (something is
  wrong, slow, failing, late or to fix, and no one in particular is asked), **Update** (the rest:
  progress, news, a decision, a welcome). The first three show in ink, Update muted. "Decision", "Warning"
  and "Info" were tried first: the model filed almost everything under Decision, and Info said nothing. Never more than 180 characters: whole sentences are kept
  as far as they fit. "Show original" opens the message in full, "Show summary" goes back.
- **Folded with it:** the link previews of the message, which come back with the original. Pictures,
  files, reactions and the thread link stay under the summary.
- **Not shown:** a summary that is not clearly shorter than the message (over 70% of its length), whose
  first sentence alone passes the limit, or that is empty or refused.
- **Wording of the instructions is copied:** "something is wrong", used to define a Problem, came back
  as the summary of a QA report ("…validation: something is wrong."). The kinds are defined with nouns
  (a bug, a failure, a delay, a risk) and the sentence must name the bug or the request itself.
- **Wording matters:** asked for a "blocked" case or for a telegraphic style, the model wrote "SUP-931
  blocks the release" of a message that said nothing blocked. The instructions ask for full sentences
  and for no statement stronger than the message's.
- **Reads:** the message already in `SlackStore`. Derived data keyed by channel, message and text (an
  edit is another version), in `IntelligenceStore`, memory only. No network request.
- **Measured:** 1.2 to 2.7 s for a 700-character report.

## 6. Settings › Intelligence

A new page between Notifications and Launch, built like the others (`SectionHead`, `SettingRows`,
`SettingRow` with a switch). No master switch: one per use, all on by default.

```
Intelligence
Runs on this Mac. Nothing leaves it.

Summaries
  Long messages                         [on]
  Detected mentions  @✦                 [on]
  Issue summary                         [on]
  Language            [ Source | English ]
Writing
  Issue from a message                  [on]
  Draft a reply                         [on]   (not built yet)
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
  could run the model but it is off or not ready: what Dever would do here (shorten long messages) and
  a link to System Settings. Dismissed once, never shown again.
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
| 1. Slack catch-up | **Dropped** after four forms on real channels (5.1). | 0 |
| 1b. Long messages | **Built:** 5.7, with kinds and the arrow for what is asked of the user, tuned on real channels. | 0 |
| 2. Writing | **Built:** issue creation and its sheet (useful without the model) and its filling (5.3). **Left:** the reply draft (5.4); the onboarding line "never posts on your behalf". | 0; the sheet itself depends on nothing |
| 3. Issue summary | 5.5. | 0 |
| 4. Pipeline failure | job and log reads, then 5.6. | 0 |

Each phase updates data-freshness.md (a budget row for each new kind of data in section 4, the new exits
in section 5) in the same change.

## 10. Open points

- **Thresholds.** 6 unread messages and 1,500 characters are starting points, to adjust on real channels.
- **Long catch-ups.** Settled for now by reading the newest unread and saying what is covered (5.1).
  Loading older unread messages and summarising in chunks stays possible; measured cost is 5 to 8 s per
  chunk of 2,000 to 3,500 tokens.
- **Why nothing shows.** `log show --predicate 'subsystem == "io.github.eri.dever" AND category == "intelligence"'`
  gives the reason for each catch-up written or not: counts and causes, never a message's words.
- **Threads.** The catch-up reads the channel's unread messages, not the new replies inside threads
  (only opened threads are loaded). A busy thread is where decisions are made; loading unread replies
  for the catch-up costs one request per thread and needs its own budget row.
- **Detected mentions with no name.** "He wrote that screen, he should look" needs the thread around
  it and will produce false positives; the rate has to be looked at on real channels before 5.2 reaches
  the Overview.
- **Onboarding wording.** A tooltip says Dever "never posts on your behalf" while thread replies post
  as the user; issue creation adds a second write. To be reworded with phase 2.
