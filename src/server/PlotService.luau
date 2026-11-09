--!strict
-- Player ranches ("plots"). Max 5 per server, one per player, auto-assigned.
--
-- Each plot is a square corral of translucent honeycomb energy walls on posts.
-- The security track raises the walls (animated on the client), then adds an
-- Air Net roof, longer gate locks, intrusion alarms and thief tagging.
--
-- Server is the authority on who may be inside a LOCKED corral: walls and nets
-- physically block normal players, and anyone who ends up inside without a
-- legit way in (noclip, teleport, standing on props) gets ejected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local Collision = require(script.Parent.Collision)
local DataService = require(script.Parent.DataService)
local ItemFactory = require(script.Parent.ItemFactory)

local P = Config.Plot
local HALF = P.Size / 2
local GATE = P.GateWidth / 2
local FLOOR = P.FloorTop

local NotifyRemote = Remotes.event("Notify")
local FxRemote = Remotes.event("Fx")

export type Panel = { Part: BasePart, Rail: BasePart, Mid: Vector3, Dir: Vector3, Len: number }
export type Post = { Part: BasePart, Cap: BasePart, Pos: Vector3, IsGate: boolean }
export type Plot = {
	Index: number,
	CFrame: CFrame,
	Model: Model,
	Owner: Player?,
	Panels: { Panel },
	Posts: { Post },
	Net: BasePart,
	Barrier: BasePart,
	SlimeField: BasePart,
	SignAnchor: BasePart,
	SignName: TextLabel,
	SignTier: TextLabel,
	Screen: TextLabel,
	ScreenText: string,
	Utilities: { [string]: Model },
	CollectorPoint: Vector3,
	FeederPoint: Vector3,
	Locked: boolean,
	LockEnds: number,
	Inside: { [Player]: boolean },
	AlarmAt: { [Player]: number },
	LOSParts: { BasePart },
}

local PlotService = {}
PlotService.Plots = {} :: { Plot }

local plotsFolder: Folder
local byOwner: { [Player]: Plot } = {}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function notify(player: Player, text: string, kind: string?)
	NotifyRemote:FireClient(player, text, kind or "info")
end
PlotService.notify = notify

local function mk(className: string, props: { [string]: any }, parent: Instance): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
		if props.CanTouch == nil then
			inst.CanTouch = false
		end
	end
	inst.Parent = parent
	return inst
end

local function tierOf(plot: Plot)
	local data = if plot.Owner then DataService.get(plot.Owner) else nil
	return Config.SecurityTiers[if data then data.Security else 1], data
end

