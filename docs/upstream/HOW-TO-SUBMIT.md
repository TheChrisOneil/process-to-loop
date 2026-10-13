# How to land a change in Gas City

Written 2026-10-13, from `CONTRIBUTING.md` and `ROADMAP.md` at that date. **Re-read theirs before
starting** — this is a summary of somebody else's process and will go stale.

---

## Before writing any code

**Open an issue first.** Their roadmap says a change should be *"backed by an issue when the change
warrants one"*, and a new priority area needs an issue tagging the roadmap owner. A patch arriving
without one is a patch arriving into a conversation that has not happened.

Read, in this order:

- `docs/index.mdx`
- `engdocs/contributors/index.md`
- `engdocs/contributors/codebase-map.md`
- `engdocs/architecture/index.md`
- `TESTING.md`
- `ROADMAP.md` — what is planned, and how to propose work

Check `ROADMAP.md` for the current priority areas. A change outside them is not refused, but it
competes with reliability work on a list of several hundred open issues.

---

## Setting up

```bash
gh repo fork gastownhall/gascity --clone
cd gascity
```

Then the prerequisites from `docs/getting-started/installation.md`, **plus Bazelisk** — Bazel is
how it builds and CI gates on `bazel test`.

```bash
brew install bazelisk          # not installed on this machine as of 2026-10-13
make setup                     # tooling and git hooks
```

Opt in to their read-only build cache, which turns results CI already computed into cache hits:

```bash
# .bazelrc.local  (gitignored)
build --config=fork-cache
```

Misses build on your machine; nothing you build is uploaded. Without this a first
`bazel test //...` on a repo with ~78 MB of Go is a long wait.

---

## What to run, by what you touched

| what changed | run |
|---|---|
| anything | `make check` — `bazel test //...` plus the shell guards |
| `gc` commands end to end | `make test-acceptance` |
| runtime, controller, or workflow behaviour | `make test-integration` |
| docs, navigation, links | `make check-docs` |
| imports, packages, files added or removed | `make bazel-sync`, then commit the regenerated BUILD files |

Narrow while iterating:

```bash
bazel test //internal/config:config_test
```

`go test ./internal/config -run TestX` is a fine inner loop and **is not what CI enforces** — it
runs none of the nogo, format, generated-artifact or policy targets.

### Without Bazel

Every `make` target has a plain-Go twin for offline work: `make check-go`, `make test-go`,
`make test-acceptance-go`, `make test-integration-go`, `make check-docs-go`.

`check-go` is `fmt-check lint-golangci vet-go` plus their four policy guards plus `test-go`. It
catches most of what a reviewer would and is explicitly *not* what CI runs. Useful for a first
pass; not sufficient for saying a change is ready.

---

## The hooks will change files under you

`make setup` installs a pre-commit hook that:

- auto-formats staged Go files
- regenerates `internal/api/openapi.json` and `docs/reference/schema/openapi.json` from the live
  supervisor **whenever any Go file is staged**, and stages both
- runs nogo over staged packages, and `make check-docs` for docs changes

So a Go change produces spec churn you did not write. That is intended — it keeps the committed
spec from drifting — but do not be surprised by it, and do not revert it.

**If a spec change is staged and npm is missing, the hook fails closed.** It regenerates the typed
API client and the dashboard bundle, and a stale client would otherwise ship silently.

The pre-push hook runs `bazel test //...` on Go changes, and says so loudly if it has to fall back
to plain `go test`.

---

## Touching the dashboard or the API schema

`internal/api/dashboardspa/web/` is a TypeScript SPA against the supervisor's OpenAPI endpoints.
Changing `internal/api/openapi.json` regenerates the typed client and rebuilds the embedded bundle.

```bash
make dashboard-check        # typecheck, Vitest, build, and the drift checks
make dashboard-dev          # Vite HMR while iterating
make dashboard-lock         # after changing npm dependencies
```

Smoke the built app before pushing:

```bash
cd internal/api/dashboardspa/web && npm run preview -- --host 127.0.0.1 --port <port>
```

---

## Checklist before opening the PR

- [ ] an issue exists, and the approach was agreed there
- [ ] `make check` passes — not `check-go`
- [ ] the tier for what you touched passes (acceptance / integration / docs)
- [ ] `make bazel-sync` run and regenerated BUILD files committed, if files moved
- [ ] generated specs and dashboard artifacts committed, not reverted
- [ ] the PR explains the change, as their roadmap asks: *"lands a change with a well-explained
      pull request, backed by an issue when the change warrants one"*

---

## Our standing rule

Nothing goes upstream on a hunch — see `docs/upstream-parking-lot.md`. A proposal leaves that file
when it has run against more than one city, over more than a few weeks, and its numbers have
stopped moving.

**And ranked honestly.** We filed one issue and withdrew it the same day because it was a
diagnostic nicety competing with their reliability work. Before opening anything, answer: *is
somebody blocked by this?* If not, it belongs in the parking lot until something is.
