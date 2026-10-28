# M22 Dungeon Rooms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No rushing to the barrow king: gates that open only once the room before them is cleared, plus a few blocking obstacles and walk-through decor in each room, kept sparse.

**Architecture:** The dungeon layout snaps to the 16 px tile grid so obstacles and gates can be tile sets, like built pieces. `Dungeon` keeps `solid` (obstacle tiles + tiles of closed gates) and `blocked` (`walls` + `solid`). `SimWorld.blocker` answers from `run.solid` inside a run, so the enemy step/slide/lunge code, projectiles and pathing pick it up without changes of their own. The client gets obstacles, gates and `cleared` with `Net.dungeon`, rebuilds the same `solid` with the same static function and walks against it.

**Tech Stack:** Godot 4 typed GDScript, gdUnit4 tests (`python tools/run_tests.py -a res://tests/<file>.gd`), `python tools/check.py`.

**Spec:** `docs/PLAN.md` §8, row M22, plus the 2026-10-28 brainstorm: only the way forward locks and the way back stays open; "not too cluttered".

## Global Constraints

- Rooms stay sparse: obstacle tiles ≤ 8 % of a room's tiles, at most 6 obstacles per room, and no gap narrower than 3 tiles (48 px, the corridor width) between two obstacles or between an obstacle and a wall it doesn't touch.
- Gate rule: gate `k` sits in the last tile column of corridor `k` (room `k` → room `k+1`) and is open iff `run.cleared >= k`. Gates only ever go from shut to open. The way back is never shut.
- Nobody builds in a run, so inside a run `SimWorld.blocker` looks only at `run.solid`, never at pieces.
- Bump `Net.PROTOCOL_VERSION` 22 → 23.
- Commits: `type(scope): summary`, authored as r4b2, no AI trailers. `python tools/check.py` must pass before each push (it needs `.venv/bin` on the PATH for gdtoolkit).
- Commit the `*.gd.uid` files Godot generates for new scripts.

## Review Focus

- **More players than spawn points:** with 4–10 players `_wake_rooms` places extra enemies 16 px apart, which can land inside an obstacle. They must be moved to the nearest open tile (test in Task 2).
- **Knockback into a pillar:** an enemy pushed by a heavy hit or arrow must stop at the obstacle, not pass through it or get stuck in it (test in Task 2, through `_slide`, which already uses `world.blocker`).
- **Arrows and frost bolts at obstacles:** player and enemy projectiles end at an obstacle or a closed gate. An enemy arrow hitting one must not error in `damage_piece` (test in Task 2).
- **Late joiner and retreat:** a player who joins within `dungeon_join_window`, or one who retreats into earlier rooms, never finds a gate behind them shut (test in Task 2).
- **Delve bot stuck behind a pillar:** the balance bot walks straight lines today. It must path around obstacles and wait at a shut gate, or the dungeon balance numbers become meaningless (Task 5 reruns the sim).

---

### Task 1: Tile-aligned layout and room obstacles in the data

**Files:**
- Create: `game/scripts/content/room_obstacle.gd`
- Modify: `game/scripts/content/room_def.gd`, `game/scripts/sim/dungeon.gd` (`_init`), `game/data/rooms/*.tres` (all six)
- Test: `game/tests/content_test.gd`, `game/tests/dungeon_test.gd`

