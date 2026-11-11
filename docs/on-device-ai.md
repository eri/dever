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
| Detected mentions | the "for you" items of the Overview | automatic, by name, without the model |
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
   four lines, its summary takes the place of the cut (5.7). The block is there from the start, with
   the first two lines of the message in it until the sentence is written; "Show original" gives the
   message in full at any moment, written or not; the room always shows messages.
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
never taken for the message. The block holds its place before the summary exists: "Summarising" at its
head and the start of the message in muted ink, at the height the sentence will take, so that nothing
in the rail moves when it lands (rule 7). The sparkle breathes, in lime, on the one summary the model
is writing and nowhere else; VoiceOver hears "Summary, Request, asked of you: …", the caveat as the hint.

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

**Built.** An unread message that speaks of the user by name without a Slack mention shows among the
project's "for you" items in the Overview.

- **Where:** a "for you" item of the project, after the Slack mentions and the review requests, with
  the `@✦` glyph and the message one click away, like a mention. It counts in the "N for you" chip and
  leaves the "N more unread" line.
- **Never** a system notification (rule 4), and never mixed with real mentions: its own list in the
  snapshot (`SlackStats.detected`), its own glyph in muted ink, a tooltip and an accessible name that
  say it is detected and may be wrong. A message that carries a real mention of the user is never
  detected too.
- **How: in code, with no model** (`DetectedMention`). The model cannot be trusted to say who a message
  is about (9b), so nothing is asked of it. A message is kept when its prose holds a word of the user's
  display name as a whole word, whatever the case and the accents:
  - words of three letters or more; initials and particles do not count;
  - a word another person of the workspace also carries names no one (two people called Sam: "Sam"
    is dropped, the family name still counts); bots do not count as people;
  - prose only: mentions of others, channels, links, addresses, inline code and code blocks are
    removed first, so a name in a branch, a URL or a command is not a mention;
  - a name that is also a common English or French word (a short fixed list: Will, Mark, Rose, Max,
    Pierre…) counts only with its capital, and at the head of a sentence only when it is called out
    ("Will, can you…"). "Will you merge?", "Mark this as done" and "it will break" name no one.
