# Handoff 2: put round 2 into stealaranch_v1_merged

You're the Claude session on the user's PC with Roblox Studio connected over MCP.
`stealaranch_v1_merged` is open. Everything below is already written and pushed. Your job is to
**install it into the place and connect it to the place's own systems**.

Code: https://github.com/daviddamiansrr-droid/David1test/tree/claude/clever-rubin-s0o2nh
(read `README.md`, section "Round 2").

**Rules**
- Save a backup copy of the place first.
- Don't publish.
- Keep player data working: never reset coins or progress.
- Server-authoritative. No new remotes that trust the client.
- After each step, Play with 2 players (Local Server) and fix everything in Output.

## 1. Install the scripts
Clone the branch and run `python tools/build_place.py`. Insert from `build/`:
| File | Insert into |
|---|---|
| `Shared.rbxmx` | ReplicatedStorage (replace the old `Shared`) |
| `Server.rbxmx` | ServerScriptService (replace the old `Server`) |
| `Client.rbxmx` | StarterPlayer > StarterPlayerScripts (replace the old `Client`) |
| `StudioTools.rbxmx` | ServerStorage |

If you can write script Source through MCP, you can copy the files from `src/` instead.

## 2. Currency → Slime Coins
1. Find the place's existing money system: leaderstats, DataStore, money station, shop prices, and every UI showing `$`.
2. Make Slime Coins that same currency. Migrate the saved value 1:1. Don't run two currencies side by side.
3. Hook up the HUD and station:
   - Set the player attributes `Coins` and `CoinsPerSecond` from the server, and `RanchLevel`, `RanchXP` and `RanchXPMax` if the game has levels.
   - On every money station pad: add the tag `CoinStation` and keep the attribute `Stored` up to date. On collect, set `CollectedBy = UserId`, increment `CollectCount`, and set `Stored = 0`.
4. Import `assets/coin/SlimeCoin.obj` (with its texture) as a MeshPart named `SlimeCoin` in `ReplicatedStorage.Assets`.
5. Remove or hide the old money UI so there's only one HUD.

## 3. HUD buttons
Connect `Hud.IndexPressed`, `Hud.HoverboardPressed` and `Hud.SettingsPressed` to the place's existing Index, hoverboard and settings systems. If Shop should open the place's own shop instead of the vac shop, change it in `Client/Main`.

## 4. Walls
1. In the beach world and the volcano world, place guide Parts along where the old boundary walls are: long on X, front face toward the play area, bottom on the ground.
2. Delete the old wall pieces.
3. Select the guides and run:
```lua
require(game.ServerStorage.WallKit).fromSelection("Beach")    -- beach world guides
require(game.ServerStorage.WallKit).fromSelection("Volcano")  -- volcano world guides
```
4. Make sure StreamingEnabled is on. The walls average about 6 parts per stud.

## 5. Signs and cracks
1. Select every area sign model (INFERNO PEAK, SUNSET BAY, etc.) and run `require(game.ServerStorage.Fixers).signs()`.
2. Select the remaining volcano lava cracks (or their model) and run `require(game.ServerStorage.Fixers).cracks()`.
3. Read Output for anything the fixers skipped and fix those by hand.

## 6. Portals
In every portal, delete the spinning square blocks and tag the portal's flat surface part `PortalSwirl`. Set the attributes `Color1` and `Color2` to match each world.

## 7. Sounds
1. Upload `assets/sfx/*.ogg`. Bulk import works.
2. Paste the ids into `Shared/Config` → `Config.Sounds`. Lists hold the variants.
3. Tag the hoverboard's main part `Hoverboard`.
4. Remove or replace any old hoverboard, suction and slime sounds the place still plays.

## 8. Area 3 → 4 and getting home
1. Add a TravelPad pair between area 3 and area 4. Each pad is a part tagged `TravelPad`, with attribute `PadName`, and `Target` set to the other pad's name.
2. Add a pad with `Target = "Home"` near each far-area portal.
3. Show the user the pad locations before building if this changes progression.

## 9. Report back
Give the user a short list of:
- what changed
- anything that was skipped and why
- what to test
