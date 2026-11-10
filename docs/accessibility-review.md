# Accessibility review — sheets and onboarding

Scope: product UI · WCAG 2.2 AA · onboarding (4 stages), Import channels, Import projects,
New / Edit project, Connect GitHub. Contrast computed from the palette values, not eyeballed.

Verdict after fixes: ✅ 0 Blockers · 2 Warnings · 4 Advisories

## Contrast (measured)

| Pair | Ratio | Need | Result |
|---|---|---|---|
| Body text white on surface `#1a1a1a` | 17.40:1 | 4.5 | ✅ |
| Secondary text `#8f8f8f` on ground `#0f0f0f` | 5.93:1 | 4.5 | ✅ |
| Secondary text `#8f8f8f` on surface | 5.38:1 | 4.5 | ✅ |
| Lime text `#dafa9c` on ground / surface | 16.55 / 15.03:1 | 4.5 | ✅ |
| Button label on lime | 16.55:1 | 4.5 | ✅ |
| Field underline, idle | 2.34:1 → **5.93:1** | 3 | fixed |
| Radio / check ring, idle | 2.77:1 → **5.38:1** | 3 | fixed |
| Secondary button and chip edge | 1.10:1 → **3.87:1** (ground), **3.51:1** (surface) | 3 | fixed |
| Selected outline (lime 50 %) on surface | 4.65:1 | 3 | ✅ |

## Sheet redesign (filled fields)

Inputs and selects are 44px filled fields (`SootField`, `SearchPicker`) with a label above them;
the focused one gets a 2px lime edge. Measured:

| Pair | Dark | Light | Need |
|---|---|---|---|
| Field edge `Soot.edge` on ground / on surface | 3.87 / 3.51:1 | 3.13 / 3.45:1 | 3 |
| Focus edge `Soot.lime` on ground | 16.55:1 | 6.43:1 | 3 |
| Selected import row edge (lime, full) | 15.03:1 | 7.08:1 | 3 |
| Placeholder `Soot.muted` on surface | 5.38:1 | 6.05:1 | 4.5 |
| Field label `Soot.ink` on ground | 18.4:1 | 17.5:1 | 4.5 |

Disabled primary buttons use the surface fill with muted text (5.4:1) instead of a dimmed lime,
whose label measured 2.3:1.
Targets: fields and selects 44px, list rows 40–60px, chips and footer links 32px, close 32px.
Hairlines between sections (`Soot.line`) are decorative and carry no information.

## Blockers fixed

- **1.4.11 Non-text contrast** — idle field underlines, radio rings and secondary-button/chip
  edges were under 3:1; they now use `#8f8f8f` and `#707070` (`Soot.edge`).
- **3.3.2 Labels or instructions** — "Name in Dever", channel name, prefix and search fields
  relied on placeholders; each now has a visible label (`FieldLabel`) or an icon plus an
  accessible name.
- **2.4.7 Focus visible** — custom buttons, option rows and radio rows drew no focus ring;
  they now show a 2px lime ring (`FocusOutline`), 16.6:1 dark / 6.4:1 light against the ground —
  the same colour as a focused field's edge.
- **1.3.1 / 4.1.2** — the project editor's mode chips ("New / Existing / Later") were not
  understandable as a choice; they are now radio groups with full sentences
  ("Use an existing channel", "Create a new channel", "Don't link a channel for now"),
  grouped under a heading, selection exposed as `isSelected`.

## Warnings

- **2.5.8 Target size** — chips and the close button are 32px tall: above the 24px minimum,
  below the comfortable 44px. Fields, selects and rows are 44px or more.
- **1.4.1 Use of colour** — the selected option is shown by the lime ring and dot (shape and
  fill, not hue alone) and by the `isSelected` trait; keep it that way if restyled.

## Advisories (runtime, not verifiable from screenshots)

- Keyboard order and Escape/Return handling in every sheet (2.1.1, 2.4.3).
- VoiceOver reading of the radio groups and of the onboarding preview (4.1.2).
- Text size: layouts use fixed point sizes; check with larger system text.
- The connecting animation honours Reduce Motion; the skeleton pulse does too.

## Issue page (Linear)

Scope: the issue page reached from a project's Issues list, dark and light, checked on captures
(`DEVER_SNAPSHOT_ISSUE=1`). Names, focus and keyboard verified in code; contrast computed.

