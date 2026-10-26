# Jotra — Project Plan

Norse dark-fantasy survival game with a persistent procedural world, top-down 3/4 pixel art, fast Hades-style combat, and Risk of Rain-style roguelite dungeons. Co-op for 1–10 players. Every game runs on a server process, even solo.

This file is the single source of truth for scope, design and architecture. Built from scratch in a new repo; lessons from the Two Wards PoC (yggdrion/card-defense) are listed at the end.

---

## 1. Vision

- **Valheim** gives the world: persistent, procedural, biomes, gathering, crafting, building, hard survival, bosses unlock the next biome.
- **Hades** gives the feel: top-down camera, fast dash-based combat, every hit has weight.
- **Risk of Rain** gives the dungeons: random layouts, stacking item buffs with synergies, scaling difficulty, every run different.
- **Name and lore hook:** *Jotra*, an invented word from Old Norse *jötunn* (giant). In Norse myth the world was built from a slain giant (Ymir): bones became mountains, blood the sea, skull the sky. Each server world can be the remains of a different slain giant, with biomes as parts of the corpse (bone mountains, blood marshes, rot forests). This gives the procedural world a reason to exist; details are open (question 8).
- **Visual reference:** Graveyard Keeper, Stardew Valley (2D pixel art, 3/4 top-down view).
- **Closest existing game overall:** V Rising. Also study Core Keeper, Necesse, Tribes of Midgard, Hyper Light Drifter, Children of Morta, Enter the Gungeon.

## 2. Design decisions (set)

| Topic | Decision |
|---|---|
| World | One persistent procedural world per server, generated from a seed, divided into biomes. Lives forever (no wipes, no seasons) |
| Hub | None. The world itself is the game |
| View / art | 2D pixel art, top-down 3/4 view. Characters animated in 4 directions; attacks aim freely at the mouse |
| Name | Jotra |
| Setting | Norse dark fantasy |
| Players | 1–10 co-op, PvE only |
| Progression | Classless. Power comes from equipment crafted from biome materials |
| Biome gating | Each biome has a boss; killing it unlocks materials/recipes for the next, harder biome |
| Survival | Hard, Valheim-like: health, stamina, hunger, day/night. Punishing on purpose |
| Combat | Hades-style: dash with i-frames, light/heavy attacks, few abilities with weight. Abilities come from gear, not classes |
| Dungeons | Entrances placed in the world, dungeon types per biome. Each entry generates a new layout from handmade room chunks |
| Dungeon buffs | Risk of Rain-style stacking passive items with rarities and synergies. They exist only inside the dungeon |
| Dungeon rewards | Materials, gear with random affixes, and a guaranteed end chest/boss drop with a raised chance for rare loot |
| Dungeon death | You keep everything you brought in; everything found during that run is lost. Exit alive: keep everything |
| Difficulty | No selectable tiers. The game scales itself (see 5.6) |
| Building | Simple grid placement for now; may grow later |
| Cheating | Not a concern (co-op with friends). Netcode optimizes for feel, not security |
| Assets | AI-generated. Placeholders first; free assets as interim |

## 3. Open questions

1. Survival details: which stats beyond health/stamina/hunger (temperature, rest, weather)? How punishing is death in the overworld (Valheim-style corpse run?)
2. Combat details: weapon types, ability slots, how gear grants abilities
3. Buff list: first ~15 dungeon buffs and their synergies
4. Relics: can any dungeon buff leave as a weakened permanent "relic" with limited slots?
5. Building depth beyond simple grid placement
6. Art pipeline: which AI tool (PixelLab was used in Two Wards), palette (Endesga 32 again?), and the fallback of rendering 3D models to pixel sprites (Dead Cells pipeline) if animation consistency is a problem
7. Persistence backend: start with files, switch to SQLite (godot-sqlite GDExtension) if needed — see 4.7
8. Lore: how far to take the "world built from a slain giant" idea (biomes as body parts, why players are there, what the bosses are). Name *Jotra* is chosen; a web search found no existing game with that name, but a formal check (Steam, itch.io, domains, EU trademark register) is still to do. Note: *Jotun* (2015, Thunder Lotus) is an existing Norse game with a similar-sounding name
9. Who does what: code, art, design, infra

