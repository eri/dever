# Setting up Dever (once, by an admin)

Dever connects to Slack and Linear through two team-owned "Dever" OAuth apps. They are free
and only need to be created once; after that, each teammate clicks "Connect" and approves
in their browser. Nobody has to create an API key.

The resulting credentials go into `config/dever.json` (a copy of `config/dever.example.json`).
That file is not committed: it is bundled into the app at build time.

## 1. Slack redirect page (GitHub Pages, free)

✅ Already live: https://eri.github.io/dever/oauth/slack-callback.html (repository `eri/dever`).
The steps below are only needed to publish it elsewhere (e.g. the team's GitHub organization).

Slack only accepts HTTPS redirect URLs. We therefore publish `docs/oauth/slack-callback.html`,
a static page that forwards to the app (`http://localhost:47321/slack/callback`).

1. Push this repository to GitHub.
2. Settings → Pages → Source: branch `main`, folder `/docs`.
3. The page URL is `https://<account>.github.io/<repo>/oauth/slack-callback.html`
   → `slack.redirectURL` in `config/dever.json`.

## 2. Slack app

Fastest: https://api.slack.com/apps → **Create New App** → **From a manifest** → pick the workspace →
paste [`docs/slack-manifest.json`](slack-manifest.json) (adjust the redirect URL if you host the page
elsewhere) → **Create**. Then skip to step 3 below.

Manual alternative:

1. https://api.slack.com/apps → **Create New App** → *Blank app* → name `Dever`, the team's workspace.
2. **OAuth & Permissions**:
   - *Redirect URLs*: the GitHub Pages URL above.
   - *User Token Scopes*: `channels:read`, `groups:read`, `channels:history`, `groups:history`,
     `channels:write`, `groups:write`, `users:read`, `team:read`, `files:read`, `chat:write`,
     `reactions:read`, `reactions:write`, `emoji:read`.
   - Do **not** enable *Token Rotation* (tokens would then expire every 12 h).
3. **Basic Information** → *Client ID* and *Client Secret* → `slack.clientID` / `slack.clientSecret`.

The app stays internal to the workspace (no public distribution). If the workspace requires
app approval, a Slack admin approves it once.

> The *Client Secret* is bundled into the app: fine for an internal tool, but only share the
> DMG within the team.

## 3. Linear app

1. Linear → **Settings → Administration → API** → *OAuth applications* → **New** (admin rights required).
2. Name `Dever`, *Callback URL*: `http://localhost:47321/linear/callback`.
3. Copy the *Client ID* → `linear.clientID`. The secret is not used (PKCE).

Linear tokens last 24 h and are renewed automatically by the app.

## 4. GitHub (optional)

By default Dever uses GitHub CLI's public OAuth client (sign-in with a code).
If the GitHub organization restricts OAuth apps, create an *OAuth App* (Settings →
Developer settings), tick **Enable Device Flow**, and put its Client ID in `github.clientID`.

## 5. Code signing (avoids repeated Keychain prompts)

macOS remembers "Always Allow" for the Keychain per *code identity*. An ad-hoc signature
changes on every build, so the prompt would come back after each update. `build-app.sh`
therefore signs with the first valid code-signing identity it finds. A free
**Apple Development** certificate is enough: Xcode → Settings → Accounts → add your Apple ID →
Manage Certificates → **+** → Apple Development. To pick a specific one:
`DEVER_SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh`.

Always build the DMGs you share with the same identity, so teammates keep their Keychain
approval across updates.

## 6. Build and share

```bash
DMG=1 ./scripts/build-app.sh
```

Share `build/Dever.dmg`. The app is ad-hoc signed (no paid Apple Developer account), so macOS
blocks it on first launch. Right-click Dever.app → **Open** → **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Dever.app
```

## Preview environments (optional)

Teams whose pull requests deploy preview environments at `pr-<N>-<target>.<domain>` put that domain in
`preview.domain` of `config/dever.json`. Without it the Preview panel still follows the workflow's
comments and runs, but finds no deployed target to open or probe.
