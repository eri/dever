# Settings — redesign review

Scope: the Settings page (`Sources/Dever/Views/SettingsView.swift`, reached from the rail's user tile in
`Views/ContentView.swift`), every section (Accounts, Repositories, Appearance, Alerts, Launch, About)
and every account state (connected, not connected, connecting, session expired, offline, unreachable),
dark and light, at the 1080×680 minimum window. Stack: SwiftUI, soot tokens (`Views/SootUI.swift`),
`BrandLogo`, `ConnectFlow`, `RepositoryModeRows`. Conventions read: `README.md`,
`docs/accessibility-review.md`, `docs/reviews/project-work-view.md`, `docs/reviews/project-preview.md`,
`docs/skills/superfuture-design-review.md`, `docs/skills/find-animation-opportunities.md`.
Method: the `better-interface` orchestration (jakubkrehel/skills, the six domain skills applied by
hand), the accessibility review, then the animation sweep. Evidence: captures from
`DEVER_SNAPSHOT_SETTINGS=1 DEVER_SNAPSHOT_SIZE=1080x680`, plus the state run
`DEVER_SNAPSHOT_DISCONNECTED=github DEVER_SNAPSHOT_UNAUTHORIZED=linear DEVER_SNAPSHOT_FAILING=slack=offline
DEVER_SNAPSHOT_CONNECTING=github`.

## Before

The page was a form: a title, a sentence, four label-and-panel rows (services as three text rows with two
buttons each, three appearance tiles, a notification status, a prefix field) and ~90 words of explanatory
copy, on the blue-grey "framed sheet" that the rest of the app had already left for the soot ground.

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Writing | old `SettingsView.swift` section descriptions | 4 paragraphs of "how it works" (Keychain, 5-minute checks, browser approval) | One quiet line per section head; the mechanics live in tooltips | The onboarding sets the voice: a headline and one control. Settings read like documentation |
| HIGH | Layout | old `AccountRow` | Two buttons per connected service (Check connection, Disconnect…), the account as a sentence | One action per row; the account as a person (picture, name, workspace); the health check runs on its own when the section opens and only speaks when something is wrong | One primary action per row (layout); the check was a button whose answer nobody needed when it passed |
| MEDIUM | Consistency | whole page | `Theme.*` sheet tokens, `PrimaryButtonStyle` | `Soot.*` ground and surface, `LimeButton` / `QuietButton`, `FocusOutline` | The project page, sheets and onboarding use the soot language; Settings was the last framed sheet |
| MEDIUM | Layout | first redesign pass (grid of six panels) | Three tiles, then two blocks, then three blocks, then a footer | An identity column (picture, name, sections) and one section at a time on the right | The user's own verdict on the grid: "blocks placed one after the other". A section list gives the page a spine and leaves each section with one group of controls |
| MEDIUM | Accessibility | `AppearancePicker` | Selected tile shown by a 2px edge in the text colour and the label weight | Selected tile shown by the lime ring and the label weight; `isSelected` exposed; the thumbnail is a small Dever window in that appearance | Shape and fill carry the state; the picture says what each option does without a sentence |
| LOW | Accessibility | notification toggles | 15px switches as the only target | The whole 56px row toggles (`SettingRow(tap:)`) | WCAG 2.5.8 asks 24px; the small switch alone is under it |

## After

### Structure

- **Left column**: your generated picture (`GenerativeAvatar`, seeded, with a "draw another" button),
  your name, and the six sections as rows; the selected row's marker springs between rows. A count on
  Accounts says how many tools still need connecting or reconnecting.
- **Right column**: one section at a time, a 28pt headline and a 13pt line, then rows on one surface.
- **Accounts**: a row per tool (logo, name, the person behind the token with their picture, state glyph,
  one action). Four faces: not connected (dashed edge, what the tool brings, Connect), connecting (lime
  sweep, Cancel), connected (check), rejected or unreachable (the problem in words, Reconnect). The
  Slack channel prefix row sits under them.
- **Repositories**: the repository mode rows shared with onboarding, the workspace repository picker where
  the mode has one, one line on what the choice means.