---

## 4. Architecture

### 4.1 One executable, server always

- One Godot project, one executable. Started with `--server` (plus `--headless`) it runs as the game server; otherwise it is the client.
- **Every session goes through a server process.** Solo is a server with one player; there are no special local code paths.
- The server owns the truth. The client renders and sends input.
- Client and server share code: item/recipe/enemy definitions, collision shapes, combat rules, world generation.

### 4.2 Three modes

```
SOLO          client ──ENet localhost──▶ server process (spawned locally)

PLAYER HOST   host client ─┐                    ┌─ friend (WebRTC via lobby, NAT punch / TURN)
                           ├─▶ server process ◀─┤
              (spawned on host's machine)       └─ friend ...
                    └── server registers a room with the lobby → room code

DEDICATED     server process on vServer ◀──ENet UDP, public port── everyone
```

- **Solo:** client spawns the server with `OS.create_process(OS.get_executable_path(), ["--headless", "--", "--server", "--solo", "--port=<free port>"])` (plus `--path <project>` when run from source; `--world=<name>` from M2) and connects via ENet to localhost.
- **Player host:** client spawns the server the same way with `--mode=host`. **The server process itself connects to the lobby**, opens a room, gets the code and accepts WebRTC peers. The server reports the room code to the host client (e.g. via a server→client RPC after connect).
  - A Godot `MultiplayerAPI` takes one peer type, so in this mode **everyone uses WebRTC, including the host's own client over loopback**. The host joins its own room by code like everyone else. (Alternative rejected: a custom `MultiplayerPeerExtension` merging ENet and WebRTC.)
- **Dedicated:** the same executable runs headless in a Docker container on the vServer, `--mode=dedicated`, public UDP port, plain ENet. No lobby needed (optional later: register for a server list).
- A `Transport` layer creates the `MultiplayerPeer` (ENet server/client, or WebRTC via lobby). Gameplay code only sees Godot's multiplayer signals and RPCs.

### 4.3 Lifecycle rules (all modes)

- **Pause when empty:** when the last player disconnects, the world tick stops and the world is saved (saving from M2). First join resumes it.
- **Local server dies with the client:** in solo and player host, the server saves and exits when the host's connection drops, or when the host never joins within 30 s. (Polling the parent's pid does not work: `OS.is_process_running` only sees processes the same Godot instance spawned.)
- **Host leaves in player host:** the session ends for everyone. No host migration; the dedicated mode covers always-on play.
- **One world format everywhere:** worlds live on the host's machine (solo / player host) or on the vServer (dedicated) in the same format, so a world can move between modes unchanged.
- **Reconnect:** a player can leave and rejoin a running world at any time; their character, inventory and position are restored from the save.

### 4.4 Netcode model (state replication, feel first)

Lockstep (as in Two Wards) does not fit: too many entities, mid-game joins, a persistent world. Use server-authoritative state replication with client authority where it improves feel:

| What | Who decides |
|---|---|
| Own character movement | Client moves it immediately; sends position + facing to the server ~20 Hz. Server accepts it with only a basic sanity check (max speed, teleport bugs) |
| Own attacks | Client plays them instantly and reports what it hit; server applies damage |
| Enemy attacks on players | Server decides; the dash i-frame window gets a small latency tolerance |
| Enemies, AI, loot, inventories, crafting, building, world changes, survival stats | Server |
| Remote players and all entities on clients | Rendered with ~100 ms interpolation from server snapshots |

