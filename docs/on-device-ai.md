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
| Issue summary | top of the Linear issue page | automatic, from a threshold of length |
| Explain a pipeline failure | "Start here" tile, pull request chip of the issue page | on demand (built) |

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
  Several sessions at once were measured and gain nothing: six summaries of one 330-character message
  took 12.5 s one after the other (1.9 to 2.2 s each) and 11.0 to 12.0 s with two, three or six
  sessions running together; the answers still came out about two seconds apart, each request simply
  waiting longer. The system runs one generation at a time whatever the app asks. What saves time is
  not asking: summaries are kept between launches (5.7).


## 3. Rules

1. **Nothing leaves without you.** A generated text is never sent, created or saved to Slack, Linear or
   GitHub without an explicit act (Return in the composer, "Create" in a sheet). Once sent it is the
   user's text and carries no mark.
2. **Never in place of facts.** Pipeline, review, deploy and preview states, counts, dates, names and
   priorities shown as data are always the raw value. The model may explain beside a fact; it never
   replaces, recolours or reorders one. An explanation of a pipeline failure sits next to the link to
   the real log, never instead of it.
3. **Everything stays on the Mac.** Only the system model. No online AI service, no Slack, Linear or
   GitHub content sent anywhere else. Generated text lives in memory, with one exception asked for by
   the user: the summary of a long message is kept in a file on this Mac (`SummaryCache`, readable by
   the user alone) so that it is not written again at every launch; it leaves the file when its
   message is read, when it is older than the days after which Settings calls a channel quiet (14
   unless set), and when "Long messages" is switched off. The wording in the app: "Runs on this Mac.
   Nothing leaves it."
4. **Silent rather than inventive.** Too little material, a refusal, a guardrail or an error: no generated text at all and no error message; the screen is the one of today.
   No system notification is ever built from generated text or triggered by a model's judgement.
   An input too long to read whole is read in part only where the feature says which part and the
   text says what it covers; otherwise it is silence too.
5. **Always marked, always traceable** (section 4).
6. **Raw data first.** A generated text is added above or beside what it describes; the messages, the
   description and the comments stay where they are, readable at once, and never wait for the model.
   One exception, decided on the first real use: in the rail, where a long message is already cut at
   four lines, its summary takes the place of the cut (5.7). The block is there from the start, one
   line that says "Summarising" until the sentence is written; "Show original" gives the message in
   full at any moment, written or not; the room always shows messages.
7. **Skeletons, not spinners,** and a generated text never makes content move when it arrives: its
   place is reserved. One exception, the user's choice: a long message's block grows from its one
   line to the sentence when it lands, in one movement with the rows under it (5.7).

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
never taken for the message. The block is there before the summary exists, as one line: the sparkle
and "Summarising". On the one summary the model is writing they are lime and a glint runs through
them; on those that wait they are muted and still. VoiceOver hears "Summary, Request, asked of you: …",
the caveat as the hint.

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

### 5.2 Detected mentions (dropped)

An unread message that speaks of the user by name without a Slack mention, shown among the project's
"for you" items in the Overview with the `@✦` glyph. Built in code with no model, pushed, and removed
the same day:

1. **A Slack profile is not a name.** The match can only know the words of the display name and of the
   full name. People rename themselves for fun (a first name bent into a pun), teams use nicknames
   that are in no field, and then the message that says the real first name is never found.
2. **Who wants to be read uses a mention.** What is left for detection is mostly messages that speak
   of the user without asking anything ("Sam fixed that yesterday"): noise among the "for you" items.
3. **The model does not rescue it.** Keeping only the messages the model files as Request or Question
   (the kinds of 5.7) was measured on the real model with 20 invented short messages that name the
   reader, French and English, twice each: 36 of 40 right, 1.4 to 3.5 s a message. One real request
   was dropped in one pass of two ("On attend le retour de Sam sur le front pour merger": Problem,
   then Request), three plain statements were kept ("Sam a déjà mergé la PR, on peut tester" as Request
   both times). The same message does not always get the same kind, and the kind says that something
   is asked, not that it is asked of the reader.

