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
| Overworld death | A corpse run: the inventory (not what is worn) stays in a grave where you died, which only you can loot; you respawn at your bed, or the spawn |
| Difficulty | No selectable tiers. The game scales itself (see 5.6) |
| Building | Simple grid placement for now; may grow later |
| Cheating | Not a concern (co-op with friends). Netcode optimizes for feel, not security |
| Assets | AI-generated. Placeholders first; free assets as interim |

## 3. Open questions

1. Survival details: which stats beyond health/stamina/hunger (temperature, rest, weather)? ~~How punishing is death in the overworld~~ Settled 2026-10-27: a corpse run (M18)
2. ~~Combat details: weapon types, ability slots, how gear grants abilities~~ Settled in M17: a worn rune (a third equipment slot, `ItemDef.Slot.RUNE`) grants one ability on Q, see 5.2. Weapon types beyond sword/club/bow are still open
3. Buff list: the first 15 buffs and 4 synergies are in `game/data/buffs/` and `game/data/synergies/` (M7); which ones are fun, and synergies beyond simple stat bonuses, are open
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
- M7 so far (`sim/dungeon.gd`): each run lies in a slot of its own far below the overworld (y 200 000, slots 20 000 px apart), so no run sees another or the world's chunks. E at the barrow by the spawn (`Tuning.dungeon_entrance`) enters the run opened in the last `dungeon_join_window` seconds or a new one; rooms are rects whose union is walkable, kept by `Dungeon.clamp_to` on both sides. Dying inside, leaving the game inside and every save made inside put the player back at the entrance with the snapshot; the exit keeps everything. The last one out closes the run with its enemies and drops. The layout chains handmade rooms (`content/room_def.gd`, one file each in `game/data/rooms/`: a size and enemy spawn points) eastward: a start room, `dungeon_rooms_min`–`dungeon_rooms_max` middle rooms and an end room with the exit, joined by corridors at a height both rooms share. A room's enemies spawn when the first living player walks in, scaled by `Combat.dungeon_scaled` (depth in rooms and minutes since the run opened) on top of `Combat.scaled`. Buffs (`sim/buffs.gd`, data in `game/data/buffs/` and `game/data/synergies/`): 15 buffs in three rarities, each raising one stat per stack (damage, heavy damage, swing speed, crits, max health, armor, stamina regen, walk speed, dash i-frames, lifesteal, bleed, heal or stamina per kill, dash damage, thorns), and 4 synergy pairs that add a bonus while both are held. Enemies killed in a run drop a buff orb at `buff_chance`, rolled by `buff_rarity_weights` and rarer the deeper the run (`buff_depth_bonus`); walking over it adds a stack unless at its max. The client gets its buffs by RPC, lists them in the HUD and predicts walk speed and swing cooldowns with the same `Buffs`. Rooms scale with the players near them through `Combat.dungeon_scaled` alone (`room_count`, `room_health`), as a group fights a room together; clearing every woken room heals those inside by `room_clear_heal`, the only healing in a run besides buffs. The end chest stands in the middle of the end room, shut while an enemy is within `chest_lock_radius`; every player opens it once (E, the same `interact` as the entrance and exit) for a roll of `chest_drops`, heavy on amber and with a chance at bone gear. Balance: `python tools/balance_sim.py --dungeon` (`game/tools/delve_bot.gd`), targets in the balance-sim skill.

### 4.9 Lobby and NAT traversal (player host)

Written from scratch, same proven design as the Two Wards lobby:

- TypeScript on Bun, no runtime deps, Docker container. WebSocket `/ws`, `/healthz`, Prometheus `/metrics`.
- Room codes (4 letters, no ambiguous characters). Relays WebRTC offer/answer/ICE candidates verbatim; never sees gameplay.
- Mints time-limited coturn credentials (REST scheme, shared secret only on the server host).
- Differences from Two Wards: up to 9 guests per room; **rooms stay open while the game server runs** (heartbeat from the server, dropped when it stops) so friends can join any time; star topology (each guest connects only to the server, peer id 1; the server creates one offer per guest).
- coturn as STUN + TURN relay fallback; `total-quota` sized for 10-player rooms.
- WebRTC in Godot via the pinned webrtc-native GDExtension, installed by a tool script and shipped in every export.
- M6 built: `lobby/` (rooms in `src/rooms.ts`, lobby protocol 1), `net/lobby_client.gd` for both sides, `--server --lobby=URL` in `GameServer`. The host's client spawns the server on its solo world with `--owner=<name> --room-file=<path>`, reads the code from the file and joins by code. The server pings the lobby every 20 s and opens a new room if it loses the lobby (players already in stay). The start menu (`client/start_menu.gd`) offers solo, host and join; a failed or ended game returns to it with the reason. Deploy: `deploy/lobby/` (lobby + coturn on 3478 on the gvm host, `lobby.r4b2.de`, replacing Two Wards), live since M9a; `--lobby=URL` still picks a local one.

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
- Death and respawn (M18, settles open question 1): an overworld death moves the inventory slots (equipment stays worn) into a grave at the death spot (`SimWorld.SimGrave`), saved in its chunk file (format 3) and sent with each chunk plus a `grave` RPC per change. Only its owner loots it, with E (`Net.interact`), taking what fits; it is gone once empty. Another death makes another grave. The owner's client gets where its graves lie (`Net.own_graves`, saved with the player) and points an arrow at the screen's edge to the closest. A bed piece (`PieceDef.bed`) sets the respawn point of whoever uses it (E, saved with the player); a respawn goes there while the bed stands, else to the spawn. A dungeon death keeps the snapshot rule (4.8) and leaves no grave.
- Enemy pathing (M18): a chasing enemy walks straight at its target while the line is clear, else follows an A* route on the tile grid around blocking pieces (`sim/pathing.gd`: eight ways, no corner cutting, at most 300 tiles a search inside a 64-tile window, the blocked tiles cached until a piece changes). It searches again when a blocking piece comes or goes (`SimWorld.pieces_version`) or its target moved to another tile (at most every 0.5 s); all searches share 600 tiles a tick, the rest wait a tick. With no open way within the bound the route ends at the tile closest to the target, and it sieges the piece in its way there; running into a piece on a way that looked open makes it search again first. Behaviors keep their own approach (archer distance, wolf circling, shield facing) on top; dungeon runs have no pieces, so their enemies walk straight as before.
- Enemy AI v1: idle → notice → chase → attack → leash back.
- Healing (M17): cooked food from the fire regenerates health for a while (`ItemDef.regen`, `regen_time`); a healing draught (`ItemDef.heal`, H) heals at once with a shared cooldown (`Tuning.draught_cooldown`).
- Abilities (M17, settles open question 2): gear grants abilities through a **rune slot**, not through weapons, so any weapon can be combined with any ability. A rune item (`ItemDef.Slot.RUNE`) names an `AbilityDef` (`game/data/abilities/`: cooldown, stamina cost, kind-specific numbers); Q uses the worn one, checked on the server. One ability at a time keeps the HUD and the keybinding simple; more slots can come later. Frost bolt (a player projectile that slows), healing ward (a timed healing area) and shockwave (area damage, poise break and knockback). Runes drop from the barrow's end chest and boss; the shock and ward runes can also be crafted.

### 5.3 Loot and inventory

- Drop tables with rarity tiers. Items on the ground, pickup, grid inventory, equipment slots, stacking.
- Gear with random affixes (dungeon drops). Crafting from materials at stations.
- M4 built: all game data in `game/data/` (`tuning.tres`, `items/`, `recipes/`, `enemies/`; an item's or recipe's id is its file name), loaded by `content/content.gd`. Drop tables roll each entry on its own (`sim/loot.gd`); drops lie on the ground for 5 min and are picked up by walking over them (server side, not saved yet). 24-slot inventory plus a weapon and an armor slot (`sim/inventory.gd`); the weapon sets the light/heavy attacks, armor takes a flat amount off each hit and adds max health. Crafting by hand or at a station (`sim/crafting.gd`; since M8 a workbench players build). Random affixes wait for dungeons (M7).