- Server sim tick: 30 Hz. Snapshots to clients: 20 Hz. Reliable RPCs for events (pickups, inventory, building, chat); unreliable for snapshots and positions.
- **Interest management:** each client only receives entities and chunks within a radius of its player. Needed for 10 players and bandwidth.
- Own protocol over RPCs (one `Net` node at the same path on both sides) rather than `MultiplayerSynchronizer`, so interest management and snapshot format stay under our control.
- Protocol version checked on hello; mismatch → clear error.

### 4.5 Pure sim core

The server's simulation (world, entities, combat, loot, survival) is plain objects without the scene tree, so tests and bots can drive it directly. The client's node layer renders it. (Two Wards retro decision.)

### 4.6 World and chunks

- World generated from a seed: noise → biome map → tiles → props (trees, rocks, ore) → dungeon entrance placement.
- Fixed-size chunks: 32×32 tiles of 16 px (512 px). Server loads chunks around players, unloads idle ones. Each player sees the chunks within 2 of its own (5×5, at least 1024 px each way, wider than half the widest view in §6); generation runs on both sides from the seed, so the server only streams each chunk's delta.
- Persistence stores **deltas against the seed** (felled trees, mined rocks, buildings, dropped items), not whole chunks.
- Godot `TileMapLayer` with y-sort on the client once there is tile art (M2 draws flat placeholder rects). Objects in front of the player (trees, roofs) fade out.
- Players are identified by name (sent in hello; a random per-install token by default), so a reconnect finds its save.

### 4.7 Persistence

- Behind a `WorldStore` interface: world meta (seed, version, time of day, boss kills), chunk deltas, players (stats, inventory, equipment, position), buildings.
- First implementation (M2, `world/world_store.gd`): plain files per world (`world.json` + `chunks/<x>_<y>.json` per changed chunk + `players/<name>.json`), no GDExtension dependency. Switch to SQLite if it becomes a problem.
- Save periodically (e.g. every 60 s), on last disconnect, and on shutdown. Atomic writes (write temp file, rename).
- Save format has a version field with migrations from day one.

### 4.8 Dungeon instances

- Entering a dungeon moves the party into an instance. First version: a separate area inside the same server process (far-off coordinates or a separate sim space). Later option: its own process/container.
- On entry the server snapshots each player's inventory; death restores that snapshot, exit keeps everything.
- Buffs live on the player only while in the instance; removed on exit or death.

### 4.9 Lobby and NAT traversal (player host)

Written from scratch, same proven design as the Two Wards lobby:

- TypeScript on Bun, no runtime deps, Docker container. WebSocket `/ws`, `/healthz`, Prometheus `/metrics`.
- Room codes (4 letters, no ambiguous characters). Relays WebRTC offer/answer/ICE candidates verbatim; never sees gameplay.
- Mints time-limited coturn credentials (REST scheme, shared secret only on the server host).
- Differences from Two Wards: up to 9 guests per room; **rooms stay open while the game server runs** (heartbeat from the server, dropped when it stops) so friends can join any time; star topology (each guest connects only to the server, peer id 1; the server creates one offer per guest).
- coturn as STUN + TURN relay fallback; `total-quota` sized for 10-player rooms.
- WebRTC in Godot via the pinned webrtc-native GDExtension, installed by a tool script and shipped in every export.
- M6 built: `lobby/` (rooms in `src/rooms.ts`, lobby protocol 1), `net/lobby_client.gd` for both sides, `--server --lobby=URL` in `GameServer`. The host's client spawns the server on its solo world with `--owner=<name> --room-file=<path>`, reads the code from the file and joins by code. The server pings the lobby every 20 s and opens a new room if it loses the lobby (players already in stay). The start menu (`client/start_menu.gd`) offers solo, host and join; a failed or ended game returns to it with the reason. Deploy: `deploy/lobby/` (lobby + coturn on 3478 on the gvm host, `jotra.r4b2.de`, replacing Two Wards), done in M9a; until then the built-in lobby URL doesn't answer, so play through a local lobby with `--lobby=URL`.

