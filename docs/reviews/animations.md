# Animation sweep (find-animation-opportunities)

Rubric: `docs/skills/find-animation-opportunities.md` (Emil Kowalski's skill, copied from the
Figma community). Method: every screen read in code and captured (`Support/Snapshotter.swift`,
dark and light), each seam run through the four gates (frequency, purpose, speed, function),
then the survivors implemented with the vocabulary in `Sources/Dever/Views/Motion.swift`.

## Vocabulary (Motion.swift)

| Name | Curve | For |
| --- | --- | --- |
| `Motion.quick` | 120 ms ease-out | press and hover feedback, barely seen |
| `Motion.ui` | 200 ms ease-out | swaps, fades, tab changes, skeleton → content |
| `Motion.exit` | 150 ms ease-in | something leaving |
| `Motion.move` | spring, response 0.38, damping 0.86 (~350 ms, no overshoot) | a larger move that settles: the Slack room, the thread pane |
| `Motion.settle` | spring, response 0.3, damping 0.82 | a marker travelling between choices |

Rules applied everywhere: nothing linear; every animation explicit (`Motion.run`,
`.motion(value:)`, a `matchedGeometryEffect` or a `FadeSwap`), never an implicit `.animation`
on a whole view; animate opacity, transform and the frame of the thing that moves, never the
data the user reads. Reduce Motion: movement, scale and springs are off (`Motion.reduced`,
`accessibilityReduceMotion`); dissolves stay, as Apple's guidance allows.

## Part 1: Opportunities, ranked by leverage

| # | Location | Today | Purpose | Frequency | Motion applied |
| --- | --- | --- | --- | --- | --- |
| 1 | Project page, Slack rail → room (`ProjectDetailView.toggleSlackWide`, `SlackThreadView`) | Snappy 0.3 s on a hierarchy swap: the work column vanished, the messages re-laid out at every width, the room's list was recreated | Spatial consistency | Occasional | One spring (`Motion.move`): the panel's frame grows in place over the work column, which slides 40 pt left and fades; inside, the rail's list dissolves into the room's (200 ms), each laid out at its own final width (`widths`) and clipped by the panel, so no message reflows; the header's Back and Open in Slack fade in. Reverse on the way back. Instant under Reduce Motion. |
| 2 | Thread pane beside the room (`SlackThreadView.setThread`, `ThreadPane`) | Implicit `.animation` on the whole HStack; a second pane slid over the first when changing thread | Spatial consistency | Occasional | Pane slides in from the trailing edge over the aside (`Motion.move`); changing thread cross-fades the pane's content (200 ms) instead of sliding a new pane; the chosen message's lime bar fades in and the row steps aside (200 ms). |
| 3 | Onboarding stage change (`OnboardingView.go`, `FadeSwap`) | Hard cut between headlines | Preventing a jarring change | Rare, first run | The stage fades out (150 ms ease-in) and the next rises in 8 pt (200 ms ease-out); progress marks slide (`Motion.settle`); the window crop on the right dissolves its skeletons into data as each tool connects. Fade only under Reduce Motion. |
| 4 | Onboarding "Connect" rows (`ServiceRow`) | Check mark appeared flat | Delight (rare tier) | Rare, first run | Check mark lands from 0.4 scale on a spring (response 0.35, damping 0.6): the one bounce in the app. Fade only under Reduce Motion. |
| 5 | Skeleton → content (project page, Overview rows and KPIs, issue page, Preview panel, Slack panel) | Content replaced the skeleton with a jump | Preventing a jarring change | Occasional (each load) | Cross-fade (200 ms) scoped to the loaded flag, so the panel resizes in the same breath and nothing else on the page animates. Stays under Reduce Motion (a dissolve). |
| 6 | Counters that refresh (Overview KPIs, open PRs, Slack messages, "15 of 15 shipped", percent, GitHub line, legend and tab counts) | Digits swapped | State indication | Occasional (refresh) | `contentTransition(.numericText())` under `rollingNumber`, 200 ms; a plain dissolve under Reduce Motion. |
| 7 | Tabs and filters (`CountTabs`, Overview KPI underline, `ChipPicker`) | Fill jumped from pill to pill | State indication | Tens/day | The lime pill or underline travels with `matchedGeometryEffect` on `Motion.settle`; the dropped rows fade out and the kept rows slide up (200 ms, scoped to the filter); the delivery bar's other stages step back (opacity only). No travel under Reduce Motion. |
| 8 | Settings section switch, marker, appearance | Done in the Settings redesign | State indication | Occasional | Kept. Appearance now cross-fades the whole window: a picture of the old appearance fades out over the new one (250 ms, AppKit), as macOS itself does; instant under Reduce Motion. |
| 9 | Sheets and their steps (`StepSheet`, `SootSheet`, `ProjectEditorSheet`) | macOS slides the sheet; the content was just there; steps cut | Preventing a jarring change | Occasional | `SheetEntrance`: the content rises 6 pt and fades in (200 ms) as the sheet lands; steps use `FadeSwap` and the step marks slide. |
| 10 | Expanding lists ("Show all", `ChoiceCard` nested controls, Preview options, issue notice) | Rows appeared at once; the page jumped | Preventing a jarring change | Occasional | The toggle runs in one transaction (`Motion.run(Motion.ui)`): the list grows and the new rows fade in; nested controls rise under their choice; the notice line rises in and fades out. |
| 11 | File lightbox (`FilePreviewHost`, `FileLightbox`) | 180 ms, implicit on the whole page | Spatial consistency | Occasional | Backdrop and sheet pop in (0.97 scale, 200 ms ease-out), leave in 150 ms ease-in; explicit transaction. |
| 12 | Press and hover feedback (every button style, tiles, chips, rows, links, rail tiles) | Hover was an instant tone step; no press feedback | Feedback | Tens to 100+/day | Hover tone fades in 120 ms (a dissolve, so it stays under Reduce Motion); press is a 0.97 scale over 120 ms (`PressButton`, `pressScale`), off under Reduce Motion. Near-imperceptible by design. |
| 13 | Screen switch from the rail (Overview, project, Settings) | Hard cut | Preventing a jarring change | 100+/day | A 150 ms dissolve only, no movement: core navigation gets the least motion in the app. Rail tiles: the selection ring fades in 120 ms. |
| 14 | Waiting lines (`ToolbarButton` busy, connect rows, "Show earlier") | Appeared and vanished at once | State indication | Occasional | Fade in and out (200 ms); the lines themselves were already clock-driven and still under Reduce Motion. |

