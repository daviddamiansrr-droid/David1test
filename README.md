# Steal a Ranch: ranch rebuild

A rebuild of the ranch plots, map and vac tool. It plays like a cozy slime-ranching game, and you can also steal other players' slimes. Everything is generated in code: terrain, plots, the tool and the UI. Nothing needs to be imported except one optional texture.

The repo was empty when this was written, so this is a **standalone system**. It doesn't patch your existing place. See [Merging into the existing place](#merging-into-the-existing-place).

## Getting it into Studio

**Option A: no Rojo**
```
python3 tools/build_place.py        # writes build/SlimeRanch.rbxlx
```
Open `build/SlimeRanch.rbxlx` in Studio and press Play.

**Option B: Rojo**: `rojo serve default.project.json`, then connect from the Studio plugin.

Then:
1. **Game Settings > Places > Server Size = 5.** The game has 5 plots, so a 6th player would get nothing.
2. **Game Settings > Security > Enable Studio Access to API Services** if you want saving to work in Studio. Without it, data runs in offline mode and prints a warning.
3. **Honeycomb texture (recommended).** Upload `assets/honeycomb.png` (Asset Manager > Bulk Import, or Creator Hub > Images). Then set `Config.Fence.HexTexture = "rbxassetid://<id>"`. Without it, the client draws the hex pattern with GUI frames. That still looks right, but it costs more on mobile.
4. **Sounds.** `Config.Sounds` uses built-in `rbxasset://` sounds so everything works out of the box. They're generic, so swap in Creator Store sounds (vacuum loop, pop, slurp) for the real feel.
5. **Bake the terrain (optional).** `Config.Map.BuildTerrain = true` **wipes `workspace.Terrain`** and regenerates it on every server start (about 1–2 s). To bake it, run once, copy the Terrain from the running server, paste it into edit mode, and set the flag to `false`.

## What's in it

### Map: long and narrow
South to north, about 1050 studs long and about 150 wide:
- Sea and dock
- Hub: spawn, ranch house, Gem Exchange, Vac Workshop
- **Ranch Row**: 5 plots alternating on both sides of a dirt path
- A rock arch
- **The Wilds**: sandstone mesas, salt boulders, a pond, fruit trees, root patches and wild slimes that get rarer the deeper you go

The look is pastel terrain colours, warm haze, bloom and saturated colour correction.

### Plots
- A 48×48 corral of **translucent blue honeycomb energy walls** on dark posts, with glowing top rails and caps.
- **Your own walls let you walk through. Everyone else gets blocked.** This uses collision groups.
- The gate has an invisible slime field, so slimes stay in and players can walk through.
- Two consoles sit outside the gate: **Lock Gate** and **Ranch Upgrades**. Only the owner sees their prompts.

**Security track.** Each upgrade makes the walls *rise* on the client with a ripple, sparkles and sound:

| Tier | Walls | Lock | Extra |
|---|---|---|---|
| Starter Corral | 4 | 30s | anyone can hop in; hungry slimes hop out |
| High Walls (750) | 9 | 45s | can't be jumped; jetpack 1 still clears it |
| Reinforced (3k) | 14 | 60s | beats jetpack 1; alarm when someone walks in |
| Air Net (8k) | 14 + honeycomb roof | 75s | nobody gets in over the top while locked |
| Fortress Field (20k) | 18 + roof | 90s | thieves slowed for 6s when they steal |

**Utilities** (the corral-upgrade idea): Gem Collector (auto-banks gems), Music Box (+25% gem rate, calmer slimes), Auto Feeder, and Corral Expansion (12 → 18 → 24 slimes).

### Slimes and economy
- 5 types: Bubble, Pebble, Fizz, Glow, Ember. Each has a diet (Puffberry and/or Carrot Root).
- **Feed a slime and a gem pops out.** Slimes in a claimed corral also make gems slowly on their own.
- **A slime that eats another type's gem becomes a largo.** Largos are bigger, have ears in the second colour, eat both diets and drop both gems. Mixed corrals without a Collector will turn into largos on their own, same as in the game you're borrowing from.
- Unfed corral slimes eventually try to hop out. They can only clear Starter walls.
- **Gem Exchange**: prices drift and **drop as people sell the same gem**, then recover over time. Sell by **shooting gems into the funnel**, or use "Sell All Gems" (Gem Bank + gems in your tank).

