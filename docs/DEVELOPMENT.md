# Development notes

The details that used to sit in the README: how projects, repository modes and previews behave, how data is kept fresh, and how Dever photographs itself for development. Setting up the OAuth apps is in [SETUP.md](SETUP.md).

## Connecting accounts (no API keys)

| Service | Method | Lifetime |
|---|---|---|
| Slack | OAuth through the team's "Dever" app (user token `xoxp`) | Never expires |
| Linear | OAuth + PKCE through the team's "Dever" app | 24 h, renewed automatically |
| GitHub | Device Flow (enter a code) or reuse `gh auth token` | Never expires |

"Connect" opens the default browser; the app receives the authorization on `http://localhost:47321`.
Setting up the OAuth apps (once, by an admin): [docs/SETUP.md](SETUP.md).

Tokens are stored in the macOS Keychain (`io.github.eri.dever`), projects in `~/Library/Application Support/Dever/projects.json`.

## Projects

- **New project**: creates (or links) the `<prefix><slug>` channel and the Linear project; detects existing ones with the same name.
- **Import from Slack**: lists channels following the naming convention and suggests the matching Linear project.
- **Import from Linear**: lists projects and suggests the matching channel.
- A project without both a Slack channel **and** a Linear project is flagged ⚠️ incomplete.
- **Repository mode** (asked during onboarding, changeable in Settings → Repositories): *one repository for
  everything* (a workspace repository every project follows; the editor has no repository step),
  *repositories per project* (each project picks one or several) or *both* (a project follows the workspace
  repository unless it picks its own). Pull requests and pipeline runs add up across a project's repositories,
  and rows name the repository when there is more than one. Switching modes loses nothing: a project's own
  repositories stay saved while the single mode ignores them. Imports in the per-project and mixed modes link a
  repository named like the project.
- **Preview environment** (optional, needs a GitHub repository): the project follows the preview of one pull request,
  chosen in the editor ("Preview" step); "No preview needed" on the project page hides the panel until one is picked.
  The panel sits above Delivery and shows the PR, the state (not deployed, deploying, updating,
  live, failed, deleted), the deployed products (App, Back office, Client Hub: each chip opens the front, its mark folds in the
  API's health, probed with a HEAD request on `pr-<N>-<target>.<domain>`, the domain being `preview.domain` in `config/dever.json`). Deploy (one click, or with
  options from the More menu), redeploy, protect and delete post the team's own commands as PR comments
  (`/preview [--nb-api-pods=N] [--nb-app-pods=N] [--prod] [--autoscale] [--keep]`, `/delete-preview`); the state is
  read back from the workflows' result comments and runs, refreshed with the overview (every two minutes in the background, every minute on screen) and every 30 s
  after a command until the workflow answers.

## Data freshness

How Dever loads, caches and refreshes what it shows, the freshness budget of each kind of data, and the
checklist every feature answers (what it reads, writes and invalidates, its budget, its loading state):
[docs/data-freshness.md](data-freshness.md). The short rules are in [CLAUDE.md](../CLAUDE.md).

Unit tests for the data layer (the resource cache, pull request matching, checks): `swift test`.

To see what a refresh costs, run with `DEVER_TRACE_REQUESTS=1`: every request to Slack, Linear and GitHub
is printed to stderr with its status, size and duration, and the running total.

## Screenshots for development

Dever can photograph its own window, without screen-recording permission:

```bash
DEVER_SNAPSHOT_DIR=/tmp/dever-shots ./build/Dever.app/Contents/MacOS/Dever
```

