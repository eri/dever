# Overview — redesign review

Scope: the Overview page (`Sources/Dever/Views/OverviewView.swift`, data from
`Model/OverviewStore.swift`, settings in `Model/OverviewSettings.swift` and
`Views/OverviewSettingsView.swift`, the Overview section of Settings), loaded, loading, grouped,
compact, filtered-empty and no-project states, dark and light, at the 1080×680 minimum window.
Stack: SwiftUI, soot tokens (`Views/SootUI.swift`), `ToolbarButton`, `LimeButton`, `QuietButton`,
`SegmentPicker`, `SettingRow`, `Skeleton`, `PipelineGlyph`, `PreviewPhaseGlyph`, `BrandLogo`.
Conventions read: `README.md`, `docs/accessibility-review.md`, `docs/reviews/settings.md`,
`docs/reviews/project-work-view.md`, `docs/skills/superfuture-design-review.md`,
`docs/skills/find-animation-opportunities.md`.
Method: the `better-interface` orchestration (jakubkrehel/skills, cloned fresh; the six domain
skills applied by hand), the accessibility review, then the animation sweep. Evidence: captures from
`DEVER_SNAPSHOT_SIZE=1080x680` with `DEVER_SNAPSHOT_WAIT=14` (loaded), `=0` (skeletons),
`DEVER_SNAPSHOT_OVERVIEW="group=health,density=compact,sort=name,hideFinished=1"` and
`DEVER_SNAPSHOT_OVERVIEW_VIEW=1` (the View popover).

## Before

A title and a one-sentence "finding", a four-cell KPI strip that doubled as the filter, then a
bordered table on the blue-grey framed sheet (`Theme.*`): 72px rows with a status pill beside the
name, the channel and the Linear project as a second line, a delivery strip with a caption,
"Pull requests", "Pipeline" and "Slack this week" columns, a black "Add project" pill. Order and
filter were the page's own; nothing of it was a setting.

## After