## Part 2: Rejected

- Rail project tiles on hover: tens of times a day; the selection ring and the press scale are enough. **Frequency.**
- `DeliveryStrip` and the delivery bar growing on load: data the user reads. **Function.**
- A slide direction for onboarding stages (left for back, right for forward): the direction is told by the progress marks, and a view's removal transition keeps the direction it was created with, so it would lie on the second change. **Simplicity.**
- A dissolve between onboarding and the app in `ContentView`: the leaving screen holds the toolbar's search field, and a view that holds the focused field can keep its transition unfinished. **Risk over value.** The same reason `FadeSwap` is built on opacity rather than on a transition.
- Rotating the Refresh glyph while loading: a spinner by another name. **No spinners.** The waiting line along the button's foot does the job.
- Message rows entering with a stagger when the room opens: 30 rows of conversation the user came to read. **Function.**
- A hold-to-confirm on "Remove project" and "Delete preview": macOS confirmation dialogs already stand between the click and the action. **Purpose.**

## Part 3: Verdict

Dever is a crisp daily dashboard, so it needs little motion and most of it should be felt, not
seen: 120 ms hover tones, 200 ms dissolves, counters that roll. The one place that deserved a
real movement was the Slack rail growing into the reading room, and that is where the time went:
one spring, the panel as the mask, the messages laid out once at their final width. Everything
else is a short fade that keeps a state change from being a cut.

## Verification

Captures in both modes of every screen after the change (`DEVER_SNAPSHOT_*`), plus eight-frame
filmstrips of the room opening, the thread opening and the way back
(`DEVER_SNAPSHOT_SLACK_MID=1`). The thread pane was caught half-way across the aside and the
way back half-way through its cross-fade with the work column sliding in. A limit of headless
captures: SwiftUI's animation clock stops while the window is off screen (another Space, or a
Keychain dialog in front), and frames taken then show a transition frozen at its start, so a
frozen frame proves nothing on its own; the Snapshotter now brings the window to the front first.
Not verified by eye: the appearance cross-fade and the editor steps, which only run from a click.
