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

Targets: fields and selects 44px, list rows 40–60px, chips and footer links 32px, close 32px.
Hairlines between sections (`Soot.line`) are decorative and carry no information.

## Blockers fixed

- **1.4.11 Non-text contrast** — idle field underlines, radio rings and secondary-button/chip
  edges were under 3:1; they now use `#8f8f8f` and `#707070` (`Soot.edge`).
- **3.3.2 Labels or instructions** — "Name in Dever", channel name, prefix and search fields
  relied on placeholders; each now has a visible label (`FieldLabel`) or an icon plus an
  accessible name.
- **2.4.7 Focus visible** — custom buttons, option rows and radio rows drew no focus ring;
  they now show a 2px white ring (`FocusOutline`), 17:1 against the ground.
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
