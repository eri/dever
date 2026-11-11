# Buttons and links — audit and design system

Scope: every `Button`, `Link`, `Menu`, `Toggle`, picker, tappable row and chip in
`Sources/Dever/Views`. Before this pass, 418 matches across 20 files used nine different
treatments: `LimeButton`, `QuietButton`, `ToolbarButton`, `PressButton`, `.plain` with
ad-hoc fonts and colours, `HoverLink`, raw `Link`, `.borderlessButton` menus, and rows that
each tracked their own hover. Twelve of them showed no hover, nine had no cursor change,
five had no focus ring, and two (`PrimaryButtonStyle`, `SecondaryButtonStyle` in Theme.swift,
`AddProjectButton` in ProjectSetupViews.swift, `HoverRow` in Components.swift) were dead code.

Gallery: `DEVER_SNAPSHOT_DIR=<dir> DEVER_SNAPSHOT_SCREENS=0 DEVER_SNAPSHOT_GALLERY=1 ./build/Dever.app/Contents/MacOS/Dever`
writes `buttons-dark.png` and `buttons-light.png` (every role × normal, hover, pressed,
focus, disabled). The committed captures are in `docs/reviews/shots/`.

## The roles (`Views/Buttons.swift`)

One `ButtonStyle` per role, all drawn by the same private `ButtonChrome`: hover tracking,
the gallery's `buttonStateOverride`, the 2px lime `FocusOutline`, a 0.97 press scale (off
under Reduce Motion), the pointing hand while enabled (`handCursor(isEnabled)`), and every
tone change as a 150 ms ease-out fade (`Buttons.hover`; a dissolve, so it stays under Reduce
Motion). Hover = ink at 6 %, pressed = ink at 12 % (`Buttons.hoverTone` / `pressTone`);
on lime the label's ink is used instead (8 % / 16 %).

| Role | Style | Height | Font | Normal | Hover | Pressed | Disabled |
|---|---|---|---|---|---|---|---|
| Primary | `PrimaryButton(size:)` (`LimeButton` is a typealias) | 44 sheet / 36 panel | 15 / 14 semibold | lime fill, limeInk label | + limeInk 8 % | + limeInk 16 %, scale | surface fill, edge 50 %, muted label |
| Secondary | `SecondaryButton(size:)` (`QuietButton`) | 44 / 36 | 15 / 14 medium | surface fill, `Soot.edge`, ink | + ink 6 % | + ink 12 %, scale | edge 50 %, muted |
| Tertiary (text link) | `TertiaryButton(tint:lift:font:height:)` | 28 (32 in onboarding, 36 beside a 36 button) | 13 semibold (12–14 at call sites) | lime, ink or muted text, no fill | pill `lift` at 85 % (ground on a panel, surface on the page); muted → ink | pill solid, scale | muted, no pill, no hand |
| External link | `ExternalLink(title, destination:)` / `HoverLink` | 28 | 13 semibold | tertiary + `arrow.up.right` | as tertiary | as tertiary | as tertiary |
| Icon | `IconButton(fill:radius:edge:)`, `GlyphButton(symbol:label:)` | the label's frame (26–40) | glyph 11–13 semibold | surface circle or tile, ink glyph | + ink 6 % | + ink 12 %, scale | muted glyph |
| Destructive | `DestructiveButton(size:)` | 44 / 36 | 15 / 14 semibold | surface fill, negative edge, pill-negative ink | + negative 6 % | + negative 12 % | as secondary disabled |
| Toolbar | `ToolbarButton(busy:)` | 34 | glyph 12 + verb 13 semibold | surface tile, no edge | + ink 6 % | + ink 12 %, scale | muted label; `busy` keeps ink and runs the lime line |
| Chip | `ChipButton(on:fill:drawsFill:edge:)` | 30 tabs, 26 small chips, 24 reaction pills | 12–13 semibold | capsule on ground/surface, edge; `on`: lime | + ink 6 % (limeInk 8 % when on) | 12 % / 16 %, scale | edge 50 %, 60 % opacity; `on` turns muted fill |
| Segment | `SegmentButton(on:)` in `SegmentPicker` | 28 inside a 32 track, the track 360 wide (`Buttons.controlWidth`), segments of equal width | 13 medium, semibold when chosen | ground track, no edge; lime pill slides to the choice; the rest muted | + tone | + tone | — |
| Row | `RowButton(lift:radius:)` | the row's height (36–64) | the row's | none | lift one tone (`.ground` 70 %, `.surface`, `.tone` ink 6 %) | lift solid / ink 12 %, no scale | 50 % opacity |
| Menu trigger | `MenuTriggerButton(open:fill:radius:edge:)` | 30–40 | label's | surface fill, edge | + ink 6 % | + ink 12 % | muted |
| Primary segment | `PrimarySegment(open:)` | 34 (the split Add project) | 13 semibold | part of a lime capsule | limeInk 8 % | limeInk 16 % | inherits the capsule's lime (not disabled anywhere) |

