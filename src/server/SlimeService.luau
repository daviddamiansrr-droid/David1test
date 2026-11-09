--!strict
-- Slime brains + everything that ticks in the world:
--   * hop AI (seek food, wander, agitated escape attempts in low corrals)
--   * eating food -> gem pops out; eating another type's gem -> becomes a largo
--   * passive gem production for slimes in claimed corrals (capacity-limited)
--   * Gem Collector / Auto Feeder plot upgrades
--   * wild slime + wild food spawning, despawning loose stuff (mobile perf)
--
-- One staggered loop handles every slime; no per-slime threads or Touched events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ItemFactory = require(script.Parent.ItemFactory)
local PlotService = require(script.Parent.PlotService)
local StateSync = require(script.Parent.StateSync)

local S = Config.Slime
local M = Config.Map
local FxRemote = Remotes.event("Fx")

type SlimeState = {
	NextThink: number,
	LastAte: number,
	NextPassive: number,
	LooseSince: number?,
	Producing: boolean,
}

local SlimeService = {}

local states: { [Model]: SlimeState } = {}
local spawners: { { Position: Vector3, Kind: string } } = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { ItemFactory.Slimes, ItemFactory.Items }
groundParams.RespectCanCollide = true

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }

local itemOverlap = OverlapParams.new()
itemOverlap.FilterType = Enum.RaycastFilterType.Include
itemOverlap.FilterDescendantsInstances = { ItemFactory.Items }

local function now(): number
	return os.clock()
end

local function inWilds(pos: Vector3): boolean
	return pos.Z >= M.WildZ[1] - 5 and pos.Z <= M.EndZ + 20
end

local function hasUpgrade(plot: PlotService.Plot?, key: string): boolean
	if not plot or not plot.Owner then
		return false
	end
	local d = DataService.get(plot.Owner)
	return d ~= nil and d.PlotUpgrades[key] == true
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, 1)
end

local function randomDir(): Vector3
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function vacHeld(p: BasePart): boolean
	return ((p:GetAttribute("VacUntil") or 0) :: number) > now()
end

----------------------------------------------------------------------
-- gems / eating
----------------------------------------------------------------------
local function popGem(t: string, from: Vector3)
	local v = randomDir() * math.random(4, 8) + Vector3.new(0, 24, 0)
	local gem = ItemFactory.gem(t, from, v)
	FxRemote:FireAllClients("gem", gem.Position, Config.Slimes[t].Color)
end

