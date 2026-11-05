# Project page: Issues and Pull requests → one Work list

Scope: the project page's Delivery, Issues and Pull requests panels (`Sources/Dever/Views/ProjectDetailView.swift`,
`Sources/Dever/Views/ProjectPanels.swift`, `Sources/Dever/Model/Delivery.swift`), loaded, loading, empty and
not-connected states, dark and light. The Slack rail and the issue page are out of scope.
Stack: SwiftUI, soot tokens (`Soot.*` in `SootUI.swift`), `TileRow` / `TileLink` rows, `CountTabs`.
Conventions read: `README.md` (screenshots), `docs/accessibility-review.md` (measured palette),
`docs/skills/superfuture-design-review.md`. No CONTRIBUTING or design-system doc exists.
Evidence: `project-{dark,light}.png` captured with `DEVER_SNAPSHOT_WAIT=12` on the "AI Tips" project
(15 issues, 15 merged pull requests, 0 open, 0 runs), plus the source lines cited below.

## Before

### Coverage (better-interface)

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | `TileLink`, `TileRow`, `CountTabs`, `PanelHeader`, stage legend, `deliveryBar`, focus outlines, names | 1 finding |
| Layout | Panel order and heights on the captures, tab bars, row slots, fold position | 3 findings |
| Writing | Panel titles, tab labels, stage labels, empty states, "Open ↗" links | 3 findings |
| Typography | Sizes 34/17/14/13/12, `monospacedDigit` on counts, truncation with `.help` | Clear (12pt secondary is the project's own floor) |
| Colors | Icon tints in `pullRow`, `PipelineBadge` tokens, stage colours | 1 finding |
| UI | Hover tiles, skeleton pulse (reduced-motion paused), tab fills | Clear |

### Findings

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Layout | `ProjectDetailView.swift:330` (`issuesPanel`), `:475` (`githubPanel`) | Two panels, two tab bars. Issues tabs are Linear states (In progress / In review / To do / Done); PR tabs are GitHub states (Merged / Open / Pipeline). On the capture the same 15 items are listed twice, and the PR list starts at y≈1090 of a 1276px window. | One list of issues. The pull request state sits on the issue's row (merged check, open chip with its pipeline state, "No PR yet"). The delivery stages are the only filter. | Every PR Dever shows is matched to an issue (`PullRequestMatching.swift`), so the second list repeats the first with the join removed. The one fact the join produces, "does this issue have code, and where is it", is on no row: the reader has to scroll and match keys by eye. Misleads and repeats: a systemic failure. |
| HIGH | Writing | `Delivery.swift:27` vs `ProjectDetailView.swift:275`, `:313` | Three vocabularies for one row: stage "Merged, ticket not moved", list title "Merged, still in progress in Linear", and an Issues tab "In progress" that silently contains those merged issues (the tab filters on Linear's `started` type, the stage on the join). | One set of names, the delivery stages, used for the bar, the legend, the filter and the list. "Merged, ticket not moved" stays; the list title goes. | One voice, one vocabulary. "In progress 4" in Issues and "In progress 2 · Merged, ticket not moved 2" in Delivery describe the same four rows with different numbers; the reader cannot reconcile them. |
| MEDIUM | Accessibility | `ProjectDetailView.swift:236` (stage legend), `:256` (`deliveryBar`) | The legend's dot + count + label reads like the tabs under it but is static text; the bar is `accessibilityHidden`. There is no path from a stage to its issues. | The legend is the filter: `CountTabs`-style buttons with the stage dot, selection exposed as `isSelected`; the bar dims the stages not selected. | A control styled like static text (and vice versa) breaks "keep controls distinct from content"; the stage counts are the question the page asks, and they lead nowhere. |
| MEDIUM | Layout | `ProjectDetailView.swift:471` (`pullTabs`) | `Merged 15 · Open 0 · Pipeline 0`: empty tabs are shown, while `issueTabs` (`:315`) drops empty ones. | Empty stages are left out, as `CountTabs` already does for issues. | Same component, two behaviours; two dead tabs on the capture. |
| MEDIUM | Layout | `ProjectDetailView.swift:525` (pipeline tab) | Runs are listed by workflow name and branch, at most 8, no "Show all"; the reader must map a branch back to a PR. | The latest run of a PR's branch becomes a glyph on that PR's chip (check, cross, clock) and one summary line in the Delivery header. | Order by importance: the run matters through its PR, not on its own. The list also breaks the 6 + "Show all" cap every other list follows. |
| MEDIUM | Colors | `ProjectDetailView.swift:508`, `:520`; `Components.swift:45` (`PipelineBadge`) | Merged icon `Soot.lime` (the one action colour), open icon `Theme.chart2`; `PipelineBadge` text in `Theme.text` / `Theme.muted` (the old theme's greys, `#B4B6B8` dark) inside soot panels. | Lime stays for actions only. Merged → `Theme.chart1` (the Done stage colour), open → `Theme.chart2` (In review), draft → `Soot.muted`; text in `Soot.ink` / `Soot.muted`. Each paired with its glyph. | Use a token only in its role: lime on a merged icon says "act here" about something finished, and two greys for secondary text in one panel. |
| MEDIUM | Writing | `ProjectDetailView.swift:332`, `:477` (`PanelHeader(link:)`) | Two "Open ↗" links, one to Linear, one to GitHub, with the same label. | Delete both: the tool chips under the title already open each tool, with "Open X in Linear/GitHub" names. | Links describe their destination; two identical labels on one page cannot. Cheapest fix is deletion. |
| LOW | Writing | `ProjectDetailView.swift:522`, `:511` | The trailing slot of a PR row holds the author on open rows, "Draft" on draft rows and a date on merged rows. | One meaning per slot: the state glyph on the chip, the date in the row's trailing text. | A slot that changes meaning per row cannot be scanned down. |
| LOW | Writing | `ProjectDetailView.swift:233` | "100 % · 15 of 15 shipped" beside "15 In review". | Keep "shipped" (code landed is Dever's definition), and show the merged chip on each row so the headline is visibly true. | The headline and the legend seem to disagree until the rows explain it. |

### Verification (before)

- `./scripts/build-app.sh` then `DEVER_SNAPSHOT_WAIT=12 DEVER_SNAPSHOT_DIR=… ./build/Dever.app/Contents/MacOS/Dever`: `project-dark.png`, `project-light.png` captured; the PR panel's rows are below the fold in both.
- Contrast computed from tokens (see `docs/accessibility-review.md`): every text pair on the panels passes 4.5:1; `Soot.edge` tab strokes 3.9:1 dark / 3.1:1 light.
- Not verified: keyboard walk and VoiceOver reading (by code: rows are `NavigationLink`s or `Link`s with `FocusOutline`; tabs are `Button`s with `isSelected`).

Verdict (before): **Block**. Two `HIGH` findings.

### Rubric pass (superfuture design-review)

🔴 Blocking
- **What** Two lists for one set of items (Issues and Pull requests). **Why** The eye has no single focal list; the page asks "what is left to ship" and answers it in two places with different counts. **Fix** One Work list under the Delivery headline; PR state on the row.
- **What** Three names for the merged-but-open state. **Why** Microcopy that disagrees reads as a bug. **Fix** The delivery stage labels, everywhere.

🟠 Important
- **What** Stage legend looks like the tabs (dot, bold count, label) but is inert. **Why** Affordance mismatch; the most informative numbers on the page do nothing. **Fix** Make the legend the tab bar, 30px capsules, lime fill when selected (as `CountTabs`), bar segments at 35% when not selected.
- **What** `Merged 15 · Open 0 · Pipeline 0`. **Why** Dead controls; inconsistent with the Issues tabs. **Fix** Drop empty stages.
- **What** Pipeline runs as a list of workflow names. **Why** No relation to the row the reader cares about. **Fix** Run state as a glyph on the open PR chip; one summary chip in the header.
- **What** Lime merged icon, old-theme greys in `PipelineBadge`. **Why** Accent used off-role, two secondary greys. **Fix** `Theme.chart1` / `Theme.chart2` / `Soot.muted`; `Soot.ink` text.

🟡 Polish
- Two "Open ↗" links; trailing slot meaning varies per row; "shipped" vs "In review" headline.

**Strengths**
- The delivery headline + bar is a clear focal point: 34pt tabular figure, muted sentence, one bar.
- Rows are one language: `TileRow` / `TileLink`, 46px, hover lift, `FocusOutline`, title tooltip on truncation.
- `CountTabs` drops empty tabs, exposes selection, has a 3.9:1 edge and a lime fill with 16:1 label contrast.
- Every text pair passes 4.5:1 in both modes; the skeleton pulse pauses under Reduce Motion.

**Highest-leverage change**: replace the Issues and Pull requests panels with one list of issues filtered by
the delivery stages, with each issue's pull requests on its row.

## After

### The layout decision

The two panels are gone. One **Delivery** panel holds the headline (shipped %), the bar, the stages
as a tab bar (with "All"), and one list of issues. Each row is an issue; its pull requests sit on the
row as chips (`PullChip`: merge glyph for merged, pull glyph for open, pencil for draft, plus the
latest pipeline run of the branch as a check / cross / clock), "No PR yet" on started issues once
GitHub has loaded, and "+N" past two chips. The row opens the issue page; a chip opens the PR on
GitHub (`WorkTile` keeps the chips outside the navigation link, so each click goes to one target
and the focus ring spans the whole row).

Why one list and not two: every PR Dever shows reaches the page through an issue
(`PullRequestMatching.swift`), so the PR list was the issue list with the join stripped. The join is
the product; it now sits on the row, and the stage counts, the bar, the filter and the rows come
from one function (`Delivery.stage(stateType:stateName:openPR:mergedPR:)`), so they cannot
disagree. Under "All" the list is sorted by attention: merged but not moved first, then in review,
in progress, to do, done last. The bar dims the stages that are filtered out.

What keeps its own place:
- **Pull requests no issue cites** (whole-repository projects, or Linear not loaded): a titled
  list under the issues, two-line rows, same 6-row cap. The matcher now keeps unmatched PRs for
  whole-repository projects instead of skipping the match, so their linked PRs still land on rows.
- **A project with GitHub only**: the panel is titled "Pull requests" and lists them.
- **Pipeline runs**: no longer a tab. The run is a glyph on the open PR's chip, and one summary
  link in the headline row ("1 pipeline failing" / "Pipeline running" / "Pipelines passing") opens
  the repository's workflow runs. Nothing is shown when no open PR has a run.
- **GitHub's own states** (connect invitation, placeholder, failure row) sit at the foot of the panel.

Removed: the two "Open ↗" header links (the tool chips under the title open each tool),
`PipelineBadge` on this page, the Issues tabs, the "Merged, still in progress in Linear" list
(its action, "Update N in Linear ↗", now sits beside the stage tabs while those issues are listed).

### States

| State | Capture | What shows |
| --- | --- | --- |
| Loaded, dark and light | `after/project-{dark,light}.png` | Headline, bar, `All 15 · In review 15`, six rows with a merged chip each, "Show all 15". The whole panel fits above the fold (before: the PR rows started at y≈1090). |
| Loading | `loading/project-dark.png` (`DEVER_SNAPSHOT_WAIT=0`) | Skeleton of the same shape: figure, bar, four tab pills, five rows with glyph, key, title, chip and avatar. One accessibility element, "Loading the project's work". |
| GitHub not connected | `github-off/project-{dark,light}.png` (`DEVER_SNAPSHOT_DISCONNECTED=github`) | Rows without chips, no "No PR yet", `Connect GitHub` body at the foot. |
| No issues, no GitHub | `linear-only/project-dark.png` (`DEVER_SNAPSHOT_PROJECT=1`) | "No issues in this project yet"; no GitHub part. |
| Issues but no PRs | by code (`linearPart`) | Rows, then "No pull request cites one of these issues yet". |
| Whole-repository PRs with no issue | by code (`githubPart`) | "Pull requests without an issue" list under the rows. |
| Linear failing / unauthorized / offline | by code (df12501 handling kept) | `ServiceFailureRow` in place of the headline; GitHub's PRs listed as "Pull requests" when loaded. |

### Rubric pass (superfuture design-review), after

🔴 Blocking: none.

🟠 Important
- **What** With one stage, the tabs read `All 15 · In review 15`. **Why** Two tabs with the same count. **Fix** Deliberately kept: the stage tab is also the bar's legend (the dot and name are the only label the blue segment has). Hiding it would leave the bar unlabelled.

🟡 Polish
- Four skeleton tab pills whatever the project ends up with; the loaded page may show two. Harmless.
- "To do" dot (`Theme.empty`) sits at 1.4:1 / 1.1:1 on a tab; it carries a 1px `Soot.edge` ring (3.9:1 / 3.1:1) and the stage name, so it is not relied on.

**Strengths**
- The page answers its question in one place: a figure, a bar, the stages, and the rows that make them up.
- The row is still the `TileRow` language, 46px, with the PR as a bordered 26px capsule chip (control distinct from content).
- Keyboard: Tab reaches each row (ring around the whole tile), then its chips; tabs expose `isSelected`.

### Measured (chips and glyphs, on `Soot.surface`)

| Pair | Dark | Light | Need |
| --- | --- | --- | --- |
| Chip number `Soot.ink` | 17.40:1 | 18.88:1 | 4.5 |
| Chip stroke `Soot.edge` | 3.51:1 | 3.45:1 | 3 |
| Merged glyph `Theme.chart1` | 6.93:1 | 5.99:1 | 3 |
| Open / running glyph `Theme.chart2` | 6.59:1 | 5.05:1 | 3 |
| Passing glyph `Theme.positive` | 7.49:1 | 5.25:1 | 3 |
| Failing glyph `Theme.negative` | 4.88:1 | 5.78:1 | 3 |
| Draft glyph, "No PR yet", "+N" `Soot.muted` | 5.38:1 | 6.05:1 | 4.5 (text) |

Every glyph is paired with a shape (merge / pull / pencil; check / cross / clock) and a word in the
tooltip and the accessible name, so no state is carried by colour alone.

### Verification (after)

- `./scripts/build-app.sh`: clean (the three pre-existing `await` warnings in `OverviewStore.swift` are untouched).
- Captures listed above, both modes, at the default window size; the two-column layout holds, the
  stage tabs and "Update N in Linear ↗" fall back to two lines through `ViewThatFits` when the column is narrow.
- Not verified at runtime: the click split between row and chip (by construction: the chips are an
  overlay outside the `NavigationLink`), VoiceOver reading, a project with open PRs and runs (the test
  projects have 15 merged / 0 open), a whole-repository project.

Verdict (after): **Approve**. No `HIGH` findings remain; one `MEDIUM` kept on purpose and two `LOW` noted.

## After, revision 2: the ledger

Feedback on revision 1: GitHub must stay a visible presence on the page. Dever is sold as joined to
GitHub, and a list where GitHub survived only as a 26px chip lost that. Revision 2 keeps the one
list but gives each tool its own column.

### Shape

The Delivery panel is a **ledger**: a Linear column and a GitHub column, each headed by the
tool's logo and name (`Issues` / `Pull requests`, with a hairline under the headings), one issue
per line, its pull requests beside it. The GitHub column is 310px; each pull request in it is its
own tile (state glyph, `#number`, what changed, then `merged · 3 days ago` or `passing · open ·
author`), two at most, then "+N more". A started issue with no PR says "No PR yet"; a to-do or done
issue without one shows an em dash. Each column cell is its own target: the left tile opens the
issue page, the right tile opens the PR on GitHub. In the headline row, beside the shipped figure,
a GitHub line (`[logo] 0 open · 15 merged`, plus the pipeline glyph and word when an open PR has a
run) opens the repository's pull requests.

Why this beats revision 1: the join is now visible as a shape, two sources on one line, not as a
badge; GitHub is named three times on the panel (headline, column heading, every row) without a
second list; and both cells keep the row language (46px tiles, hover lift, focus ring).

Trade-off accepted: the issue title has ~300px less; it truncates sooner, with the full title in a
tooltip and on the issue page. Without GitHub the ledger has one column and no heading row for it.

Captures: `ledger/project-{dark,light}.png`, `ledger-loading/project-light.png` (skeleton of the
same two-column shape), `ledger-github-off/project-dark.png` (empty GitHub column under its heading,
`Connect GitHub` at the foot).

### Accessibility pass (better-accessibility, by code and captures)

| Check | Where | Result |
| --- | --- | --- |
| Accessible names on every control | left tile `"INA-1050, title. In review"`, right tile `"Pull request #4872, Sync tips…, merged, 3 days ago"`, GitHub headline link, stage tabs (text + count), Show all | Pass |
| Visible focus indicator | `TileLink`, `TileRow`, `HoverLink`, `CountTabs`: `FocusOutline` 2px `Soot.ink`, 17:1 dark / 18:1 light against the surface | Pass |
| Keyboard path for every pointer path | rows are `NavigationLink`s, PR tiles and the headline are `Link`s, tabs are `Button`s; nothing relies on hover | Pass |
| Meaning not by colour alone | PR state: glyph shape + word ("merged", "open", "draft"); pipeline: check / cross / clock + word; stages: dot + name + count | Pass |
| Text contrast 1.4.3 | ink 17.4 / 18.9:1, muted 5.4 / 6.1:1 on the surface; column headings ink 13pt semibold | Pass |
| Non-text contrast 1.4.11 | tab edge 3.9 / 3.1:1 (on ground); glyphs 4.9–7.5:1 on the surface; the heading hairline is decorative | Pass |
| Target size 2.5.8 (24px) | tiles 46px, tabs 30px, headline link 28px | Pass |
| Headings as structure | panel title, column headings (`isHeader`, "Issues, from Linear") | Pass |
| Loading announced once | skeleton is one element, "Loading the project's work"; empty GitHub cell hidden until GitHub has loaded | Pass |
| Reduced motion | no new motion; skeleton pulse pauses under Reduce Motion | Pass |
| Truncated content has a way back | tooltip on both titles (pointer), and the row opens the full issue or PR (keyboard) | Pass |
| 200% text | fixed point sizes, as the rest of the app (`docs/accessibility-review.md` advisory) | Not verified |
| VoiceOver reading order | by code: heading row, then left cell, right cell per line | Not verified |

Verdict (revision 2): **Approve**; the two `Not verified` rows are runtime checks.
