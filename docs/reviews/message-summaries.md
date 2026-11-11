# Long messages as summaries: design critique and animation sweep

Rubrics: `docs/skills/superfuture-design-review.md` (critique) and
`docs/skills/find-animation-opportunities.md` (motion). Subject: the feature of
[on-device-ai.md, 5.7](../on-device-ai.md#57-long-messages-as-summaries) as it stood before this
review: `SummarisedMessage`, `SummarisingLine` (`Views/Generated.swift`), the swap in `MessageRow`
(`Views/SlackThread.swift`), `refreshMessageSummaries` (`Views/ProjectDetailView.swift`).

Method: the code read end to end, the gallery captured in both themes
(`DEVER_SNAPSHOT_INTELLIGENCE=available DEVER_SNAPSHOT_GALLERY=1`), contrast computed from the
tokens of `SootUI.swift`, each state walked through (waiting, arriving, toggled, slow, silent, off,
Reduce Motion, keyboard, VoiceOver). Not seen: a real rail with real messages and the real model's
timing; findings that rest on feel say so.

## 1. Critique, most serious first

### Blocking

| # | What | Why | Fix |
| --- | --- | --- | --- |
| 1 | A summary that lands replaces the message the reader has just opened with "Show more" (`expanded` is ignored by the swap). | Text is taken from under the eyes of someone reading it; the one thing rule 6 forbids. | A message opened before its summary lands stays open: the row goes to the "original" side and offers "Show summary". |
| 2 | Each arrival changes the row's height (four cut lines and a line, about 100 pt, become a block of about 70 pt) and the rows below jump, once per long message, every one to three seconds, for as long as the queue lasts. | Rule 7 ("a generated text never makes content move when it arrives"); a rail of six long messages shifts six times in the first twenty seconds, under the pointer. | The place is held from the start: the block is there while the summary is written, at the height it will have, and the sentence is written into it. See the question put to the user (section 3). |
| 3 | "Summarising" breathes between 60% and 100% opacity on an 11 pt label: at the low point `Soot.muted` on `Soot.surface` is 2.8:1 in dark. | Below AA (4.5:1) for half of every cycle. | Only the sparkle breathes; the word stays at full `Soot.muted` (5.4:1 dark, 5.5:1 light). |

### Important

| # | What | Why | Fix |
| --- | --- | --- | --- |
| 4 | Every queued message shows a breathing "Summarising" at once, though one summary is written at a time. | Up to six loops on screen for one piece of work: decoration, and a false statement about five of them. | Only the message being written breathes; the ones that wait are still. |
| 5 | Under Reduce Motion the swap between original and summary is a hard cut: `.motion(Motion.move, value:)` is off, and nothing else carries the fade. | Motion.swift's own rule: movement goes, dissolves stay. | The swap dissolves in `Motion.ui` with `fade: true`; only the height's spring is dropped. |
| 6 | "Show original" / "Show summary": the block and the text animate, but their siblings (link previews, the buttons row, the rows below) are outside the animated subtree and snap. Link previews appear with no transition. | Half a transition reads as a glitch: content overlaps the row under it for the length of the spring. (Read from the code; not filmed.) | One explicit transaction for the toggle (`Motion.run(Motion.move)`), scoped so the row and what follows it move together; the previews fade in. |
| 7 | A read message is dimmed to 55% in the rail, block included: the kind ("Update", `Soot.muted`) falls to about 2.5:1. | The label that says what the message is becomes the least legible thing in the row. | Inside the block the kind is always `Soot.ink`-based (see 9), so the dimmed row stays above 4.5:1. |
| 8 | VoiceOver reads the block as "Generated on this Mac. May be wrong. Asked of you. Request. Kyryl asks…": the caveat first, the content last. | The listener waits through the disclaimer on every summary. | One label: "Summary, Request, asked of you: Kyryl asks…", with the caveat as the hint. |
| 9 | Pressing kinds differ from "Update" by ink alone (ink vs muted, same size and weight). | A difference of tone on an 11 pt word is not read; colour alone carries it. | Kept as is unless the user wants the kind louder; noted as a look decision (section 3). |

### Polish

| # | What | Why | Fix |
| --- | --- | --- | --- |
| 10 | The block's radius is 10 where the cards around it use `Theme.radiusCard` 8 and rows 6. | Near-but-not-quite. | 8. |
| 11 | The sparkle is lime while writing and muted once written, two separate glyphs. | The mark changes colour and place at the moment of arrival. | With the place held (2), it is one sparkle, in the header, that stops breathing and goes muted. |
| 12 | The arrow "Asked of you" is a 10 pt glyph whose meaning is only in a tooltip. | Discoverable by hover only. It is the same arrow as the Overview's "for you", which is its defence. | Kept; the accessible label already says it. |
| 13 | An edited message keeps showing its old summary, unmarked, while the new one is written. | Briefly stale without saying so. | The block shows the writing state over the old sentence (same held place). |

### Strengths

- The block cannot be taken for a message: its own ground, hairline, sparkle and kind.
- The original is always one click away, and the model's silence costs nothing: the row is today's.
- Who is asked is read from the message, not guessed by the model.
- Contrast of the block's text and marks passes AA in both themes (5.4:1 and above).

Highest-leverage change: finding 2. It removes the repeated layout shift, makes the wait present
(what the user missed on the first day) and gives the arrival its animation for free.

## 2. Animation sweep

Frequency map: a rail is opened tens of times a day; a summary arrives a handful of times per visit
and only the first time (the store keeps it for the app's lifetime); the toggle is occasional; hover
on rows is constant.

### Opportunities

| # | Location | Today | Purpose | Frequency | Suggested motion |
| --- | --- | --- | --- | --- | --- |
| A | Arrival of a summary (`MessageRow`, `SummarisedMessage`) | The message and its line leave, a block pops in at 0.97, the row shrinks and the rail jumps | Preventing a jarring change | Occasional | With the place held: the excerpt dissolves into the sentence and "Summarising" into the kind, `Motion.ui` (200 ms ease-out), opacity only; if the sentence needs a line more, the block's height follows on `Motion.move`. Reduce Motion: the dissolve stays, the height is immediate. |
| B | The wait (`SummarisingLine`) | Every pending row breathes | State indication | Occasional | One sparkle breathes (opacity 0.45 to 1, scale 0.9 to 1.05, 1.4 s period, from the clock), on the message being written only; the word is still. Still under Reduce Motion. It is the one loop, and it says work is being done. |
| C | "Show original" / "Show summary" | Block and text animate, siblings snap | State indication | Occasional | One transaction on `Motion.move`: the row's height, the block leaving (`.opacity`), the message arriving (`.opacity`), the previews fading in. Reduce Motion: `Motion.ui` dissolve, no spring. |

### Rejected

| Candidate | Gate that killed it |
| --- | --- |
| A stagger when several summaries land | Speed and function: the serial queue already spaces them by a second or more; a stagger would only delay text. |
| The sentence typed out as it is generated | Function: text the user is trying to read should not move; and the answer is checked whole (length, kind) before it may be shown. |
| A shimmer over the original while it is summarised | Function: decoration on text being read. |
| A flourish of the sparkle when the summary lands | Purpose: delight, on something seen tens of times a day. |
| Hover or press on the block | Purpose: the block is not a control; the row already answers hover, and the button roles answer press. |

### Verdict

The feature needs three motions and has the right vocabulary for them already. Today's are aimed at
the wrong thing: a pop for a block whose arrival moves the page. Holding the place (finding 2) turns
the arrival into a dissolve inside a still frame, which is the highest-leverage change in both lists.
How the dissolve and the breathing feel at the model's real pace cannot be judged from captures.

## 3. Decisions and what was done

The user chose, for finding 2, the block from the start with the first lines of the message in it
(over the message first with a gliding swap, and over a block of skeleton lines).

| Finding | Outcome |
| --- | --- |
| 1 | Done: `MessageRow` goes to the original side when a summary is wanted for a message already opened. |
| 2, 11, 13, A | Done: `SummarisedMessage` takes `excerpt`, `writing`, `active`; two lines held; the excerpt leaves in `Motion.exit`, the sentence and the kind come in `Motion.ui` after 120 ms; the rail follows a change of height on `Motion.move` (`railList`, on the summaries' states only). A message the model gives up on gets its place back. |
| 3, 4, B | Done: one sparkle breathes, on the newest pending message (the queue's order); the word is still and at full contrast. |
| 5 | Done: `dissolveWhenReduced` (Motion.swift) keeps the fade under Reduce Motion while the layout changes at once. |
| 6, C | Done: the toggle is one `Motion.run(Motion.move)`. |
| 7 | Left: the 55% dimming of read rows is the rail's own convention (names and times fall with it); to settle for the rail as a whole, not for the block alone. |
| 8 | Done: one label, the caveat as the hint. |
| 9, 12 | Kept as they were. |
| 10 | Done: radius 8. |

Captures (made-up messages, no model): `shots/summaries-{dark,light}-waiting.png`,
`shots/summaries-{dark,light}-landed.png`, `shots/generated-{dark,light}.png`; how to make them:
`DEVER_SNAPSHOT_SCREENS=0 DEVER_SNAPSHOT_GALLERY=1 DEVER_SNAPSHOT_SUMMARIES=1 DEVER_SNAPSHOT_INTELLIGENCE=available`.

Elsewhere: the user was offered the Overview's "for you" items, the Linear issue's description, both
or nothing, and chose the Overview: an item that comes from a long message shows the summary's
sentence in place of the cut excerpt, from the same store entry the rail wrote (no second
generation), otherwise one more in the queue, behind the rail's. Not built here: the Overview's
files were being changed by another piece of work. The Slack room and the thread pane stay as they
are: they are where messages are read.

## 4. After the first try on real channels

The user tried the held place on their channels and was not taken by the arrival: a text replaced by
another in a still frame reads as nothing happening. Two changes, both theirs:

- **The block is small while it waits and grows with the result.** One line, "Summarising", in lime
  with a glint running through the sparkle and the word on the one being written (ink over lime, so
  the word is at full contrast at every instant; 1 s across, every 1.6 s, eased), muted and still on
  those that wait. When the sentence lands the block grows to it and the rows under it follow on
  `Motion.move`; the kind takes the place of "Summarising". This gives up finding 2's still rail on
  purpose: the movement is now one smooth growth per summary instead of a jump, and it is the
  feedback the user was missing. The excerpt of the message is gone from the block. The glint is the
  shimmer rejected in section 2, moved from the text being read to the label of the wait.
- **Summaries are kept between launches** (`SummaryCache`), so a message that has not changed is not
  summarised again: removed when read, after the "Quiet" days of Settings, or with the switch. This
  lifts "memory only" for this one kind of generated text (on-device-ai.md, rule 3).

Not verified: a real rail with real messages after these changes, the real model's pace, the glint
and the growth in movement (captures are stills), VoiceOver by ear, and the toggle's movement.