### 5.4 Survival

- Health, stamina (regenerates, spent on dash/attacks), hunger (drains over time, eating restores; penalties at zero).
- Day/night cycle; night is more dangerous (more/stronger spawns).

### 5.5 Building

- Grid placement of a few pieces (wall, floor, door, workbench, chest, fire). Place/remove, persisted, replicated.
- M8 built: pieces are data (`game/data/pieces/`, `content/piece_def.gd`: cost, health, blocks, door, station, storage, light) placed one per 16 px tile, keyed by global tile. `sim/building.gd` holds the rules both sides share (reach, props and bodies in the way, cost, blocking, stations near a position), so the client's green/red ghost predicts the server. Build mode (B) takes the cost from the inventory, removing a piece gives it all back. Walls and closed doors block players (client prediction, server move check) and enemies; an enemy walking into one winds up and hits it instead, and a piece at 0 health breaks (a chest spills its contents). Repair is building the same piece again, refused while an enemy is near. Chests are 12 shared slots, opened with E; doors open and close with E. Fires carry a `PointLight2D`. Pieces are saved in the chunk files (format 2) and sent with each chunk plus a `piece` RPC per change. Crafting stations are built workbenches; the fixed one at the spawn is gone. M18 added pathing around them (below).

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
- **In use (M9b):** [Ninja Adventure](https://pixel-boy.itch.io/ninja-adventure-asset-pack) by Pixel-boy and AAA (CC0), only the PNGs we draw copied into `game/assets/ninja_adventure/` with its license. Items and pieces name their sprite in their `.tres` (`icon`, an `AtlasTexture` for tileset regions), the draugr its walk sheet (`sheet`); the ground, trees, rocks, barrow and dungeon regions are constants in their client views. The pack has no armor, so armor keeps its color square. Bright and not Norse: a stopgap until the AI art.
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
| Deploy | Docker Compose: lobby + coturn on the gvm host (TLS via its Caddy); the dedicated server runs locally |
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
| M1 | **Dedicated mode (local)** | Same server as a locally built Docker image via compose; clients connect by address; pause when empty; protocol version check; Prometheus metrics endpoint and a Grafana dashboard JSON | Done | v0.3.0 |
| M2 | **World + persistence** | Seeded chunk generation with placeholder biomes; chunk streaming with interest management; deltas, players and world meta survive a server restart | Done | v0.4.0 |
| M3 | **Combat** | Enemies spawn and use simple AI; light/heavy/dash with stamina; damage, death, respawn; self-scaling by nearby player count | Done | v0.5.0 |
| M4 | **Loot + inventory** | Drop tables, pickup, inventory, equipment changes stats, crafting at a station | Done | v0.6.0 |
| M4a | **Loot + inventory UX** | A new player finds out unaided how to gather, loot, equip and craft: on-screen prompts near trees, rocks and the labeled workbench; drops pulled in when walked near, an "inventory full" notice; drag-and-drop inventory with an item info panel, equipped stats and a controls line; recipes show have/need per input and why one can't be crafted | Done | v0.7.0 |
| M5 | **Survival** | Hunger, eating, day/night with stronger nights; penalties at zero | Done | v0.8.0 |
| M6 | **Player host** | Bun lobby + coturn as a deployable stack; server opens a room; host and friends join by code via WebRTC through a lobby (local or LAN for now); rooms stay open while the server runs | Done | v0.9.0 |
| M7 | **Dungeon v1** | Entrance in the world; generated instance; ~15 buffs; inventory snapshot rule; end chest; time/depth scaling | Done | v0.10.0 |
| M8 | **Building v1** | Grid placement of a few pieces, persisted and replicated | Done | v0.11.0 |
| M9 | **10-player test** | 10 headless bot clients for 30 min on the dedicated server: tick time and bandwidth within budget, no errors (§9 load budgets; 2026-10-26: mean 1.65 ms, no slow ticks, max 40 ms, peak 12.9 KB/s sent per player) | Done | v0.12.0 |
| M9a | **Lobby deploy** | Lobby + coturn (`deploy/lobby/`) run on the gvm host at `lobby.r4b2.de`, replacing the retired Two Wards stack; "Host a game" works with the built-in lobby URL; host and friends join by code from different networks, one of them through the TURN relay (2026-10-26: playtest passed) | Done | v0.14.0 |
| M9b | **Interim art** | Ground, trees, rocks, players and draugr (4-direction walk), items, pieces, barrow and dungeon drawn with the CC0 Ninja Adventure pack instead of shapes (see 6); content test checks every item and piece has a sprite | Done | v0.13.0 |
| M10 | **vServer deploy** | CI builds the server image and pushes it to GHCR; it runs on the vServer, friends connect over the internet; vector scrapes its metrics and the dashboard is in the infra Grafana (TLS/metrics stack lives in the separate `infra` repo). Dropped 2026-10-26: gvm runs only the lobby, the dedicated server stays local (M1) | Dropped | |
| M11 | **Boss** | The end room of every run holds one boss, the barrow king, at the end chest: a telegraphed area slam besides its swing, scaled like the other dungeon enemies, a boss health bar while in view, a guaranteed drop with raised rare chance; the chest stays locked until it is dead; `balance_sim.py --dungeon` reports boss kills within the targets | Done | v0.15.0 |
| M11a | **Building art + build/craft menus** | Walls pick their sprite by neighbours, so a row or corner reads as one wall; no piece sprite overhangs its tile (workbench); B opens a piece picker grouped by kind with have/need costs, info on hover and a hotbar of recent pieces, feeding the existing ghost placement; E at a workbench opens its recipe list by category with search and craft ×1/×5 | Done | v0.16.0 |
| M12 | **Combat feel** | Enemy windups show a ground indicator of the hit area that fills until the hit, enemies slow during windup and have a recovery window (replaces the yellow tint); hitstop, screenshake, sliding knockback, enemy stagger (poise) and heavies interrupting windups; player hurt knockback, flash and low-health vignette; dash afterimage plus a perfect-dodge reward; the weapon drawn in hand swinging through the arc with eased timing from `AttackDef`, smear and hit sparks, alternating light swings, heavy pull-back and lunge; enemy windup, lunge, recoil and death animations; first SFX and a volume bus; leash measured from the target with a visible give-up and gradual heal; `balance_sim.py` rerun | Done | v0.19.0 |
| M13 | **Menus** | Escape menu (resume, settings, quit to start menu, quit); settings with volume, fullscreen and controls; C character screen with stats, gear and active buffs; start menu lists solo worlds, creates (name, seed) and deletes them, and "Host a game" picks from the list | Done | v0.17.0 |
| M14 | **Tools + gathering** | Axe and pickaxe as tools with a tier; trees need an axe and rocks a pickaxe, gathered by swinging at nodes with health; sticks and pebbles by hand so the first tools are craftable | Done | v0.20.0 |
| M15 | **Ranged combat** | A sim projectile entity sent in snapshots, shared by players and enemies; bow with arrows as ammo, hold to draw, aimed at the mouse | Done | v0.18.0 |
| M16 | **More enemies** | Draugr archer (telegraphed arrow line), wolf packs (lunge, drop meat and hide), shield draugr (blocks from the front), a swarm or exploder; AI variants as a behavior in `sim_enemy.gd`, spawn mix per day and night | Done | v0.21.0 |
| M17 | **Healing + magic** | Cooked food at the fire regenerates health; a healing draught with a cooldown; a worn rune grants one gear ability on Q (frost bolt, healing ward, shockwave), settling open question 2 | Done | v0.22.0 |
| M17a | **Combat + bot leftovers** | Arrows wear poise and push like a light swing; lifesteal, bleed and kill buffs apply to arrow and ability hits; magic (frost bolt, shockwave) goes through a shield, arrows stay blocked; snapshots carry an enemy's `facing` and the client draws the shield arc from it; an exploder killed in its windup still detonates; bots use their rune ability and the draught, dodge inside the perfect window and stew berries without foraging far more (cause found); `balance_sim.py` (solo, groups, `--dungeon`) rerun with groups of 4 dying ≤ ~3× solo | Done | v0.23.0 |
| M18 | **Death + base** | Overworld death drops the inventory (not equipment) as a saved grave at the death spot that its owner loots with E, marked on screen until looted; a bed piece sets its owner's respawn point (saved with the player); enemies path around blocking pieces to reach a player and siege only when no way is open; a key panel in a screen corner always shows the current bindings of the main actions, and every on-screen key hint reads the InputMap, so rebinds show everywhere | Done | v0.24.0 |
| M18a | **Playtest fixes** | After a respawn the player walks normally again (bug found and covered by a test); settings are split into categories that fit any screen height; screenshake is lower by default with a strength slider in settings; the Tab inventory fits the screen; while the build menu is open the weapon is not drawn in hand and clicks stay in the menu | Done | v0.25.0 |
| M19 | **Enemy attack shapes + solo balance** | A melee enemy's normal attack is a frontal sweep aimed when its windup starts (indicator drawn as that cone), dodged by stepping out of it or behind; slams and the exploder stay circular; `balance_sim.py` rerun with novice solo within 2–4 deaths a day (2026-10-27: sweep in, night_count 2 → 1.5; average 0.33 and expert 0.25 solo on target, novice still ~5, needs the playtest) | Done | v0.26.0 |
| M20 | **Start menu + characters** | A redesigned start menu; characters are created (name, look, a starting kit: sword, bow or staff) and picked before the world; where characters live (per world or across worlds) settled first (2026-10-27: a character is a name, look and kit kept on the player's machine; each world keeps its own progress for it, so no items cross into someone else's server) | Done | v0.27.0 |
| M21 | **Map markers** | Markers placed and removed on the M map, synced to everyone in the world and saved with it | Done | v0.28.0 |

Dedicated (M1) comes before player host (M6) because it is almost free once solo works. It runs locally only; hosting it publicly (M10) was dropped.

**Ideas not yet scheduled (2026-10-27 playtest):** biome 2 with its boss gate, more animals, first-minute tutorial prompts (dodge, eat, build; the M18 key panel comes first), sprites for runes, wolves and armor, the final art pass (open question 6) before content grows much further.

**First prototype scope (after M9):** one biome, one dungeon type, ~15 buffs, one boss, basic building, all placeholders, 1–10 player co-op in all three modes.

---

## 9. Testing

| Layer | Tool | Covers |
|---|---|---|
| Unit | gdUnit4 | Sim core: combat math, loot tables, scaling formula, inventory, survival ticks, world gen determinism (same seed → same chunks), save/load round trip and migrations |
| Network | Headless Godot: 1 server + N bot clients (ENet, localhost) | Join/leave, replication, pause on empty, reconnect restores state, dungeon snapshot rule |
| Balance | `tools/balance_sim.py`: SurvivalBots of three skill levels play the sim headless for in-game days, solo and in groups | Deaths, day/night damage, hunger, time spent per activity, gear times against the difficulty targets in `.claude/skills/balance-sim/SKILL.md` |
| Load | Bot clients against the dedicated server (`tools/run_load_test.py`, opt-in) | Tick time, bandwidth, entity counts at 10 players |

**Load budgets** (10 players, ENet, dedicated server): tick mean ≤ 5 ms, at most 0.1% of ticks over one 30 Hz tick (33 ms) and none over 100 ms (a hitch a player notices); server sends ≤ 20 KB/s and receives ≤ 2 KB/s per player in the busiest minute (night); every bot exits 0, no log has an error line, and no player drops out.
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
