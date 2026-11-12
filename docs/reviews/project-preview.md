# Preview panel — design review

Scope: the project page's **Preview** panel (`Sources/Dever/Views/PreviewPanel.swift`), the editor's
Preview step (`Views/ProjectSetupViews.swift`) and the overview row's preview glyph (`Views/OverviewView.swift`),
in every state the panel has (no preview linked, loading, not deployed, deploying, live, failed, deleted,
GitHub not connected, GitHub failing), dark and light. Stack: SwiftUI, Soot tokens (`Views/SootUI.swift`),
shared panel blocks (`Views/ProjectPanels.swift`). Project conventions read: `README.md`,
`docs/accessibility-review.md`, `docs/reviews/project-work-view.md`, `docs/skills/superfuture-design-review.md`.
Method: the `better-interface` orchestration (its six domain skills applied by hand; the skill is not
installed in this session) and the superfuture rubric, on the captures listed under Verification.

## Coverage

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | Every control of `PreviewPanel.swift` (names, focus ring, hit areas, disabled use, colour pairs), the captures in both modes | 4 findings, fixed |
| Layout | Panel rows, action row, options row, chips wrapping (`FlowRow`), captures at 1998px and the stacked layout | 1 finding, fixed |
| Writing | Every string of the panel, the dialogs, the menu, the editor step | 3 findings, fixed |
| Typography | Sizes and weights against the page's scale (11 mono · 12 · 13 · 14 · 15 · 17) | 1 finding, fixed |
| Colors | Phase glyph, chips, Kept pill, lime use, measured pairs | 1 finding, fixed |
| UI | Hover, press, motion (`WaitingLine`, `Skeleton`), radii | Clear |

## Findings (all applied)

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Accessibility | `PreviewPanel.swift` actions | "Deploy preview" and "Update" disabled with a tooltip when the PR is closed or merged | The buttons are not shown; one line says "The pull request is merged: nothing to deploy. Pick another one from More." | A tooltip on a disabled control never shows and the control is unreachable by keyboard; the reason has to be text |
| HIGH | Accessibility | `PreviewPanel.swift` actions | "Copy app URL" disabled when the preview has no App host | Not shown when there is no App host | Same rule: disabled means unavailable, and the help text was the only explanation |
| MEDIUM | Colors | `KeepPill` | Edge `Soot.lime.opacity(0.6)` | Edge `Soot.lime` | The 60 % lime over white measures 2.9:1, under the 3:1 bar for a component boundary (1.4.11); full lime is 7:1 light, 14:1 dark |
| MEDIUM | Layout | `PanelHeader(link:)` | Header "Open ↗" to the App host, beside an "App ↗" chip opening the same URL | Header link removed | Two controls for one destination split the eye; the chip already names what it opens (prefer delete) |
| MEDIUM | Writing | `PanelHeader(subtitle:)` | `pr-4714-app.preview.example.com` | `preview.example.com · pull request #4714` | The App host is not always deployed; the subtitle named a URL that may not exist |
| MEDIUM | Writing | Primary action, live | "Update" | "Update preview" | Verb plus object: "Update" alone could read as updating the project |
| LOW | Writing | Protect confirmation | Button "Redeploy with --keep" | "Protect and redeploy" | The button says what happens, the message carries the flag |
| LOW | Accessibility | Status row | The "·" separator read by VoiceOver | `accessibilityHidden(true)` | Decorative punctuation in the reading order |
| LOW | Accessibility | Overview row glyph | Glyph label "Preview live" followed by the word "Preview" | One combined element "Preview live" | The same word read twice |
| LOW | Typography | `KeepPill` | 11pt label, 22px pill | 12pt, 24px | 12 is the page's floor for a word (11 mono is reserved for identifiers); 24px meets the target floor |