One table on one surface: the name (mark, name, the logos of the linked tools), then one cell per
tool (Slack: messages this week and the last message's age; Linear: a shipped bar and `shipped/total`;
GitHub: the pipeline's glyph and word, open pull requests), the preview's phase, the target date,
and the health as a glyph and a word. Above it the counts in one quiet line ("4 projects ·
2 incomplete · 2 on track · updated now"), on the right Refresh, View and the lime Add project.
Order, grouping, density, columns, pinning and hiding finished projects live in Settings › Overview
and in the page's View popover, both the same `OverviewSettingsView` writing `AppState.overview`.

## Findings (ranked) and what was applied

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Layout | first pass of the new table | Column widths added up to 1136px with the rail: the window's own content overflowed at 1080px (rail and chevron clipped in the capture) | Columns 76/136/124/96/72/124, 14px gaps, 150px name minimum: 1048px in all, verified in the 1080×680 capture | Content clipped at a supported size is a trigger |
| HIGH | Accessibility | `PinButton` | The pin read `isFocused` outside the focusable button, so a keyboard user could land on an invisible control | `@FocusState` on the button itself; the pin shows on hover, on focus and when pinned | 2.4.7: a focused control has to be visible |
| MEDIUM | Layout | old `OverviewView` KPI strip + title finding + list | Three structures: a sentence, a strip of four big numbers, a table | One structure: the counts become the line under the title, the filter becomes grouping in Settings | The user's rule: one list, no grid of unrelated blocks |
| MEDIUM | Consistency | whole page | `Theme.*` framed sheet, `PrimaryButtonStyle`-like black pill, `Pill` status badges | `Soot.*` ground and surface, `ToolbarButton`, `LimeButton`, `FocusOutline`, 28px headline like Settings | The onboarding, Settings and the project page are soot; the Overview was the last framed sheet |
| MEDIUM | Writing | old row second line "#23-leaderboard · No Linear project", "Link a Linear project to see delivery" | Sentences in cells | A dash for "not linked" (tooltip says why), the tool logos beside the name say what is linked | As little text as possible; the row's shape stays the same |
| MEDIUM | Accessibility | old status pill (colour tint + word), old pipeline "No runs" with no glyph | Status partly by tint | `HealthMark`: glyph + word, `PipelineGlyph` + word, target date past = glyph + the negative colour + "past" in the VoiceOver summary | 1.4.1: never colour alone |
| MEDIUM | Layout | columns setting, first pass | Six chips in one 56px row did not fit beside the label | Two rows of three, trailing-aligned in Settings, leading-aligned in the popover | Nothing clipped, the row keeps its label |
| LOW | Writing | summary line | "4 project" | "4 projects" / "1 project" | Plural |
| LOW | Writing | filtered-empty row | "The one project is finished and hidden" | "Every project is finished and hidden" + "Show finished projects" | One sentence for every count, with the way back |
| LOW | Typography | counts and dates | — | `monospacedDigit()` on every number that changes | Tabular numbers on changing values |

Declined: a search field on the page (the toolbar's `.searchable` stays, it is native and ⌘F);
column sorting by clicking headers (sorting is a setting, by design); hiding the health column when
grouped by health (the row's shape stays the same whatever the grouping).

## Strengths

- One structure: every row has the same seven cells, groups are rows inside the same table.
- The settings are real: `AppState.overview` persists as JSON in UserDefaults, the page and both
  entry points (Settings › Overview, the View popover) read the same value, snapshots can simulate it.
- Skeletons at the exact size of the value they stand for, so nothing shifts when data lands.
- Health, pipeline, preview and target are each a glyph and a word.

Highest-leverage change made first: the single table with settings-driven order and grouping.

## Settings added

| Setting | Values | Where it bites |
| --- | --- | --- |
| Sort by | name, activity (last Slack message), health, target date | `OverviewView.ordered` |
| Group by | none, health, repository (first followed), team (Linear team, now fetched) | `OverviewView.sections` |
| Density | comfortable (56px rows), compact (44px) | `ProjectRow`, `GroupRow` |
| Columns | any of Slack, Linear, GitHub, Preview, Target, Health | `ColumnHeader`, `ProjectRow` |
| Quiet after | 7, 14 or 30 days without a Slack message before a project reads Quiet (`Preferences.quietAfterDays`) | `Project.status` |
| Pinned projects | always first, no switch: a pin that does not move the project means nothing. Pinned from the row (pin button, context menu), stored as `Project.favorite` | `OverviewView.ordered` |
| Hide finished projects | every Linear issue done | `OverviewView.visible`, with "Show finished projects" when all are hidden |

## Animation sweep (find-animation-opportunities)

| # | Location | Today | Purpose | Frequency | Motion |
| --- | --- | --- | --- | --- | --- |
| 1 | Rows on the page's first appearance | popped in | Preventing a jarring change | Occasional (page open) | opacity 0→1 and 8px rise, 300ms ease-out, 40ms stagger capped at 12 rows; Reduce Motion: fade only, 200ms |
| 2 | Skeleton → value in every cell | swap | State indication | Occasional (refresh) | `.transition(.opacity)` under `.animation(.easeOut(0.25), value: loaded)`; Reduce Motion: instant |
| 3 | Counts (summary line, Slack messages, shipped) | swap | Feedback | Occasional | `contentTransition(.numericText())`, 250ms ease-out |
| 4 | Shipped bar | static | State indication | Occasional | fills from 0 on first appearance and re-fills on change, spring 0.45 / 0.9; Reduce Motion: none |
| 5 | Sort / group / pin changes | teleport | Spatial consistency | Occasional (a setting) | rows and group rows move as identified `ForEach` children under spring 0.4 / 0.85; Reduce Motion: instant |
| 6 | Row hover | none | Feedback | Tens of times a day | background tone only, 150ms ease-out; no movement |

Rejected: press scale on rows (core navigation, tens of times a day: gate 1); custom popover
motion (the system's; gate 2 has no purpose); animating the summary line's reorder (data the user
reads: gate 4); a shimmer on skeletons (the project's `Skeleton` pulses on its own, gate 3).

## Not verified

- The reorder spring and the numeric counters were checked in code, not replayed at 10% speed.
- VoiceOver's reading of the row summary (`accessibilityLabel`) was checked in code only.
- Group by team needs a Linear project with a team; the test workspace's projects have one but
  the capture ran grouped by health.

## Round 3 — what is waiting for you

The table above is superseded. A developer rarely follows more than two projects at once, so the
page now answers "what is waiting for me", with what waits listed under its project.

**Row.** Mark, name, a lime "N for you" chip when something waits (otherwise the last activity in
one muted line: "Ana wrote in #proj-search · 1d", "sam merged #212 · 3d"), the optional columns,
then one status at the trailing edge: what blocks (CI failing, preview failed, past due date, a
pull request waiting for a review for more than three days), else how much has shipped
("15/16 shipped" with a small bar), else the one link an incomplete project lacks, as a
secondary "Link Linear" / "Link Slack" button that opens the editor on that step.

**Items.** Under a project with things waiting, one line each, indented under the name: icon,
sentence, age. Mentions first ("Léa: can you check the staging build? · 40m"), then review
requests ("Review #4871 Tip preview width · 2h"), then one line for the rest of the unread
messages ("6 more unread in #proj-checkout"). Three at most, then "Show all N". A click opens the
item inside Dever: a Slack message opens the project's reading room on it (earlier pages load
first when needed); a pull request opens the page of the Linear issue it belongs to, or the
project page when it belongs to none. When nothing waits anywhere, the list stays plain: no
empty block, no message.

**What counts as waiting.** Pull requests of the project (the shared-repository scoping applies)
whose review is requested from your GitHub login; unread messages in the project's channel since
Slack's read cursor, which Dever moves when you read the channel here, from others, over the last
seven days; among them, the ones that name you, put forward. Your own tickets and pull requests
are not in this list.

**Order.** Pinned first, then projects where something waits, then the most recently active
(the newer of the last message and the last merge). Settings › Overview › Sort offers For you
(that order), Activity and Name.

**Columns.** None by default: the row already says what waits, what happened last and what
blocks. Slack (unread messages), Linear, GitHub, Preview and Due date stay available in the View
popover and in Settings › Overview. The Health column is gone: the trailing status says it in
words. The settings moved to the `overview.v2` key, so the table's saved choice (every column on)
does not carry over.

**People only.** Joins, renames, pins, topics and what apps and bots post (an alerting bot added
to the channel, say) neither count as unread nor become the last activity.

**Motion.** Items enter with `Motion.rise`, the chip with `Motion.pop`, reorders on `Motion.move`,
counts roll; all fade only under Reduce Motion.

**Accessibility.** A row reads "Checkout, pinned, 4 for you, 7 unread in Slack, 15 of 16 shipped";
each item reads its sentence and its age, with the hint "Opens the message in the project" or
"Opens the pull request in the project"; the items of a project are a group named "Waiting for you
in Checkout". Status is a glyph and a word; the mention icon is lime and also an "@".

**Demo.** `DEVER_SNAPSHOT_OVERVIEW_DEMO=busy|quiet` (with `DEVER_SNAPSHOT_DIR`) runs the page on a
made-up workspace: waiting items, a failing pipeline, a long-waiting pull request, a finished
project and an incomplete one; `quiet` is the same with nothing waiting.

**Not verified by hand.** Real unread counts and mentions against a live channel, review requests
on live pull requests (the workspace had none asked of the viewer), the deep links landing on the
message and on the issue page, VoiceOver.