### 4.10 Observability

- The server exposes Prometheus metrics: tick time, players, entities, loaded chunks, bandwidth per client, save duration.
- The lobby exposes room/connection counters.
- Shipped to VictoriaMetrics with vector, dashboards in Grafana (same stack as Two Wards).

---

## 5. Game systems (server)

### 5.1 Entities

Players, enemies, dropped items, resource nodes, buildings, projectiles. Stable entity IDs, spawned/despawned by the server, replicated by interest.

### 5.2 Combat

- Hitboxes/hurtboxes on the 2D plane. Light attack, heavy attack, dash with i-frames, stamina cost on attack and dash.
- Damage = weapon damage × modifiers − armor. Damage numbers, hit flash, knockback.
- Death and respawn (overworld respawn rules: open question 1).
- Enemy AI v1: idle → notice → chase → attack → leash back.

### 5.3 Loot and inventory

- Drop tables with rarity tiers. Items on the ground, pickup, grid inventory, equipment slots, stacking.
- Gear with random affixes (dungeon drops). Crafting from materials at stations.
- M4 built: all game data in `game/data/` (`tuning.tres`, `items/`, `recipes/`, `enemies/`; an item's or recipe's id is its file name), loaded by `content/content.gd`. Drop tables roll each entry on its own (`sim/loot.gd`); drops lie on the ground for 5 min and are picked up by walking over them (server side, not saved yet). 24-slot inventory plus a weapon and an armor slot (`sim/inventory.gd`); the weapon sets the light/heavy attacks, armor takes a flat amount off each hit and adds max health. Crafting by hand or at the one workbench at the spawn (`sim/crafting.gd`; player-built stations come with M8). Random affixes wait for dungeons (M7).

### 5.4 Survival

- Health, stamina (regenerates, spent on dash/attacks), hunger (drains over time, eating restores; penalties at zero).
- Day/night cycle; night is more dangerous (more/stronger spawns).

### 5.5 Building

- Grid placement of a few pieces (wall, floor, door, workbench, chest, fire). Place/remove, persisted, replicated.

### 5.6 Self-scaling

One formula in one place:

- Enemy health, damage and spawn count scale with the number of players near the encounter.
- Overworld: base strength by biome tier.
- Dungeons: additionally scale with depth and time spent inside (Risk of Rain timer).

### 5.7 Dungeon runs

- Layout generated from handmade room chunks per dungeon type. Enemy mix per biome.
- Buffs drop from enemies/chests inside, stack, have rarities and synergies.
- Guaranteed end chest / boss with raised rare-loot chance.
- Inventory snapshot rule (4.8).

---

## 6. Art and assets

- 2D pixel art, top-down 3/4 view, 4-direction animations, y-sorting, fade-out for occluding objects. Godot 2D lights for night and fire.
- **Screen:** base resolution 640×360. The game draws at the window's real size (stretch mode `disabled`) and zooms all 2D by the largest whole number at which 640×360 still fits (`content_scale_factor`, set on every resize in `boot/main.gd`): 3× at 1080p, 4× at 1440p, 1× below 1280×720. Every window size and aspect is filled edge to edge and the rest of the screen shows more world, so the visible area varies per player: 640×360 at 16:9, 860×360 at 21:9 (3440×1440), wider still on 32:9. Godot's integer stretch modes were tried and dropped: they letterbox the remainder (1264×680 showed a 668×360 picture) and got resampled wrongly after leaving fullscreen. Sprites can sit between art pixels (at screen resolution), which reads as smooth movement. Consequences:
  - Interest management (4.4, M2) must cover the widest view, plus a margin, not just 640×360.
  - UI is anchored to screen edges/center (Control anchors), never placed at fixed 640×360 positions.
  - Spawns, enemy aggro and "off-screen" logic use world distances, never "is it on my screen".
