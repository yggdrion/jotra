# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`docs/PLAN.md` is the source of truth for scope, design, architecture and milestones; read it before starting work. Setup, run and check commands are in `README.md`.

## Git workflow (early phase)

- **No PRs for now.** Commit straight to `main` and push. Session worktree branches get merged into `main` (fast-forward) and pushed; don't open a PR unless asked.
- **Semantic commits:** `type(scope): summary` (`feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`), imperative, lowercase, no trailing period. Commits are authored as **r4b2**, with no AI co-author or attribution trailers.
- **Run the local check before every push:** `python tools/check.py` must end with "All checks passed" (it is also the pre-push hook; never skip it with `--no-verify`).
- **Watch `main`'s CI now and then**, at least after each push: `gh run list --branch main --limit 5`, and `gh run view <id> --log-failed` when one is red. A red `main` gets fixed before new work.
- **Milestone releases:** when a milestone from `docs/PLAN.md` §8 is done (its checks green in CI on `main`, short playtest done), bump the minor version and push the tag. The tag runs CI, which publishes a GitHub Release with the Linux and Windows zips:

      git tag v0.<n>.0 && git push origin v0.<n>.0

  M0 → `v0.1.0`, M1 → `v0.2.0`, and so on; patch tags (`v0.<n>.1`) for fixes between milestones.
- Renovate (`.github/renovate.json`) opens dependency PRs and automerges non-major updates once CI passes; those are the exception to "no PRs".

## Code conventions

- The server sim (`game/scripts/sim/`) is plain `RefCounted`, no scene tree; it only advances through `tick(delta)`. Tests build it directly.
- Client and server share one `Net` node at `/root/Main/Net`; all RPCs live there. Bump `Net.PROTOCOL_VERSION` on any RPC or payload change.
- Typed GDScript; tests in `game/tests/*_test.gd`. Commit the `*.gd.uid` files Godot generates next to scripts.
- Tools are one stdlib-only Python script each in `tools/`, run as `python tools/<name>.py` on Windows and Linux.