Declined: a cancel for a deploy in progress (the workflow has no cancel command; the run link is the
way). Declined: a "Protect" toggle that could switch off (the label can only be lifted by deleting the
preview or closing the PR; the Kept pill's help says so, and the only control offered is Protect).

## Superfuture rubric, after the fixes

- **Hierarchy**: one focal point per state (the phase word with its glyph), one lime action per state
  (Deploy preview / Update preview / Deploy in the options row); the rest is quiet or behind More.
- **Typography**: within the page's scale; identifiers mono 11; numbers tabular (pod counts).
- **Spacing**: 16 between rows, 8 between buttons, 6 between chips, 12/16 inside tiles: the page's steps.
- **Colour**: phase and host state carried by shape and word, colour second (check / clock / cross,
  "down"). Pairs: ink and muted on surface (documented ≥ 4.5:1), edges `Soot.edge` (≥ 3:1), Kept pill lime.
- **Motion**: `WaitingLine` and `Skeleton` only, both still under Reduce Motion; no spinner.
- **States**: loading (skeleton at the loaded shape), empty (no preview: one line and one quiet button),
  not connected (`ConnectPanelBody` / `ConnectPlaceholder`), failing (`ServiceFailureRow`), in progress
  (line + current step), failed (glyph, note in Dever's words, run link, Deploy preview again), deleted.
- **Accessibility**: every control named; `FocusOutline` on every custom control; targets ≥ 24px (chips 30,
  buttons 36, stepper 30); destructive Delete behind a confirmation and in the destructive role.
- **Copy**: verb-first buttons; errors say what failed and where to look ("The deploy failed. The run's
  logs say why."); the comment Dever will post is shown verbatim before sending.

Strengths: the commands are the team's own (the comment is visible before it is sent); the state is read
from the workflow's own results rather than guessed; the panel never shows a raw error.
Highest-leverage change made: the closed-PR case became a sentence instead of a greyed button.

## Verification

Captures (sample data, `DEVER_SNAPSHOT_PREVIEW=…`, both modes) in
`/private/tmp/claude-501/-Users-eri-Documents-work-dever/a517bb30-bf5f-4acf-aea3-ddec34aee239/scratchpad/shots3/`:
`{live,deploying,failed,deleted,notdeployed,none}/project-{dark,light}.png`, `options/project-{dark,light}.png`
(deploy options open), `editor/sheet-new-project{,-popover}.png` (the Preview step and its picker), and
`live/overview-{dark,light}.png` (the row glyph).

Passed: build (`./scripts/build-app.sh`); every state renders in both modes with no clipping at the app's
minimum width; the chips wrap (`FlowRow`); Kept pill edge measured 7:1 light / 14:1 dark.

Not verified: posting a real `/preview` or `/delete-preview` (the user tests the live flow); the run-step
line against a real in-progress run; VoiceOver reading order; the probe against a host that times out.

## Verdict

Approve. No HIGH finding remains; every domain inspected.

## Revision 2 (user feedback: panel at the top, quieter once set, "No preview needed")

Scope: the same panel after the user's four points. Method as above (the `better-interface` orchestration
applied by hand), on the captures in `…/scratchpad/shots6/`.

What changed:
- The panel is first in the work column: it is the thing to open or to deploy, and it is now one or two lines.
- `Project.previewDismissed`: "No preview needed" hides the panel; picking a pull request in the editor brings it
  back (`Project.showsPreview`).
- Quieter once set: a `PanelHeader`-free headline (globe, "Preview", the PR as a link in the same line, the phase
  with its time, Run ↗, Kept at the right), then one line with the hosts on the left and the actions on the right.
  "Update preview" and "Copy app URL" are quiet buttons: a live preview asks nothing of the user. Lime stays on
  "Deploy preview" only, when deploying is the one thing to do.
- The travelling light no longer spans the panel (the user read it as a broken progress bar): it is a 72px light
  beside the step name, so it belongs to "Build and push API image" and reads as "still going".
- Failed: the note and "Deploy preview" share the second line.

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| MEDIUM | Layout | `PreviewPanel.swift` body | Full-width `WaitingLine` between the headline and the step | 72px light beside the step name, on the second line | A line across the panel with nothing to anchor it read as a progress bar with no progress; the light now belongs to the running step |
| MEDIUM | Colors | Live actions | "Update preview" in lime | Quiet buttons; lime only for "Deploy preview" | One lime action per view, and only where there is one thing to do; a live preview has none |
| MEDIUM | Layout | Page order | Preview under Delivery, off-screen on most projects | First in the column, 2 lines tall | The panel carries the links the user comes for; its height no longer competes with the list |
| LOW | Writing | Empty state | "No preview yet" title plus a line | One line and two choices: Add a preview · No preview needed | The user asked for a way out; the sentence says what following a preview gives |
| LOW | Accessibility | Busy row | Step text and the More menu on two rows | One row | Keeps the panel at two lines in every state; reading order stays headline → step → actions |

Not changed (belongs to the editor, handed to the sheets session): the hub/ready step overflowing at five rows
with Save cut; the hub row reading "Not needed"; the editor's snapshot sample.

Verification: `./scripts/build-app.sh`; captures `shots6/{live,deploying,failed,deleted,notdeployed,none,options}/
project-{dark,light}.png`. Not verified: the live `/preview` round trip; the editor fix (other session).

Verdict: Approve for the panel and page; the editor overflow remains open in the sheets session.

## Revision 3 (user feedback: too much on the line; simplify)

The user's reading of the set state: the PR title says nothing here; links to the APIs are not for people; the
run, the shield, "Update preview" and "Copy app URL" are noise next to the product chips. Applied with the
`better-interface` order of fixes (delete, then use what exists, then add):

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| MEDIUM | Layout | Headline | Number, title, state, Run ↗, Kept pill | `#4714` (a link) and the phase with its time | Everything else was a second place for things the menu already holds; the number is enough to tell which PR |
| MEDIUM | Writing | Host chips | Six chips, one per host (App, API, Back office, BO API, Client Hub, Client Hub API) | Three product chips (App, Back office, Client Hub); each opens its front and its glyph folds in the API's health (check · "down" · "API down" with a warning triangle) | People open products, not APIs; the API's state still shows, as a mark on its product |
| MEDIUM | Layout | Actions, live | Copy app URL · Update preview · More | More only | The chips already open the apps; "Update" was unclear. Both moved under More as "Copy app URL" and "Redeploy with the latest commits" |
| LOW | Writing | Protection | Kept pill | A disabled "Protected from the Saturday cleanup" line in More, or "Protect…" when not | The shield meant nothing on its own; the sentence says what it is where the action to change it lives |
| LOW | Layout | Deploy | "Deploy preview" opened the flags row first | One click posts `/preview`; "Deploy with options…" in More opens the flags | The common deploy has no flags; the row was a step in front of every deploy |

Captures: `…/scratchpad/shots7/{live,failed}/project-{dark,light}.png`. Verdict: Approve.

## Revision 4 (user feedback: the set state still weighs too much; one line)

The live panel said one thing ("the preview is live, here are three links") on two rows, with four green
checks, the pull request's title back under the name, and four outlined controls.

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| MEDIUM | Layout | Panel | Header, then a row of chips and the More button | One line: globe, "Preview", the number, the phase and its age on the left; the products, the step or "Deploy preview" and More on the right. The right part drops under the header only when the line does not fit | One piece of information, one line; the panel is about a third of its height |
| MEDIUM | Colors | Product chips | A green check on each chip, beside the green check of "Live" | The name alone when the product answers; a cross and "down", or a warning and "API down", when it does not | The phase already says live; a mark that only repeats it hides the one that says something is wrong |
| MEDIUM | Layout | Product chips, More | Three outlined capsules and an outlined More button | Plain links (`ExternalLink`, ink) and a borderless More | The outlines outweighed the words they held |
| LOW | Writing | Header | The pull request's title as a subtitle, "Draft" beside the number, "updated 5 days ago" | No subtitle; the state word only for merged or closed; "5 days ago" | The title and "Draft" change nothing here (both stay in the number's tooltip); the age needs no verb next to the phase |
| LOW | Layout | Phase and age | At the far right, away from the name | Beside the number | The state reads with what it is the state of |

Kept on a second line: the failure note (it explains the lime button above it), the deploy options, and the
invitation when no pull request is linked.

Captures: `…/scratchpad/shots8/{live,deploying,failed,notdeployed,none}/project-{dark,light}.png`. Verdict: Approve.

## Revision 5 (user feedback: "Live" beside a product that is down; the progress light over the text; the empty boxes)

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Writing | Phase, live | "Live" with a green check while a product did not answer | "Partly down" with a warning triangle when some hosts fail, "Down" with a cross when all do (`PreviewStatus.health`, `word`); the product that fails keeps its own mark and "down" / "API down". Same word on the Overview row | The state must not contradict the link beside it; the word says something is wrong, the mark on the link says which |
| HIGH | Layout | Progress | The waiting light ran unclipped across the step text | The step, then a 64 pt clipped track the light runs in | The light was drawn over the words it belongs beside |
| MEDIUM | Layout | No preview yet | A tile with a logo, a line and two buttons under the header | The header's own line: "Follow a pull request's preview here" as its subtitle, "Add a preview" and "No preview needed" on the right | The panel is the box; a box inside it doubled the frame and the glyph |
| MEDIUM | Layout | `PanelEmpty`, `ConnectPanelBody` (every panel) | A tile on the ground colour with a 28 pt logo | One muted line and the button, no tile, no second logo | Same reason, for "link Linear / a repository / a channel" and "connect" on every panel |
| HIGH | Data | Delivery, Linear not connected | The invitation row, then every open pull request of the repository (hundreds) under "Pull requests" | The header is the invitation (pitch as subtitle, "Connect Linear" on the right, no "Open ↗"); no pull requests until the issues can be read (`ProjectPulls.waitsForIssues`), unless the project takes the whole repository | A project that follows its issues cannot tell its pull requests from the others' without them; listing the repository's showed other projects' work as its own |

The Overview follows the same rule (`waitsForIssues`): its GitHub column reads "Needs Linear" rather than counting
the repository's pull requests while the project's issues cannot be read.

Captures: `…/scratchpad/shots9/{live,deploying,none,disc2}/project-{dark,light}.png`. Verdict: Approve.

## Revision 6 (incident: a preview stopped redeploying and was shown as Live)

A pull request in conflict with its base gets no `pull_request` workflow from GitHub, so the update workflow never
ran when its head moved. The hosts kept answering on a commit several days old and the panel said "Live".

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Data | Phase, live | "Live" as long as the hosts answer | "Live, behind the pull request" with a warning triangle and "deployed 6 days ago" when the head is not what was deployed; "Live, won't redeploy" when the pull request conflicts but the preview is still on its head (`PreviewStatus.tracking`, `conflict`, `drift`) | Rule 7: a deploy state is never drawn as current when it is not |
| HIGH | Writing | Under the line | Nothing | One sentence in the warning tone: the conflict with its base and that GitHub runs no workflow until it is resolved, and the commit served against the pull request's head when a run tells it. "Resolve conflicts ↗" (the pull request's conflicts page) when conflicting, "Redeploy" otherwise | The reason and the way out, where the state is read |
| MEDIUM | Data | Overview, Status | "On track" | "Preview behind" / "Preview won't redeploy" (warning triangle, the sentence as tooltip), after CI failing and Preview failed, before the due date | What is tested on the preview is not the pull request: worth the row's one status |

