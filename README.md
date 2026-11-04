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

## Screenshots for development

Dever can photograph its own window, without screen-recording permission:

```bash
DEVER_SNAPSHOT_DIR=/tmp/dever-shots ./build/Dever.app/Contents/MacOS/Dever
```

It opens Overview, the first project and Settings in dark then light mode, saves one PNG per screen, and quits.
Add `DEVER_SNAPSHOT_ONBOARDING=1` to capture the onboarding stages too, and `DEVER_SNAPSHOT_WAIT=0` to capture the loading state.
`DEVER_SNAPSHOT_ISSUE=1` opens the first project's first issue and saves `issue-{dark,light}.png` plus a `-end` capture
scrolled to the comments; add `DEVER_SNAPSHOT_CHOICE=Status` (or `Priority`, `Assignee`) to open that chip's list, and
`DEVER_SNAPSHOT_TRIAGE=1` to write the issue's current priority back and show the confirmation line.

## Onboarding

New users (no project yet) start with a three-stage welcome: what Dever does and their display name, connecting
Slack, Linear and GitHub (with what each one is used for), then a first project. Reopen it from Help → Welcome to Dever….
