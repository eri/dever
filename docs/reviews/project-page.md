# Project page — one panel grammar

Scope: every block of the project page (`Sources/Dever/Views/ProjectDetailView.swift`,
`Views/PreviewPanel.swift`, `Views/ProjectPanels.swift`, the in-panel connect invitation of
`Views/ConnectStates.swift`), in these states: complete project, project without Linear, without a
preview, without Slack, with no tool at all, Linear linked but not connected, loading; dark and light.
Stack: SwiftUI, soot tokens (`Views/SootUI.swift`), `BrandLogo`, `Motion`. Conventions read: `README.md`,
`docs/accessibility-review.md`, `docs/reviews/project-work-view.md`, `docs/reviews/project-preview.md`,
`docs/skills/superfuture-design-review.md`, `docs/skills/find-animation-opportunities.md`.
Method: the superfuture rubric, the `better-interface` orchestration (its six domains applied by hand;
the skill is not installed in this session), the accessibility pass, then the animation sweep.
Evidence: `project-{dark,light}.png` from the runs listed under Verification.

## Before

A project with Slack and a repository but no Linear project showed three blocks built three ways:

- **Preview**: its own header (15pt title, globe, 16px padding), a 20-word sentence, an outlined
  "Add a preview" and a lime text link "No preview needed". The secondary action wore the accent.
- **Pull requests**: `PanelHeader` (17pt, no logo), then one muted 21-word line with a link glyph
  and nothing to click. The only way to link Linear was "Edit project", then the Linear row.
- **Slack**: a third header (16pt, hand-built), and for a project with no channel a dashed
  `EmptySection` in the old `Theme.*` tokens.

## Findings

| # | Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 🔴 | States | Pull requests without Linear | A sentence, no action | Linear logo, "Link a Linear project to see its pull requests", lime **Link Linear** opening the editor on its Linear step | An empty state that names the fix must offer it; the page had a dead end |
| 2 | 🟠 | Consistency | The three panel heads | 15 / 17 / 16pt titles, logo or not, 16 or 20px padding | One `PanelHeader` everywhere: 18px logo-or-glyph slot, 17pt title, one 12pt line, trailing action; every block is `sootPanel()` (20px, radius 12) | Three grammars on one page read as three products |
| 3 | 🟠 | Hierarchy | Preview, no pull request | Outlined primary, lime secondary | Lime **Add a preview**, quiet outlined **No preview needed** | The accent belongs to the one action that moves the project forward |
| 4 | 🟠 | Writing | Empty states | 20 and 21 words; "No Slack channel" + a sentence | One line of at most 8 words each (table below); the reason moved to the button's tooltip | The onboarding's voice: a line and a control |
| 5 | 🟠 | States | Slack, no channel; Delivery, no repository | Dashed `EmptySection`; nothing | The same tile with **Link Slack** / **Link a repository**, each opening its editor step | Same shape, same verb as the header's "+ Link a tool" |
| 6 | 🟠 | Consistency | `ConnectPanelBody` (tool linked, account not connected) | Bold "Connect X" title, a second line, a button repeating the title | The same tile: logo, one line, **Connect X** | The title said what the button says; link and connect now differ only by their verb |
| 7 | 🟡 | Layout | Panel heads | The preview's `#number` pill made its title row 2px taller | Title row fixed at 22px | Titles of adjacent panels sit on one line |
| 8 | 🟡 | Writing | Slack head with no channel | "0 messages this week" | "No channel yet" | A count of nothing for a thing that does not exist is a misleading state |
| 9 | 🟡 | Layout | `QuietEmpty` | Label at 12px padding, 38px tall | Glyph in the 18px slot, 46px row | Lines up with the rows it replaces |
| 10 | 🟡 | Affordance | Delivery / Pull requests head | No way to the tool from the head | Trailing "Open ↗" to the Linear project or the repository's pull requests | The head's fourth slot was empty on two panels out of three |
| 11 | 🟡 | Affordance | Header "+ Link a tool" | Opened the editor's recap | Opens the first missing tool's step (Slack, else Linear) | Same destination as the panel's button, one click less |

Empty-state lines (words): "Link a Linear project to see its pull requests" (8) · "Link a tool to see the
work here" (8) · "Link a repository to see its pull requests" (7) · "Link a channel to read it here" (7) ·
"Follow a pull request's preview here" (6) · "No messages yet" (3).