local function jetpackValue(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return Config.VacUpgrades.Jetpack.Values[data.Vac.Jetpack] or 0
end

function PlotService.isInside(plot: Plot, pos: Vector3, extraHeight: number?): boolean
	local l = plot.CFrame:PointToObjectSpace(pos)
	local tier = tierOf(plot)
	return math.abs(l.X) <= HALF + 0.5
		and math.abs(l.Z) <= HALF + 0.5
		and l.Y > -3
		and l.Y < FLOOR + tier.WallHeight + (extraHeight or 25)
end

function PlotService.plotAt(pos: Vector3): Plot?
	for _, plot in PlotService.Plots do
		if PlotService.isInside(plot, pos) then
			return plot
		end
	end
	return nil
end

function PlotService.plotOf(player: Player): Plot?
	return byOwner[player]
end

function PlotService.randomInteriorPoint(plot: Plot, y: number?): Vector3
	local r = HALF - 5
	return plot.CFrame:PointToWorldSpace(Vector3.new(math.random() * 2 * r - r, FLOOR + (y or 3), math.random() * 2 * r - r))
end

-- Parts that block vac line-of-sight. The owner's own fence never blocks them.
function PlotService.losBlockers(forPlayer: Player): { BasePart }
	local out = {}
	for _, plot in PlotService.Plots do
		if plot.Owner ~= forPlayer then
			table.move(plot.LOSParts, 1, #plot.LOSParts, #out + 1, out)
		end
	end
	return out
end

local function rebuildLOS(plot: Plot)
	local list = {}
	for _, panel in plot.Panels do
		table.insert(list, panel.Part)
	end
	if plot.Net.Parent then
		table.insert(list, plot.Net)
	end
	if plot.Barrier.Parent then
		table.insert(list, plot.Barrier)
	end
	plot.LOSParts = list
end

----------------------------------------------------------------------
-- construction
----------------------------------------------------------------------
local METAL = Color3.fromRGB(58, 66, 88)
local SLAB = Color3.fromRGB(214, 220, 232)

local function segments(): { { Vector3 } }
	local H = HALF
	return {
		{ Vector3.new(-H, 0, -H), Vector3.new(-GATE, 0, -H) }, -- front, left of gate
		{ Vector3.new(GATE, 0, -H), Vector3.new(H, 0, -H) }, -- front, right of gate
		{ Vector3.new(H, 0, -H), Vector3.new(H, 0, H) },
		{ Vector3.new(H, 0, H), Vector3.new(-H, 0, H) },
		{ Vector3.new(-H, 0, H), Vector3.new(-H, 0, -H) },
	}
end

local function buildUtilities(plot: Plot)
	local cf = plot.CFrame
	local function utilModel(name: string): Model
		local m = Instance.new("Model")
		m.Name = name
		return m
	end

	-- Gem Collector: a silo in the back-right corner
	local col = utilModel("Collector")
	local cpos = Vector3.new(HALF - 4, FLOOR, HALF - 4)
	mk("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 3.4, 3.4), CFrame = cf * CFrame.new(cpos + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(235, 240, 250), Material = Enum.Material.SmoothPlastic }, col)
	mk("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3.7, 3.7), CFrame = cf * CFrame.new(cpos + Vector3.new(0, 5.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Config.Fence.Color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }, col)
	mk("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), CFrame = cf * CFrame.new(cpos + Vector3.new(0, 7, 0)), Color = Config.Fence.Color, Material = Enum.Material.Glass, Transparency = 0.4 }, col)
	plot.CollectorPoint = cf:PointToWorldSpace(cpos + Vector3.new(0, 8, 0))
	plot.Utilities.Collector = col

	-- Auto Feeder: hopper in the back-left corner
	local feed = utilModel("Feeder")
	local fpos = Vector3.new(-HALF + 4, FLOOR, HALF - 4)
	mk("Part", { Size = Vector3.new(3.4, 5, 3.4), CFrame = cf * CFrame.new(fpos + Vector3.new(0, 2.5, 0)), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.SmoothPlastic }, feed)
	mk("Part", { Size = Vector3.new(3.6, 0.4, 3.6), CFrame = cf * CFrame.new(fpos + Vector3.new(0, 4, 0)), Color = Config.Fence.Color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }, feed)
	mk("WedgePart", { Size = Vector3.new(3.4, 1.6, 3.4), CFrame = cf * CFrame.new(fpos + Vector3.new(0, 5.8, 0)), Color = Color3.fromRGB(230, 170, 100) }, feed)
	plot.FeederPoint = cf:PointToWorldSpace(fpos + Vector3.new(2.5, 6, -2.5))
	plot.Utilities.Feeder = feed

	-- Music Box: little speaker by the back wall, sparkles while it plays
	local music = utilModel("MusicBox")
	local mpos = Vector3.new(0, FLOOR, HALF - 3)
	local box = mk("Part", { Size = Vector3.new(2.4, 2, 2.4), CFrame = cf * CFrame.new(mpos + Vector3.new(0, 1, 0)), Color = Color3.fromRGB(190, 140, 255), Material = Enum.Material.SmoothPlastic }, music)
	mk("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.6, 1.6), CFrame = cf * CFrame.new(mpos + Vector3.new(0, 1, -1.25)) * CFrame.Angles(0, math.pi / 2, 0), Color = Color3.fromRGB(40, 30, 60), CanCollide = false }, music)
	local att = mk("Attachment", { Position = Vector3.new(0, 1.4, 0) }, box)
	mk("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 4,
		Lifetime = NumberRange.new(1.5, 2.2),
		Speed = NumberRange.new(2, 3),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new(0.5, 0),
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 255)),
	}, att)
	plot.Utilities.MusicBox = music

	for _, m in plot.Utilities do
		m.Parent = nil
	end
end

local function buildPlot(index: number): Plot
	local def = Config.Map.Plots[index]
	local cf = CFrame.lookAt(def.Center, def.Center + def.Facing)
	local model = Instance.new("Model")
	model.Name = `Plot{index}`
	model:SetAttribute("Index", index)
	model.Parent = plotsFolder

	local fenceGroup = Collision.fence(index)

	-- slab + grass
	mk("Part", { Name = "Slab", Size = Vector3.new(P.Size + 4, FLOOR, P.Size + 4), CFrame = cf * CFrame.new(0, FLOOR / 2, 0), Color = SLAB, Material = Enum.Material.Concrete }, model)
	mk("Part", { Name = "Grass", Size = Vector3.new(P.Size - 0.2, 0.05, P.Size - 0.2), CFrame = cf * CFrame.new(0, FLOOR + 0.025, 0), Color = Color3.fromRGB(128, 210, 120), Material = Enum.Material.Grass, CanCollide = false, CastShadow = false }, model)
	mk("WedgePart", { Name = "Ramp", Size = Vector3.new(P.GateWidth + 4, FLOOR, 4), CFrame = cf * CFrame.new(0, FLOOR / 2, -HALF - 4), Color = SLAB, Material = Enum.Material.Concrete }, model)

	local plot: Plot = {
		Index = index,
		CFrame = cf,
		Model = model,
		Owner = nil,
		Panels = {},
		Posts = {},
		Net = nil :: any,
		Barrier = nil :: any,
		SlimeField = nil :: any,
		SignAnchor = nil :: any,
		SignName = nil :: any,
		SignTier = nil :: any,
		Screen = nil :: any,
		ScreenText = "",
		Utilities = {},
		CollectorPoint = Vector3.zero,
		FeederPoint = Vector3.zero,
		Locked = false,
		LockEnds = 0,
		Inside = {},
		AlarmAt = {},
		LOSParts = {},
	}

	-- walls + posts
	local postKeys: { [string]: boolean } = {}
	local function addPost(pos: Vector3, isGate: boolean)
		local k = `{math.round(pos.X)},{math.round(pos.Z)}`
		if postKeys[k] then
			return
		end
		postKeys[k] = true
		local post = mk("Part", { Name = "Post", Size = Vector3.new(1.1, 1, 1.1), Color = METAL, Material = Enum.Material.Metal, CollisionGroup = fenceGroup }, model)
		local cap = mk("Part", { Name = "Cap", Size = Vector3.new(1.5, 0.45, 1.5), Color = Config.Fence.Color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }, model)
		post:SetAttribute("Riser", "Grow")
		cap:SetAttribute("Riser", "Move")
		table.insert(plot.Posts, { Part = post, Cap = cap, Pos = pos, IsGate = isGate })
	end

	for _, seg in segments() do
		local a, b = seg[1], seg[2]
		local len = (b - a).Magnitude
		local n = math.ceil(len / P.SegmentMax)
		local dir = (b - a).Unit
		for i = 0, n - 1 do
			local pa = a + dir * (len * i / n)
			local pb = a + dir * (len * (i + 1) / n)
			local mid = (pa + pb) / 2
			local w = (pb - pa).Magnitude
			local panel = mk("Part", {
				Name = "Wall",
				Size = Vector3.new(w, 1, 0.35),
				Color = Config.Fence.Color,
				Material = Enum.Material.Glass,
				Transparency = Config.Fence.PanelTransparency,
				CastShadow = false,
				CollisionGroup = fenceGroup,
			}, model)
			panel:SetAttribute("Honeycomb", "Wall")
			panel:SetAttribute("Riser", "Grow")
			local rail = mk("Part", { Name = "Rail", Size = Vector3.new(w, 0.3, 0.55), Color = Config.Fence.Color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }, model)
			rail:SetAttribute("Riser", "Move")
			mk("Part", {
				Name = "BaseRail",
				Size = Vector3.new(w, 0.6, 0.7),
				CFrame = cf * CFrame.fromMatrix(mid + Vector3.new(0, FLOOR + 0.3, 0), dir, Vector3.yAxis),
				Color = METAL,
				Material = Enum.Material.Metal,
				CollisionGroup = fenceGroup,
			}, model)
			table.insert(plot.Panels, { Part = panel, Rail = rail, Mid = mid, Dir = dir, Len = w })
			addPost(pa, math.abs(pa.Z + HALF) < 0.01 and math.abs(math.abs(pa.X) - GATE) < 0.01)
			addPost(pb, math.abs(pb.Z + HALF) < 0.01 and math.abs(math.abs(pb.X) - GATE) < 0.01)
		end
	end

	-- gate: invisible-ish slime field (always) + lock barrier (only while locked)
	plot.SlimeField = mk("Part", { Name = "SlimeField", Size = Vector3.new(P.GateWidth, 1, 0.3), Color = Config.Fence.Color, Material = Enum.Material.Glass, Transparency = 0.9, CastShadow = false, CollisionGroup = "SlimeField", CanQuery = false }, model)
	plot.SlimeField:SetAttribute("Riser", "Grow")
	plot.Barrier = mk("Part", { Name = "LockBarrier", Size = Vector3.new(P.GateWidth, 1, 0.45), Color = Config.Fence.LockColor, Material = Enum.Material.Glass, Transparency = 0.5, CastShadow = false, CollisionGroup = fenceGroup }, model)
	plot.Barrier:SetAttribute("Honeycomb", "Barrier")
	plot.Barrier:SetAttribute("Riser", "Grow")
	plot.Barrier.Parent = nil

	plot.Net = mk("Part", { Name = "AirNet", Size = Vector3.new(P.Size, 0.25, P.Size), Color = Config.Fence.Color, Material = Enum.Material.Glass, Transparency = Config.Fence.PanelTransparency + 0.1, CastShadow = false, CollisionGroup = fenceGroup }, model)
	plot.Net:SetAttribute("Honeycomb", "Net")
	plot.Net:SetAttribute("Riser", "Move")
	plot.Net.Parent = nil

	-- owner sign floating over the gate
	plot.SignAnchor = mk("Part", { Name = "SignAnchor", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CanQuery = false }, model)
	plot.SignAnchor:SetAttribute("Riser", "Move")
	local bb = mk("BillboardGui", { Size = UDim2.fromOffset(280, 74), MaxDistance = 140, LightInfluence = 0, ResetOnSpawn = false }, plot.SignAnchor)
	plot.SignName = mk("TextLabel", { Size = UDim2.fromScale(1, 0.6), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Text = "Open Ranch" }, bb)
	plot.SignTier = mk("TextLabel", { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Config.Fence.Color, TextStrokeTransparency = 0.5, Text = "" }, bb)

	-- consoles outside the gate
	local function console(x: number, accent: Color3, title: string): (BasePart, TextLabel)
		mk("Part", { Name = "Console", Size = Vector3.new(1.8, 3.4, 1.8), CFrame = cf * CFrame.new(x, 1.7, -HALF - 6), Color = METAL, Material = Enum.Material.Metal }, model)
		local screen = mk("Part", { Name = "Screen", Size = Vector3.new(3.4, 2.2, 0.3), CFrame = cf * CFrame.new(x, 3.9, -HALF - 6) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(20, 24, 36) }, model)
		local g = mk("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0, MaxDistance = 80 }, screen)
		mk("TextLabel", { Size = UDim2.fromScale(1, 0.35), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = accent, Text = title }, g)
		local body = mk("TextLabel", { Size = UDim2.fromScale(1, 0.6), Position = UDim2.fromScale(0, 0.38), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "" }, g)
		return screen, body
	end
	local lockScreen, lockBody = console(-GATE - 4, Config.Fence.Color, "GATE")
	plot.Screen = lockBody
	local upgScreen, upgBody = console(GATE + 4, Color3.fromRGB(255, 210, 110), "UPGRADES")
	upgBody.Text = "Ranch Tech"

	local lockPrompt = mk("ProximityPrompt", { ActionText = "Lock Gate", ObjectText = "Ranch Security", HoldDuration = 0.35, MaxActivationDistance = 11, RequiresLineOfSight = false }, lockScreen)
	lockPrompt:SetAttribute("OwnerOnly", true)
	local upgPrompt = mk("ProximityPrompt", { ActionText = "Ranch Upgrades", ObjectText = "Ranch Tech", HoldDuration = 0.15, MaxActivationDistance = 11, RequiresLineOfSight = false }, upgScreen)
	upgPrompt:SetAttribute("OwnerOnly", true)

	lockPrompt.Triggered:Connect(function(player)
		PlotService.tryLock(plot, player)
	end)
	upgPrompt.Triggered:Connect(function(player)
		if plot.Owner ~= player then
			notify(player, "That's not your ranch.", "error")
			return
		end
		Remotes.event("OpenShop"):FireClient(player, "Ranch")
	end)

	buildUtilities(plot)
	return plot
end

----------------------------------------------------------------------
-- state -> visuals
----------------------------------------------------------------------
local function layoutWalls(plot: Plot, h: number)
	local cf = plot.CFrame
	for _, panel in plot.Panels do
		panel.Part.Size = Vector3.new(panel.Len, h, 0.35)
		panel.Part.CFrame = cf * CFrame.fromMatrix(panel.Mid + Vector3.new(0, FLOOR + h / 2, 0), panel.Dir, Vector3.yAxis)
		panel.Rail.CFrame = cf * CFrame.fromMatrix(panel.Mid + Vector3.new(0, FLOOR + h, 0), panel.Dir, Vector3.yAxis)
	end
	for _, post in plot.Posts do
		local ph = FLOOR + h + 0.6
		post.Part.Size = Vector3.new(if post.IsGate then 1.6 else 1.1, ph, if post.IsGate then 1.6 else 1.1)
		post.Part.CFrame = cf * CFrame.new(post.Pos + Vector3.new(0, ph / 2, 0))
		post.Cap.CFrame = cf * CFrame.new(post.Pos + Vector3.new(0, ph + 0.2, 0))
	end
	local gateCF = cf * CFrame.new(0, FLOOR + h / 2, -HALF)
	plot.SlimeField.Size = Vector3.new(P.GateWidth, h, 0.3)
	plot.SlimeField.CFrame = gateCF
	plot.Barrier.Size = Vector3.new(P.GateWidth, h, 0.45)
	plot.Barrier.CFrame = gateCF
	plot.Net.CFrame = cf * CFrame.new(0, FLOOR + h + 0.12, 0)
	plot.SignAnchor.CFrame = cf * CFrame.new(0, FLOOR + h + 4, -HALF)
end

local function refreshGateColors(plot: Plot)
	local c = if plot.Locked then Config.Fence.LockColor else Color3.fromRGB(120, 255, 170)
	for _, post in plot.Posts do
		if post.IsGate then
			post.Cap.Color = c
		end
	end
end

function PlotService.applyState(plot: Plot)
	local tier, data = tierOf(plot)
	local h = tier.WallHeight
	local prev = plot.Model:GetAttribute("WallHeight")
	layoutWalls(plot, h)
	plot.Net.Parent = if tier.AirNet then plot.Model else nil

	for key, m in plot.Utilities do
		m.Parent = if data and data.PlotUpgrades[key] then plot.Model else nil
	end

	if plot.Owner then
		plot.SignName.Text = `{plot.Owner.DisplayName}'s Ranch`
		local tierIndex = (data :: any).Security
		plot.SignTier.Text = string.rep("★", tierIndex) .. string.rep("☆", #Config.SecurityTiers - tierIndex) .. `  {tier.Name}`
		plot.Model:SetAttribute("OwnerUserId", plot.Owner.UserId)
		plot.Model:SetAttribute("Tier", tierIndex)
	else
		plot.SignName.Text = "Open Ranch"
		plot.SignTier.Text = "Join to claim"
		plot.Model:SetAttribute("OwnerUserId", 0)
		plot.Model:SetAttribute("Tier", 1)
	end
	if prev ~= h then
		plot.Model:SetAttribute("PrevWallHeight", prev or h)
		plot.Model:SetAttribute("WallHeight", h)
	end
	refreshGateColors(plot)
	rebuildLOS(plot)
end

----------------------------------------------------------------------
-- locking / ejecting
----------------------------------------------------------------------
local function ejectCharacter(plot: Plot, player: Player, reason: string)
	local char = player.Character
	if not char then
		return
	end
	local out = plot.CFrame * CFrame.new(math.random(-3, 3), FLOOR + 3, -HALF - 11)
	char:PivotTo(CFrame.lookAt(out.Position, out.Position + plot.CFrame.LookVector))
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	notify(player, reason, "error")
end

local function unlock(plot: Plot)
	plot.Locked = false
	plot.Barrier.Parent = nil
	plot.Model:SetAttribute("Locked", false)
	refreshGateColors(plot)
	rebuildLOS(plot)
	FxRemote:FireAllClients("lock", plot.Index, false)
	if plot.Owner then
		notify(plot.Owner, "Your gate unlocked. Lock it again at the console!", "warn")
	end
end

function PlotService.tryLock(plot: Plot, player: Player)
	if plot.Owner ~= player then
		notify(player, "That's not your ranch.", "error")
		return
	end
	if plot.Locked then
		notify(player, `Already locked ({math.ceil(plot.LockEnds - Workspace:GetServerTimeNow())}s left)`, "info")
		return
	end
	local tier = tierOf(plot)
	plot.Locked = true
	plot.LockEnds = Workspace:GetServerTimeNow() + tier.LockSeconds
	plot.Barrier.Parent = plot.Model
	plot.Model:SetAttribute("Locked", true)
	plot.Model:SetAttribute("LockEnds", plot.LockEnds)
	refreshGateColors(plot)
	rebuildLOS(plot)
	FxRemote:FireAllClients("lock", plot.Index, true)
	notify(player, `Gate locked for {tier.LockSeconds}s`, "good")

	-- security sweep: nobody else stays inside a freshly locked corral
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and PlotService.isInside(plot, root.Position) then
				ejectCharacter(plot, other, "Security sweep! That ranch just locked.")
			end
		end
	end
end

local function canBeInsideLocked(plot: Plot, player: Player): boolean
	local tier = tierOf(plot)
	if tier.AirNet then
		return false
	end
	-- 1 stud of slack for physics jitter
	return Config.Jetpack.Reach[jetpackValue(player)] + 1 >= tier.WallHeight
end

local function securityTick()
	local now = Workspace:GetServerTimeNow()
	for _, plot in PlotService.Plots do
		if plot.Locked and now >= plot.LockEnds then
			unlock(plot)
		end
		local tier = tierOf(plot)
		local seen: { [Player]: boolean } = {}
		for _, player in Players:GetPlayers() do
			if player == plot.Owner then
				continue
			end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or not PlotService.isInside(plot, root.Position) then
				continue
			end
			if plot.Locked and not canBeInsideLocked(plot, player) then
				ejectCharacter(plot, player, "This ranch is locked.")
				continue
			end
			seen[player] = true
			if not plot.Inside[player] and plot.Owner and tier.Alarm then
				local last = plot.AlarmAt[player] or 0
				if os.clock() - last > P.AlarmCooldown then
					plot.AlarmAt[player] = os.clock()
					notify(plot.Owner, `ALARM: {player.DisplayName} is in your ranch!`, "alarm")
					FxRemote:FireClient(plot.Owner, "alarm", plot.Index)
				end
			end
		end
		plot.Inside = seen

		-- console text
		local text: string
		if not plot.Owner then
			text = "VACANT"
		elseif plot.Locked then
			text = `LOCKED {math.max(0, math.ceil(plot.LockEnds - now))}s`
		else
			text = "OPEN"
		end
		if text ~= plot.ScreenText then
			plot.ScreenText = text
			plot.Screen.Text = text
			plot.Screen.TextColor3 = if plot.Locked then Config.Fence.LockColor else Color3.fromRGB(150, 255, 190)
		end
	end
end

----------------------------------------------------------------------
-- ownership
----------------------------------------------------------------------
local function setCharacterCollision(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local plot = byOwner[player]
	Collision.setCharacterGroup(char, if plot then Collision.owner(plot.Index) else Collision.PLAYERS)
end

local function onCharacter(player: Player, char: Model)
	char:WaitForChild("HumanoidRootPart", 10)
	setCharacterCollision(player)
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			local plot = byOwner[player]
			d.CollisionGroup = if plot then Collision.owner(plot.Index) else Collision.PLAYERS
		end
	end)
	local spawnCF = PlotService.spawnPoint(player)
	if spawnCF then
		task.defer(function()
			if char.Parent then
				char:PivotTo(spawnCF)
			end
		end)
	end
end

function PlotService.spawnPoint(player: Player): CFrame?
	local plot = byOwner[player]
	if not plot then
		return nil
	end
	local pos = plot.CFrame:PointToWorldSpace(Vector3.new(0, FLOOR + 4, -HALF - 10))
	return CFrame.lookAt(pos, pos + plot.CFrame.LookVector)
end

function PlotService.claim(player: Player): Plot?
	for _, plot in PlotService.Plots do
		if plot.Owner == nil then
			plot.Owner = player
			byOwner[player] = plot
			plot.Locked = false
			plot.Barrier.Parent = nil
			plot.Model:SetAttribute("Locked", false)
			PlotService.applyState(plot)
			setCharacterCollision(player)

			-- respawn saved slimes inside the corral
			local data = DataService.get(player)
			if data then
				for _, id in data.Slimes do
					local parsed = ItemIds.parse(id)
					if parsed and parsed.Kind == "slime" then
						ItemFactory.slime(parsed.A, parsed.B, CFrame.new(PlotService.randomInteriorPoint(plot)))
					end
				end
			end
			player:SetAttribute("PlotIndex", plot.Index)
			if player.Character then
				task.spawn(onCharacter, player, player.Character)
			end
			return plot
		end
	end
	notify(player, "All 5 ranches are taken on this server.", "error")
	return nil
end

-- Write the slimes currently inside the corral into the save.
local function snapshot(plot: Plot, data: DataService.Data)
	local cap = Config.Capacity.Levels[data.Capacity]
	local list = {}
	for _, m in ItemFactory.Slimes:GetChildren() do
		local root = (m :: Model).PrimaryPart
		if root and PlotService.isInside(plot, root.Position) then
			if #list >= cap then
				break
			end
			table.insert(list, root:GetAttribute("Id") :: string)
		end
	end
	data.Slimes = list
end

-- Called on leave BEFORE the data is released, so nothing can be stolen
-- between the snapshot and the corral being cleared (no dupes).
function PlotService.vacate(player: Player)
	local plot = byOwner[player]
	if not plot then
		return
	end
	local data = DataService.get(player)
	if data then
		snapshot(plot, data)
	end
	for _, m in ItemFactory.Slimes:GetChildren() do
		local root = (m :: Model).PrimaryPart
		if root and PlotService.isInside(plot, root.Position) then
			m:Destroy()
		end
	end
	for _, item in ItemFactory.Items:GetChildren() do
		if PlotService.isInside(plot, (item :: BasePart).Position) then
			item:Destroy()
		end
	end
	byOwner[player] = nil
	plot.Owner = nil
	plot.Locked = false
	plot.Barrier.Parent = nil
	plot.Inside = {}
	plot.AlarmAt = {}
	plot.Model:SetAttribute("Locked", false)
	PlotService.applyState(plot)
end

-- Someone vacuumed a slime out of a plot they don't own.
function PlotService.onStolen(plot: Plot, thief: Player, display: string)
	if not plot.Owner then
		return
	end
	notify(plot.Owner, `{thief.DisplayName} stole your {display}!`, "alarm")
	notify(thief, `Stolen: {display}. Get it home!`, "good")
	local tier = tierOf(plot)
	if tier.TagThieves then
		local hum = thief.Character and thief.Character:FindFirstChildOfClass("Humanoid")
		if hum and not thief:GetAttribute("Tagged") then
			thief:SetAttribute("Tagged", true)
			local before = hum.WalkSpeed
			hum.WalkSpeed = before * 0.65
			task.delay(6, function()
				if hum.Parent then
					hum.WalkSpeed = before
				end
				thief:SetAttribute("Tagged", nil)
			end)
		end
	end
end

-- Call once per player, before claim().
function PlotService.hookPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
end

function PlotService.init()
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "RanchPlots"
	plotsFolder.Parent = workspace
	for i = 1, Config.MaxPlots do
		local plot = buildPlot(i)
		PlotService.Plots[i] = plot
		PlotService.applyState(plot)
	end

	DataService.onBeforeSave(function(player, data)
		local plot = byOwner[player]
		if plot then
			snapshot(plot, data)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(P.EjectCheckInterval)
			local ok, err = pcall(securityTick)
			if not ok then
				warn("[Plot] security tick:", err)
			end
		end
	end)
end

return PlotService