### Vac tool
- Hold to suck, tap to shoot. You get 3 → 5 slots, and each slot holds one item type.
- PC: hold LMB to vac, tap RMB or F to shoot, 1–5 or Q to pick a slot.
- Gamepad: R2 / L2, DPad.
- Mobile: big VAC/SHOOT buttons, and tap a slot to select it.
- Feel: suction streams converge into the nozzle and start instantly (client-predicted). The rotor spins up, the vac loop sound pitches up, and items *slurp* into the nozzle with a pop. Absorbing in a combo raises the pitch. The camera kicks on recoil and the FOV pushes while vacuuming. Slots bounce, there's a fill gauge on the tool's canister, the character turns to face your aim, and slimes squish when they land.
- **Jetpack** (Vac Workshop): hold jump in the air. Fuel is limited per level.

## Security model
- The client only sends intent: start/stop, an aim direction (validated unit vector, rate-limited), shoot (cooldown) and slot select. The server picks what's in the cone, **raycasts against other players' walls** (no vacuuming through fences), pulls objects and owns the tank.
- Slimes and items are server network-owned, so they can't be flung or teleported by claiming physics.
- **Locked corrals:**
  - Locking sweeps every non-owner out.
  - While locked, any non-owner inside who couldn't legitimately get in is ejected. "Legitimately" is judged by wall height vs their jetpack reach, and an Air Net means nobody can. This covers noclip and teleport.
- Purchases are validated server-side: price, order, max level and distance to the right terminal.
- **Data:**
  - UpdateAsync with a session lock (no server-hop dupes) and retries with backoff.
  - Every loaded field is sanitised and clamped.
  - On leave, the corral is snapshotted and cleared *before* the save, so nothing can be stolen between the save and the cleanup.

Known limits:
- Movement is client-authoritative like any Roblox game. Speed and fly exploits still move faster. The eject rule stops them using that to raid locked corrals, but not to grab loose slimes.
- `Config.Jetpack.Reach` assumes default JumpHeight 7.2. **If your game changes jump power, update Reach**, or legit players will get ejected (or exploiters won't).
- Thief tagging sets WalkSpeed server-side, which an exploiter can override.

## Performance (mobile)
- 5 plots max. Hard caps: 150 slimes, 140 items, 30 wild.
- Loose food, gems and slimes despawn. Each corral holds at most 40 gems.
- One staggered loop runs all slime AI. There are no per-slime threads or Touched handlers.
- Fences are plain parts. The honeycomb is client-side: one Texture per face, or LOD'd GUI frames.
- Decor is anchored, non-touch and mostly shadowless. The map is terrain.

## Merging into the existing place
Things that will collide with what you already have:
- **Old map and plots**: remove them. This builds `workspace.RanchMap`, `RanchPlots`, `Slimes` and `Items`, and wipes Terrain (see above).
- **SpawnLocations**: keep only `RanchSpawn`. Owners get moved to their plot on spawn anyway.
- **leaderstats.Coins**: created here. If you already have currency, point `DataService`/`StateSync` at it instead.
- **DataStore** `SlimeRanch_v1` is a new store, so existing progress won't carry over unless you migrate it in `DataService.sanitize`.
- **StarterPack**: the server inserts a `Vac` tool.
- **Collision groups** used: `Players`, `Slimes`, `Items`, `SlimeField`, `Fence_1..5`, `Owner_1..5`. All characters are moved into `Players`.

## Test checklist (2+ players: Studio > Test > Local Server)
- [ ] Spawn at your plot. The sign shows your name and walls are 4 high. Your own walls let you through; another player's walls block you.
- [ ] Wilds: vac slimes, fruit and roots. Pull feels snappy, absorbs pop, the slot bounces and the tank fills. Shoot them back out.
- [ ] Shoot slimes into your corral, feed them, and gems pop out. Feed a gem of another type and you get a largo.
- [ ] Shoot gems into the funnel. Coins go up, the price on the board drops, then recovers.
- [ ] Buy High Walls: the walls ripple upward. Lock the gate: the barrier fades in, the other player gets swept out, and they can't jump in. With Jetpack 1 they *can* get over High Walls but not Reinforced.
- [ ] Other player steals a slime through the open gate: owner gets an alert. At Fortress Field, the thief is slowed.
- [ ] Leave and rejoin: slimes (up to capacity), coins, upgrades and tank contents are restored. Try a quick server hop and check nothing duplicates.
- [ ] Mobile emulator: VAC/SHOOT buttons work, tapping a slot selects it, the HUD scales, and frame rate holds with 5 players.

## Layout
```
src/shared   Config (all tunables), ItemIds, Remotes
src/server   Main, MapBuilder, PlotService, SlimeService, VacService, MarketService,
             ShopService, DataService, StateSync, ItemFactory, Collision
src/client   Main, Hud, ShopUI, VacController, VacFx, Jetpack, Honeycomb, PlotFx,
             SlimeJuice, Sounds, ClientState
tools        build_place.py (rbxlx without Rojo), make_honeycomb.py
assets       honeycomb.png
```