| Pair | Dark | Light | Need |
|---|---|---|---|
| Code accent (`MarkdownTheme.code`, teal) on ground / on surface | 7.63 / 6.93:1 | 5.44 / 5.99:1 | 4.5 |
| Banner subtitle `Soot.muted` on the lime-tinted banner (8 %) | 4.99:1 | 4.89:1 | 4.5 |
| Activity line (`Soot.ink` name, `Soot.muted` change) on surface | 17.4 / 5.38:1 | 17.5 / 6.05:1 | 4.5 |
| Chip edge `Soot.edge` on surface (status, priority, assignee, branch) | 3.51:1 | 3.45:1 | 3 |
| State dot ring (Linear's colour) | — | — | not relied on: the state name is always beside it |

- Every chip and link is a button or a `Link` with a visible shape or underline and a 2px focus
  ring (`FocusOutline`); hover adds a pill, nothing moves.
- Targets: chips 30px, links 28px, rows 46px (WCAG 2.5.8 asks 24px).
- Status changes are announced by the confirmation line (`updatesFrequently`), not by motion.
- Icons in the activity thread are decorative (`accessibilityHidden`); the sentence carries the
  change, with the state's dot as a second cue next to its name.
- Truncated titles in linked-issue rows carry the full title in a tooltip and open the issue.
- Text sizes: body 15, activity 14, secondary 13, captions 12; the title's inline code is set
  at the title size minus 1.5.

## Repository mode (onboarding stage, project editor, Settings)

Scope: the "Where's the code?" onboarding stage, the editor's Repositories step (per-project
and mixed modes), the import rows' repository match, the Repositories section of Settings, and
the repository label on pull request chips. Checked on captures in dark and light; names, focus
and keyboard verified in code; contrast computed from the palette.

| Pair | Dark | Light | Need |
|---|---|---|---|
| Mode row title `Soot.ink` / detail `Soot.muted` on surface (onboarding, editor) | 17.4 / 5.38:1 | 17.5 / 6.05:1 | 4.5 |
| Mode row title `Theme.text` / detail `Theme.muted` on the Settings panel | ≥ 12 / 5.0:1 | ≥ 12 / 5.2:1 | 4.5 |
| Idle ring `Soot.muted` on surface; selected ring and tick box (lime, full) | 5.38 / 15.03:1 | 6.05 / 7.08:1 | 3 |
| Selected mode edge in Settings (`Theme.text`, 2px) | ≥ 12:1 | ≥ 12:1 | 3 |
| Workspace repository picker edge `Soot.edge`; focused / open (lime, 2px) | 3.51 / 16.55:1 | 3.45 / 6.43:1 | 3 |
| Repository name on a pull request chip, `Soot.muted` on surface | 5.38:1 | 6.05:1 | 4.5 |

- The three mode rows are buttons in a group named "Repository mode"; each reads as
  "<title>. <detail>" and exposes `isSelected`. The selected row is shown by the filled ring and
  the edge (shape and fill, not hue alone), and in Settings by a 2px edge in the text colour.