local function produce(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local a = root:GetAttribute("A") :: string
	local b = root:GetAttribute("B") :: string?
	local top = root.Position + Vector3.new(0, root.Size.Y / 2 + 0.8, 0)
	popGem(a, top)
	if b then
		popGem(b, top)
	end
end

local function becomeLargo(model: Model, gemType: string)
	local root = model.PrimaryPart :: BasePart
	local a = root:GetAttribute("A") :: string
	local cf = root.CFrame + Vector3.new(0, 0.6, 0)
	model:Destroy()
	local largo = ItemFactory.slime(a, gemType, cf)
	FxRemote:FireAllClients("largo", cf.Position, Config.Slimes[gemType].Color)
	local st = states[largo]
	if st then
		st.LastAte = now()
	end
end

local function canEat(a: string, b: string?, item: BasePart): boolean
	local parsed = ItemIds.parse(item:GetAttribute("Id"))
	if not parsed then
		return false
	end
	if parsed.Kind == "food" then
		return ItemIds.eats(a, b, parsed.A)
	elseif parsed.Kind == "gem" then
		-- normal slimes eat other types' gems and turn into largos
		return b == nil and parsed.A ~= a
	end
	return false
end

local function eat(model: Model, st: SlimeState, item: BasePart)
	local parsed = ItemIds.parse(item:GetAttribute("Id"))
	if not parsed then
		return
	end
	local root = model.PrimaryPart :: BasePart
	local color = item.Color
	item:Destroy()
	st.LastAte = now()
	FxRemote:FireAllClients("eat", root.Position, color)
	if parsed.Kind == "food" then
		produce(model)
	else
		becomeLargo(model, parsed.A)
	end
end

----------------------------------------------------------------------
-- brain
----------------------------------------------------------------------
local function think(model: Model, st: SlimeState, t: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	if vacHeld(root) then
		st.NextThink = t + 0.3
		return
	end
	local radius = root.Size.Y / 2
	local grounded = Workspace:Raycast(root.Position, Vector3.new(0, -(radius + 0.9), 0), groundParams)
	if not grounded then
		st.NextThink = t + 0.25
		return
	end

	local a = root:GetAttribute("A") :: string
	local b = root:GetAttribute("B") :: string?
	local plotIndex = (root:GetAttribute("Plot") or 0) :: number
	local plot = if plotIndex > 0 then PlotService.Plots[plotIndex] else nil

	-- look for food
	local target: Vector3? = nil
	if t - st.LastAte > S.HungerDelay then
		local best: BasePart? = nil
		local bestDist = math.huge
		for _, p in Workspace:GetPartBoundsInRadius(root.Position, S.SeekRadius, itemOverlap) do
			if not vacHeld(p) and canEat(a, b, p) then
				local d = (p.Position - root.Position).Magnitude
				if d < bestDist then
					best, bestDist = p, d
				end
			end
		end
		if best then
			if bestDist <= radius + S.EatDistance then
				eat(model, st, best)
				st.NextThink = t + 0.6
				return
			end
			target = best.Position
		end
	end

	local agitateAfter = S.AgitateAfter * (if hasUpgrade(plot, "MusicBox") then 1.5 else 1)
	-- hungry corral slimes sometimes make a break for it (only clears Starter walls)
	local agitated = plot ~= nil and plot.Owner ~= nil and t - st.LastAte > agitateAfter and math.random() < 0.35

	local dir: Vector3
	if target then
		dir = flat(target - root.Position)
	elseif plot then
		local l = plot.CFrame:PointToObjectSpace(root.Position)
		local fromCenter = Vector3.new(l.X, 0, l.Z)
		if agitated then
			-- hungry and unhappy: throw itself at the nearest wall
			dir = plot.CFrame:VectorToWorldSpace(flat(fromCenter))
		elseif fromCenter.Magnitude > Config.Plot.Size / 2 - 8 then
			dir = plot.CFrame:VectorToWorldSpace(flat(-fromCenter + randomDir() * 6))
		else
			dir = randomDir()
		end
	elseif root.Position.Z < M.WildZ[1] + 15 and inWilds(root.Position) then
		dir = flat(Vector3.new(0, 0, 1) + randomDir() * 0.6) -- drift back into the wilds
	else
		dir = randomDir()
	end

	local height = if agitated then S.AgitatedHopHeight elseif target then S.HopHeight * 0.8 else S.HopHeight
	local vy = math.sqrt(2 * Workspace.Gravity * height)
	local speed = S.HopSpeed * (if agitated then 1.3 elseif target then 1.2 else 1)
	root.AssemblyLinearVelocity = dir * speed + Vector3.new(0, vy, 0)
	local align = root:FindFirstChildOfClass("AlignOrientation")
	if align then
		align.CFrame = CFrame.lookAt(Vector3.zero, dir)
	end

	st.NextThink = t + (if target then 0.7 else S.ThinkMin + math.random() * (S.ThinkMax - S.ThinkMin))
end

----------------------------------------------------------------------
-- world ticks
----------------------------------------------------------------------
local function setPlotAttr(p: BasePart, idx: number)
	if p:GetAttribute("Plot") ~= idx then
		p:SetAttribute("Plot", idx)
	end
end

local function classifyTick()
	local t = now()
	local counts: { [number]: number } = {}

	for model, st in states do
		local root = model.PrimaryPart
		if not root or not model.Parent then
			continue
		end
		local pos = root.Position
		if pos.Y < -60 then
			model:Destroy()
			continue
		end
		local plot = PlotService.plotAt(pos)
		local idx = if plot then plot.Index else 0
		setPlotAttr(root, idx)

		if plot and plot.Owner then
			st.LooseSince = nil
			counts[idx] = (counts[idx] or 0) + 1
			local d = DataService.get(plot.Owner)
			local cap = if d then Config.Capacity.Levels[d.Capacity] else 0
			st.Producing = counts[idx] <= cap
			if st.Producing and t >= st.NextPassive and not vacHeld(root) then
				local interval = S.PassiveInterval / (if hasUpgrade(plot, "MusicBox") then S.MusicBoxMultiplier else 1)
				st.NextPassive = t + interval
				produce(model)
			end
		else
			st.Producing = false
			st.NextPassive = math.max(st.NextPassive, t + 10)
			if inWilds(pos) then
				st.LooseSince = nil
			else
				st.LooseSince = st.LooseSince or t
				if t - (st.LooseSince :: number) > Config.World.LooseSlimeLifetime then
					FxRemote:FireAllClients("poof", pos, root.Color)
					model:Destroy()
				end
			end
		end
	end

	-- items: tag plot, collector, despawn, per-corral gem cap
	local gemsByPlot: { [number]: { BasePart } } = {}
	local loose: { BasePart } = {}
	for _, inst in ItemFactory.Items:GetChildren() do
		local p = inst :: BasePart
		local pos = p.Position
		if pos.Y < -60 then
			p:Destroy()
			continue
		end
		local plot = PlotService.plotAt(pos)
		local idx = if plot then plot.Index else 0
		setPlotAttr(p, idx)
		local age = t - ((p:GetAttribute("SpawnedAt") or t) :: number)
		local kind = p:GetAttribute("Kind")

		if plot and plot.Owner then
			if kind == "gem" then
				if hasUpgrade(plot, "Collector") and age > 2.5 and not vacHeld(p) then
					local d = DataService.get(plot.Owner)
					local parsed = ItemIds.parse(p:GetAttribute("Id"))
					if d and parsed then
						d.Bank[parsed.A] = (d.Bank[parsed.A] or 0) + 1
						FxRemote:FireAllClients("collect", pos, plot.CollectorPoint, p.Color)
						StateSync.mark(plot.Owner)
						p:Destroy()
						continue
					end
				end
				gemsByPlot[idx] = gemsByPlot[idx] or {}
				table.insert(gemsByPlot[idx], p)
			end
		elseif age > Config.World.LooseLifetime then
			p:Destroy()
			continue
		else
			table.insert(loose, p)
		end
	end
	for _, list in gemsByPlot do
		if #list > Config.Plot.GemCap then
			table.sort(list, function(x, y)
				return ((x:GetAttribute("SpawnedAt") or 0) :: number) < ((y:GetAttribute("SpawnedAt") or 0) :: number)
			end)
			for i = 1, #list - Config.Plot.GemCap do
				list[i]:Destroy()
			end
		end
	end
	-- global item cap: drop the oldest loose items first
	local over = ItemFactory.itemCount() - Config.World.MaxItems
	if over > 0 then
		table.sort(loose, function(x, y)
			return ((x:GetAttribute("SpawnedAt") or 0) :: number) < ((y:GetAttribute("SpawnedAt") or 0) :: number)
		end)
		for i = 1, math.min(over, #loose) do
			loose[i]:Destroy()
		end
	end
end

local function pickWeighted(weights: { [string]: number }): string
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = math.random() * total
	for name, w in weights do
		r -= w
		if r <= 0 then
			return name
		end
	end
	return Config.SlimeOrder[1]
end

local function wildCount(): number
	local n = 0
	for model in states do
		local root = model.PrimaryPart
		if root and (root:GetAttribute("Plot") or 0) == 0 and inWilds(root.Position) then
			n += 1
		end
	end
	return n
end

local function spawnWild(): boolean
	if ItemFactory.slimeCount() >= Config.World.MaxSlimes then
		return false
	end
	local band = Config.Wild.Bands[math.random(1, #Config.Wild.Bands)]
	local x = math.random(-50, 50)
	local z = band.ZMin + math.random() * (band.ZMax - band.ZMin)
	local hit = Workspace:Raycast(Vector3.new(x, 160, z), Vector3.new(0, -220, 0), terrainParams)
	if not hit or hit.Material == Enum.Material.Water or hit.Position.Y > 40 then
		return false
	end
	ItemFactory.slime(pickWeighted(band.Weights), nil, CFrame.new(hit.Position + Vector3.new(0, 3, 0)))
	return true
end

local function spawnerTick()
	for _, sp in spawners do
		if math.random() > Config.Wild.ProduceChance then
			continue
		end
		if ItemFactory.itemCount() >= Config.World.MaxItems then
			return
		end
		local near = Workspace:GetPartBoundsInRadius(sp.Position, 7, itemOverlap)
		if #near < Config.Wild.SpawnerItemCap then
			local offset = Vector3.new(math.random(-20, 20) / 10, 0, math.random(-20, 20) / 10)
			ItemFactory.food(sp.Kind, sp.Position + offset, randomDir() * 3)
		end
	end
end

local function feederTick()
	for _, plot in PlotService.Plots do
		if not hasUpgrade(plot, "Feeder") then
			continue
		end
		local foods = 0
		for _, inst in ItemFactory.Items:GetChildren() do
			if inst:GetAttribute("Plot") == plot.Index and inst:GetAttribute("Kind") == "food" then
				foods += 1
			end
		end
		if foods >= Config.Plot.FeederFoodCap then
			continue
		end
		-- feed whatever the residents actually eat
		local wants: { string } = {}
		for model in states do
			local root = model.PrimaryPart
			if root and root:GetAttribute("Plot") == plot.Index then
				local a = root:GetAttribute("A") :: string
				local b = root:GetAttribute("B") :: string?
				for food in Config.Foods do
					if ItemIds.eats(a, b, food) then
						table.insert(wants, food)
					end
				end
			end
		end
		if #wants > 0 then
			for _ = 1, 2 do
				ItemFactory.food(wants[math.random(1, #wants)], plot.FeederPoint, randomDir() * 6 + Vector3.new(0, 8, 0))
			end
			FxRemote:FireAllClients("feed", plot.FeederPoint)
		end
	end
end

----------------------------------------------------------------------
function SlimeService.init(mapSpawners: { { Position: Vector3, Kind: string } })
	spawners = mapSpawners

	local function track(child: Instance)
		if child:IsA("Model") then
			local t = now()
			states[child] = {
				NextThink = t + math.random() * 2,
				LastAte = t,
				NextPassive = t + S.PassiveInterval * (0.4 + math.random() * 0.6),
				LooseSince = nil,
				Producing = false,
			}
		end
	end
	ItemFactory.Slimes.ChildAdded:Connect(track)
	ItemFactory.Slimes.ChildRemoved:Connect(function(child)
		states[child :: Model] = nil
	end)
	for _, c in ItemFactory.Slimes:GetChildren() do
		track(c)
	end

	-- brain loop: 10Hz scan, each slime only thinks when its timer is up
	task.spawn(function()
		while true do
			task.wait(0.1)
			local t = now()
			for model, st in states do
				if t >= st.NextThink and model.Parent then
					local ok, err = pcall(think, model, st, t)
					if not ok then
						warn("[Slime] think:", err)
						st.NextThink = t + 2
					end
				end
			end
		end
	end)

	local function every(interval: number, fn: () -> (), name: string)
		task.spawn(function()
			while true do
				task.wait(interval)
				local ok, err = pcall(fn)
				if not ok then
					warn(`[Slime] {name}:`, err)
				end
			end
		end)
	end
	every(1, classifyTick, "classify")
	every(Config.Wild.ProduceInterval, spawnerTick, "spawners")
	every(Config.Plot.FeederInterval, feederTick, "feeder")
	every(Config.Wild.SpawnInterval, function()
		if wildCount() < Config.Wild.MaxSlimes then
			spawnWild()
		end
	end, "wild")

	-- initial population
	for _ = 1, math.floor(Config.Wild.MaxSlimes * 0.6) do
		spawnWild()
	end
end

return SlimeService
