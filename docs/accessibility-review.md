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