- **Appearance**: three small windows (Auto split down the middle).
- **Alerts**: the macOS status, or one switch row per situation.
- **Launch**: open at login, open on Overview or the last project, refresh every 1/5/15/30 minutes.
- **About**: version, releases on GitHub, the welcome tour.

### Settings added (all wired)

| Setting | Where it is read |
| --- | --- |
| Refresh every 1/5/15/30 min (`Preferences.refreshMinutes`) | `OverviewStore.staleAfter`, so refreshes and alerts follow it |
| Open at login (`SMAppService.mainApp`) | macOS login items; a refusal is written under the switch |
| Open on Overview / Last project (`Preferences.landing`, `lastProjectID`) | `ContentView.onAppear`; the last project is recorded on every selection |
| Alert kinds (pipeline failing, past target date, merged but still open) | `AlertKind.isEnabled`, honoured by `Notifier.process` |
| Welcome tour | posts `.showOnboarding` |
| Version and releases | `CFBundleShortVersionString`, github.com/eri/dever/releases |
| Account pictures | Slack `users.info`, Linear `viewer.avatarUrl`, GitHub's public avatar; cached in `ImageCache` and in UserDefaults for the next open |

Left out on purpose: Slack density and mark-as-read (they belong to the conversation panel, which has its
own owner), "Check connection" (now automatic), a cross-fade on theme switch (see Motion).

### Coverage (better-interface)

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | Every control of `SettingsView.swift` and `GenerativeAvatar.swift`: names, focus rings, targets, state cues, Reduce Motion; captures in both modes and six states | 2 findings, fixed (switch rows, segment focus ring) |
| Layout | The two columns at 1080×680 (every section fits without scrolling; Accounts is the tallest at 390pt), row heights, shared edges at x=28 and x=40 | Clear |
| Writing | Every string: section heads, row titles, states, buttons, confirmations | Clear (verbs first, one vocabulary with onboarding: Connect, Reconnect, Disconnect, Cancel) |
| Typography | 28 / 22 / 15 / 14 / 13 / 12 / 11, tracking on the two headlines, no text under 11 | Clear |
| Colors | Every rendered pair measured (table in `docs/accessibility-review.md`); `Theme.negative` kept for the two error lines, which the project already uses on soot (`ServiceFailureRow`) | Clear |
| UI | Hover, press, selection, enter and exit of each section, the connecting sweep, the picture reshuffle; replayed in code, not in a browser | 1 finding, fixed (a phantom second stroke around the segment pickers, clipped) |

Verdict: **Approve**. Not verified at runtime: VoiceOver reading of the section switch (the new headline
is a header; no live region), the login-item registration on a notarised build.

## Motion (find-animation-opportunities)

Recon: SwiftUI, the project's own vocabulary (`WaitingLine` and `SweepLine` for waiting, `Breathing` on a
connecting logo, `Skeleton` pulse, 150–250 ms ease-out on state, spring 0.3 / 0.85 on selection).
Settings is an *occasional* surface (opened a few times a week), so it earns standard motion and no more.

### Applied

| # | Location | Today | Purpose | Frequency | Motion |
| --- | --- | --- | --- | --- | --- |
| 1 | `SettingsView` section switch | Content swapped instantly | Preventing a jarring change | Occasional | Cross-fade plus 6pt rise, 200 ms ease-out; opacity only under Reduce Motion |
| 2 | `Identity` section rows | Marker jumped | State indication | Occasional | Marker travels between rows, spring (response 0.3, damping 0.85); no motion under Reduce Motion |
| 3 | `SegmentPicker`, `AppearanceSection` | Pill and ring jumped | State indication | Occasional | Same spring on the lime pill and the lime ring |
| 4 | `ServiceRow` | Account picture popped in once loaded | Preventing a jarring change | Occasional | 200 ms fade from the initial on its tint |
| 5 | `ServiceRow` logo | No hover response | Feedback | Tens/day | Scale 1.08 over 160 ms ease-out, with a 4 % lift of the row; not under Reduce Motion |
| 6 | `Identity` picture | Reshuffle replaced it instantly | Delight (rare) | Rare | Cross-fade with a 0.92 scale, 200 ms ease-out; fade only under Reduce Motion |
| 7 | `ServiceRow` connecting | Already there | State indication | Occasional | `WaitingLine` along the row's foot and `Breathing` on the logo, both still under Reduce Motion |