- **Placeholders first:** colored shapes/capsules for players and enemies, spheres for loot, flat colored tiles per biome.
- **Free interim assets** (check each license): Kenney (CC0), Quaternius (CC0), KayKit (CC0), OpenGameArt, itch.io free packs.
- AI-generated final art; pipeline decided later (open question 6). Consistent style guide and palette before mass generation.

---

## 7. Tech stack

| Area | Choice |
|---|---|
| Engine | Godot 4.7.2 (pinned, checksums verified), GDScript, typed |
| Networking | Godot high-level multiplayer; ENet (solo, dedicated, tests); WebRTC via webrtc-native GDExtension (player host) |
| Lobby | TypeScript on Bun, `bun test` |
| NAT traversal | coturn (STUN + TURN) |
| Persistence | `WorldStore` interface, file-based first |
| Tests | gdUnit4 for unit tests; headless multi-process network tests with bot clients |
| Tooling | Python, one cross-platform script per tool (no `.sh`/`.ps1` twins) |
| CI | GitHub Actions (hosted): lint, unit tests, headless network test, lobby tests, Linux + Windows exports |
| Deploy | Docker Compose on the vServer: dedicated game server, lobby, coturn, vector; TLS via the existing Caddy |
| Monitoring | Prometheus metrics → vector → VictoriaMetrics → Grafana |

### Repo layout

```
game/        Godot project (client + server in one)
  scripts/
    boot/    command-line parsing, mode selection, server spawning
    net/     transport, lobby client, protocol, snapshots, interest
    sim/     pure sim core: world, entities, combat, loot, survival, dungeons
    world/   generation, chunks, WorldStore
    client/  rendering, input, camera, interpolation, UI
  tests/     gdUnit4 suites
lobby/       Bun lobby/signaling server + tests + Dockerfile
deploy/      docker-compose (server, lobby, coturn, vector), configs, Grafana dashboard
tools/       Python: install Godot/addons, dev launcher, tests, export, net test
docs/        PLAN.md (this), style guide, decisions
```

---

## 8. Milestones

Each milestone ends with its checks green in CI and a short playtest, then a release tag: every finished milestone bumps the minor version (see `CLAUDE.md`). Work that comes up between two planned milestones gets a lettered milestone (M0a, M0b, …) instead of renumbering the rest. Keep the Status and Release columns current.

| # | Milestone | Done when | Status | Release |
|---|---|---|---|---|
| M0 | **Skeleton + solo** | Tooling installs pinned Godot; client spawns a local headless server, connects via ENet localhost; capsule players move with client-authoritative movement and interpolation; server exits when the client closes; `tools/dev.py` starts server + N clients; headless net test (server + 2 bots) passes in CI | Done | v0.1.0 |
| M0a | **Debug overlay** | F3 overlay in every build: fps, build commit, server address, player id and count, ping, snapshot rate, position. Server polls the network well above its 30 Hz tick, so localhost ping stays ~10 ms | Done | v0.2.0 |
| M0b | **Fullscreen + any resolution** | Starts borderless fullscreen, F11 / Alt+Enter toggles a window; any window size or aspect works with crisp integer pixel scaling, wider/taller screens see more world instead of black bars (see 6) | Done | v0.2.0 |
| M1 | **Dedicated mode (local)** | Same server as a locally built Docker image via compose; clients connect by address; pause when empty; protocol version check; Prometheus metrics endpoint and a Grafana dashboard JSON (vServer deploy is M10) | Done | v0.3.0 |
| M2 | **World + persistence** | Seeded chunk generation with placeholder biomes; chunk streaming with interest management; deltas, players and world meta survive a server restart | Done | v0.4.0 |
| M3 | **Combat** | Enemies spawn and use simple AI; light/heavy/dash with stamina; damage, death, respawn; self-scaling by nearby player count | Done | v0.5.0 |
| M4 | **Loot + inventory** | Drop tables, pickup, inventory, equipment changes stats, crafting at a station | Done | v0.6.0 |
| M4a | **Loot + inventory UX** | A new player finds out unaided how to gather, loot, equip and craft: on-screen prompts near trees, rocks and the labeled workbench; drops pulled in when walked near, an "inventory full" notice; drag-and-drop inventory with an item info panel, equipped stats and a controls line; recipes show have/need per input and why one can't be crafted | Done | v0.7.0 |
| M5 | **Survival** | Hunger, eating, day/night with stronger nights; penalties at zero | Done | v0.8.0 |
| M6 | **Player host** | Bun lobby + coturn as a deployable stack; server opens a room; host and friends join by code via WebRTC through a lobby (local or LAN for now); rooms stay open while the server runs | Done | v0.9.0 |
| M7 | **Dungeon v1** | Entrance in the world; generated instance; ~15 buffs; inventory snapshot rule; end chest; time/depth scaling | Next | |
| M8 | **Building v1** | Grid placement of a few pieces, persisted and replicated | | |
| M9 | **10-player test** | 10 headless bot clients for 30 min on the dedicated server: tick time and bandwidth within budget, no errors | | |
| M9a | **Lobby deploy** | Lobby + coturn (`deploy/lobby/`) run on the gvm host at `jotra.r4b2.de`, replacing the retired Two Wards stack; "Host a game" works with the built-in lobby URL; host and friends join by code from different networks, one of them through the TURN relay. Needs SSH access to r4b2.de from the dev machine | | |
| M10 | **vServer deploy** | CI builds the server image and pushes it to GHCR; it runs on the vServer, friends connect over the internet; vector scrapes its metrics and the dashboard is in the infra Grafana (TLS/metrics stack lives in the separate `infra` repo) | | |

