<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/dever-mark-lime.svg">
  <img src="docs/brand/dever-mark-green.svg" width="56" height="56" alt="Dever">
</picture>

# Dever

macOS app (SwiftUI) that brings together, per project, its Slack channel, its Linear project and its GitHub repository.

```bash
cp config/dever.example.json config/dever.json   # then fill it in (docs/SETUP.md)
./scripts/build-app.sh && open build/Dever.app
```

## Connecting accounts (no API keys)

| Service | Method | Lifetime |
|---|---|---|
| Slack | OAuth through the team's "Dever" app (user token `xoxp`) | Never expires |
| Linear | OAuth + PKCE through the team's "Dever" app | 24 h, renewed automatically |
| GitHub | Device Flow (enter a code) or reuse `gh auth token` | Never expires |

"Connect" opens the default browser; the app receives the authorization on `http://localhost:47321`.
Setting up the OAuth apps (once, by an admin): [docs/SETUP.md](docs/SETUP.md).

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
  API's health, probed with a HEAD request on `pr-<N>-<target>.preview.mendo.cloud`). Deploy (one click, or with
  options from the More menu), redeploy, protect and delete post the team's own commands as PR comments
  (`/preview [--nb-api-pods=N] [--nb-app-pods=N] [--prod] [--autoscale] [--keep]`, `/delete-preview`); the state is
  read back from the workflows' result comments and runs, refreshed with the overview every 5 minutes and every 30 s
  after a command until the workflow answers.

## Screenshots for development

Dever can photograph its own window, without screen-recording permission:

```bash
DEVER_SNAPSHOT_DIR=/tmp/dever-shots ./build/Dever.app/Contents/MacOS/Dever
```

It opens Overview, the first project and Settings in dark then light mode, saves one PNG per screen, and quits.
Add `DEVER_SNAPSHOT_ONBOARDING=1` to capture the onboarding stages too, and `DEVER_SNAPSHOT_WAIT=0` to capture the loading state.
`DEVER_SNAPSHOT_PROJECT=1` captures the second project instead of the first.
`DEVER_SNAPSHOT_DELIVERY=busy` (or `grab`, `done`) fills the Delivery panel with a made-up project, to capture every situation.
`DEVER_SNAPSHOT_ISSUE=1` opens the first project's first issue and saves `issue-{dark,light}.png` plus a `-end` capture
scrolled to the comments; add `DEVER_SNAPSHOT_CHOICE=Status` (or `Priority`, `Assignee`) to open that chip's list, and
`DEVER_SNAPSHOT_TRIAGE=1` to write the issue's current priority back and show the confirmation line.
Connection states, without touching the Keychain: `DEVER_SNAPSHOT_DISCONNECTED=slack,linear,github` runs as if those
tools had never been connected, `DEVER_SNAPSHOT_UNAUTHORIZED=linear` as if the service rejected the token,
`DEVER_SNAPSHOT_FAILING=github,slack=offline` as if calls failed (a 503, or no network), and
`DEVER_SNAPSHOT_CONNECTING=linear` shows that tool mid-connection on the project page.
Preview panel states from sample data (PR #4714, no network): `DEVER_SNAPSHOT_PREVIEW=live|deploying|failed|deleted|notdeployed|none`
(`none`: no pull request linked); add `DEVER_SNAPSHOT_PREVIEW_OPTIONS=1` for the deploy options row, and
`DEVER_SNAPSHOT_SHEETS=1 DEVER_SNAPSHOT_SCREENS=0 DEVER_SNAPSHOT_STEP=preview DEVER_SNAPSHOT_PICKER="Pull request"` for the editor's step.
Repository modes: `DEVER_SNAPSHOT_REPO_MODE=single|perProject|mixed[:owner/name]` runs under that mode (and workspace
repository), `DEVER_SNAPSHOT_REPOS=owner/a,owner/b` gives the first project those repositories, and
`DEVER_SNAPSHOT_UNLINK=slack,linear,github,preview` runs as if the captured project had not linked those tools
(nothing is written back). `DEVER_SNAPSHOT_SCROLL_END=1` adds each main screen scrolled to its end (`settings-dark-end.png` shows the Repositories section).
Nothing is written back in these runs.

## Onboarding

New users (no project yet) start with a short welcome: their display name, connecting Slack, Linear and GitHub
(with what each one is used for), where the code lives (the repository mode, with GitHub), the channel prefix, then
a first project. Reopen it from Help → Welcome to Dever….
