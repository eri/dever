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
| MEDIUM | Writing | `PanelHeader(subtitle:)` | `pr-4714-app.preview.mendo.cloud` | `preview.mendo.cloud · pull request #4714` | The App host is not always deployed; the subtitle named a URL that may not exist |
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
`/private/tmp/claude-501/-Users-eri-Documents-work-dever/a517bb30-bf5f-4acf-aea3-ddec34aee239/scratchpad/shots2/`:
`{live,deploying,failed,deleted,notdeployed,none}/project-{dark,light}.png`, `options/project-{dark,light}.png`
(deploy options open), `editor/sheet-new-project{,-popover}.png` (the Preview step and its picker), and
`live/overview-{dark,light}.png` (the row glyph).

Passed: build (`./scripts/build-app.sh`); every state renders in both modes with no clipping at the app's
minimum width; the chips wrap (`FlowRow`); Kept pill edge measured 7:1 light / 14:1 dark.

Not verified: posting a real `/preview` or `/delete-preview` (the user tests the live flow); the run-step
line against a real in-progress run; VoiceOver reading order; the probe against a host that times out.

## Verdict

Approve. No HIGH finding remains; every domain inspected.
