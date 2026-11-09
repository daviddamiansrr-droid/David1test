# Handoff: merge the ranch rebuild into stealaranch_v1

You're picking this up in a local Claude Code session on the user's Windows PC (DESKTOP-NMM4VOP). The user has Roblox Studio installed. The last session ran in the cloud and couldn't reach their PC, so this part is yours.

## Who the user is
- A Roblox dev who works in Luau in Studio. Don't explain Roblox basics.
- They want short, direct answers. No filler or flattery.
- Just do the work; don't ask permission for every step.
- Flag security risks without being asked: anything that trusts the client, unvalidated remotes, unsafe DataStore writes.
- Production-safe patterns: server-authoritative, DataStore retries, no unbounded loops.
- **Don't publish to Roblox.** Give them a file to open and test. They publish it themselves.

## What already exists
**1. Their live game: `stealaranch_v1`.** It's a "steal a ranch" game, where players run ranches and steal from each other. It's open in Studio and saved somewhere on this PC, possibly in a folder called "Roblox Templates". **Nobody has seen its scripts yet.**

**2. A rebuild, written last session.** It's in GitHub repo `daviddamiansrr-droid/David1test` on branch **`claude/clever-rubin-s0o2nh`**. Read its `README.md` first. In short:
- Slime Rancher-style ranch plots, max 5 per server.
- Translucent blue honeycomb energy walls.
- A 5-tier security track: walls rise, Air Net roof, longer gate locks, alarm, thief slowdown.
- Gate lock console, plus an eject rule that kicks people out of locked corrals.
- Utilities: Gem Collector, Music Box, Auto Feeder, Corral Expansion.
- A long, narrow terrain map: sea → hub → ranch row → rock arch → the Wilds.
- Slimes with diets, gem drops, largos, and escape attempts.
- A vac tool with server-validated suck/shoot and heavy client effects. Mobile buttons. A jetpack.
- A Gem Exchange with drifting prices that drop as players sell.
- A session-locked DataStore (`SlimeRanch_v1`).
- Rojo layout: `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server, `src/client` → StarterPlayerScripts.Client.
- Every tunable is in `src/shared/Config.luau`.
- `python tools/build_place.py` turns `src/` into `build/SlimeRanch.rbxlx`, no Rojo needed.

**The rebuild has never run in Studio.** It was only parse-checked with StyLua. Expect some runtime errors on the first Play.

## Your job
Merge the rebuild into `stealaranch_v1`. You should end up with one updated place: the new plots, map, vac and upgrades, while the user's existing economy and progress keep working.

### Steps
1. **Get the code.** Run `git clone -b claude/clever-rubin-s0o2nh https://github.com/daviddamiansrr-droid/David1test`.
2. **Get the place in a readable form.** `.rbxl` is binary. Ask the user to do File → Save to File As… → "Roblox XML Place Files (*.rbxlx)" in the stealaranch_v1 window, then find that file. If they can't, use Lune (`roblox` library) to read the binary `.rbxl`.
3. **Audit their scripts before changing anything.** Write a short list for the user:
   - Plot/base system: assignment, ownership, locks, stealing logic.
   - Map and spawn.
   - Tools in StarterPack.
   - Currency and leaderstats.
   - DataStore names and data shape.
   - Gamepasses and dev products (MarketplaceService, ProcessReceipt).
   - Collision groups.
   - Anything that conflicts with the rebuild: `workspace.RanchMap`, `RanchPlots`, `Slimes`, `Items`, the `Vac` tool, `leaderstats.Coins`, terrain, and the groups `Players`, `Slimes`, `Items`, `SlimeField`, `Fence_1..5`, `Owner_1..5`.
4. **Decide what to replace and what to keep.** Show the user the plan in a few lines before doing a large deletion.
   - Replace: old plots, old map, old steal tool.
   - Keep and wire in: their currency, their DataStore (so players keep progress), gamepasses and dev products, and anything unrelated to plots or the map.
   - If their stealing works on different creatures (not slimes), say so. Ask whether to keep their creatures or switch to slimes. That's a real design decision, so ask.
5. **Merge.**
   - Point `DataService` at their existing store, or migrate their data inside `sanitize()`.
   - Point coins at their currency.
   - Keep `ProcessReceipt` working.
   - Remove or disable the replaced scripts.
   - Check `Config.Jetpack.Reach` against their JumpHeight/JumpPower. It assumes the default 7.2. If they changed it, locked-corral ejects will misfire.
6. **Test in Studio.** Use Test → Clients and Servers → Local Server with 2 players.
   - Fix everything in the Output window.
   - Run the README's test checklist: spawn at plot, vac/shoot, feeding → gems → largo, selling at the funnel, security upgrade wall rise, lock + sweep + eject, steal alert, rejoin restores data, mobile emulator.
7. **Deliver.**
   - Save `stealaranch_v1_merged.rbxlx` next to the original. **Never overwrite the original.**
   - Open it with `start "" "<path>"` so it opens in Studio.
   - Commit the code changes to the same branch and push. Don't open a PR unless asked.
   - Give the user a short summary: what changed, what got removed, what they have to do by hand, and what to test.

### Manual steps the user still has to do
Remind them about these:
- Game Settings → Places → **Server Size = 5**.
- Game Settings → Security → **Enable Studio Access to API Services**, to test saving.
- Upload `assets/honeycomb.png` and put its id in `Config.Fence.HexTexture`. Without it, the walls use a slower GUI-frame fallback.
- Swap in real sounds in `Config.Sounds`. The current ones are generic built-ins.
- `Config.Map.BuildTerrain = true` **wipes Terrain on every server start**. Bake the terrain once, then set it to false.

### Known weak spots to check first
- `Honeycomb.luau` sets `SurfaceGui.ClipsDescendants`. Confirm it doesn't error.
- `SlimeJuice.luau` calls `Model:ScaleTo` on the client on server-owned slimes. That's cosmetic only; remove it if it causes jitter.
- `VacController.luau` writes `Camera.FieldOfView` every frame. That will fight any sprint/FOV script they already have.
- Strict-mode type warnings will probably show up in Script Analysis. They're warnings, not runtime errors.