All eleven are applied.

### Coverage (better-interface)

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | New buttons, tile, header link, glyph slot; pairs measured (see `docs/accessibility-review.md`, Project page) | Clear after 1, 5, 6 |
| Layout | Heads, tile, row heights (46 issue row, 56 pull request row, 46 quiet line, 68 tile), the 420px Slack rail | 7, 9 |
| Writing | Every string of the empty states and heads | 4, 8 |
| Typography | Sizes 32 / 17 / 14 / 13 / 12 and 11 mono; the 15 and 16pt titles are gone | 2 |
| Colors | Lime only on the primary and on links; tile `Soot.ground` at 60 % on surface | 3 |
| UI | Press scale and focus outline come with `LimeButton` / `QuietButton`; hover tones unchanged | Clear |

### Left as recommendations

- Slack messages keep their own rhythm (32px avatar, 14px between authors, grouped lines tighter): an
  ungrouped message is never under 46px, but forcing one row height on prose would hurt reading.
- The preview's "More" menu is a system menu behind a soot button. A soot popover would match the
  rest; it is a restructuring of the preview actions, not a safe fix.
- With several tools unconnected the page still shows `ConnectSection` on top and bar placeholders in
  the panels; that state has its own review (`connection states`) and was left as is.

## Animation sweep (find-animation-opportunities)

| # | Location | Today | Purpose | Frequency | Suggested motion |
| --- | --- | --- | --- | --- | --- |
| 1 | Empty tile → content, after the editor links the tool | Swapped at once | Preventing a jarring change | Rare | `Motion.ui` (200 ms ease-out), opacity only, keyed to `project.linear == nil`, `repos.isEmpty`, `project.slack == nil`, `project.previewPullNumber == nil`; same under Reduce Motion (a dissolve) |
| 2 | Skeleton → empty tile or content in the work panel | Already 200 ms on `loaded` for the column | State indication | Occasional | Same curve on the panel itself, so the Slack panel's hand-over and the work panel's match |

Applied: both, with `.motion(_:fade:value:)` only. Button feedback needed nothing: `LimeButton` and
`QuietButton` already scale to 0.97 for 120 ms on press and stay still under Reduce Motion.

Rejected:
- A staggered entrance of the panels: the page is opened tens of times a day (frequency).
- A lime pulse on "Link Linear": decoration on a control the user is about to read (function).
- A rise on the empty tile: it is there from the first frame, nothing to bridge (purpose).

Verdict: the page needed two dissolves and nothing else; the highest-leverage one is the hand-over
after linking, which is the moment the redesign exists for.

## Verification

Captures, each `project-dark.png` and `project-light.png`, 3024×1898:

| State | Run |
| --- | --- |
| Complete | `DEVER_SNAPSHOT_PROJECT=0` |
| Without Linear | `DEVER_SNAPSHOT_PROJECT=2` (a project with a channel and the shared repository) |
| Without a preview | `DEVER_SNAPSHOT_PROJECT=0 DEVER_SNAPSHOT_UNLINK=preview` |
| Without Slack | `DEVER_SNAPSHOT_PROJECT=0 DEVER_SNAPSHOT_UNLINK=slack` |
| No tool | `DEVER_SNAPSHOT_PROJECT=3 DEVER_SNAPSHOT_UNLINK=slack DEVER_SNAPSHOT_REPO_MODE=perProject` |
| Linear not connected | `DEVER_SNAPSHOT_PROJECT=0 DEVER_SNAPSHOT_DISCONNECTED=linear` |
| Loading | `DEVER_SNAPSHOT_PROJECT=0 DEVER_SNAPSHOT_WAIT=0` |

`DEVER_SNAPSHOT_UNLINK=slack,linear,github,preview` is new: the captured project runs as if it had
not linked those tools. A snapshot run never writes `projects.json` (guarded in `saveProjects`).

Not verified at runtime: the click on **Link Linear** / **Link Slack** / **Link a repository** landing
on its editor step (the path is the one "Add a preview" already used, `ProjectEditorSheet.openAt`);
the two dissolves replayed; VoiceOver's reading of the tile.