- The editor's repository list uses a rounded tick box instead of the radio ring where several
  rows can be on at once (1.3.1: the shape says "pick several"); the count of picked
  repositories is written under the list. In mixed mode, the two radio rows ("Use the workspace
  repository" / "Its own repositories") are grouped under "Which repositories".
- The workspace repository picker is a `SearchPicker`: named "Workspace repository", value read
  as the picked name or "None", type-to-filter list, Return picks the first match. Without
  GitHub, a sentence replaces it ("Connect GitHub to pick it") rather than a disabled control.
- Every new control carries the 2px lime focus ring (`FocusOutline`); nothing moves on hover.
- Targets: mode rows 64px (onboarding) / 52px (Settings), list rows 44px, picker 40px.
  Pull request chips stay at 26px with the repository label (2.5.8 asks 24px; they sit in a
  56px row that opens the same issue).
- The pull request chip's accessible name says the repository ("Pull request #4864, in
  owner/name, open") only when the project follows more than one, so single-repository
  projects keep their shorter names.
- The one-line consequence under the Settings picker is plain text that changes with the
  mode, not a live region: the change is the user's own action.

## Settings

Scope: the Settings page (`Sources/Dever/Views/SettingsView.swift`, `GenerativeAvatar.swift`), six
sections and six account states, dark and light, captured at the 1080×680 minimum
(`DEVER_SNAPSHOT_SETTINGS=1 DEVER_SNAPSHOT_SIZE=1080x680`). Names, focus and keyboard verified in code;
contrast computed from the palette values.

| Pair | Dark | Light | Need |
|---|---|---|---|
| Headline and row titles `Soot.ink` on ground / on surface | 19.17 / 17.40:1 | 17.15 / 18.88:1 | 4.5 |
| Section lines, details and states `Soot.muted` on ground / on surface | 5.93 / 5.38:1 | 5.49 / 6.05:1 | 4.5 |
| Error lines "Session expired", "Can't reach" (`Theme.negative`) on surface / on ground | 4.88 / 5.38:1 | 5.78 / 5.25:1 | 4.5 |
| Section count and segment label `Soot.limeInk` on lime | 16.55:1 | 7.08:1 | 4.5 |
| Lime check, Reconnect fill, selected ring (`Soot.lime`) on surface / on ground | 15.03 / 16.55:1 | 7.08 / 6.43:1 | 3 |
| Row edge when not connected (dashed), picker track and field edge `Soot.edge` on surface / on ground | 3.51 / 3.87:1 | 3.45 / 3.13:1 | 3 |
| Appearance thumbnail edge `Soot.edge` on surface | 3.51:1 | 3.45:1 | 3 |
| Selected section row: surface on ground | 1.10:1 | 1.10:1 | not relied on: the label turns to `Soot.ink` and semibold, and `isSelected` is exposed |
| Hairlines between setting rows (`Soot.line`) | decorative | decorative | — |

- **Targets**: section rows 36px full width, account rows 64px, setting rows 56px (a switch row toggles
  from anywhere in the row, so the 15px switch is never the only target), segments 26px high and at least
  44px wide, appearance options 128×112, the reshuffle button 26px (2.5.8 asks 24px), buttons 36px.
- **Names**: every row is one element ("Slack: connected as Eray", "GitHub: not connected. Pull requests
  and previews", "Linear: session expired, reconnect"); the action buttons name their tool ("Disconnect
  Slack"); the reshuffle button is "Draw another picture"; the prefix field is "Slack channel prefix";
  the segment groups are "Refresh interval" and "Screen at launch"; the section list is "Settings
  sections" with `isSelected` on the open one; the generated picture and the account pictures are
  decorative (`accessibilityHidden`).
- **Focus**: custom buttons carry the 2px lime `FocusOutline`; a segment's ring is drawn inside it, ink on
  the lime pill and lime on the track, so it is visible whichever segment has it (2.4.7); the text field
  and the switches keep the system ring. Keyboard order: picture, reshuffle, sections, then the open
  section's controls top to bottom.
- **State without hue** (1.4.1): connected = check glyph and the person's name; expired = exclamation
  glyph, "Session expired" in words, Reconnect; offline = wifi glyph and "You're offline"; not connected
  = dashed edge, the tool's pitch and Connect; connecting = the sweep and "Approve in your browser…" with
  Cancel. The selected appearance has the ring and a semibold label; the selected segment has the pill.
- **Reduce Motion**: the section cross-fade keeps opacity only; the marker, pill and ring stop
  travelling (`withAnimation(nil)`); the logo hover scale and the picture reshuffle scale are off;
  `WaitingLine` and `Breathing` are still, as before. Nothing moves on its own for more than the sweep,
  which is the connecting state and stops with it.
- **Disabled means unavailable**: no control is disabled; "Connect GitHub to pick it" replaces the
  workspace picker without GitHub; a login-item refusal is written under the switch, which stays usable.
- **Fit**: every section fits the 1080×680 window without scrolling (Accounts, the tallest, ends at
  390pt); the right column still scrolls for larger text.
- Not verified at runtime: VoiceOver's reading of a section switch (the new headline is a header; no
  live region), and the login item on a notarised build.

## Overview

Scope: the Overview page (`Sources/Dever/Views/OverviewView.swift`, `OverviewSettingsView.swift`,
the Overview section of Settings), loaded, loading, grouped, compact, filtered-empty and no-project
states, dark and light, at the 1080×680 minimum (`DEVER_SNAPSHOT_SIZE=1080x680`, `DEVER_SNAPSHOT_WAIT=0|14`,
`DEVER_SNAPSHOT_OVERVIEW=…`, `DEVER_SNAPSHOT_OVERVIEW_VIEW=1`). Names, focus and keyboard verified in
code; contrast computed from the palette values.

| Pair | Dark | Light | Need |
|---|---|---|---|
| Headline, names, cell values `Soot.ink` on surface | 17.40:1 | 18.88:1 | 4.5 |
| Summary line, column headers, ages, dashes `Soot.muted` on ground / on surface | 5.93 / 5.38:1 | 5.49 / 6.05:1 | 4.5 |
| Connect chip `Theme.muted` on surface | 8.56:1 | 6.42:1 | 4.5 |
| Overdue date `Theme.negative` on surface (13pt, with a glyph) | 4.88:1 | 5.78:1 | 4.5 |
| On-track check, pin, segment pill `Soot.lime` on surface | 15.03:1 | 7.08:1 | 3 |
| Needs-attention glyph `Theme.negative`; quiet moon `Theme.chart3` on surface | 4.88 / 7.62:1 | 5.78 / 4.25:1 | 3 |
| Shipped bar fill `Theme.chart1`; merged segment `Theme.chart3` on surface | 6.93 / 7.62:1 | 5.99 / 4.25:1 | 3 |
| Shipped bar track `Theme.empty` on surface | 1.27:1 | 1.25:1 | decorative: the `shipped/total` text beside it carries the value |
| Segment track and column chip edge `Soot.edge` on ground / on surface | 3.87 / 3.51:1 | 3.13 / 3.45:1 | 3 |
| Button label `Soot.limeInk` on lime (Add project, chosen segment, shown column) | 16.55:1 | 7.08:1 | 4.5 |
| Hovered row (ground at 70 % on surface) | ≈1.1:1 | ≈1.1:1 | not relied on: hover only; the hand cursor and the focus ring carry the state |

- **Targets**: rows 56px (comfortable) or 44px (compact), full width; the pin 28px; Refresh and View
  34px; Add project 36px and its chevron 30×36; segments 26px high and at least 44px wide; column chips
  26px (2.5.8 asks 24px); setting rows 56px, and a switch row toggles from anywhere in the row.
- **Names**: each row is one element reading, in column order, "AI Tips, pinned, Slack: 12 messages this
  week, last yesterday, Linear: 15 of 15 shipped, GitHub: pipeline passing, 0 open pull requests,
  preview live, target 12 November, past, On track", with the hint "Opens the project"; the pin is
  "Pin AI Tips to the top" / "Unpin AI Tips"; the summary line is one element; the column headers are
  hidden (the row's summary names every column); the group rows are headers ("Incomplete 2"); View is
  "View options"; the chevron is "Add many projects"; column chips are toggles with "Shown" / "Hidden"
  values; the segment groups are "Sort projects by", "Group projects by", "Row density"; the mark,
  the tool logos and every glyph are decorative, their word sits beside them.
- **Focus**: rows, the pin, the toolbar buttons, the lime button, the column chips and the empty state's
  Settings link carry the 2px lime `FocusOutline`; segments keep their inside ring. The pin is drawn at
  opacity 0 until hovered, focused or pinned (`@FocusState`), so keyboard focus never lands on an
  invisible control (2.4.7). Order: Refresh, View, Add project, its chevron, then row by row with the
  row's pin after the row. The View popover closes with Escape.
- **State without hue** (1.4.1): health = glyph and word (exclamation "Needs attention", moon "Quiet",
  check "On track", dashed circle "Incomplete", link "Not connected"); pipeline = glyph and word;
  preview = glyph and word; past target date = exclamation glyph, the negative colour and "past" in
  the summary; a pinned row = filled pin and "pinned" in its name; a hidden tool = dash with a tooltip.
- **Reduce Motion**: row entrance keeps a 200ms fade without the rise; skeleton-to-value fades, the
  shipped bar's fill, the reorder spring and the numeric counters are off (`nil` animations); row hover
  stays a 150ms tone change with no movement; `Skeleton` is still, as before. Nothing moves on its own.
- **Loading**: every cell's skeleton has the size of the value it stands for; the row's height never
  depends on what has loaded; "refreshing" is written in the summary line and `Refresh` carries the
  value "Refreshing" while the `WaitingLine` runs along its foot.
- **Empty states**: no project → a headline, one line, Add project and the import buttons that the
  connected tools allow, plus a link to Settings when Slack or Linear is missing; every project hidden
  → "Every project is finished and hidden" with "Show finished projects"; no search match → the query
  and "Clear search".
- Not verified at runtime: VoiceOver's reading of the row summary and of the popover; the numeric
  counters and the reorder spring replayed at low speed.
## Project page (one panel grammar)

Scope: the project page's blocks after the redesign (`ProjectDetailView.swift`, `PreviewPanel.swift`,
`ProjectPanels.swift`: `PanelHeader`, `PanelGlyph`, `PanelEmpty`, `QuietEmpty`; `ConnectPanelBody`),
states complete, without Linear, without a preview, without Slack, no tool, Linear not connected,
loading; dark and light. Findings and captures: `docs/reviews/project-page.md`. Names, focus and
keyboard verified in code; contrast computed from the palette values. The empty tile is
`Soot.ground` at 60 % over the surface: `#131313` dark, `#F8F8F7` light.

| Pair | Dark | Light | Need |
|---|---|---|---|
| Empty-state line `Soot.ink` on the tile | 18.58:1 | 17.77:1 | 4.5 |
| Panel title `Soot.ink` on surface | 17.40:1 | 18.88:1 | 4.5 |
| Panel line, quiet empty line `Soot.muted` on surface / on the tile | 5.38 / 5.75:1 | 6.05 / 5.69:1 | 4.5 |
| Primary label `Soot.limeInk` on lime (Link Linear, Link Slack, Link a repository, Add a preview, Connect X) | 16.55:1 | 7.08:1 | 4.5 |
| Quiet button label `Soot.ink` on surface; its edge `Soot.edge` on the tile | 17.40 / 3.75:1 | 18.88 / 3.25:1 | 4.5 / 3 |
| "Open ↗" and "+ Link a tool" `Soot.lime` on surface / on ground | 15.03 / 16.55:1 | 7.08 / 6.43:1 | 4.5 |
| Tool logo in the tile `Soot.ink` on the tile (Slack keeps its colours) | 18.58:1 | 17.77:1 | 3 |
| The tile against the surface | 1.07:1 | 1.06:1 | not relied on: the logo, the line and the button carry the state |

- **Targets**: Link / Connect / Add a preview / No preview needed 36px high; "Open ↗" 28px with its
  hover tile; "+ Link a tool" 28px; the tile itself is not a control.
- **Names**: each button is its own words ("Link Linear", "Link Slack", "Link a repository", "Add a
  preview", "No preview needed"), with the reason as a tooltip; the line beside it is read first, then
  the buttons; panel titles are headers; the head's logo or glyph is decorative (`PanelGlyph` is
  hidden, the title names the block); "Open ↗" reads "Open the project in Linear", "Open the pull
  requests on GitHub", "Open the channel in Slack".
- **Focus**: every new button is a `LimeButton` or a `QuietButton`, which carry the 2px lime
  `FocusOutline`; the header links keep `HoverLink`'s outline. Order: title row (tool chips, Link a
  tool, Refresh, Edit project), Preview (pill, then its action, then the alternative), Delivery or Pull
  requests (Open, then the tile's button or the rows), Slack (Mark as read, full width, then the tile's
  button or the messages). Link opens the editor sheet, which takes focus and gives it back on close.
