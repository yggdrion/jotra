# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`docs/PLAN.md` is the source of truth for scope, design, architecture and milestones; read it before starting work. Setup, run and check commands are in `README.md`.

## Where we are

Keep this section current: update it in the same push that finishes a milestone or changes what's next, so a new session can pick up from here.

- **Done:** M0 skeleton + solo (`v0.1.0`), M0a F3 debug overlay and M0b fullscreen + any resolution (`v0.2.0`), M1 dedicated mode, local (`v0.3.0`), M2 world + persistence (`v0.4.0`). Status per milestone: `docs/PLAN.md` §8.
- **Screen rules** (`docs/PLAN.md` §6): the visible world area differs per player (aspect `expand`), so UI uses anchors and gameplay never depends on what is on someone's screen.
- **Dedicated server:** a local Docker image via `deploy/docker-compose.yml` (built from the Linux export, no registry); `--metrics-port` serves Prometheus metrics, dashboard in `deploy/grafana/jotra.json`. The world pauses while nobody is online. vServer, GHCR and the `infra` wiring are the last milestone, M10.
- **World:** `world/world_gen.gd` generates chunks from the seed on both sides; `SimWorld` loads the chunks around players and streams each one's delta (removed props, E in game); `world/world_store.gd` saves meta, chunk deltas and players (by name) as JSON in `--world=DIR`.
- **Combat (M3, built, waiting for its playtest):** numbers and the scaling formula in `sim/combat.gd`, enemy AI in `sim/sim_enemy.gd`, attacks/dash/death in `SimWorld`. Clients report what their swing hit and the server checks it with slack; enemy hits are server-side, dodged by dash i-frames. After the playtest: mark M3 Done in `docs/PLAN.md` §8, tag `v0.5.0`, then M4 loot + inventory (which also moves the combat constants into `.tres` data).
- **Known gotchas:** `OS.is_process_running` only sees processes the same Godot instance spawned, so a solo server can't watch its parent; it exits when its player disconnects instead. Run the game through `python tools/godot.py` (it imports first), or new `class_name` scripts fail to resolve.

## Git workflow (early phase)

- **No PRs for now.** Commit straight to `main` and push. Session worktree branches get merged into `main` (fast-forward) and pushed; don't open a PR unless asked.
- **Semantic commits:** `type(scope): summary` (`feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`), imperative, lowercase, no trailing period. Commits are authored as **r4b2**, with no AI co-author or attribution trailers.
- **Run the local check before every push:** `python tools/check.py` must end with "All checks passed" (it is also the pre-push hook; never skip it with `--no-verify`).
- **Watch `main`'s CI now and then**, at least after each push: `gh run list --branch main --limit 5`, and `gh run view <id> --log-failed` when one is red. A red `main` gets fixed before new work.
- **Milestones are tracked in `docs/PLAN.md` §8.** When work finishes a milestone, set its Status to Done (and the next one to Next) in the same push. Work that doesn't fit a planned milestone gets a lettered one inserted after the current one (M0a, M0b, …) with its own "done when", rather than renumbering.
- **Milestone releases:** when a milestone is done (its checks green in CI on `main`, short playtest done), bump the minor version over the latest tag, push the tag and write it into the Release column. The tag runs CI, which publishes a GitHub Release with the Linux and Windows zips:

      git tag -a v0.<n>.0 -m "M<x>: <name>" && git push origin v0.<n>.0

  Lettered milestones count too, so version numbers don't map 1:1 to milestone numbers. Patch tags (`v0.<n>.1`) for fixes between milestones.
- Renovate (`.github/renovate.json`) opens dependency PRs and automerges non-major updates once CI passes; those are the exception to "no PRs".

## Code conventions

- The server sim (`game/scripts/sim/`) is plain `RefCounted`, no scene tree; it only advances through `tick(delta)`. Tests build it directly.
- Client and server share one `Net` node at `/root/Main/Net`; all RPCs live there. Bump `Net.PROTOCOL_VERSION` on any RPC or payload change.
- Typed GDScript; tests in `game/tests/*_test.gd`. Commit the `*.gd.uid` files Godot generates next to scripts.
- Tools are one stdlib-only Python script each in `tools/`, run as `python tools/<name>.py` on Windows and Linux.