Dedicated (M1) comes before player host (M6) because it is almost free once solo works. It runs locally first; putting it on the vServer waits until the end (M10).

**First prototype scope (after M9):** one biome, one dungeon type, ~15 buffs, one boss, basic building, all placeholders, 1–10 player co-op in all three modes.

---

## 9. Testing

| Layer | Tool | Covers |
|---|---|---|
| Unit | gdUnit4 | Sim core: combat math, loot tables, scaling formula, inventory, survival ticks, world gen determinism (same seed → same chunks), save/load round trip and migrations |
| Network | Headless Godot: 1 server + N bot clients (ENet, localhost) | Join/leave, replication, pause on empty, reconnect restores state, dungeon snapshot rule |
| Balance | `tools/balance_sim.py`: SurvivalBots of three skill levels play the sim headless for in-game days, solo and in groups | Deaths, day/night damage, hunger, time spent per activity, gear times against the difficulty targets in `.claude/skills/balance-sim/SKILL.md` |
| Load | Bot clients against the dedicated server | Tick time, bandwidth, entity counts at 10 players |
| Lobby | `bun test` | Rooms, multi-guest signaling, heartbeat expiry, TURN credentials |
| Manual | Real machines on different networks | WebRTC NAT traversal and TURN fallback, feel |

All checks run locally with one Python command (also as a pre-push hook); CI is the safety net.

---

## 10. Conventions

- Git commits authored as GitHub account **r4b2**, with no AI co-author or attribution trailers.
- Typed GDScript, small focused scripts, data-driven content (`.tres` resources for items, enemies, buffs, recipes).
- Every gameplay number lives in data, not code.

## 11. Lessons carried over from Two Wards

- Pipeline worked: pinned Godot + addons with checksums, headless tests in CI, local check script before push, CI exports for every playtest.
- Data-driven content held up; keep effects/items as resources with a scripted escape hatch.
- Split a pure sim core from the scene tree from the start.
- One cross-platform Python script per tool instead of shell/PowerShell twins.
- Godot exposes no WebRTC stats; a debug overlay (F3) with ping, transport and ICE candidate types helped debugging NAT issues.
- Lobby stays tiny and stateless-ish; game protocol is versioned separately from the lobby protocol, so game-only changes need no lobby redeploy.