What the matching taught, for any later use of names: whole words of three letters or more with case
and accents folded; a word a colleague also carries names no one; mentions of others, links, addresses
and code are removed first; a name that is also a common word (Will, Mark, Rose) needs its capital and
more at the head of a sentence. The system's spelling dictionary takes "sam", "tom" and "martin" for
ordinary words, and the system's word tagger (`NLTagger`) reads a first name written without its
capital at the head of a French sentence as a pronoun: neither can tell a name from a word.

The `@✦` mark and the "Detected mentions" case of `IntelligenceFeature` stay unused.

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

**Built.** A failed pipeline opens its own card; on that click only, the checks that failed as GitHub
names them and, under the first, one generated sentence.

- **Where:** the failed state itself is the button, as on the release line. "CI failed on #N ⌄" on the
  "Start here" tile of the Delivery board, and on the issue page the pull request chip, which now
  reads "#N CI failed" when the copy the app already holds says so (no request of its own; past twice
  the budget of a pull request's checks the chip is drawn muted, with the age of that copy). A first
  form put a "✦ Why?" link beside the state and the explanation in a panel under it: the link read as
  unrelated to the pipeline, and was dropped for the card.
- **When:** on click only. Nothing is read from GitHub and nothing is generated without it. A click
  elsewhere or Escape closes the card.
- **What the card shows,** built like the release line's: the pull request; "Failed 12m ago" (the
  run's age); each failed check with its step, raw, as a link to its log; under the first one the
  sentence, behind the sparkle; "2 failing · 17 passing"; "Open on GitHub ↗". The red state, the
  counts and the word "failed" are GitHub's (rule 2), and the log link is the line above the sentence.
- **Which job:** the Actions job that failed first on the pull request's head commit (what fails after
  it often fails because of it). A check another service reports has no log to read: its name, which
  leads to its page, and "No log Dever can read for this check."
- **What the model reads:** not the tail of the log but the failed step alone, cut out in code
  (`PipelineLog.excerpt`): the step's command, its last 60 lines of output at most (1,600 tokens at
  most), the runner's error. The runner's time stamps, colour codes, set-up and clean-up are removed.
- **"The log does not say why." is decided in code, not by the model.** When no line of the step
  reports something going wrong (a step that prints its progress and exits 1, a formatter that prints
  a diff, warnings only), the model is not asked at all. Asked whether the log states the error, the
  real model answered yes every time, including for a log that only waits and exits: the boolean is
  kept in the guided answer so that the model decides before it writes, and is not relied on.
- **The model must point before it writes.** The guided answer is, in this order: does the log state
  the error, the line of the log that states it (copied), the sentence. The sentence is shown only
  when that line is really in the log (four words in five of one line, the model tidies as it
  copies), is not the runner's exit code, and is not a warning. Otherwise: the job, the log link, and
  no sentence (rule 4).