It opens Overview, the first project and Settings in dark then light mode, saves one PNG per screen, and quits.
Add `DEVER_SNAPSHOT_ONBOARDING=1` to capture the onboarding stages too (`DEVER_SNAPSHOT_STAGE=name|connect|repositories|channels|intelligence|project` for that stage alone), and `DEVER_SNAPSHOT_WAIT=0` to capture the loading state.
`DEVER_SNAPSHOT_PROJECT=1` captures the second project instead of the first.
`DEVER_SNAPSHOT_DELIVERY=busy` (or `grab`, `done`) fills the Delivery panel with a made-up project, to capture every situation.
`DEVER_SNAPSHOT_ISSUE=1` opens the first project's first issue and saves `issue-{dark,light}.png` plus a `-end` capture
scrolled to the comments; add `DEVER_SNAPSHOT_CHOICE=Status` (or `Priority`, `Assignee`) to open that chip's list, and
`DEVER_SNAPSHOT_TRIAGE=1` to write the issue's current priority back and show the confirmation line.
Connection states, without touching the Keychain: `DEVER_SNAPSHOT_DISCONNECTED=slack,linear,github` runs as if those
tools had never been connected, `DEVER_SNAPSHOT_UNAUTHORIZED=linear` as if the service rejected the token,
`DEVER_SNAPSHOT_FAILING=github,slack=offline` as if calls failed (a 503, or no network), and
`DEVER_SNAPSHOT_CONNECTING=linear` shows that tool mid-connection on the project page.
Preview panel states from sample data (PR #4714, no network): `DEVER_SNAPSHOT_PREVIEW=live|behind|conflict|deploying|failed|deleted|notdeployed|none`
(`none`: no pull request linked); add `DEVER_SNAPSHOT_PREVIEW_OPTIONS=1` for the deploy options row, and
`DEVER_SNAPSHOT_SHEETS=1 DEVER_SNAPSHOT_SCREENS=0 DEVER_SNAPSHOT_STEP=preview` for the editor's step.
Editor pages: `DEVER_SNAPSHOT_STEP=name|slack|linear|github|preview|ready` opens that step's question, `DEVER_SNAPSHOT_PHASE=detail`
its second page, `DEVER_SNAPSHOT_CHOICE=create|existing` picks that answer, `DEVER_SNAPSHOT_DETECT=1` names the project after
one of your channels so a match is found, and `DEVER_SNAPSHOT_SHEET_THEME=light` captures sheets in light mode.
Repository modes: `DEVER_SNAPSHOT_REPO_MODE=single|perProject|mixed[:owner/name]` runs under that mode (and workspace
repository), `DEVER_SNAPSHOT_REPOS=owner/a,owner/b` gives the first project those repositories, and
`DEVER_SNAPSHOT_UNLINK=slack,linear,github,preview` runs as if the captured project had not linked those tools
(nothing is written back). `DEVER_SNAPSHOT_SCROLL_END=1` adds each main screen scrolled to its end (`settings-dark-end.png` shows the Repositories section).
On-device intelligence: `DEVER_SNAPSHOT_INTELLIGENCE=available|notReady|off|unsupported` runs as if the Mac's model were in
that state and shows every feature's interface (Settings › Intelligence included); with `DEVER_SNAPSHOT_GALLERY=1` it adds
`generated-{dark,light}.png`, generated text in each of its states, and with `DEVER_SNAPSHOT_SUMMARIES=1`
`summaries-{dark,light}-{waiting,landing-0…5,landed}.png`: a rail of made-up long messages whose summaries land one after the other.
With `DEVER_SNAPSHOT_OVERVIEW_DEMO=busy` the Overview's long mention shows as its summary (as its start with
`DEVER_SNAPSHOT_INTELLIGENCE=off`; without the variable the Mac's own model writes it).
`DEVER_SNAPSHOT_WHY=1` with `DEVER_SNAPSHOT_DELIVERY=busy` opens the failed checks' card on the "Start here" tile; `DEVER_SNAPSHOT_WHY=open` with
`DEVER_SNAPSHOT_ISSUE=1` shows a made-up failed pull request on the issue page with its card open.
`DEVER_SNAPSHOT_ONBOARDING=1 DEVER_SNAPSHOT_STAGE=intelligence` with each value of `DEVER_SNAPSHOT_INTELLIGENCE` captures the onboarding's
Intelligence stage in that state; with `unsupported` the stage is not part of the flow, and the capture shows the first-project
stage and five progress marks.
Nothing is written back in these runs.

## Onboarding

New users (no project yet) start with a short welcome: their display name, connecting Slack, Linear and GitHub
(with what each one is used for), where the code lives (the repository mode, with GitHub), the channel prefix, what the Mac's own model does
(where the Mac can run it), then a first project. Reopen it from Help → Welcome to Dever….

Every stage opens with the same head (`StageHead` in `OnboardingView.swift`): a glyph and the stage's name in lime
(Welcome, Accounts, Repositories, Slack channels, Enable Local Intelligence, Projects), the headline, and one sentence
of 15 pt muted text that says why it is asked. The sentence is left out where the stage has no room for it at the
smallest window (Repositories, whose rows say it). Under the head: rows, at most one line of reassurance, one action.