Rules shared by every role: radius `Soot.radius` (8) for tiles, capsule for chips and text
pills, `Soot.fieldRadius` (10) for rows that sit in a sheet; focus ring 2px lime 3px outside
(inside for segments and the split button, so it never crosses the track); disabled never
lime, label ≥ 4.5:1 (measured in docs/accessibility-review.md → Buttons); every icon-only
button carries `.help` and an accessible name (`GlyphButton` makes both mandatory).

System controls kept as they are: `Toggle(.switch)` tinted lime (the row around it gets the
hand), `confirmationDialog` and `contextMenu` buttons, the items inside `Menu`s.

## Inventory (file:line → role)

Lines are those of the files after this pass (ProjectDetailView, PreviewPanel and ProjectPanels were then rebased onto the
project-page commit b998181, so their lines may be off by a few; `PanelEmpty`'s buttons there use `LimeButton` / `QuietButton`,
which are the primary and secondary roles). States: N normal · H hover · P pressed · D
disabled · F focus-visible · ✋ hand cursor. Before = what the control had; after, every row
has N H P D F ✋ through its style unless noted.

### Views/SootUI.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 53 | `ToolChip` (Slack / Linear / GitHub chip under the project name) | HoverLink + per-call handCursor: N H F ✋ | External link via `HoverLink` → TertiaryButton(ink) |
| 76 | `OptionRow` (Connect GitHub: sign in with a code / gh CLI) | PressButton + own hover: N H P D(0.45) | Row (`.tone`) |
| 132 | `ChipPicker` pills | PressButton + FocusOutline: N P F | Chip (`drawsFill: false`, pill slides) |
| 198 | `SheetTitle` close ✕ | PressButton: N P F | Icon via `GlyphButton("xmark", "Close")` |
| 222 | `RadioRow` | `.plain` + FocusOutline: N F | Row (`.tone`, radius 6) |
| 318 | `SwitchRow` tap area | onTapGesture only | hand added (switch stays system) |
| 357 | `ChoiceCard` head | `.plain` + FocusOutline: N F | Row (`.tone`, fieldRadius) |
| 416 | `StepSheet` close ✕ | PressButton: N P F | Icon (`GlyphButton`) |
| 464 | `BackButton` ‹ | PressButton: N P F | Icon (`GlyphButton("chevron.left", "Back")`) |
| 584 | `SearchPicker` trigger (select with ⌃⌄) | `.plain`, own edge, lime when open: N F, open | Menu trigger (`open:`, fieldRadius) |
| 684 | `PickerRow` (search picker results) | `.plain` + own hover: N H F | Row (`.surface`) |

### Views/Components.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 131 | `OpenSettingsButton` "Open Settings" | unstyled system button | Secondary |

### Views/ConnectStates.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 170 | "Cancel" while a connection runs | QuietButton | Secondary |
| 173 | "Connect X" / "Reconnect X" | LimeButton | Primary |
| 312 | "Retry" in a failure row | QuietButton | Secondary |