**Interfaces:**
- Produces: `class_name RoomObstacle extends Resource` with `enum Kind { PILLAR, TOMB, RUBBLE }`, `@export var kind := Kind.PILLAR`, `@export var tiles := Rect2i()` (in tiles from the room's top-left). `RoomDef.obstacles: Array[RoomObstacle]`. Every `Dungeon.rooms`/`area` rect has its position and size on multiples of `WorldGen.TILE`.

- [ ] **Step 1: Write the failing tests**
  - `content_test.gd::test_rooms_are_sparse_and_open`: for every room, check that
    - `size` is a multiple of 16 on both axes;
    - obstacle tiles ≤ 8 % of the room's tiles, and there are ≤ 6 obstacles;
    - no obstacle tile lies in the first or last 3 tile columns (corridor mouths can be at any height);
    - every spawn's tile, grown by `Building.BODY`, touches no obstacle;
    - START rooms have no obstacles, and in END rooms the center tile (chest and boss) and the exit tile (`size.x - Dungeon.DOOR_INSET`, center y) are clear;
    - a flood fill over the room's non-obstacle tiles reaches all of them;
    - every pair of obstacles, and every obstacle against each wall it doesn't touch, keeps a gap of ≥ 3 tiles.
  - `content_test.gd`: assert that `corridor_length` and `corridor_width` are multiples of 16.
  - `dungeon_test.gd::test_layout_sits_on_the_tile_grid`: build `Dungeon.new(0, 0.0, rng)` for 20 seeds and assert that every `area` rect's `position` and `size` are multiples of 16. Also assert that `walls` holds no tile whose center is inside `area`.

- [ ] **Step 2: Run them and see them fail**

  Run: `python tools/run_tests.py -a res://tests/content_test.gd` and the same for `dungeon_test.gd`
  Expected: FAIL (`obstacles` doesn't exist; room sizes such as 200 aren't multiples of 16; rooms are placed at random float heights).

- [ ] **Step 3: Implement**
  - In `Dungeon._init`, snap the start position, `center_y` and the corridor `y` to the 16 px grid. Pick the corridor `y` as a random tile row within `[top, bottom - corridor_width]`, both ends snapped inward.
  - Resize the rooms to multiples of 16 and lay out their obstacles. Start from this; the test is the judge:

    | Room | Size (px) | Obstacles (tile rects x, y, w, h) |
    |---|---|---|
    | antechamber (START) | 240×208 | none |
    | burial_chamber (END) | 384×304 | PILLAR at (5,3,2,2), (17,3,2,2), (5,14,2,2), (17,14,2,2) |
    | crypt | 320×320 | TOMB (9,8,2,3); PILLAR (14,3,1,1), (14,16,1,1) |
    | gallery | 560×160 | PILLAR against the walls at (10,0,1,1), (10,9,1,1), (24,0,1,1), (24,9,1,1); RUBBLE (19,4,2,2) |
    | hall | 416×240 | PILLAR colonnade at (7,4), (7,10), (19,4), (19,10), each 1×1 |
    | ossuary | 288×256 | RUBBLE against the walls at (7,0,2,2), (7,14,2,2); TOMB (4,7,1,2) |

    Keep the existing spawn px values where they pass. Move any that the test rejects.

- [ ] **Step 4: Run the tests and see them pass**, plus the whole of `dungeon_test.gd` (the layout changed under it).

- [ ] **Step 5: Commit** `feat(dungeon): lay rooms on the tile grid and give them obstacles`

### Task 2: Obstacles and gates block in the sim

**Files:**
- Modify: `game/scripts/sim/dungeon.gd`, `game/scripts/sim/building.gd`, `game/scripts/sim/sim_world.gd` (`blocker`, `blocked_at`, `move_player`, `_wake_rooms`, `_use_portal` event, `damage_piece` unchanged but relied on)
- Test: `game/tests/dungeon_test.gd`

**Interfaces:**
- Consumes: `RoomDef.obstacles`, the tile-aligned `Dungeon.rooms` and `area` (Task 1).
- Produces:
  - `Building.tile_blocker(tiles: Dictionary, at: Vector2) -> Variant`: the first tile in `{tile: true}` that a body (`BODY`) at `at` overlaps, or null.
  - `Building.can_walk_tiles(tiles: Dictionary, from: Vector2, to: Vector2) -> bool`, with the same escape rule as `can_walk`.
  - `Dungeon.obstacles: Array[Rect2i]` (world tiles), `Dungeon.obstacle_kinds: PackedByteArray` (`RoomObstacle.Kind`, same order), `Dungeon.gates: Array[Rect2i]` (gate `k` = corridor `k`'s last tile column, full corridor height).
  - `static func Dungeon.solid_tiles(obstacles: Array[Rect2i], gates: Array[Rect2i], cleared: int) -> Dictionary`: the obstacle tiles plus the tiles of every gate `k > cleared`. The client calls this too.
  - `Dungeon.solid: Dictionary` and `Dungeon.blocked: Dictionary` (`walls` merged with `solid`), rebuilt by `Dungeon.set_cleared(n: int) -> void`, which `_wake_rooms` calls instead of assigning `cleared`.
  - `Dungeon.open_spot(at: Vector2) -> Vector2`: the nearest tile center not in `blocked`, searched in rings (at itself if its tile is free).
  - Event `["dungeon", id, area, exit, chest, position, obstacles, obstacle_kinds, gates, cleared]` (on leaving, the four new fields are empty arrays and 0). New event `["gates", id, cleared]` for each player in the run whenever `cleared` changes.

- [ ] **Step 1: Write the failing tests** in `dungeon_test.gd`, on a run built through `world.interact(1)`:
  - `test_a_shut_gate_stops_the_player_until_the_room_is_cleared`: enter, walk the player to room 1, and tick so it wakes. Then check:
    - `move_player` into gate 1's tiles returns false;
    - kill every enemy and tick: gate 1's tiles are gone from `run.solid`, the event `["gates", 1, 1]` was appended, and `move_player` through gate 1 returns true;
    - gate 0 was open from the start (`cleared` starts at 0).
  - `test_the_way_back_stays_open`: with room 2 woken and its enemies alive, `move_player` back through gate 1 and gate 0 into the start room returns true.
  - `test_obstacles_block_players_enemies_and_arrows`. With a hall or crypt forced into the layout (`run.defs`, or a seed known to give one, whichever is simpler), check that:
    - `move_player` onto an obstacle tile returns false;
    - an enemy knocked (`knock_vel`) toward a pillar ends next to it, not inside;
    - a player arrow and an enemy arrow fired at a pillar are gone from `projectiles` after a few ticks, without an error.
  - `test_extra_enemies_never_wake_inside_an_obstacle`: 10 players in one run and woken rooms, so every enemy's tile is free in `run.blocked`.
  - `test_enemies_path_around_obstacles`: `Pathing.find(world.blocked_at(p), a, b, SimEnemy.PATH_NODES)` across a pillar has waypoints, and none of them is in `run.blocked`.
  - Update `test_entering_needs_the_entrance_and_leaving_the_exit` to the new event shape.

- [ ] **Step 2: Run them and see them fail**: `python tools/run_tests.py -a res://tests/dungeon_test.gd`

- [ ] **Step 3: Implement**
  - `SimWorld.blocker(at)`: if `_run_at(at)` is a run, return `Building.tile_blocker(run.solid, at)`; otherwise return the pieces as now.
  - `blocked_at` returns `run.blocked`.
  - `move_player` also rejects `not Building.can_walk_tiles(player.run.solid, player.position, position)`.
  - `_wake_rooms` places each enemy at `run.open_spot(clamp_to(...))`. When `cleared` changes it calls `set_cleared`, appends the `gates` events and bumps `pieces_version`, so enemies repath through the opened gate (say so in a comment).
  - `free_spot` already uses `blocked_at`, so drops keep off obstacles without a change.
  - The `"dungeon"` event gets its new fields.

- [ ] **Step 4: Run the tests and see them pass**, then the whole suite: `python tools/run_tests.py`

- [ ] **Step 5: Commit** `feat(dungeon): shut the way on until a room is cleared and let obstacles block`

### Task 3: Client: walk against obstacles and gates, draw them

**Files:**
- Modify: `game/scripts/net/net.gd` (`dungeon` RPC + new `gates` RPC, `PROTOCOL_VERSION` 23), `game/scripts/net/game_server.gd` (dispatch `"dungeon"` and `"gates"`), `game/scripts/client/game_client.gd` (`_on_dungeon`, `_walk`, gate prompt), `game/scripts/client/dungeon_view.gd`, `game/scripts/client/sfx.gd`
- Test: `game/tests/net_test.gd` if it covers the dungeon payload (check first), else a run in the game

**Interfaces:**
- Consumes: Task 2's event fields and `Dungeon.solid_tiles`.
- Produces: `Net.dungeon(area: Array, exit: Vector2, chest: Vector2, at: Vector2, obstacles: Array, kinds: PackedByteArray, gates: Array, cleared: int)`, and `Net.gates(cleared: int)` (authority, reliable) with `gates_received(cleared)`. `DungeonView.obstacles`, `kinds`, `gates`, and `DungeonView.set_cleared(n: int)`, which redraws.

- [ ] **Step 1: Implement the payload, and `_solid` in `GameClient`**, built by `Dungeon.solid_tiles` in `_on_dungeon` and again on `gates_received`. `_walk` tries each step only where both `Building.can_walk(_pieces, …)` and `Building.can_walk_tiles(_solid, …)` hold, keeping the axis sliding.

- [ ] **Step 2: Feedback when a gate opens and near a shut one**
  - On `gates_received`: announce "The way on opens" (`Color("feae34")`) and play a new procedural gate grind in `sfx.gd`.
  - In `_update_target`: within `portal_reach` of a shut gate, `Hud.show_prompt` says "Sealed until the room is cleared" (no key, since nothing to press).

- [ ] **Step 3: Draw obstacles and gates in `DungeonView`**
  - PILLAR: a block of `dungeon_wall.png` with a lighter top face and a short shadow on the floor to the south.
  - TOMB: the same block with an inset lid.
  - RUBBLE: `craftpix/props/decor/rubble.png`/`ruin.png` filling its rect.
  - A shut gate: iron bars across its column. An open one: only the frame posts at its ends.
  - All of this is flat at the floor's z, with no y-sort, so keep the art no taller than its tiles plus an 8 px top face.

- [ ] **Step 4: Verify in the game** (skill `run`): host a solo game and enter the barrow. Check that:
  - you can't pass a pillar or a shut gate, and you slide along them;
  - the gate opens with the sound and announcement once the room is clear;
  - arrows stop at pillars;
  - going back is never blocked.

  Take a screenshot of a room with obstacles and a shut gate.

- [ ] **Step 5: Run `python tools/check.py`** (the network test exercises the protocol bump) and expect "All checks passed".

- [ ] **Step 6: Commit** `feat(dungeon): show and walk against obstacles and gates on the client`

### Task 4: Walk-through decor

**Files:**
- Modify: `game/scripts/client/dungeon_view.gd` (and `client/decor.gd` only if loading a sprite through `Decor.sprite` is the cleanest way)

**Interfaces:**
- Consumes: `DungeonView.area`, `obstacles`, `gates`, `set_cleared` (Task 3).

- [ ] **Step 1: Scatter decor** with a hash of the tile, so every client sees the same:
  - on about 4 % of room floor tiles (never in corridors, and not on or next to an obstacle, the chest, the exit or a spawn), using bones, skulls, ribs, spine, long_bone, bones_small, bone_heap and skull_pile from `craftpix/props/decor/`;
  - a procedural cobweb (a few `draw_line`s and arcs) in some room corners, chosen by the same hash;
  - two procedural torches on the corridor walls beside each gate, red while it is shut and warm (`feae34`) and flickering once it opens.

  Sparse is the goal: compare the screenshot to Task 3's; the room should read as furnished, not filled.

- [ ] **Step 2: Verify in the game** and take a screenshot of two or three rooms.

- [ ] **Step 3: Run `python tools/check.py`, commit** `feat(dungeon): scatter bones, cobwebs and gate torches in the rooms`

### Task 5: Delve bot, balance, docs and release

**Files:**
- Modify: `game/tools/delve_bot.gd` (`_walk_to`, `_delve`), `docs/PLAN.md` (§4.8 / §5.7 text, §8 M22 Done + release, M23 Next), `CLAUDE.md` (Dungeon bullet and Where we are), `.claude/skills/balance-sim/SKILL.md` only if the dungeon targets' notes need the gates

- [ ] **Step 1: Teach the delve bot to path:** `_walk_to` follows `Pathing.find(me.run.blocked, me.position, target, SimEnemy.PATH_NODES)`'s first waypoint, then clamps to the area as now. At a shut gate it waits in the corridor and fights whatever comes, so it never sits idle with a room uncleared behind it.

- [ ] **Step 2: Run `python tools/balance_sim.py --dungeon`** and compare to the targets in the balance-sim skill. Report the clear rates and lowest health, before and after the change (run on `HEAD~` first for the baseline). Gates should lower the clear rate for weak gear. Don't tune numbers in this milestone unless a group can no longer finish at all; report it instead.

- [ ] **Step 3: Docs**
  - PLAN §4.8/§5.7: gates, obstacles and the tile grid.
  - CLAUDE.md "Dungeon": `Dungeon.solid`/`blocked`/`gates`, `set_cleared`, `Net.gates`, `RoomObstacle`, and that `SimWorld.blocker` answers from the run.
  - M22 Done, M23 Next.

- [ ] **Step 4: Run `python tools/check.py`, commit** `docs: finish m22 dungeon rooms`, push, check `gh run list --branch main --limit 5`.

- [ ] **Step 5: Release** once CI is green on `main`: `git tag -a v0.30.0 -m "M22: Dungeon rooms" && git push origin v0.30.0`, then write `v0.30.0` into the Release column (a `docs` commit).