How "behind" is known (`PreviewStore.tracking`), from what was already read:

1. an update run (`pull_request`) that succeeded for the head: following;
2. the last update that succeeded is for another commit and no `/preview` was posted since: behind, and that
   commit is the one served;
3. otherwise the head commit's date against the last `/preview`: made after it, it was not in that deploy;
4. nothing known: not called behind.

The preview exposes its commit nowhere (no header on the probe, no version endpoint, nothing in the workflows'
result comments), and an `issue_comment` run carries the default branch's commit, not the pull request's: the
served commit is the last successful update run's, and unknown after a `/preview`. Commits behind are not
counted (a compare request per poll); the age of the deploy is shown instead.

Data contract:

- Reads: `preview(project)` in `PreviewStore`, same entry. New fields from the same responses: `mergeable`,
  `mergeable_state`, `base.ref`, `head.sha` of `GET pulls/{n}`; `head_sha` of the workflow runs. New: the head
  commit's date (`GET git/commits/{sha}`), kept per commit for the app's life.
- Writes: none new ("Redeploy" is the existing `/preview` command: optimistic phase, 30 s polling).
- Invalidates: nothing new. "Resolve conflicts" opens GitHub: `LookAgain` marks the data dirty, the preview is
  read again on return.
- Budget: the preview's (60 s; 15 s while a run goes).
- Loading: none of its own; the sentence appears and leaves with the panel's motion.
- Failure: a failed refresh keeps the last status, drift included. While GitHub has not worked the merge out
  (`mergeable` null), what was known for the same head stays.
- Exits: the conflicts page (above).
- Cost: no request more per poll. One request of under 1 kB once per new head commit, and only in case 3.

Not done: a mark on the pull request rows of Delivery (needs `mergeable` in the repository's GraphQL list), a
notification "Preview stopped following the pull request" (the notifier has no preview alert yet).

Captures: `…/scratchpad/shots10/{behind,conflict}/{project,overview}-{dark,light}.png`. Verdict: Approve.