### Views/ContentView.swift (the rail)
| Line | Element | Before | Role now |
|---|---|---|---|
| — | Overview tile | PressButton + FocusOutline: N P F, selected | Icon (`fill: nil`, radius 10) + hover tone; `sootTip("Overview")` |
| — | Project tiles (initials) | PressButton + FocusOutline: N P F, selected, system context menu | Icon (`fill: nil`, radius 12); `sootTip(name, detail: health · unread · for you)`; right click / control click / ⌥↩ open the in-window `RailMenu` (`MenuPanel`); VoiceOver gets Edit, Pin/Unpin and Remove as actions on the tile |
| — | `RailMenu` rows: Open, Edit project, Pin/Unpin, Open in Slack ↗, Open in Linear ↗, Pull requests on GitHub ↗, Remove from Dever… | system `contextMenu` (Edit links…, Remove from Dever…) | `MenuPanelRow` (row role, surface lift; links carry ↗; Remove in the negative tone, same confirmation dialog as the editor's Remove project) |
| — | User / Settings tile | PressButton + FocusOutline | Icon (`fill: nil`, circle); `sootTip(name, detail: accounts hint)` |
| — | "+" add project | PressButton, no focus ring | Icon (`fill: nil`, radius 10); `sootTip("Add a project", "⌘N")` |
| — | Dever mark | `.help` | `sootTip("Dever", detail: workspace)` (not a button) |
| — | confirmation dialog | system | system (unchanged) |

Tooltips: `sootTip` shows the app's own `TipCard` beside the view after 300 ms, drawn by the
`tipHost()` on the main view so the rail's scroll clip never cuts it; the gallery shows the card.
The rail capture: `DEVER_SNAPSHOT_RAIL=1` → `rail-tip-{dark,light}.png`, `rail-menu-{dark,light}.png`.

### Views/OverviewView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 158 | "Refresh" (⌘R) | ToolbarButton(busy:) | Toolbar (same style, shared chrome) |
| 166 | "View" (opens view options popover) | ToolbarButton | Toolbar |
| 258, 261 | "Clear search" / "Show finished projects" | QuietButton | Secondary |
| 279–286 | empty state: "Add project", "Add many from Slack/Linear" | LimeButton / QuietButton | Primary / Secondary |
| 291 | "Connect Slack and Linear in Settings…" | `.plain` lime text, FocusOutline: N F | Tertiary (lime, lift surface, 13 medium) |
| 333, 344 | split "Add project" ▏⌄ | private `LimeSegment`: N H P F(inside) ✋ | `PrimarySegment` (moved to Buttons.swift) |
| 411 | `MenuRow` (Add many: From Slack / From Linear / Settings) | `.plain` + own hover + handCursor: N H F ✋ | Row (`.surface`) |
| 509 | `OverviewRow` (a project row) | `.plain` + own hover + handCursor + context menu: N H F ✋ | Row (`.ground`); the hover state is still read for the pin |
| 797 | `PinButton` | `.plain` + own hover, invisible until hover/focus: N H F | Icon (`fill: nil`), same reveal rule |

### Views/OverviewSettingsView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 26 | "Reset to defaults" | QuietButton, D | Secondary |
| 38–50 | `SegmentPicker` ×3 | see SettingsView | Segment |
| 56, 61 | switches | system Toggle | system; the row gets the hand |
| — | `ColumnChips` / `ListMiniature` column heads (toggle a column) | `.plain` + FocusOutline | Chip (`on:`), as drawn by the Settings redesign |

### Views/ProjectDetailView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 184, 193 | "Refresh" (⌘R), "Edit project" (⌘E) | ToolbarButton | Toolbar |
| 225 | "+ Link a tool" (incomplete project) | `.plain` lime, FocusOutline: N F | Tertiary (lime, lift surface) |
| 368 | GitHub "N open · N merged" line → pull requests | HoverLink: N H P F | External link (`HoverLink`) |
| 411 | "Update N in Linear ↗" | HoverLink | External link |
| 404 | stage tabs (`CountTabs`) | see ProjectPanels | Chip |
| 614 | "‹ Back" (wide Slack) | PressButton + handCursor + FocusOutline: N P F ✋ | Chip (surface fill) |
| 640 | "Open in Slack ↗" | raw `Link` + handCursor: N ✋ | `ExternalLink` |
| 644 | "Mark as read" | PressButton + handCursor, muted 12: N P F ✋ | Tertiary (muted, 12 semibold) |
| 651 | expand ⤡ (read full width) | PressButton + handCursor: N P F ✋ | Icon (`fill: Soot.ground`) |
| 727 | `ShowAllButton` | see ProjectPanels | Tertiary |

### Views/ProjectPanels.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 51 | `PanelHeader` "Open ↗" | HoverLink | External link |
| 76 | `TileRow` (a row that opens a URL) | `.plain` Link + own hover + FocusOutline: N H F | Row (`.ground`) |
| 99 | `CountTabs` (All 16 · In review 16…) | PressButton + FocusOutline: N P F | Chip (`drawsFill: false`, pill slides); count ink raised to 80 % (5.2:1 light) |
| 140 | `ShowAllButton` "Show all 15 / Show fewer" | PressButton + own pill hover: N H P F | Tertiary |
| 190 | `PullChip` (#4864 with state and pipeline glyph) | PressButton + handCursor + own hover: N H P F ✋ | Chip (surface fill, 26) |
| 247 | `WorkTile` (issue row → issue page) | `.plain` NavigationLink + own hover + FocusOutline: N H F | Row (`.ground`) |

### Views/PreviewPanel.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 105 | "#4714 Draft" → pull request | HoverLink | External link |
| 148 | "Add a preview" | QuietButton | Secondary |
| 150 | "No preview needed" | `.plain` lime, FocusOutline(8), 36 high: N F | Tertiary (36 high beside the 36 button) |
| 224 | "Deploy preview" / "Sending…" | LimeButton, D | Primary |
| 234 | More "⋯" `Menu` | `.menuStyle(.button)` + QuietButton, 20×36 label | Menu trigger (36×36) |
| 286, 289 | options row "Deploy" / "Cancel" | LimeButton / QuietButton | Primary / Secondary |
| 394 | `ProductChip` (App ↗ · Back office ↗ · Client Hub ↗) | `.plain` Link + handCursor + own hover: N H F ✋ | Chip (surface fill, 30) |
| 448 | `PodsStepper` − / + | `.plain`, D, FocusOutline: N D F | Icon (`fill: nil`, radius 8) |
| 467 | `OptionSwitch` tap area | onTapGesture | hand added |
| 78–88 | confirmation dialogs | system | system |

### Views/IssueDetailView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 88 | "‹ Back" (⌘[) | `.plain` + FocusOutline: N F | Chip (surface fill) |
| 108 | "Open in Linear ↗" | HoverLink (surface lift) | `ExternalLink(lift: surface)` |
| 147–149 | status / priority / assignee `ChoiceChip` | see IssueRows | Menu trigger |
| 155 | "Blocked by N other issues" (scrolls to links) | `.plain` + FocusOutline: N F | Row (`.ground`, radius 8) |
| 208 | "Open on GitHub ↗" on the merged card | HoverLink | `ExternalLink(tint: ink)` |
| 280 | labels "+2 / Less" | `.plain`, own edge, FocusOutline: N F | Chip (clear fill, 20) |
| 506 | `TileLink` rows (linked issues) | see IssueRows | Row |
| 528 | `ShowAllButton` | see ProjectPanels | Tertiary |
| 900 | Markdown image → opens the URL | `.plain` Link: N | Row (`.none`) + `.help` |
| 908 | Markdown image fallback "Image ↗" | raw `Link` lime 13: N | `ExternalLink` |

### Views/IssueRows.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 251 | `TileLink` (row → issue page) | `.plain` NavigationLink + own hover + FocusOutline | Row (`.ground`) |
| 274 | `ChoiceChip` (opens a choice popover) | PressButton + own hover, lime edge when open: N H P F, open | Menu trigger (`open:`) |
| 320 | `ChoiceRow` (one choice in the popover) | `.plain` + own hover + FocusOutline: N H F, selected | Row (`.surface`, radius 6) |
| 357 | `CopyChip` (branch name, copies) | PressButton + own hover + FocusOutline: N H P F | Chip (surface fill); its hover still reveals the copy glyph |

### Views/JumpToLatest.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 61 | "↓ Latest" pill | PressButton + handCursor + own hover: N H P F ✋ | Chip (surface fill, 32) + shadow |

### Views/OnboardingView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 88 | progress marks (back to an earlier stage) | `.plain`, D: N D | Icon (`fill: nil`) + `.help("Back to …")` |
| 108 | "Skip for now" | PressButton lime 14, FocusOutline(16), 32 high: N P F | Tertiary (lime, lift surface, 14 semibold, 32) |
| 144, 181, 349 | "Continue" ×3 | LimeButton, D | Primary (`.sheet`, 44) |
| 222 | "Cancel" (connection running) | `.plain` muted 14: N | Tertiary (muted, 14 medium) |
| 226 | "Connect" (service row) | `.plain` lime 14: N | Tertiary (lime, 14 semibold) |
| 370 | prefix choice rows | `.plain`: N, selected | Row (`.tone`) |
| 473 | "Open Settings" (alerts denied) | `.plain` lime 14: N | Tertiary (lime, 14 semibold) |
| 481 | Alerts switch + row tap | system Toggle, onTapGesture | system; the row gets the hand |

### Views/ProjectSetupViews.swift (project editor, import)
| Line | Element | Before | Role now |
|---|---|---|---|
| 163, 255, 366 | "Continue / Done" ×3 | LimeButton, D | Primary (`.sheet`) |
| 260, 371 | "Skip" ×2 | `.plain` muted 14 medium, FocusOutline(6): N F | Tertiary (muted, lift surface, 14 medium) |
| 355 | "Show every channel" | QuietButton | Secondary |
| 411 | "Create project / Save / Saving…" | LimeButton, D | Primary (`.sheet`) |
| 428 | recap rows (Slack / Linear / GitHub / Preview → step) | `.plain` + FocusOutline: N F | Row (`.tone`, fieldRadius) |
| 495 | "Connect X in Settings →" | `.plain` lime 14, FocusOutline(6): N F | Tertiary (lime, lift surface, 14 semibold; the glyph is `arrow.right` since it stays in the app) |
| 607 | `PickRow` (channel / project / repository choice) | `.plain` + FocusOutline: N F, selected | Row (`.tone`, fieldRadius) |
| 754, 757 | import empty state "Find more channels" / "Clear search" | `.plain` lime 13: N | Tertiary (lime, lift surface) |
| 767 | footer "Select all / Select none" | `.plain` lime 13, FocusOutline(6): N F | Tertiary |
| 774 | footer "Find more channels" | QuietButton | Secondary |
| 779 | "Add N projects" | LimeButton, D | Primary (`.sheet`) |
| 829 | `ImportRow` (tick row) | `.plain` + FocusOutline: N F, selected | Row (`.tone`, fieldRadius) |
| 188, 800 | `SearchPicker` (Team, Workspace repository) | see SootUI | Menu trigger |

### Views/RepositoryModeView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 14 | mode rows (one / per project / later) | `.plain` + FocusOutline: N F, selected | Row (`.tone`) |
| 110 | "Continue" | LimeButton, D | Primary (`.sheet`) |

### Views/SettingsView.swift
| Line | Element | Before | Role now |
|---|---|---|---|
| 102 | reshuffle picture ⟲ | `.plain` + FocusOutline: N F | Icon (surface circle) + ground ring |
| 125 | section list (Accounts … About) | `.plain` + FocusOutline, surface slides to the open one: N F, selected | Row (`.tone`) |
| 210 | `SettingRow` tap area (switch rows) | onTapGesture | hand when the row toggles |
| 273 | `StatusMenuRow` (Check status / Disconnect) | `.plain` + own hover + handCursor: N H F ✋, D, destructive tint | Row (`.surface`) |
| 541 | "Cancel" (approval running) | QuietButton | Secondary |
| 545, 556 | "Reconnect" / "Connect" | LimeButton | Primary |
| 589 | status trigger (glyph + ⌄) | `.plain` + handCursor + FocusOutline: N F ✋, open | Menu trigger (`open:`, ground fill, no edge) |
| 828 | appearance options (System / Light / Dark) | PressButton + FocusOutline: N P F, selected | Row (`.tone`, radius 8) |
| 990 | "Open System Settings" | QuietButton | Secondary |
| 1001 | "Turn on alerts" | LimeButton | Primary |
| 1015, 1071 | alert switches, "Open at login" | system Toggle | system; row gets the hand |
| 1101 | `SegmentPicker` segments | `.plain` + private `SegmentFocus` (inside ring): N F | Segment (hover tone + hand added; inside ring kept) |
| 1151 | "Check for updates ↗" | HoverLink | `ExternalLink` |
| 1160 | "Start" (welcome tour) | QuietButton | Secondary |
| 1193 | "Copy / Copied" (GitHub code) | QuietButton | Secondary (`.sheet`) |
| 1215 | "Open GitHub" (Link) | LimeButton | Primary (`.sheet`) + `arrow.up.right` |
| 1220 | `OptionRow` ×2 | see SootUI | Row |
| 442–443 | Disconnect confirmation | system | system |

### Views/SlackPreview.swift (file preview)
| Line | Element | Before | Role now |
|---|---|---|---|
| 54 | "Save" | ToolbarButton | Toolbar |
| 59 | "⋯" `Menu` (Open in Slack, Copy link) | `.borderlessButton` + handCursor + FocusOutline: N F ✋ | Menu trigger (`.menuStyle(.button)`, no edge) + `.help` |
| 77 | close ✕ | `.plain` + handCursor + FocusOutline | Icon (`GlyphButton`, 30) |
| 349 | zoom % (fit / actual size) | `.plain` + handCursor: N ✋ | Icon (`fill: nil`) |
| 347, 358 | zoom − / + | `.plain` + handCursor + FocusOutline, D | Icon (`GlyphButton`, no fill) |
| 18, 321 | backdrop tap, double-click to zoom | gestures | unchanged (not buttons) |

### Views/SlackThread.swift (room, thread, cards)
| Line | Element | Before | Role now |
|---|---|---|---|
| 614 | "Show earlier" | PressButton lime 12, FocusOutline(4): N P F | Tertiary (lime, 12) |
| 648, 695 | "Read the conversation ⤡" ×2 | PressButton + handCursor lime 13, FocusOutline(4) | Tertiary |
| 817 | people "Show all 8 / Show fewer" | `.plain` + handCursor lime 12 | Tertiary (12) |
| 828 | link cards (Links section) | `.plain` Link + handCursor + FocusOutline: N F ✋ | Row (`.tone`) |
| 889 | file rows (Files section) | `.plain` + handCursor + FocusOutline, D | Row (`.tone`) |
| 1146 | thread "↗" open in Slack | raw `Link`, muted: N | Icon (`fill: nil`) |
| 1149 | thread close ✕ | `.plain` + FocusOutline: N F | Icon (`GlyphButton`, ground fill) |
| 1234 | reply "Send" | `.plain`, lime capsule, D, FocusOutline: N D F | Chip (`on:` while sendable, no edge) |
| 1348 | "Show more / Show less" | `.plain` muted 12: N | Tertiary (muted, lift surface, 12) |
| 1352 | "N replies · Last reply …" (opens the thread) | `.plain` + handCursor lime 12, FocusOutline(4) | Tertiary (lime, lift surface, 12) |
| 1422 | hover strip 👍 ❤️ | `.plain` + handCursor + FocusOutline(5): N F ✋, on | Icon (`fill: nil`, radius 5) + `.help` |
| 1433 | hover strip add reaction ☺ | `.plain` + handCursor + FocusOutline | Icon + `.help` |
| 1448 | hover strip "⋯" `Menu` | `.borderlessButton` + handCursor + FocusOutline | Menu trigger (clear fill, radius 5) + `.help` |
| 1551 | `ReactionPill` (emoji + count) | private `ReactionPillStyle` + handCursor + own hover (scale 1.05, who-reacted popover after 450 ms): N H P F ✋ | kept (chip role, its own style: the hover scale and the delayed popover are specific to it) |
| 1700 | emoji picker cells | `.plain` + handCursor + FocusOutline | Icon (`fill: nil`, radius 6) |
| 1786 | inline image (opens the preview) | `.plain` + handCursor: N ✋ | Row (`.none`) |
| 1855, 1859 | `FileRow` (preview / open in Slack) | `.plain` + handCursor + FocusOutline | Row (`.tone`) |
| 1941 | link preview card | `.plain` Link + handCursor + FocusOutline | Row (`.tone`) |
| 1091 | pane width handle | resize cursor + drag gesture | unchanged (not a button) |

## What changed per screen

- **Onboarding**: Continue ×3 are 44px primaries; "Skip for now", "Connect", "Cancel" and
  "Open Settings" are tertiary links with a hover pill (they had none); the progress marks
  show the hand and a tooltip where they lead back; the prefix choice rows lift on hover.
- **Settings › Overview, Launch and the View popover**: the segment pickers share one 360pt column
  with segments of equal width (edges line up from row to row), a track without edge (ground on a
  card, surface in the popover), 32px and 13pt, the words not chosen muted.
- **Settings**: section list rows, appearance thumbnails and status-menu rows lift on hover;
  the status trigger is a menu trigger that turns lime-edged while open; segments get a hover
  tone and the hand; Connect / Reconnect / Cancel / Start / Open System Settings / Copy /
  Open GitHub use primary or secondary; "Check for updates ↗" is an `ExternalLink`.
- **Overview**: Refresh / View keep the toolbar form on the shared chrome; project rows and
  the Add-many menu rows are `RowButton`s; the pin is an `IconButton`; the empty state's
  Settings sentence is a tertiary link with a hover pill; the split Add project uses
  `PrimarySegment` from Buttons.swift.
- **Project page**: Back, PR chips, product chips and the Back capsule are `ChipButton`s;
  stage tabs are chips with a sliding pill; "Open in Slack ↗", "Update N in Linear ↗",
  "Open ↗" and the GitHub line are external links; Mark as read is a muted tertiary; the
  expand glyph is an icon button on the ground tone. The project-page session's work in
  ProjectDetailView / PreviewPanel / ProjectPanels was touched only at the style lines.
- **Preview panel**: Deploy / Cancel / Add a preview on primary / secondary; "No preview
  needed" is a 36px tertiary; the More "⋯" is a 36×36 menu trigger with an edge; the pods
  stepper's − / + are icon buttons with a hover tone and a disabled glyph.
- **Slack room, thread and file preview**: every lime text action (Show earlier, Read the
  conversation, Show all, N replies) has a hover pill and the hand through the style; file
  rows, link cards and the inline image lift on hover; the hover strip's glyphs and "⋯" have
  tooltips; Send is a chip that is lime only while a message can be sent; the thread's
  close / open-in-Slack are icon buttons; the preview's ⋯ menu uses `.menuStyle(.button)` so
  its label is styled like every other trigger.
- **Linear issue page**: Back is a chip, status / priority / assignee are menu triggers,
  linked-issue rows and "Blocked by" are row buttons, the label "+2" is a small chip,
  "Open in Linear ↗" and "Open on GitHub ↗" are external links, the branch chip is a chip.
- **Sheets** (new / edit project, import, GitHub): close and back are `GlyphButton`s, every
  Continue / Save / Add is a 44px primary, Skip and Select all are tertiary, recap / pick /
  import rows lift on hover, the search picker trigger is a menu trigger.

## Verified / not verified
- Built and captured: gallery (both themes), overview, project, Slack wide, issue, settings,
  sheets, onboarding — checked by eye for regressions in size and colour.
- Hover, press and focus are verified in the gallery through the style override; the real
  pointer path (`onHover`, `CursorArea`) is the same code the previous per-call modifiers used.
- Not verified at runtime: `Menu` labels under `.menuStyle(.button)` with a custom
  `ButtonStyle` open on click as before in the preview panel (already in use there) — the two
  Slack menus were switched to the same form and build, but their popups were not clicked.
