# Data freshness

How Dever loads, caches, refreshes and invalidates what it shows, what is wrong with it today, and the
strategy every feature follows from now on.

Two goals, held together:

1. **Fresh.** A state that drives a decision (a failed check, a review asked of you, a mention, a deploy)
   is never shown as current when it is not. Showing "passing" five minutes after GitHub said "failed"
   is the failure this document exists to prevent.
2. **No waiting.** A screen that has been seen once never goes back to skeletons, and a change made in
   Dever shows everywhere at once. Refreshing is targeted and happens behind what is already on screen.

Contents: [audit](#1-audit) · [options](#2-options-weighed) · [strategy](#3-strategy) ·
[budgets](#4-freshness-budgets) · [screens and exits](#5-screens-and-exits) · [plan](#6-plan) ·
[**checklist for every feature**](#7-checklist-for-every-feature)

---

## 1. Audit

State of `main` in November 2026, **before phases 1 and 2** (section 6 says what they changed; findings
they closed are marked there). File references are under `Sources/Dever/`.

### 1.1 Where data lives

| Data | Fetched by | Held in | Lifetime | Refetched by |
| --- | --- | --- | --- | --- |
| Overview row (Linear counts, Slack week and unread, mentions, PR counts, pipeline, review requests, last merge) | `OverviewStore.refresh` | `OverviewStore.snapshots` | app session | timer, Overview appearing when stale, Refresh, a repository-mode change |
| Linear issue rows of a project | `IssueStore.load` | `IssueStore.projects` | app session | project page appearing, Refresh (full) |
| Linear issue detail, team states and members, blockers, viewer id | `IssueStore.detail / team / loadPlanContext` | `IssueStore` | detail: until its `updatedAt` changes · team: 15 min · blockers: each page load · viewer: once | issue page appearing |
| Open and merged pull requests, workflow runs, review verdicts | `ProjectDetailView.loadGitHub` | **view `@State`** | one visit of the page | page appearing, Refresh |
| Slack channel messages, read cursor, thread replies | `ProjectDetailView.loadSlack`, `ThreadPane.load` | **view `@State`** | one visit of the page | page appearing, after a reply or a reaction |
| Slack members, custom emoji, linked channel names | `SlackDirectory` | actor + disk copy | 15 min · 1 h · session | on demand |
| Release line: last merge into staging and production, staging checks, open release pull request | `ReleaseStore.refresh` (one or two GraphQL queries, about 2 kB) | `ReleaseStore.state` | 2 min | Overview cycle, Refresh, back to Dever after opening one of its parts on GitHub |
| Preview environment of a pull request | `PreviewStore.load` | `PreviewStore.states` | 60 s, shared by Overview and project page | Overview cycle, panel appearing, every 30 s after a command |
| Images, Slack files | `ImageCache`, `SlackMediaCache` | disk | size and age purge | on demand |
| Projects, settings, credentials | `AppState` | JSON file, UserDefaults, Keychain | permanent | local only |

There are four caching styles for four kinds of data. `IssueStore` and `PreviewStore` are the good ones:
app-lifetime, keyed, concurrent calls share one request, a failed refresh keeps the last value.
`IssueStore` also refreshes by delta (`updatedAt > newest seen`) and writes optimistically with rollback.
The pull requests and the Slack channel have none of that: they are copies owned by one view.

### 1.2 What triggers a fetch today

| Trigger | What happens |
| --- | --- |
| Launch | `OverviewStore.startAutoRefresh`: a loop that wakes every 60 s and refreshes **every project** when the last refresh is older than Settings › Refresh every (1/5/15/30 min, default 5). |
| Overview appears | A full refresh if stale by the same setting, otherwise nothing. |
| Refresh button, ⌘R (Overview) | Full refresh of every project. |
| Project page appears (sidebar, Overview row, back from an issue) | `load()`: Slack page + cursor, Linear delta, then GitHub in full, then up to 30 review requests. |
| Refresh button (project page) | The same with a full Linear reload. |
| Issue page appears | Detail if its `updatedAt` differs from the cached one; team context if older than 15 min. |
| Thread opens | Its replies, once. |
| After a preview command | The preview every 30 s until the phase settles (up to 40 min). |
| A token arrives | Project page reloads. |
| App becomes active, window regains focus | **Nothing.** (Only the notification-permission rows in Settings and onboarding listen.) |
| Wake from sleep, network back | **Nothing** specific; the 60 s loop notices on its next tick. |
| Staying on a project page | **Nothing.** No timer reaches the page's own state. |

### 1.3 Measurements

GitHub was measured against a real, busy shared repository (about 95 open pull requests) with the same
requests the app sends. Slack and Linear counts are read off the code (their tokens live in the Keychain
and were left alone).

| Request (`per_page=100`) | Time | Body | With `If-None-Match` |
| --- | --- | --- | --- |
| Open pull requests, page 1 | 2.3 s | 3.2 MB | 304, 0 KB, quota untouched |
| Closed pull requests, pages 1 to 3 | 8.0 s | 6.4 MB | 304 each, quota untouched |
| Workflow runs of the repository | 5.5 s | 1.7 MB | 304, quota untouched |
| One pull request | 0.9 s | 17 KB | 304 |
| Its comments (64) | 1.3 s | 267 KB | 304 |
| **One repository, as the Overview fetches it** | **≈ 16 s** in sequence (5 s if sent together) | **11.3 MB** | |
| GraphQL: 50 open pull requests with check rollup, review decision, head | 3.2 s | **14 KB** | cost: 1 point |

Three facts from this table shape everything below:

- **A refresh of one repository downloads 11 MB.** At the default 5 minutes that is about 1 GB of JSON in
  a working day, to recompute a handful of numbers. Lowering the timer is not an option as things are.
- **The 100 latest workflow runs covered 3 hours and 11 branches.** The app derives each pull request's
  CI state from that window. Any pull request whose last run is older has no state, and a project's
  pipeline is the worst of the few branches that happened to run recently. The GraphQL rollup, which is
  what GitHub itself shows on the pull request, reported 27 failing among the 50 most recent.
- **Conditional requests work**: a 304 costs no quota and no body. GraphQL is smaller still.

Request counts per action (one project with Slack, Linear, one repository and a preview):

| Action | Slack | Linear | GitHub | Notes |
| --- | --- | --- | --- | --- |
| Overview refresh, per project | 2 to 3 (`history` 200, `info`, sometimes `history` 20) | 1 (`projectSummary`, first 250 issues) | 5 to 7 per distinct repository, in sequence; preview 5 to 6 + one HEAD per target | Four projects at a time. `users.list` once per 15 min. |
| Open a project page | 2 to 3 | 2 to 3 (delta, blockers, viewer once) | 5 to 7 again, then up to 30 `reviews` | The GitHub part repeats what the Overview fetched seconds earlier. |
| Back from an issue | the same again | the same | the same | The page's `.task` runs on every appearance. |
| Reply or react in Slack | 1 write + 2 to 3 (whole channel page and cursor again) | | | |
| Move or take an issue | | 1 mutation | | Optimistic; nothing else refetched. |

Rate limits are not the binding constraint today (GitHub: 5,000 requests an hour per user; Slack:
`conversations.history` and `.info` are Tier 3, about 50 a minute, for a workspace's own app; Linear: on
the order of 1,200 to 1,500 requests an hour per user plus a complexity budget). Bytes and seconds are.
One caveat to keep in view: Slack limits `conversations.history` and `.replies` to one request a minute
for commercially distributed apps outside its Marketplace. Dever is installed as each workspace's own app,
which is exempt; a single shared Dever app would not be.

### 1.4 Findings, ranked by what the user feels

**F1. The project page never refreshes while it is open.** Pull requests, CI, reviews and messages are
loaded once into the view's own state. The Overview's timer refreshes a different copy. A check that
fails while you look at the page stays green until you press Refresh or leave and come back. On the
Overview the worst case is the setting plus a minute plus the load (over 6 minutes at the default).
*This is the "fatal" case.*

**F2. CI state is read from the wrong source.** It comes from the repository's last 100 workflow runs
(3 hours on the measured repository), not from each pull request's checks. Old failures disappear, and
"pipeline passing" can mean "the failing branches did not run lately". No refresh cadence fixes this;
the query has to change.

**F3. Every refresh is a whole reload, and it is slow.** 11 MB and about 16 s per repository on the
Overview, fetched in sequence. A project's row is published only when all of its services have answered,
so a new Slack mention waits for the GitHub chain. The project page then downloads the same again,
because nothing is shared, and adds one request per pull request for reviews.

**F4. Opening a project always starts from skeletons.** Its Slack and GitHub data live in view state and
the view is rebuilt on each selection, so data fetched a minute ago is thrown away. Only the Linear part
(in `IssueStore`) appears at once.

**F5. Nothing refreshes when you come back.** Clicking through to GitHub, Linear or Slack, acting there
and returning to Dever shows what was there before. The same after sleep or a network drop.

**F6. A write does not reach the other copies.** Moving an issue in Delivery leaves the Overview's
"Issues shipped" and status as they were until the next cycle, because the Overview counts issues from
its own `projectSummary` copy. Saving the project editor (linking Linear, a channel, a repository) left
both the open project page and the Overview row untouched (the page part is fixed, see 6.0). Reading a
mention is the one case done right (`OverviewStore.slackRead`, commit `92b6754`): it is the model.

**F7. Failure looks like freshness.** `lastRefresh` is set even when every call failed, so the header
says "updated now" over old rows and the next attempt waits a full interval. The "updated …" text does
not tick. On the project page a failed refresh replaces a panel that had data with the failure row.
Nothing shows the age of a CI or preview state.

**F8. Smaller gaps.** The Overview's Linear summary stops at 250 issues. An issue opened without a known
`updatedAt` (a blocker link) is served from cache for the whole session. An open thread and an open issue
never refresh. A reaction refetches the whole channel page.

What already works and stays: `IssueStore` (delta, optimistic writes with rollback, shared requests),
`PreviewStore` (shared, 60 s, polling only while something is in flight, last value kept on failure),
`SlackDirectory` (long-lived reference data with a disk copy), skeletons only before the first load.

---

## 2. Options weighed

| Option | Verdict | Why |
| --- | --- | --- |
| **Exit-door matrix as the mechanism** (for each way out of a screen, reload what may have changed on return) | Kept as a **review tool**, not as the mechanism | It covers what *you* changed and misses what *others* change while you stay put, which is the fatal case (F1). Hand-wiring screens × exits also grows quadratically and one forgotten exit is a stale screen. Every exit reduces to two generic events: *a write happened* (invalidate named resources) and *the user is looking again* (revalidate what is visible and past its budget). The matrix in section 5 checks that those two events cover every door. |
| **Optimistic writes with reconciliation** | **Adopt everywhere** | Already proven in `IssueStore.update`. The UI changes on the click, the server's answer replaces the guess, a refusal restores the old value and says so. |
| **Per-resource stores with a freshness budget** (keyed cache, age per resource type, shared in-flight requests) | **Adopt: the core** | One copy of each thing, so a write or a refresh shows on every screen; staleness is decided per kind of data instead of one global timer. |
| **Stale-while-revalidate, skeletons on first load only** | **Adopt** | Falls out of the stores: a screen renders what the store has and refreshes behind it. |
| **Refresh on activation, wake, network return, and return from an external link** | **Adopt** | Cheap, and it is exactly when the user looks. Debounced, limited to what is visible and past its budget; the entity just opened externally is refreshed regardless of age. |
| **Adaptive polling** | **Adopt, after requests are cheap** | Fast for what is volatile and visible (a running check, the open channel), slow for the rest, paused when nobody looks. Only affordable once a poll costs kilobytes (next two rows). |
| **GitHub conditional requests (ETag)** | **Adopt** for the REST calls that remain | Measured: 304, no body, no quota. |
| **GitHub GraphQL for pull requests** | **Adopt** | One 14 KB request replaces 3.2 MB of pulls, 1.7 MB of runs and one `reviews` call per pull request, and returns the real check rollup (fixes F2). |
| **Linear and Slack incremental reads** | **Adopt** | Linear: `updatedAt > cursor`, already in `IssueStore`, extended to the Overview. Slack: `conversations.history` with `oldest` = newest known `ts`, plus `conversations.info` for the read cursor. |
| **Data age on screen** | **Adopt, for decision states only** | CI, review, preview, deploy. "Checked 20 s ago" when it matters; a state past twice its budget, or whose last refresh failed, is drawn as stale with its time, never as current. Not on every row: noise. |
| **Push** | **Not now; keep the door open** | See below. |
| **A shorter global timer** | Rejected | 11 MB per repository per tick, still up to a minute stale, still whole reloads. |
| **A local database of everything** (SQLite, SwiftData) | Rejected for now | The data is small and re-derivable. A plain disk snapshot of the stores for instant launch is an optional later step. |
| **A third-party data library** | Rejected | The package has no dependencies; the store pattern is about 200 lines and two stores already implement most of it. |

**What a desktop app can and cannot receive.** Webhooks (GitHub, Linear, Slack Events API) are HTTP calls
to a public server; a desktop app has none. Slack Socket Mode is an outbound WebSocket and would work from
a desktop, but it needs an app-level token shipped in every copy, allows ten connections per app, and
delivers each event to only *one* of them, so several users of the same workspace app would each miss
most events. Linear and GitHub offer clients no public push at all. Real push therefore means a small
relay service that receives the webhooks and fans them out to connected apps. That is a product decision
(Dever has no backend today), not an optimisation. The strategy does not depend on it; the stores expose
`invalidate(key)` so a push source can be plugged in later without touching a screen.

---

## 3. Strategy

**One store per kind of remote data, keyed by resource, with a freshness budget. Screens read stores.
Three events refresh: a write, someone looking, and a clock that runs faster for what is volatile and
visible.**

### 3.1 Resources and stores

- Every remote thing is a **resource** with a key: `pulls(repo)`, `checks(repo, pull)`, `merged(repo)`,
  `channel(id)`, `cursor(channel)`, `thread(channel, ts)`, `issues(project)`, `issue(id)`,
  `preview(project)`.
- Resources live in **app-lifetime stores** (`IssueStore`, `PreviewStore`, and the missing `GitHubStore`
  and `SlackStore`), never in a view's `@State`. A view keeps only what is about the view: scroll
  position, an open thread, a draft.
- Each entry carries its value, `fetchedAt`, and whether its last refresh failed. Concurrent requests for
  one key share one call. A failed refresh keeps the value.
- **Derived data is computed, not fetched**: the Overview row, the Delivery plan and "for you" are
  functions of the stores. There is one copy of a project's issues and one of a repository's pull
  requests, so two projects on one repository, the Overview and the project page all see the same thing
  at the same moment.

### 3.2 Reading: stale-while-revalidate

A screen asks the store for a resource. If there is a value, it is shown at once; if it is older than its
budget, a refresh starts behind it and the rows update in place when it lands. Skeletons appear only when
there is no value at all. A refresh never empties a list, never resets scroll, and merges by id.

### 3.3 Writing: optimistic, reconciled, invalidating

1. Apply the change to the store at once.
2. Send it. Replace the guess with the server's answer.
3. On refusal, restore the previous value and say so.
4. **Invalidate by name** every resource the write can change on the server side that the answer does not
   contain (for instance a comment posted on a pull request invalidates `preview(project)`).

Because derived data is computed from the stores, steps 1 to 3 already update every screen.

### 3.4 Refresh triggers

| Event | Effect |
| --- | --- |
| A screen appears | Revalidate its resources that are past budget. |
| The app becomes active, wakes, or the network returns | The same for the visible screen, debounced; then the background cycle if it is due. |
| The user opened something externally (a pull request, an issue, a message, a run) | That resource is marked dirty: the next activation refreshes it whatever its age. |
| A write | Section 3.3. |
| The clock | Each visible resource at its own cadence (section 4), faster while something is in flight (a running check, a deploying preview). Everything else at Settings › Refresh every. Nothing visible, app inactive: the background cycle only, so notifications still fire. |
| Errors, HTTP 429, `Retry-After` | Back off per service; the age label says the data is old. |

### 3.5 Cheap requests

Polling every 15 to 60 s is only acceptable if a poll that finds nothing new costs almost nothing:

- **GitHub**: GraphQL for the pull request lists with their check rollup, review decision and requested
  reviewers; `If-None-Match` on the REST calls that remain (one pull request, its comments, workflow runs
  of the preview). Never the repository-wide runs list to infer a pull request's CI.
- **Linear**: delta by `updatedAt`, one query per project; a full reload every 30 min as today to catch
  deletions and moves out of the project.
- **Slack**: `oldest` = newest known `ts` for the channel, and `conversations.info` for the cursor;
  replies only for the open thread.

### 3.6 Honesty about age

- Decision states (CI, review, preview, deploy) show when they were checked once that is older than their
  budget, with a ticking label (`TimelineView`).
- Past **twice** its budget, or after a failed refresh, the state is drawn as stale (muted, with its
  time), and a refresh is attempted. It is never drawn with the colour of a current state.
- "Updated" is the time of the last *successful* fetch of that data, never of the last attempt.

---

## 4. Freshness budgets

The budget is the oldest a value may be **while it is visible**. Background projects follow Settings ›
Refresh every. "Volatile" is the cadence while something is in flight.

| Data | Budget (visible) | Volatile | Refreshed by, besides the clock | Cheap read |
| --- | --- | --- | --- | --- |
| Checks of an open pull request | 60 s | 15 s while a check is queued or running | activation, opened externally | GraphQL rollup |
| Open pull requests, review decision, requested reviewers | 60 s | | activation, opened externally | GraphQL |
| Merged pull requests | 5 min | | a pull request left the open list | GraphQL |
| Default-branch health | 5 min | 30 s while running | activation | GraphQL |
| Failed checks of a pull request's head commit (the failed job, its step) | on opening the failed state's card, once per run | | the click; dropped when the pull request's checks stop failing | GraphQL, about 1 kB |
| End of a failed job's log, and the sentence generated from it on the Mac | on opening the failed state's card, once per run | | the click; dropped with the entry above; memory only (`FailureStore`) | the last 64 kB at most, never the whole log |
| Preview environment | 60 s | 15 s while deploying, updating or deleting (30 s after a command posted from Dever) | command posted, activation | ETag. Conflict and "behind the pull request" come from the same reads (the pull request's `mergeable` fields and head, the update runs' commits): no request more per poll, plus one git commit object (under 1 kB) once per new head, only when no run settles it |
| Slack channel: new messages | 20 s | | reply sent, activation | `oldest` cursor |
| Slack channel: edits, reactions, reply counts of what is shown | 60 s | | reaction or reply made here (local, at once) | latest page |
| Summary and kind of a long Slack message (generated on the Mac from the message already in `SlackStore`) | follows the message: rewritten when it is edited | | the message entering the rail or being listed as a long mention on the Overview (one entry for both), an edit, the model becoming ready, its switch | no request: derived, in memory (`IntelligenceStore`) and kept on disk between launches while the message is unread (`SummaryCache`): dropped when the message is read, after the "Quiet" days of Settings (14), or with its switch |
| Slack read cursor, unread, mentions | 20 s | | mark read (local, at once), activation. A cursor moved back in Slack ("Mark unread") wins over what was read here, except in the 10 s after a move made here | `conversations.info` |
| Thread replies (open thread) | 20 s | | reply sent | `conversations.replies` |
| Linear issue rows, blockers | 60 s | | any issue write (local, at once), activation | `updatedAt` delta |
| Linear issue detail (open issue) | 60 s | | write, opened externally | compare `updatedAt` from the delta |
| Team states, members | 15 min | | | |
| Project lead, team, target date | 15 min | | | |
| Slack members · custom emoji | 15 min · 1 h | | | disk copy |
| Catalogues in pickers (channels, Linear projects, repositories, pull requests) | on opening the picker | | | |
| Account identity (Settings) | on opening Settings | | connect, disconnect | |

Cost check for one visible project at these cadences: Slack 6 calls a minute (limit about 50), Linear 60
an hour (limit over 1,000), GitHub 60 to 240 GraphQL points an hour (limit 5,000). Ample room.

---

## 5. Screens and exits

For each door: what can have changed, what the screen shows today, and the targeted update. "Stores"
means the behaviour once sections 3.1 to 3.4 are in place.

### Overview

| Exit or action | May have changed | Today | Target |
| --- | --- | --- | --- |
| Open a project and come back | Whatever was done there | Old rows unless the timer is due | Rows are derived from the stores: already current |
| Click a mention or "N unread" | Read cursor | Removed in place (`slackRead`) | Keep |
| Stay on the page with a long mention listed | Nothing remote: its summary is written on the Mac | The line is the start of the message, then its summary dissolves in, same height | Keep. Reads the entry the project's rail writes (`IntelligenceStore`, keyed by channel and message); no request, no budget of its own: it follows the message (section 4) |
| Click a review request | Review given on GitHub | Stays until the next cycle | Opened externally: refresh `pulls(repo)` on return |
| Open a part of the release line (Prod, Staging, Next prod) on GitHub | A merge, the checks, the release pull request | Read again when Dever is active again (`ReleaseStore.opened`) | Keep |
| Link Linear / edit a project | The project's links | Row unchanged until the next cycle | Load that one project's resources on save |
| Add or import projects | New rows | Skeleton rows until the next cycle | Load the new projects only |
| Refresh, ⌘R | Everything | Whole reload, row by row, 11 MB per repository | Revalidate all, cheap requests, rows update in place |
| Stay on the page | Others' activity | Up to the setting + 1 min | Visible budgets for mentions, reviews, CI |
| Notification click | The alerted state | Opens the project; data as old as the cycle | Refresh that project's alerted resource first |
| Leave the app and return, wake | Anything | Nothing | Activation trigger |

### Project page

| Exit or action | May have changed | Today | Target |
| --- | --- | --- | --- |
| Stay on the page | CI, reviews, new pull requests, messages, issue moves by others | Never updates (F1) | Visible budgets, in place |
| Open an issue and come back | That issue | Whole page reloads behind the content (5 to 7 GitHub requests + reviews) | Nothing to fetch; the store already has the write |
| Start / Take it / Move / Undo | One issue | Optimistic in `IssueStore`; Overview copy stale | Same, and the Overview follows because it is derived |
| Open the card of "CI failed on #N", a check's log | The checks (a new run) | Nothing read before the click; then the failed checks and the end of one log, kept for that run | Dropped when the pull request's checks stop failing; a reading problem says so with "Try again" |
| "Fix CI", "Review", open a pull request, merge on GitHub | That pull request, its checks, its issue | Old until Refresh | Mark `pulls(repo)` and `issues(project)` dirty; refresh on activation |
| Open in Linear | That issue | Old until the page reappears | Mark `issues(project)` dirty |
| Start with / Continue with a coding agent | One issue (the move to its started state, as Start); later its branch and pull request, made in the agent | Not offered | The move is Start's optimistic write; the agent's app shows nothing Dever displays, so nothing is marked dirty: the pull request arrives within the open pull requests' budget and on activation |
| Deploy / redeploy / delete preview | Preview phase | Optimistic phase, 30 s polling | Keep; also poll when a push started the run |
| Open the Slack room, read | Read cursor | Cursor moved after 3 s, Overview follows | Keep; move into `SlackStore` |
| Reply in a thread | Thread, parent's reply count | Whole channel page + cursor + thread refetched | Append the reply locally, refetch the thread only |
| React | One message's reactions | Local toggle, then whole channel page refetched | Local toggle, reconcile that message |
| Open in Slack, act there | Messages, cursor | Old until the page reappears | Mark `channel(id)` dirty |
| Edit the project (sheet) | Links, preview pull request | Page now reloads (6.0); Overview row stale | Load the changed services only |
| Refresh | Everything on the page | Whole reload, Linear in full | Revalidate the page's resources |
| Go to Overview or another project | | Page state discarded; next visit starts from skeletons (F4) | State is in the stores: instant |

### Issue page

| Exit or action | May have changed | Today | Target |
| --- | --- | --- | --- |
| Change status, priority, assignee | The issue | Optimistic, confirmed, rolled back on refusal | Keep |
| Stay on the page | Comments, state by others | Never updates | 60 s: the project delta says whether `updatedAt` moved; refetch the detail only then |
| Open in Linear, comment there, return | Comments, anything | Cached detail if the list's `updatedAt` is unchanged | Dirty on external open, refetch on activation |
| Follow a blocker link | Another issue | Cached for the session when opened without `updatedAt` | Budget applies to every detail |
| Open its pull request | The pull request | Old | Mark `pulls(repo)` dirty |
| Open with a coding agent (Details) | Later, the issue's branch and pull request, made in the agent | Not offered | Nothing is written and nothing marked dirty; the pull request arrives within its budget and on activation |
| Open the card of a failed pull request chip, a check's log | The checks (a new run) | The chip reads `GitHubStore`'s copy with its age; the explanation is read on the click | Dropped when the copy says the checks no longer fail; "No failed check on the latest commit" marks the repository to be read again |
| Back | | Project page reloads everything | Nothing to fetch |

### Slack room and thread

Covered by the project page rows. In addition: an open thread refreshes its replies every 20 s; the room
appends new messages at the bottom without moving the reading position (the "jump to latest" control
already exists for this).

### Sheets (new project, import, editor, pickers)

| Exit or action | May have changed | Today | Target |
| --- | --- | --- | --- |
| Open a picker | Channels, Linear projects, repositories, open pull requests | Loaded on opening | Keep (budget: on opening) |
| Create a channel or a Linear project on save | The catalogue | Created, project saved | Keep; add the created item to the catalogue |
| Save | The project's links | The project page reloads; the Overview reads that project alone, at once, when its channel, Linear project or repositories changed (`OverviewStore.relinked`, `refresh(project:)`) | Done |

### Settings

| Exit or action | May have changed | Today | Target |
| --- | --- | --- | --- |
| Connect or reconnect a tool | Everything from that tool | Project page reloads on the token; Overview waits for the cycle | Revalidate that service's resources everywhere |
| Disconnect | The same | Rows fail on the next cycle | Drop that service's resources at once |
| Repository mode or workspace repository | Which pull requests belong to which project | Whole Overview refresh | Recompute from the stores; fetch only repositories not yet loaded |
| Refresh every | The background cadence | Read at the next tick | Keep |
| System Settings for notifications and back | Permission | Rechecked on activation | Keep |
| Settings › Agents: the code folder, where each tool opens | Nothing remote: which local clone a launch uses | Not offered | The folder is read when the page opens and at each launch; no request |
| System Settings for Apple Intelligence and back (Settings › Intelligence, the invitation in the Slack rail, the Intelligence stage of onboarding) | Whether the Mac's model can be used | Read again on activation and when the system says it changed (`IntelligenceStatus`); no request | Keep |

### Onboarding

Connecting tools and creating the first project follow the Settings and sheet rows. Nothing is cached
before the first project exists.

### App-level

| Event | Today | Target |
| --- | --- | --- |
| Window or app regains focus | Nothing | Revalidate the visible screen (debounced), then the cycle if due |
| Wake from sleep | Next 60 s tick, if the setting has elapsed | The same as activation, at once |
| Network returns | Wait up to a full interval (`lastRefresh` was set by the failed attempt) | Retry at once; failed refreshes do not count as refreshes |
| Token rejected | Rows say "needs reconnecting" | Keep |

---

## 6. Plan

Safest and most felt first. Each phase ships on its own and leaves the app better than before.

### 6.0 Done with this document

- This document, the checklist, the contributor rules (`CLAUDE.md`).
- Project page: saving the editor (a Linear project, a channel, a repository linked or changed) now
  reloads the page instead of leaving empty panels until Refresh.

### Status

| Phase | State | Where |
| --- | --- | --- |
| 1 | **Done** | `Model/LookAgain.swift`, `Views/AgeNotice.swift`, `ProjectDetailView.load / keepCurrent`, `OverviewStore.refresh`, `Support/RequestLog.swift` |
| 2 | **Done** | `GitHubClient.repository / mergedPulls / graphql`, ETags in `GitHubClient.send` |
| 3, step 1: GitHub | **Done** | `Model/ResourceCache.swift` (the shared helper), `Model/GitHubStore.swift`; the Overview (`RepoCache`) and the project page (`derivePulls`, `loadGitHub`) read it |
| 3, step 2: the Overview row derived from the stores | **Done** | `Model/OverviewRow.swift` (pure functions), `OverviewStore.rederive`, `IssueStore.load(maxAge:)` and `facts` |
| 3, step 3: Slack | **Done** | `Model/SlackStore.swift` (messages, cursor, opened threads per channel); `ProjectDetailView` keeps only view state |
| 4 | **Done** | `Model/RefreshCadence.swift` (the budgets and the backoff), `ProjectDetailView.keepCurrent / poll`, `SlackStore.poll`, `GitHubStore.refreshChecks`, `OverviewStore.inFront`, `AppError.rateLimited` |
| 5, 6 | Not started (optional) | |

The "Refresh every" setting is gone. Once the screen in front was read every minute and everything was
read on return, it only set how late an alert could be while Dever is behind another app, against a cost
that phase 2 had divided by about fifty: a question nobody can answer by picking 1, 5, 15 or 30 minutes.
The background cycle now sets itself (`RefreshCadence.background`): every two minutes, longer with many
projects so that a cycle's Slack calls stay under 30 a minute, and three times as long (ten minutes at
least) in Low Power Mode. Where this document says "the setting" for the background cadence, read that.

After step 1 of phase 3 a repository is read once for the Overview and every project page that follows
it (a read within 20 s serves all of them), a project whose issues and repositories are already held
opens without a skeleton for its work panel, an open project page follows the Overview's cycle, and a
link to github.com marks its repository dirty. Unit tests: `swift test` (`Tests/DeverTests`).

After step 2 the Overview counts a project's issues from the list the project page uses (`IssueStore`,
a delta after the first load, no limit at 250) and asks Linear only for the project's lead, team and
target date, a quarter of an hour apart. A row's Linear and GitHub parts are worked out by the same
functions during a cycle and between cycles: moving or taking an issue in Delivery, or a project page
reading its repository again, changes the row at once, without a request (F6 for Linear writes, the 250
limit of F8). Notifications are still sent from the cycle only.

After step 3 a project's conversation is held by channel for the session: coming back to a project shows
its messages, names and read position at once (F4), a reply reads its thread again and updates the
parent's count, a reaction changes its one message, and neither reads the channel again (F8). An opened
thread shows the replies it had while they are read again. Still separate: the Overview's own Slack read
(this week's messages, unread and mentions), which does not go through the store yet.

After phase 4 the open project page reads each kind of data at its own pace while Dever is the active
app: messages that arrived since the newest one held and the read cursor every 20 s (two small requests,
nothing published when nothing changed), the channel's latest page, the issues' delta and the
repositories every minute, the checks of the pull requests whose checks are running every 15 s (one
query of under a kilobyte, measured 0.7 KB for six pull requests), a moving preview every 15 s. The
Overview in front runs its cycle every minute, quietly; behind, every two minutes (below). A tool that fails is asked half as often each time, up to five minutes, and a rate limit
(`Retry-After`) pauses every call to that tool until it lifts.

Measured after phase 2 on the same repository, with the app's own client code
(`DEVER_TRACE_REQUESTS=1`): one repository costs **3 requests, 112 KB, 5.4 s** (open pull requests with
checks and reviews 44 KB, merged 2 × 34 KB, sent together) instead of 7 requests, 11.3 MB and about 16 s,
plus up to 30 `reviews` calls on the project page. A repeated REST read answers 304 with no body.

What phases 1 and 2 changed in the findings: F1 (the project page reads everything again every minute
while it is in front, the preview every 20 s while it deploys), F2 (each pull request carries the rollup
of its own checks; the project's pipeline is the worst of its pull requests'), most of F3 (bytes and
time; the Overview and the project page still fetch separately until phase 3), F5 (activation, wake,
network return, links opened in another app), F7 (the Overview's "updated" is the last refresh that
reached the tools and ticks; a failed cycle retries after 30 s, doubling; a failed refresh keeps the
rows and the panels and says how old they are). Still open: F4 and F6 (phase 3), F8.

One visible consequence of F2: a project whose pull requests fail checks that ran more than a few hours
ago now reads "Pipeline failing", where it read "passing" or "no runs" before.

### Phase 1: refresh when someone looks, and stop lying about age (about 1 to 2 days)

No new architecture; small, separate changes.

- Refresh on `didBecomeActive`, wake and network return (debounced; the visible screen if older than
  30 s, then the cycle if due).
- Project page: a quiet refresh every 60 s while it is visible and the app is active, merging in place.
- `lastRefresh` only on success; a failed cycle retries with backoff; the "updated" label ticks.
- A failed refresh keeps the panel's data and adds a one-line notice instead of replacing it.
- Age on CI, review and preview states, and the stale drawing of section 3.6. (Done as one line under
  the project's title, `AgeNotice`, once GitHub data is older than 150 s or a refresh failed; muting each
  glyph is left to phase 3, when every state knows its own `fetchedAt`.)
- Mark what was opened externally as dirty so activation refreshes it first.
- Publish a project's Overview row per service as it arrives (Slack does not wait for GitHub).
- A request log behind an environment variable (count, bytes, duration per endpoint), so the next phases
  are measured, not estimated.

Risk: low. Cost while GitHub is still expensive: the 60 s project refresh is the heavy one, which is why
phase 2 follows immediately; until then it can be limited to Slack, Linear and the preview.

### Phase 2: GitHub, correct and 200 times lighter (about 2 to 3 days)

- One GraphQL query per repository: open pull requests with check rollup, review decision, requested
  reviewers, head branch, linked numbers; one for recently merged; default-branch rollup.
- Drop the repository-wide runs list and the per-pull-request `reviews` calls.
- `If-None-Match` on the remaining REST calls (preview: pull request, comments, workflow runs).
- Expected on the measured repository: 11.3 MB and 5 to 7 requests in sequence become about 30 KB and
  2 requests; CI state becomes the one GitHub shows. Fixes F2, most of F3.

Risk: medium (new query, the matching code reads different fields). Verified against the REST results on
the same repository before switching.

### Phase 3: shared stores (about 3 to 5 days)

- `GitHubStore` (per repository) and `SlackStore` (per channel, with cursor and threads), on the model of
  `IssueStore`; one small shared helper for budget, `fetchedAt`, shared in-flight requests and
  `invalidate`.
- `ProjectDetailView` reads the stores and keeps only view state. Opening a project seen before is
  instant; coming back from an issue fetches nothing.
- The Overview row becomes derived: its Linear numbers come from `IssueStore` (delta, no 250 limit), its
  GitHub numbers from `GitHubStore`. Writes show everywhere (F6), and the Overview and the project page
  stop fetching the same things twice (F3, F4).
- Reply and reaction update one message; no channel reload.

Risk: the largest refactor, mostly moving code. Done one store at a time (GitHub first, then Slack), each
with its screens switched in the same change.

### Phase 4: adaptive polling (about 2 days)

- A scheduler that knows which resources are visible and applies section 4: 15 s while a check runs or a
  preview deploys, 20 s for the open channel, 60 s for the rest of the visible project, the setting for
  everything else, paused when the app is inactive except for the notification cycle.
- Per-service backoff on errors and `Retry-After`.
- Settings › Refresh every becomes "background projects"; its wording says so.

### Phase 5, optional: instant launch (about 1 to 2 days)

A disk snapshot of the stores, shown with its age at launch until the first refresh lands.

### Phase 6, optional: push

A relay service for GitHub, Linear and Slack webhooks, calling `invalidate(key)` in connected apps.
Needs a backend and a decision that Dever has one.

---

## 7. Checklist for every feature

Every change that shows remote data or changes it answers these in its pull request description (or in
the commit message when there is no pull request). A change that cannot answer one is not ready.

```
Data contract
- Reads:        which resources (store + key), and which are new
- Writes:       which mutations; optimistic value; what happens on refusal
- Invalidates:  which resources each write makes stale, here and on other screens
- Budget:       max age while visible, cadence while in flight (table in section 4)
- Loading:      skeleton on first load only; what shows during a background refresh
- Failure:      what stays on screen, how its age is said
- Exits:        each way out of the screen that can change this data, and what refreshes on return
- Cost:         requests and rough bytes per refresh; per hour at the budget
```

Rules, checkable in review:

1. **Remote data lives in a store, not in a view.** No `@State` holding something fetched from Slack,
   Linear or GitHub, apart from pickers that load on opening.
2. **One copy.** A screen that needs data another screen already loads reads the same store entry. No
   second query for the same thing in a different shape; extend the store instead.
3. **A new resource has a row in the budget table** (section 4) in the same change.
4. **Skeletons only when there is no value.** A refresh never clears, reorders by surprise, or scrolls
   what is on screen. Never a spinner over existing content.
5. **Every write is optimistic, reconciled with the server's answer, restored on refusal, and names what
   it invalidates.** A write that changes what the Overview shows is checked on the Overview.
6. **Every external link to something Dever displays marks that resource dirty.**
7. **A decision state (CI, review, deploy, preview) carries its age** and follows section 3.6. "Updated"
   means the last successful fetch.
8. **A failed refresh keeps the last value** and says it is old; it never replaces data with an error.
9. **No fetch of a whole collection to learn about one item**, and no request in a loop over rows; add a
   field to the list query or a keyed resource.
10. **A poll that finds nothing new must be cheap**: a delta cursor, a conditional request, or a small
    GraphQL query. State the cost.
11. **New screens and new exits get a row in section 5.**