- **State without hue** (1.4.1): a missing tool is its logo, a sentence and a named button; the
  preview's phase stays glyph and word; pull request state stays glyph and word.
- **Reduce Motion**: the hand-overs (skeleton → tile or content, tile → content after linking) are
  200 ms dissolves, which stay; the press scale of the buttons is off; nothing moves.
- **Loading**: skeletons only, at the size of the rows they stand for; a tile for a tool that is not
  linked shows from the first frame, since it does not depend on a load.
- Not verified at runtime: VoiceOver's reading of the tile; the editor opening on the asked step from
  each button; the stacked tile (line above the button) at widths other than the 420px rail.

## Motion (the animation sweep)

Findings and rejections are in `docs/reviews/animations.md`; the vocabulary lives in
`Sources/Dever/Views/Motion.swift`.

- **Durations**: press and hover 120 ms ease-out; swaps, fades, tab changes and skeleton → content
  200 ms ease-out; exits 150 ms ease-in; the Slack room and the thread pane a spring of ~350 ms
  (response 0.38, damping 0.86, no overshoot); travelling markers a spring of ~300 ms. Nothing
  linear, nothing longer than half a second, no spinner anywhere (waiting lines are clock-driven).
- **Explicit only**: every animation is tied to the one value that changes (`Motion.run`,
  `.motion(value:)`), so a refresh landing in a panel never moves another; the Slack room is laid
  out once at its final width behind a clipped frame, so no text reflows while it grows.