### Rejected

- Page entrance stagger (first pass had one). **Rejected: the section switch already has its moment; a
  second entrance on every open of Settings adds delay.**
- Cross-fade on Auto/Light/Dark. **Rejected: every colour on screen would transition at once and smear
  (better-ui's theme-switch rule); the ring moves, the theme cuts.**
- Press scale on `LimeButton` / `QuietButton`. **Rejected here: shared styles, and they already dim on
  press; a change belongs to `SootUI.swift`, not to this page.**
- The rail's user tile opening Settings. **Rejected: core navigation, 100+/day. No animation.**
- Toggles. **Rejected: the system switch animates on its own.**

### Elsewhere in the app

- `OverviewView` KPI tabs: the underline cuts between tabs; a 200 ms ease-out slide would be state
  indication at occasional frequency. Small win.
- `ProjectDetailView` panels: skeletons are replaced by content in one frame; a 150 ms fade on the panel's
  content (opacity only) would bridge it. Medium win, every project open.
- `StepSheet`: steps swap instantly; the same 200 ms cross-fade as Settings sections. Small win.
- `DeliveryStrip`: do **not** animate the bar growing on load; it is data the user reads.
- Rail project tiles on hover: do **not** animate; tens of times a day, and the selection ring is enough.

## Strengths

- The onboarding's voice carries through: one headline, one group of controls, few words.
- Every account state is a different picture, not a different sentence.
- Nothing on the page relies on hue alone; every custom control has the same 2px lime focus ring.

Highest-leverage next change: the panel-content fade on the project page (above), which every open of a
project would feel.

## Follow-up: account actions and the channel prefix

### Account rows

The 36px "Disconnect" button was the loudest thing on a row whose job is to say "this works". It moves
into a menu, in the overview's "Add many" menu style: soot ground, 12pt radius, hairline edge, shadow.
The trigger is the state glyph with a chevron. The menu's head says what the glyph means ("Connected and
working", "Linear answered 1 second ago. The token stays in your Keychain"). Under it are **Check status**
and **Disconnect**, which keeps its confirmation. Checking runs the lime line along the row's foot, never
a spinner. Reconnect stays outside the menu, as the one lime action, when a session expired.

### Channel prefix (better-interface + superfuture critique)

Before: a "Slack channel prefix" row with a 140px field top-right. Under it was a two-column example of
invented channels (`#23-checkout → Checkout`, `#general` greyed) with arrows.

| Severity | Domain | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- |
| HIGH | Writing | `SettingsView.swift`, the prefix row's detail | "Channels that start with it become projects" | "Import offers the channels that start with this; new ones are named the same way" | The prefix only filters what Import offers and names new channels (`ProjectSetupViews.swift:515`, `:743`, `:511`). Nothing becomes a project by itself, so the sentence misled |
| HIGH | Layout | the prefix row | Field top-right, its effect bottom-left, about 600pt apart | The field is the start of a channel name: `# [23-] acme-website` | The control and what it changes must touch. The eye crossed the card twice to connect them |
| MEDIUM | Writing | the example | Invented channels and projects | The user's real channels that match, prefix in lime, with a live count ("8 of your channels match", rolling) and `+N` past four | Made-up data reads as decoration; real channels answer "is my prefix right?" at a glance |
| MEDIUM | Colors | `#general` greyed as "not a project" | Meaning carried by dimming alone | Only matching channels are listed; the count states the rest | 1.4.1: a grey row is not a statement |
| LOW | Layout | the example's arrows | Floating arrows across a 140pt gap with no shared edge | Removed | Delete before adding: the composer already shows the mapping |

States: Slack not connected says "Connect Slack to see which of your channels match". An empty prefix says
"you pick project channels yourself when you import". While channels load, three skeleton chips show. No
match says so in words.

Superfuture rubric: one focal point (the composer, the only lime field), the scan path follows it (title,
composer, proof), and no number is invented. The field keeps a 2px lime edge when focused, and its
accessible name is "Slack channel prefix".