- **What it misses, by choice** (silent rather than inventive): a common-word name written without
  its capital ("pierre tu regardes ?") or heading a sentence without a comma ("Mark knows the billing
  code"); a nickname that is not a word of the display name; "he wrote that screen, he should look",
  which names nobody. What it still gets wrong: a month or a word with a capital in mid-sentence for
  someone called June or Rose, and a message that speaks of the user without asking anything
  ("Sam fixed that yesterday").
- **Checked and not used:** the system's spelling dictionary takes "sam", "tom" and "martin" for
  ordinary words, and the system's word tagger (`NLTagger`) reads a first name written without its capital at the head
  of a French sentence as a pronoun and the one in "Will, can you review?" as a verb. Neither can tell a name from a word.
- **The model as a filter, measured and not used so far.** Keeping only the messages the model files
  as Request or Question (the kinds of 5.7) was measured on the real model with 20 invented short
  messages that name the reader, French and English, twice each
  (`RealModelTests.testKindOfShortMessagesThatNameTheReader`): 36 of 40 right, 1.4 to 3.5 s a message.
  One real request was dropped in one pass of two ("On attend le retour de Sam sur le front pour
  merger" came back as Problem, then as Request), and three plain statements were kept ("Sam a déjà
  mergé la PR, on peut tester" as Request both times, "Sam is off tomorrow, I'll cover the release"
  once). The same message does not always get the same kind, and the kind says that something is
  asked, not that it is asked of the reader.
- **Follows the read cursor:** reading the channel in Dever removes them in place (`slackRead`), like
  mentions.
- **Switch:** "Detected mentions" in Settings › Intelligence. Off, these messages are unread messages
  like the others. The switch lives on that page, so the feature shows only where the page does (the
  model available), although it does not use the model.
- **Data contract.** Reads: the unread messages and the members' names the Overview's cycle already
  holds (`OverviewStore.loadSlack`); nothing new. Writes: none. Invalidates: nothing. Budget: that of
  "Slack read cursor, unread, mentions". Loading: none of its own, it arrives with the Slack part of
  the row. Failure: a failed cycle keeps the last list with the row's age. Exits: opening the message
  reads the channel, which removes the item. Cost: no request, no generation.
- **Rule 2 holds:** the Slack mentions are unchanged; detected ones are added beside them.

### 5.3 Issue from a message (dropped)

"Create an issue" in the ⋯ menu of a Slack message opened a sheet with title, description and priority
proposed by the model, then created the issue in the project's Linear project. Built whole (issue
creation in the Linear client and the store, the sheet, the proposal), tried, and removed: it did not
convince. What it taught, kept for the next features: titles came out well ("Refresh tips list after
language change"); the description mostly repeated the message; and the priority could not be trusted
(the model read "to fix before the release" as Urgent), so it was kept only when the message had a word
for urgency. Dever still has no issue creation.

### 5.4 Draft a reply (dropped)

A sparkle button in the thread composer wrote a reply from the thread alone, one or two sentences, marked
"✦ Draft" until the first change. Built, tried on the real model, and removed: to commit the user to
nothing the thread did not hold, the instructions left the model one thing to say, and it said it every
time ("I will look at it and come back"), a question of opinion included. A draft that safe saves no
time; a bolder one would speak for the user. Writing on the user's behalf is not a job for this model.

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
- **When:** by itself, for the messages the rail shows, the newest first, one at a time. The block is
  in the message's place at once: "Summarising" at its head and the first two lines of the message,
  muted, where the sentence will be. Only the one being written has a breathing sparkle; the others
  wait, still. When the sentence lands the excerpt fades out (150 ms) and the sentence and its kind
  fade in (200 ms) in the same frame: the rail does not move, or by one line when the sentence takes
  three, and then the rows under it follow on `Motion.move`. Under Reduce Motion the sparkle is still
  and the swap is a dissolve. The first form (the cut message, a "Summarising" line under it, then
  the block) moved the rail at every arrival: see [reviews/message-summaries.md](reviews/message-summaries.md).
- **Given up:** when the model has nothing to show, the block gives the place back to the message,
  cut at four lines as before.
- **Never over what is being read:** a message opened with "Show more" before its summary was wanted
  stays open, with "Show summary" under it. An edited message keeps its old sentence under
  "Summarising" until the new one lands.
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
  as far as they fit. "Show original" opens the message in full, "Show summary" goes back: one movement
  for the row, its link previews and the rows under it.
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
Pipelines
  Explain a failure                     [on]
```

- **Language** applies to summaries only: "Source" (default) keeps the language of what is summarised,
  "English" forces English. A segment picker, not a system dropdown.
- A switch turned off removes the feature's interface entirely, and drops what it had generated.

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
- **Slow:** skeleton lines in the reserved place; the content under it is usable at once. A long
  message's block holds its place with the start of the message; "Show original" does not wait.
- **Failing** (refusal, guardrail, context exceeded, rate limit, unsupported language): rule 4. The
  place closes without a message; the next change of the input may try again, the same input does not.
- Availability is observed (`SystemLanguageModel` is `Observable`): features appear when the model
  becomes ready, without a relaunch.

## 8. Architecture

- `Services/Intelligence.swift`: the only file that imports `FoundationModels`. Availability as a small
  enum the rest of the app can read on macOS 14; a serial queue with two priorities (on screen,
  background); one function per use, each with its instructions, its `@Generable` output and its input
  budget. Token counts with `tokenCount(for:)` where it exists, a character estimate before 26.4.
- `Model/IntelligenceStore.swift`: app-lifetime, memory only. Holds what the model wrote by key
  (detected mentions are not generated: they live in the Overview's snapshot); views read it, never call the model (rule 1 of CLAUDE.md).
- Prompts are English instructions that name the output language; inputs are plain text
  (`SlackPlain.text`), with authors' display names, never ids.
- Views: one `GeneratedMark` and one `GeneratedText` component (sparkle, tooltip, skeleton, fade through
  `Motion`), links through the existing button roles.
- Tests in `Tests/DeverTests`: thresholds, keys and invalidation, input budgeting and truncation, what
  each failure does. The model itself is behind a protocol so tests run without it.
- Snapshots: `DEVER_SNAPSHOT_INTELLIGENCE=available|notReady|off|unsupported` stands in for the system's
  answer and shows every feature's interface, built or not, so captures need neither the model nor the
  network. With `DEVER_SNAPSHOT_GALLERY=1` it also writes `generated-{dark,light}.png`: the marks, a
  text being written, a written one, the summary block in each state, the invitation. With
  `DEVER_SNAPSHOT_SUMMARIES=1` it plays a rail of made-up long messages whose summaries land 1.5 s
  apart (`SummaryRailScene`) and writes `summaries-{dark,light}-waiting.png`, six frames around the
  first arrival (`-landing-0…5`) and `-landed.png`.
- `IntelligenceFeature.built` lists the features that exist. A feature not in it has no switch, no
  interface and no invitation, and Settings › Intelligence is not listed while the set is empty: the
  ground can ship before any feature does.

## 9. Plan

| Phase | Content | Depends on |
| --- | --- | --- |
| 0. Ground | **Done.** `Intelligence` service and availability gating, `IntelligenceStore`, the mark and the generated block, Settings › Intelligence, the one-time invitation, snapshot states, tests, measurements (section 2). | |
| 1. Slack catch-up | **Dropped** after four forms on real channels (5.1). | 0 |
| 1b. Long messages | **Built:** 5.7, with kinds and the arrow for what is asked of the user, tuned on real channels. | 0 |
| 2. Writing | **Dropped:** issue from a message (5.3) and the reply draft (5.4). | 0 |
| 2b. Detected mentions | **Built:** 5.2, by name in code, in the Overview. | |
| 3. Issue summary | 5.5. | 0 |
| 4. Pipeline failure | job and log reads, then 5.6. | 0 |

Each phase updates data-freshness.md (a budget row for each new kind of data in section 4, the new exits
in section 5) in the same change.

## 9b. What the first day on real channels showed

Apple's on-device model (about three billion parameters, 4,096 tokens) was put to five jobs. One held.

| Job | Outcome |
| --- | --- |
| Shorten one long message, and say what kind it is | **Kept.** One input, one sentence out, checkable in a click. |
| Sum up a channel (four forms) | Dropped: vague or false across several messages; the reliable form repeated the rail. |
| Propose an issue from a message | Dropped: good titles, a description that repeats the message, a priority that cannot be trusted. |
| Draft a reply | Dropped: safe enough to send means too bland to help. |
| Say who a request is for | Never trusted: done in code (`MessageSummary.isForReader`). |

The pattern: the model transforms one short text well; it does not weigh several texts against each
other, judge importance, or speak for someone. Anything left in the plan is to be measured against that
before it is built.

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
  it and a judgement the model does not make reliably: not detected (5.2).
- **Onboarding wording.** A tooltip says Dever "never posts on your behalf" while thread replies post
  as the user; issue creation adds a second write. To be reworded with phase 2.