- **Reduce Motion** (`accessibilityReduceMotion`, `Motion.reduced`): movement, scale and springs
  are off everywhere: the room and the thread pane switch instantly, markers and pills jump, the
  check mark and the lightbox appear without scaling, stages and steps change with a plain fade,
  rolling counters become a dissolve, pressed buttons do not shrink. Dissolves (hover tones,
  skeleton → content, the 150 ms screen switch, the sheet's content fade) stay, as WCAG 2.3.3 and
  Apple's guidance allow for opacity-only changes. The appearance cross-fade is skipped.
- **Nothing moves on its own**: no autoplay beyond the waiting lines of a running connection, which
  stop with it; no animation blocks input (a transition never gates a control).
- **Vestibular safety**: no parallax, no zoom larger than 3 % (0.97 → 1), no motion across the
  whole screen except the 150 ms screen dissolve.
- Not verified at runtime: the behaviour with Reduce Motion switched on mid-session (the
  `NSWorkspace` flag is read at each animation, the environment value at each render).

## Buttons (the role system, `Views/Buttons.swift`)

Every button and link now uses one of the roles in docs/reviews/buttons.md. Contrast is
computed from the palette for each state (hover and press tones are blended at their real
opacity); the gallery captures (`DEVER_SNAPSHOT_GALLERY=1`) are `docs/reviews/shots/buttons-dark.png`
and `buttons-light.png`.

| Pair | Dark | Light | Need | Result |
|---|---|---|---|---|
| Primary label · normal (limeInk on lime) | 16.55:1 | 7.08:1 | 4.5 | ✅ |
| Primary label · hover (lime + limeInk 8 %) | 14.08:1 | 5.85:1 | 4.5 | ✅ |
| Primary label · pressed (lime + limeInk 16 %) | 11.86:1 | 4.85:1 | 4.5 | ✅ |
| Primary / secondary / destructive · disabled (muted on surface) | 5.38:1 | 6.05:1 | 4.5 | ✅ |
| Secondary label · normal (ink on surface) | 17.40:1 | 18.88:1 | 4.5 | ✅ |
| Secondary label · hover (surface + ink 6 %) | 14.79:1 | 16.68:1 | 4.5 | ✅ |
| Secondary label · pressed (surface + ink 12 %) | 12.18:1 | 14.64:1 | 4.5 | ✅ |
| Secondary / chip / menu edge on surface (non-text) | 3.51:1 | 3.45:1 | 3 | ✅ |
| Secondary / chip / menu edge on ground (non-text) | 3.87:1 | 3.13:1 | 3 | ✅ |
| Tertiary lime · normal on surface | 15.03:1 | 7.08:1 | 4.5 | ✅ |
| Tertiary lime · normal on ground | 16.55:1 | 6.43:1 | 4.5 | ✅ |
| Tertiary lime · hover (pill: ground 85 % over surface) | 16.35:1 | 6.52:1 | 4.5 | ✅ |
| Tertiary lime · hover (pill: surface 85 % over ground) | 15.28:1 | 6.98:1 | 4.5 | ✅ |
| Tertiary muted · normal on surface | 5.38:1 | 6.05:1 | 4.5 | ✅ |
| Tertiary muted · normal on ground | 5.93:1 | 5.49:1 | 4.5 | ✅ |
| Tertiary muted · hover (ink on pill) | 18.93:1 | 17.40:1 | 4.5 | ✅ |
| Tertiary · disabled (muted on ground) | 5.93:1 | 5.49:1 | 4.5 | ✅ |
| Icon glyph · normal (ink on surface) | 17.40:1 | 18.88:1 | 4.5 | ✅ |
| Icon glyph · disabled (muted on surface) | 5.38:1 | 6.05:1 | 4.5 | ✅ |
| Destructive label · normal (pill-negative ink on surface) | 6.48:1 | 9.77:1 | 4.5 | ✅ |
| Destructive label · hover (surface + negative 6 %) | 6.09:1 | 8.88:1 | 4.5 | ✅ |
| Destructive label · pressed (surface + negative 12 %) | 5.65:1 | 8.05:1 | 4.5 | ✅ |
| Destructive edge (negative on surface, non-text) | 4.88:1 | 5.78:1 | 3 | ✅ |
| Toolbar label · normal (ink on surface) | 17.40:1 | 18.88:1 | 4.5 | ✅ |
| Toolbar label · disabled (muted on surface) | 5.38:1 | 6.05:1 | 4.5 | ✅ |
| Chip off · label (ink on ground) | 19.17:1 | 17.15:1 | 4.5 | ✅ |
| Chip off · count (muted on ground) | 5.93:1 | 5.49:1 | 4.5 | ✅ |
| Chip off · hover (ink on ground + ink 6 %) | 16.78:1 | 15.16:1 | 4.5 | ✅ |
| Chip on · label (limeInk on lime) | 16.55:1 | 7.08:1 | 4.5 | ✅ |
| Chip on · count (limeInk 80 % on lime; was 70 %, 4.41:1 light) | 9.60:1 | 5.21:1 | 4.5 | fixed |
| Chip on · hover (lime + limeInk 8 %) | 14.08:1 | 5.85:1 | 4.5 | ✅ |
| Chip on · disabled (limeInk on muted fill) | 5.93:1 | 5.49:1 | 4.5 | ✅ |
| Row · hover lift (ink on ground 70 % over surface) | 18.69:1 | 17.66:1 | 4.5 | ✅ |
| Row · hover lift (ink on surface over ground) | 17.40:1 | 18.88:1 | 4.5 | ✅ |
| Menu trigger · label (ink on surface) | 17.40:1 | 18.88:1 | 4.5 | ✅ |
| Menu trigger · open edge (lime on surface, non-text) | 15.03:1 | 7.08:1 | 3 | ✅ |
| Focus ring (lime on ground, non-text) | 16.55:1 | 6.43:1 | 3 | ✅ |
| Focus ring (lime on surface, non-text) | 15.03:1 | 7.08:1 | 3 | ✅ |
| Primary segment · focus ring inside (limeInk on lime, non-text) | 16.55:1 | 7.08:1 | 3 | ✅ |

- **Disabled** is surface fill, edge at half, `Soot.muted` label, arrow cursor, no hover:
  never lime, never under 4.5:1. The destructive role first used `Theme.negative` as its
  label, which fell to 4.49:1 on hover (dark); it now uses the negative pill's ink.
- **Hover is visible on every text link** (WCAG 1.4.13 is not at stake, but 2.4.7's intent
  is): a pill one tone from the surface fades in over 150 ms, a muted label turns ink.
  Hover tones are dissolves, so they stay under Reduce Motion; the 0.97 press scale goes.
- **Focus** (2.4.7): every role draws the 2px lime ring 3px outside its shape (inside for
  segments and the split Add project). The gallery's "Focus" column forces it through the
  style's override, so it is checked without a keyboard.
- **Cursor**: the pointing hand comes from the style (`handCursor(isEnabled)`), so no
  button can forget it; a disabled button shows the arrow.
- **Names** (4.1.2): icon-only buttons go through `GlyphButton`, which requires a label used
  both as tooltip and accessible name; the Slack hover strip's three glyphs and both "⋯"
  menus gained tooltips in this pass.
- **Segment pickers and column chips** (Settings › Overview, Launch, the View popover): track 32px,
  segments 28px in a 360px column of equal widths; unchosen words `Soot.muted` (5.9:1 dark / 5.5:1
  light on the ground track), chosen `Soot.limeInk` on lime (16.6 / 7.1:1); a hidden column's chip is
  muted on ground with a dash, a shown one ink on surface with a lime check and a 3:1 edge.
- **Targets** (2.5.8): primaries 44 in sheets / 36 in panels, toolbar 34, chips 26–30, text
  links 28 (32 in onboarding), icon buttons 26–40, rows 36–64. The 20px label chip ("+2")
  and the 24px reaction pills stay under 24px in height but sit alone in their line.