- **Measured on the real model** (`RealModelTests.testWhyAStepFailed`, 8 made-up steps and 5 real
  public job logs, three passes each, 3 to 7 s an answer). First wording: 24 sentences, the cause
  right each time but the step misnamed ("the test in ExportButton.tsx had a type error", "Test
  ./scripts/deploy-preview.sh failed") because the instructions said "naming the test, the file or
  the command". Second: "the build failed" for runs of tests. Third, kept: the reader already sees
  the job and the step, so the sentence says only what went wrong; 27 sentences, 26 faithful to the
  log, 1 false (a deprecation warning taken for the cause, now refused in code). The sentences stay
  close to the log's own line ("19.97 was not equal to 19.98 in tests/test_billing.py", "The C
  compiler /usr/bin/clang is not able to compile a simple test program"): the model picks the line
  and puts it in plain words, it does not diagnose. The three steps whose log states no error were
  never sent to it.
- **Failures.** Offline, a rate limit, a rejected token, anything else: one line of fixed words and
  "Try again"; nothing is kept. No failed check on the latest commit any more: said so, and the
  repository is marked to be read again. The log gone or not readable with this account (403, 404,
  410): the job, "The log can't be read from here.", the link. The model refusing or failing: the
  job and the link, no sentence, no message.
- **Kept:** in `FailureStore`, memory only, by repository and pull request. Dropped when the pull
  request's checks are no longer failing in `GitHubStore` (a new run started or passed), when the
  switch is turned off, and never refreshed by a timer. It carries the run's age.
- **Switch:** "Explain a failure" in Settings › Intelligence. Off: the failed state is not a button,
  nothing is read, nothing kept.
- **Data contract.** Reads: two new ones, on click only: `failedChecks(repo, pull)` (one GraphQL
  query, about 1 kB for ten checks) and `jobLogTail(repo, job)` (GitHub's redirect, the size of the
  log, then its last 64 kB at most, never the whole log; the token is not sent to the storage host).
  Writes: none. Invalidates: `GitHubStore`'s repository when GitHub no longer reports a failure.
  Budget: none, read once per run and per ask. Loading: skeleton lines in the card, then for the
  sentence; the failed checks show as soon as GitHub answers. Failure: as above. Exits: "Open log"
  opens GitHub; the pull request's checks are refreshed on return by the page's own rule. Cost: three
  API requests and at most 64 kB per ask; one generation of 3 to 7 s.

### 5.7 Long messages as summaries

- **Where:** the Slack rail, in the place of each message it would cut ("Show more", over 240
  characters). Not in the room, not for short messages.
- **When:** by itself, for the messages the rail shows, the newest first, one at a time. The block is
  in the message's place at once, one line high: "Summarising", in lime with a glint running through
  it (1 s across, every 1.6 s) on the one being written, muted and still on those that wait. When
  the sentence lands, "Summarising" gives way to the kind (150 ms out, 200 ms in), the block grows to
  the sentence and the rows under it follow, in one movement (`Motion.move`); the sentence fades in
  as it is uncovered. Under Reduce Motion nothing runs or moves and the swap is a dissolve. Two
  earlier forms were set aside: the cut message with a "Summarising" line under it, then the block
  (the rail jumped at every arrival), and a block holding the sentence's height with the start of
  the message in it (still, but the user found the arrival flat): see
  [reviews/message-summaries.md](reviews/message-summaries.md).
- **Kept between launches:** a summary, or the model's silence, is saved with the version of its
  input (`SummaryCache`, a file in the app's folder): at the next launch the same message shows its
  summary at once and the model is not asked. Removed when the message is read (Slack's cursor
  passes it; what is on screen stays until the app quits), after the days Settings gives a channel
  before it is "Quiet" (14 unless set) whether read or not, and when the switch is turned off. An
  edited message is another version and is written again.
- **Given up:** when the model has nothing to show, the block gives the place back to the message,
  cut at four lines as before.
- **Never over what is being read:** a message opened with "Show more" before its summary was wanted
  stays open, with "Show summary" under it. An edited message keeps its old sentence under
  "Summarising" until the new one lands.
- **Compact:** the sparkle, the kind and the sentence are one text, the kind at the head of the first
  line, in a block with small margins: two lines take about 52 pt. The kind had a line of its own at
  first (about 80 pt), which the user found took too much room for something meant to save some.
- **What:** the kind of message at the head of the sentence and one short sentence of at most 14 words that
  stands on its own: who or what it is about, then what is asked, wrong, decided or announced. Names,
  numbers and ticket identifiers kept. Guided generation; the kind is chosen after the sentence.
- **Asked of the user:** a lime arrow before the kind when the message is a Request or a Question and
  names the user, with an @ or by a word of their name (`MessageSummary.isForReader`). Read from the
  message, not asked of the model.
- **Kinds,** by what the message expects of its readers: **Request** (someone is asked to do, send,
  check, fix or decide), **Question** (an answer or an opinion is asked for), **Problem** (something is
  wrong, slow, failing, late or to fix, and no one in particular is asked), **Update** (the rest:
  progress, news, a decision, a welcome). The first three show in ink, Update muted. "Decision", "Warning"
  and "Info" were tried first: the model filed almost everything under Decision, and Info said nothing. Never more than 120 characters (two lines of the rail, most of a line of the Overview; 20 words and 180 characters at first, which the user found too long): whole sentences are kept
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
  edit is another version), in `IntelligenceStore`, and on disk while the message is unread
  (`SummaryCache`). No network request.
- **Also in the Overview,** and nowhere else: a "for you" item that comes from a long message (a
  mention over 240 characters, the same test as the rail's; 120 was tried so that a mention cut on the
  line would be summarised too, and given up: on a message that short the model keeps one of its two
  points, a different one at each run, or mixes them) shows who wrote it, the sparkle, the kind
  and the sentence, on the item's one line, in place of the cut message. No block and no taller row:
  the line is too small to be taken for the message, and the mark says what it is. Until the sentence
  is written, and when the model stays silent, the line is the start of the message as before; the
  sentence dissolves in (`Motion.ui`, a fade under Reduce Motion too) and the row keeps its height. The
  tooltip is still the message's own words, and a click still opens the room on the message. The
  author, the age and the "N for you" count are the raw values. Short mentions, review requests and
  the "N unread" line are never touched.
  - **One copy:** the item reads the entry the rail writes (`MessageSummary.subject(channel:ts:)`, the
    same input version, carried by the mention in the project's snapshot), so a message summarised in
    the rail costs nothing here, and the other way round.
  - **Who asks:** the Overview page (`OverviewView.refreshMessageSummaries`), never a row; only for
    the items listed (the first three of a project, all of them after "Show all", filters applied),
    the newest first, in the background queue, six at most (`WaitingItem.mostSummaries`).
  - **Cost:** no request. One to three seconds of generation per long mention listed, one at a time:
    a usual Overview holds none to two, so 0 to 6 s after it loads; 18 s at the cap. Each one asked
    for here delays the rail's by as much, which is why short messages and the rest of the unread
    are left out.
  - **Off:** with "Long messages" switched off, or the model not ready, the items are as they were.
  - Captures: `docs/reviews/shots/overview-summary-{dark,light}.png` (written) and
    `overview-excerpt-{dark,light}.png` (the same item with the model off), both with the made-up
    answer of capture runs; `overview-summary-model-{dark,light}.png` is the same made-up message
    summarised by the Mac's own model (no `DEVER_SNAPSHOT_INTELLIGENCE`). Not yet looked at on real
    channels: how often a real long mention is met with silence, and how the line reads when the
    sentence is cut by the columns.
- **Measured:** 1.2 to 2.7 s for a 700-character report.

## 6. Settings › Intelligence

A page between Notifications and Launch, built like the others (`SectionHead`, `SettingRows`,
`SettingRow` with a switch). No master switch: one per use, all on by default.

```
Intelligence  (Beta)
Dever reads the long parts for you, on this Mac. It can be wrong. The original is always one click away.

Summaries
  Long messages                         [on]
  Language            [ Source | English ]

┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
  Catch up without reading it all  (Coming soon)
  Today Dever shortens one message at a time. A second model,
  an optional download, will take on a whole channel, issue or pipeline.
  [picture]            [picture]           [picture]
  A busy channel,      A long issue,       A failed pipeline,
  caught up            summed up           explained
  Runs entirely on this Mac · Nothing leaves it
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
```

- **Language** applies to summaries only: "Source" (default) keeps the language of what is summarised,
  "English" forces English. A segment picker, not a system dropdown.
- A switch turned off removes the feature's interface entirely, and drops what it had generated.
- **Beta.** Every feature carries a maturity in the model (`IntelligenceFeature.maturity`), beta for all
  of them today. `IntelligenceFeature.betaMark(among:)` decides where the word shows for the features
  the page lists: once, beside the page's title, while all of them are beta (a tag on every row would
  say the same thing four times); on each beta row once some have left beta. The line under the title
  says first what Intelligence is for, then what Beta means here (`betaHeadline`): Dever reads the long
  parts for you on this Mac, it can be wrong, the original is always one click away. Short sentences,
  no colon and no semicolon in what the user reads. A feature added to `built` is marked without touching the page.
- **Coming soon.** The local model of docs/local-model-benchmark.md is announced, not built
  (`LocalModelOutlook`, `ComingSoonBlock`). A dashed frame, so that it reads as a place kept and never as
  a disabled control: no switch, no button, nothing dimmed, nothing clickable. Its title is the benefit
  ("Catch up without reading it all"); one line says why a second model (Apple's shortens one message,
  this one will take on a whole channel, issue or pipeline) and that it is an optional download; three
  small pictures in the app's own shapes show the raw thing and, behind the sparkle, what will be
  written of it. No date, no model name, no size. "Larger" was tried in the title and refused: it reads
  as "heavier on my Mac". To VoiceOver the block is one element that reads the whole announcement; it
  does not move, so Reduce Motion changes nothing.
- **Where the announcement shows:** only on a Mac the benchmark's recommendation covers, Apple silicon
  with 16 GB of memory or more (`LocalModelOutlook.announced`). On any other Mac it would promise what
  may never reach it.
- **Onboarding** has an Intelligence stage (`OnboardingIntelligence.swift`), after the channel names and
  before the first project: the tools are connected and described by then, and the projects are the way
  out of onboarding. It replaces the quiet line the Connect stage carried while there was nothing to choose.
  - **Left,** top to bottom: what is asked, by name (a lit sparkle, "Enable Local Intelligence" in lime
    and the word Beta, whose tooltip gives the meaning); the headline "Skip the long reads"; one
    sentence that says whose model it is and what it does here ("Apple Intelligence, the model built
    into your Mac, sums up long messages and explains failed pipelines."); the answer, as two rows
    drawn like the channel-naming stage's ("Turn it on", Recommended, and "Not now", with "Turn it on
    any time in Settings"); what it costs, as three short facts with a glyph each ("Runs on your Mac's
    own chip", "Nothing leaves it", "Nothing to install"); Continue.
  - **Why this shape.** A first form had the word Beta alone above the headline and one switch per
    use: the user found that the screen did not say what it was about, did not say it was Apple's
    model running on the Mac, had no plain way to say no, and did not say that nothing had to be
    installed. The switches per use stay in Settings; here the question is one.
  - **What is not said.** "Nothing to install" shows only while the model is there (off or not ready,
    the system may still have it to fetch). Nothing claims that it uses no resources: a summary keeps
    the chip busy for one to three seconds (section 2). The chip is not named (the framework does not
    say which part of it runs the model).
  - **Right:** on the lime stage, in the place of the window crop, a made-up project page: a long message
    of the rail as its summary, a failed pipeline with its card and the sentence behind the sparkle. What
    the Mac wrote is lit, which it never is in the app (section 4): a lime edge and a soft lime light,
    and above it a lime sparkle with "Summed up by your Mac" or "Explained by your Mac"; the message
    as it came stays above its summary, dimmed, so the picture reads as before and after. Large
    sparkles sit on the lime stage around it. Every sparkle of the stage breathes on a 2.4 s beat
    (`Twinkle`), still under Reduce Motion. The
    picture answers to the choice: with "Not now", the message is cut at four lines with "Show more" and the
    failed state is plain, with no card. It is a picture: nothing in it is clickable or read by the model.
  - **One source of truth:** a row writes, at once and for every use the stage presents, the keys of
    Settings › Intelligence (`IntelligenceFeature.settingKey`), through the one function both screens
    use (`IntelligencePreferences.set`), which also drops what a use had written when it goes off. On
    by default, as in Settings; "Turn it on" shows as chosen while any use is on, and nothing is
    written until a row is clicked, so a choice made use by use in Settings survives a replay. The
    language of summaries is not asked here; Settings has it.
  - **Off or not ready:** the same stage with, in the place of the two rows, one row: "Apple Intelligence
    is off on this Mac" and "Turn it on to use it here", or "Apple Intelligence is not ready on this Mac
    yet" and "Dever will use it once it is ready" (never "downloading", section 7), with "Open System
    Settings ↗". The picture stays: it shows what Dever will do. Back from System Settings the stage
    shows the two rows by itself (`IntelligenceStatus`).
  - **A Mac that can never run it** (macOS before 26, `deviceNotEligible`): the stage is left out, with
    its progress mark (`OnboardingView.Stage.flow`). Showing it disabled was set aside: every other
    stage asks one thing the user can answer, and here there would be nothing to choose and nothing to
    fix, only a reason to feel the Mac is too old. The local model to come is announced in Settings
    alone, where it does not stand in the way of the first project.
  - Captures: `docs/reviews/shots/onboarding-intelligence-{available,notReady,off,unsupported}.png`
    (onboarding is dark in both modes; `unsupported` shows the first-project stage and five marks).

## 7. Unavailable, slow, failing

| State | Pages | Settings › Intelligence |
| --- | --- | --- |
| macOS before 26, or a Mac that can never run it (`deviceNotEligible`) | nothing | where the local model is announced (above): "Apple Intelligence is not available on this Mac" and the Coming soon block alone, without its sentence about today, since a local model could reach this Mac. Elsewhere the page does not exist. |
| Apple Intelligence off (`appleIntelligenceNotEnabled`) | nothing, plus the invitation once; onboarding's stage gives the reason and the link (section 6) | Beta beside the title, the reason in one sentence, "Open System Settings ↗", then the Coming soon block |
| Model not there (`modelNotReady`: downloading, or held back by the system, for instance when Siri's language and the Mac's differ) | nothing, plus the invitation once | Beta beside the title, "Apple Intelligence is not ready on this Mac yet", "Dever will use it once it is ready", "Open System Settings ↗", then the Coming soon block. Never "downloading": the API does not say why. |
| Available | features on | as section 6 |

- **The invitation:** one quiet line at the top of the Slack rail, the first time only, when the Mac
  could run the model but it is off or not ready: what Dever would do here (shorten long messages) and
  a link to System Settings. Dismissed once, never shown again.
- **Slow:** skeleton lines in the reserved place; the content under it is usable at once. A long
  message's block says "Summarising" on one line; "Show original" does not wait.
- **Failing** (refusal, guardrail, context exceeded, rate limit, unsupported language): rule 4. The
  place closes without a message; the next change of the input may try again, the same input does not.
- Availability is observed (`SystemLanguageModel` is `Observable`): features appear when the model
  becomes ready, without a relaunch.

## 8. Architecture

- `Services/Intelligence.swift`: the only file that imports `FoundationModels`. Availability as a small
  enum the rest of the app can read on macOS 14; a serial queue with two priorities (on screen,
  background); one function per use, each with its instructions, its `@Generable` output and its input
  budget. Token counts with `tokenCount(for:)` where it exists, a character estimate before 26.4.
- `Model/IntelligenceStore.swift`: app-lifetime, in memory (summaries of long messages also in
  `Model/SummaryCache.swift`, a file, until read or old). Holds what the model wrote by key
  (summaries, failure explanations); views read it, never call the model (rule 1 of CLAUDE.md).
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
| 2b. Detected mentions | **Dropped:** built by name in code, removed (5.2). | |
| 3. Issue summary | 5.5. | 0 |
| 4. Pipeline failure | **Built:** the failed checks and the log tail read on click, then 5.6. | 0 |

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
| Say why a pipeline step failed, from its log | **Kept**, with the judgement taken away: code cuts out the failed step, decides whether it states an error at all, and checks the line the model says it rests on. |
| Say who a request is for | Never trusted: done in code (`MessageSummary.isForReader`). |
| Find messages that speak of the user without a mention | Dropped (5.2): done in code, defeated by what people call themselves on Slack. |

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
  it and a judgement the model does not make reliably; detected mentions are dropped (5.2).
- **Onboarding wording.** Settled: the tooltip said Dever "never posts on your behalf" while thread
  replies post as the user. It now says Dever "posts only what you write and send".
