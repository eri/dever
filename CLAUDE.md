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
- Button roles come from `Sources/Dever/Views/Buttons.swift`; motion from `Sources/Dever/Views/Motion.swift`.

## Repository

- Everything in the repository is written in English.
- Commit messages carry no tool attribution and no `Co-Authored-By` trailer.
- Names fetched at runtime (workspaces, channels, repositories, people) are data: never in code, fixtures or docs.
- Build with `./scripts/build-app.sh`; screenshots without the network: see "Screenshots for development" in the README.
