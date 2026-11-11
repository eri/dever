# Working in this repository

Rules for contributors and coding agents. Short on purpose; the linked documents hold the reasoning.

## Data: fresh, and never a whole reload

Read [docs/data-freshness.md](docs/data-freshness.md) before touching anything that shows or changes
data from Slack, Linear or GitHub. Every such change states its **data contract** (reads, writes,
invalidates, budget, loading, failure, exits, cost: the template is in
[section 7](docs/data-freshness.md#7-checklist-for-every-feature)) and follows these rules:

1. Remote data lives in an app-lifetime store (`IssueStore`, `PreviewStore`, …), never in a view's `@State`.
2. One copy of each thing: reuse or extend the store entry another screen already loads.
3. A new kind of data gets a freshness budget in the table of section 4, in the same change.
4. Skeletons only when there is no value yet. A refresh updates rows in place; no spinner over content.
5. Writes are optimistic, reconciled with the server's answer, restored on refusal, and name what they invalidate (check the Overview too).
6. A link that opens something Dever displays in another app marks that data dirty, so it refreshes on return.
7. CI, review, deploy and preview states carry their age and are never drawn as current when stale. "Updated" means the last successful fetch.
8. A failed refresh keeps the last value and says it is old.
9. No whole-collection fetch to learn about one item, no request per row.
10. A poll that finds nothing new must be cheap (delta cursor, `If-None-Match`, small GraphQL query); state its cost.
11. A new screen or a new way out of one gets a row in section 5.

## Interface

- Skeletons, not spinners.
- Motion comes from `Sources/Dever/Views/Motion.swift` (`Motion.run`, `.motion(value:)`, the four curves).

### Buttons and links: one role each, nothing hand-made

Every clickable thing uses one of the roles in `Sources/Dever/Views/Buttons.swift`
(inventory and the reasoning: [docs/reviews/buttons.md](docs/reviews/buttons.md)). A role gives
the hover tone, the press, the lime focus ring, the pointing hand, the disabled state and the
150 ms fades; a button that draws these itself gets some of them wrong, and this one did
(a "Show more" with `PressButton` showed nothing on hover).

| You are adding | Use |
|---|---|
| the one action of a view or sheet | `PrimaryButton(size: .sheet / .panel)` |
| a peer action beside it, Cancel, Retry | `SecondaryButton()` |
| a text link: Show more, Show all 15, Skip, Mark as read | `TertiaryButton(tint: .lime / .ink / .muted, lift: Soot.ground on a panel / Soot.surface on the page, font:)` |
| a link that opens a URL | `ExternalLink("Open in X", destination:)` (adds ↗) or `HoverLink` for a custom label |
| a glyph only: close, back, pin, zoom, expand | `GlyphButton(symbol:label:)` (tooltip and accessible name are required) or `IconButton(fill:radius:)` |
| a page-toolbar action with a glyph and a verb | `ToolbarButton(busy:)` |
| a capsule: a tab with a count, a PR chip, a toggle chip | `ChipButton(on:fill:)` |
| a segment of a picker | `SegmentButton(on:)` inside `SegmentPicker` |
| a row or tile that opens something | `RowButton(lift: .ground / .surface / .tone / .none)` |
| a trigger that opens a menu or a popover | `MenuTriggerButton(open:)`; a SwiftUI `Menu` gets `.menuStyle(.button)` + this style + `.menuIndicator(.hidden)` |
| an action that removes something, outside a system dialog | `DestructiveButton()` |

Never write, on a button or a link: `.buttonStyle(.plain)`, `PressButton()`, `.handCursor()`,
`.onHover` to tint it, `FocusOutline`, or a font and a colour that stand in for a role. If no
role fits, add one to Buttons.swift (and a row to the gallery) rather than a one-off.
A button drawn over selectable text (a floating pill, a hover toolbar) must keep the pointing hand:
the roles see to it (`CursorArea`), and every `NSTextView` subclasses `YieldingTextView`
(SlackPreview.swift) so its I-beam yields to what covers it. Never subclass `NSTextView` directly.

Check your button in the gallery: `DEVER_SNAPSHOT_SCREENS=0 DEVER_SNAPSHOT_GALLERY=1` writes every
role in every state to `buttons-dark.png` / `buttons-light.png`.

## Repository

- Everything in the repository is written in English.
- Commit messages carry no tool attribution and no `Co-Authored-By` trailer.
- Names fetched at runtime (workspaces, channels, repositories, people) are data: never in code, fixtures or docs.
- `swift test` passes before a push; a change to a store or to how data is matched or derived comes with a test in `Tests/DeverTests`.
- Build with `./scripts/build-app.sh`; screenshots without the network: see "Screenshots for development" in the README.
