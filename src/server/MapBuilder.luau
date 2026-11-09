--!strict
-- Builds the long, narrow ranch valley out of Terrain + a small number of parts.
--
--   south  [sea] [beach + dock] [hub: spawn, house, Gem Exchange, Vac Workshop]
--          [ranch row: 5 plots alternating sides of a dirt path]
--          [rock arch] [the Wilds: mesas, fruit trees, root patches, wild slimes]  north
--
-- Everything is seeded so every server builds the same map. Terrain is cheap on
-- mobile; decor parts are anchored, non-touch, and mostly shadowless.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local M = Config.Map
local MapBuilder = {}

export type Spawner = { Position: Vector3, Kind: string }
export type MapRefs = {
	Spawners: { Spawner },
	Intake: BasePart,
	ExchangeBoard: BasePart,
	ExchangePrompt: ProximityPrompt,
	WorkshopPrompt: ProximityPrompt,
	ExchangePosition: Vector3,
	WorkshopPosition: Vector3,
}

local rng = Random.new(M.Seed) -- terrain
local decorRng = Random.new(M.Seed + 1) -- parts (independent so baked terrain does not shift decor)
local mapFolder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	for k, v in props do
		(p :: any)[k] = v
	end
	if not props.Parent then
		p.Parent = mapFolder
	end
	return p
end

local function noise(x: number, y: number): number
	return math.noise(x, y, M.Seed / 1000)
end

----------------------------------------------------------------------
-- Lighting: warm pastel haze, saturated colours, soft bloom
----------------------------------------------------------------------
local function setupLighting()
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(95, 85, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 135, 165)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true

	local function ensure(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
		return inst
	end

	local atmo = ensure("Atmosphere", "RanchAtmosphere") :: Atmosphere
	atmo.Density = 0.32
	atmo.Offset = 0.15
	atmo.Color = Color3.fromRGB(255, 205, 190)
	atmo.Decay = Color3.fromRGB(150, 120, 170)
	atmo.Glare = 0.25
	atmo.Haze = 1.4

	local cc = ensure("ColorCorrectionEffect", "RanchColor") :: ColorCorrectionEffect
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 248, 242)

	local bloom = ensure("BloomEffect", "RanchBloom") :: BloomEffect
	bloom.Intensity = 0.55
	bloom.Size = 22
	bloom.Threshold = 1.6

	local rays = ensure("SunRaysEffect", "RanchRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.7
end

----------------------------------------------------------------------
-- Terrain
----------------------------------------------------------------------
local function region(min: Vector3, max: Vector3): Region3
	return Region3.new(min, max):ExpandToGrid(4)
end

local function buildTerrain()
	local T = workspace.Terrain
	T:Clear()

	T:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(122, 206, 112))
	T:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(96, 190, 150))
	T:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(196, 146, 168))
	T:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(238, 178, 140))
	T:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(246, 222, 172))
	T:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(176, 134, 98))
	T:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(205, 195, 185))
	T:SetMaterialColor(Enum.Material.Salt, Color3.fromRGB(250, 205, 225))
	T.WaterColor = Color3.fromRGB(70, 190, 220)
	T.WaterTransparency = 0.55
	T.WaterWaveSize = 0.12
	T.WaterWaveSpeed = 8
	T.WaterReflectance = 0.6

	-- base slab, top at y = 0
	T:FillBlock(CFrame.new(0, -10, 380), Vector3.new(320, 20, 1280), Enum.Material.Grass)

	-- sea + stepped beach slope
	T:FillBlock(CFrame.new(0, -10, -210), Vector3.new(320, 20, 120), Enum.Material.Air)
	T:FillBlock(CFrame.new(0, -26, -210), Vector3.new(320, 12, 120), Enum.Material.Sand)
	T:FillBlock(CFrame.new(0, -5, -130), Vector3.new(320, 10, 40), Enum.Material.Sand)
	for k = 1, 5 do
		local top = -k * 3.6
		T:FillBlock(CFrame.new(0, top - 5, M.SeaEdgeZ - (k - 0.5) * 6), Vector3.new(320, 10, 6), Enum.Material.Sand)
	end
	T:FillBlock(CFrame.new(0, -11, -215), Vector3.new(320, 18, 130), Enum.Material.Water)

	-- hub plaza and the dirt path down the ranch row
	T:ReplaceMaterial(region(Vector3.new(-26, -4, -100), Vector3.new(26, 0, -8)), 4,
		Enum.Material.Grass, Enum.Material.Cobblestone)
	T:ReplaceMaterial(region(Vector3.new(-M.PathHalfWidth, -4, -8), Vector3.new(M.PathHalfWidth, 0, M.GateZ[2] + 10)), 4,
		Enum.Material.Grass, Enum.Material.Ground)

	-- wilds floor
	T:ReplaceMaterial(region(Vector3.new(-160, -8, M.WildZ[1]), Vector3.new(160, 0, M.EndZ + 40)), 4,
		Enum.Material.Grass, Enum.Material.LeafyGrass)
	for _ = 1, 26 do
		local x = rng:NextNumber(-60, 60)
		local z = rng:NextNumber(M.WildZ[1] + 10, M.EndZ - 10)
		local r = rng:NextNumber(6, 13)
		T:FillBall(Vector3.new(x, -r + 0.6, z), r, Enum.Material.Sand)
	end

	-- cliffs along both sides
	for z = M.SeaEdgeZ - 20, M.EndZ + 20, 10 do
		for _, side in { -1, 1 } do
			local inner: number
			if z >= M.GateZ[1] and z <= M.GateZ[2] then
				inner = 24
			elseif z > M.GateZ[2] then
				inner = 64 + noise(z / 70, side * 3) * 12
			else
				inner = M.HalfWidth + noise(z / 90, side) * 6
			end
			local height = 52 + noise(z / 55, side * 7 + 1) * 26
			if z < M.HubZ[1] then
				height *= 0.55 -- lower near the sea so the ocean is visible
			end
			T:FillBlock(CFrame.new(side * (inner + 45), height / 2 - 6, z), Vector3.new(90, height + 12, 12),
				Enum.Material.Rock)
			-- rounded inner face; max inward reach is inner - 2, clear of plot slabs
			T:FillBall(Vector3.new(side * (inner + 9), height * 0.45, z), 8 + noise(z / 20, side) * 3,
				Enum.Material.Rock)
			T:FillBlock(CFrame.new(side * (inner + 48), height + 0.5, z), Vector3.new(84, 3, 12), Enum.Material.Grass)
		end
	end

	-- rock arch between ranch and wilds
	T:FillBlock(CFrame.new(0, 36, (M.GateZ[1] + M.GateZ[2]) / 2), Vector3.new(64, 16, 34), Enum.Material.Rock)
	T:FillBall(Vector3.new(0, 44, (M.GateZ[1] + M.GateZ[2]) / 2), 16, Enum.Material.Rock)

	-- end wall
	T:FillBlock(CFrame.new(0, 40, M.EndZ + 40), Vector3.new(320, 100, 60), Enum.Material.Rock)

	-- wild mesas
	for _ = 1, 10 do
		local x = rng:NextNumber(-50, 50)
		if math.abs(x) < 14 then
			x = 14 * math.sign(x + 0.01)
		end
		local z = rng:NextNumber(M.WildZ[1] + 30, M.EndZ - 20)
		local h = rng:NextNumber(10, 28)
		local r = rng:NextNumber(5, 10)
		T:FillCylinder(CFrame.new(x, h / 2 - 4, z), h + 8, r, Enum.Material.Sandstone)
		T:FillCylinder(CFrame.new(x, h + 0.5, z), 3, r + 0.5, Enum.Material.LeafyGrass)
	end
	-- pink salt boulders
	for _ = 1, 14 do
		local x = rng:NextNumber(-58, 58)
		local z = rng:NextNumber(M.WildZ[1], M.EndZ - 10)
		T:FillBall(Vector3.new(x, 0, z), rng:NextNumber(3, 6), Enum.Material.Salt)
	end

	-- a pond in the wilds
	local pond = Vector3.new(34, 0, 600)
	T:FillCylinder(CFrame.new(pond + Vector3.new(0, -3, 0)), 8, 13, Enum.Material.Air)
	T:FillCylinder(CFrame.new(pond + Vector3.new(0, -8, 0)), 4, 13, Enum.Material.Sand)
	T:FillCylinder(CFrame.new(pond + Vector3.new(0, -3.5, 0)), 6, 12.5, Enum.Material.Water)
end

----------------------------------------------------------------------
-- Decor
----------------------------------------------------------------------
local CANOPY = {
	Color3.fromRGB(255, 170, 200),
	Color3.fromRGB(150, 225, 140),
	Color3.fromRGB(255, 205, 120),
	Color3.fromRGB(170, 215, 255),
}

local function tree(pos: Vector3, h: number, canopy: Color3): Vector3
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, 1.6, 1.6),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(150, 105, 85),
		Material = Enum.Material.Wood,
	})
	local top = pos + Vector3.new(0, h, 0)
	for i = 1, 3 do
		local off = Vector3.new(decorRng:NextNumber(-2, 2), decorRng:NextNumber(-0.5, 1.5), decorRng:NextNumber(-2, 2))
		local s = decorRng:NextNumber(5, 8) * (if i == 1 then 1.2 else 1)
		part({
			Name = "Canopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s),
			Position = top + off,
			Color = canopy,
			CanCollide = false,
			CastShadow = i == 1,
		})
	end
	return top
end

local function lamp(pos: Vector3)
	part({
		Name = "LampPost",
		Size = Vector3.new(0.5, 7, 0.5),
		Position = pos + Vector3.new(0, 3.5, 0),
		Color = Color3.fromRGB(60, 70, 90),
		Material = Enum.Material.Metal,
		CastShadow = false,
	})
	part({
		Name = "LampBulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.3, 1.3, 1.3),
		Position = pos + Vector3.new(0, 7.4, 0),
		Color = Color3.fromRGB(170, 235, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
end

local function sign(cf: CFrame, text: string)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(10, 3, 0.4),
		CFrame = cf * CFrame.new(0, 6, 0),
		Color = Color3.fromRGB(240, 220, 190),
		Material = Enum.Material.Wood,
	})
	for _, x in { -4, 4 } do
		part({
			Size = Vector3.new(0.5, 6, 0.5),
			CFrame = cf * CFrame.new(x, 3, 0.1),
			Color = Color3.fromRGB(150, 105, 85),
			Material = Enum.Material.Wood,
		})
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 30
		g.MaxDistance = 150
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(90, 60, 70)
		l.Text = text
		l.Parent = g
		g.Parent = board
	end
end

local function prompt(parent: Instance, action: string, object: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0.2
	p.MaxActivationDistance = 16
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function buildHub(): (BasePart, BasePart, ProximityPrompt, ProximityPrompt)
	-- spawn pad
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "RanchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = M.SpawnPoint - Vector3.new(0, 2.5, 0)
	spawn.Color = Color3.fromRGB(120, 220, 230)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = mapFolder

	-- ranch house
	local h = M.RanchHouse
	local wall = Color3.fromRGB(250, 235, 215)
	part({ Size = Vector3.new(26, 1, 20), CFrame = h * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(190, 150, 120), Material = Enum.Material.WoodPlanks })
	part({ Size = Vector3.new(26, 12, 1), CFrame = h * CFrame.new(0, 6.5, 9.5), Color = wall })
	part({ Size = Vector3.new(1, 12, 20), CFrame = h * CFrame.new(-12.5, 6.5, 0), Color = wall })
	part({ Size = Vector3.new(1, 12, 20), CFrame = h * CFrame.new(12.5, 6.5, 0), Color = wall })
	part({ Size = Vector3.new(9, 12, 1), CFrame = h * CFrame.new(-8.5, 6.5, -9.5), Color = wall })
	part({ Size = Vector3.new(9, 12, 1), CFrame = h * CFrame.new(8.5, 6.5, -9.5), Color = wall })
	part({ Size = Vector3.new(8, 4, 1), CFrame = h * CFrame.new(0, 10.5, -9.5), Color = wall })
	local roofColor = Color3.fromRGB(110, 175, 205)
	part({ Size = Vector3.new(29, 1, 13.5), CFrame = h * CFrame.new(0, 15.5, -5) * CFrame.Angles(math.rad(-35), 0, 0), Color = roofColor })
	part({ Size = Vector3.new(29, 1, 13.5), CFrame = h * CFrame.new(0, 15.5, 5) * CFrame.Angles(math.rad(35), 0, 0), Color = roofColor })
	part({ Size = Vector3.new(3, 7, 3), CFrame = h * CFrame.new(8, 17, 4), Color = Color3.fromRGB(180, 120, 110), Material = Enum.Material.Brick })

	-- Gem Exchange
	local g = M.GemExchange
	part({ Size = Vector3.new(18, 1, 12), CFrame = g * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(70, 80, 105), Material = Enum.Material.Metal })
	for _, x in { -7.5, 7.5 } do
		part({ Size = Vector3.new(1.2, 13, 1.2), CFrame = g * CFrame.new(x, 6.5, 3), Color = Color3.fromRGB(60, 70, 90), Material = Enum.Material.Metal })
	end
	local board = part({
		Name = "ExchangeBoard",
		Size = Vector3.new(16, 8, 0.6),
		CFrame = g * CFrame.new(0, 9, 3),
		Color = Color3.fromRGB(25, 30, 45),
	})
	part({ Size = Vector3.new(16.6, 0.4, 0.8), CFrame = g * CFrame.new(0, 13.2, 3), Color = Color3.fromRGB(255, 205, 90), Material = Enum.Material.Neon, CastShadow = false })
	-- intake funnel
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.5, 2.5), CFrame = g * CFrame.new(0, 2, -2) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(60, 70, 90), Material = Enum.Material.Metal })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 7, 7), CFrame = g * CFrame.new(0, 4.6, -2) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(80, 90, 115), Material = Enum.Material.Metal })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7.4, 7.4), CFrame = g * CFrame.new(0, 5.4, -2) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(255, 205, 90), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	local intake = part({
		Name = "GemIntake",
		Size = Vector3.new(6, 3, 6),
		CFrame = g * CFrame.new(0, 6.2, -2),
		Transparency = 1,
		CanCollide = false,
		CanTouch = true,
		CanQuery = false,
		CollisionGroup = "Items", -- Touched only fires between collidable groups
	})
	local exchangePrompt = prompt(board, "Sell All Gems", "Gem Exchange")

	-- Vac Workshop
	local w = M.Workshop
	part({ Size = Vector3.new(14, 1, 10), CFrame = w * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(190, 150, 120), Material = Enum.Material.WoodPlanks })
	local bench = part({ Name = "Workbench", Size = Vector3.new(9, 3.5, 3.5), CFrame = w * CFrame.new(0, 2.75, 2), Color = Color3.fromRGB(120, 90, 75), Material = Enum.Material.Wood })
	part({ Size = Vector3.new(12, 8, 0.5), CFrame = w * CFrame.new(0, 5, 4.2), Color = Color3.fromRGB(235, 225, 205), Material = Enum.Material.Wood })
	part({ Size = Vector3.new(10, 0.3, 0.6), CFrame = w * CFrame.new(0, 8.6, 4), Color = Color3.fromRGB(120, 230, 255), Material = Enum.Material.Neon, CastShadow = false })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.6, 1.6), CFrame = w * CFrame.new(-2, 5, 2) * CFrame.Angles(0, math.pi / 2, 0), Color = Color3.fromRGB(110, 205, 255), Material = Enum.Material.Glass, Transparency = 0.3 })
	local workshopPrompt = prompt(bench, "Vac Upgrades", "Vac Workshop")
	sign(w * CFrame.new(0, 0, -6), "VAC WORKSHOP")
	sign(g * CFrame.new(10, 0, -5), "GEM EXCHANGE")

	-- dock out to the sea
	for i = 0, 7 do
		part({
			Name = "Plank",
			Size = Vector3.new(7, 0.6, 4.6),
			Position = Vector3.new(22, -0.2, M.SeaEdgeZ - 2 - i * 5),
			Color = Color3.fromRGB(175, 130, 100),
			Material = Enum.Material.WoodPlanks,
			CastShadow = false,
		})
	end

	return intake, board, exchangePrompt, workshopPrompt
end

local function buildRanchDecor()
	-- path lamps, skipping spots where a plot's gate consoles stand
	local function clearOfPlots(x: number, z: number): boolean
		for _, p in M.Plots do
			if math.sign(p.Center.X) == math.sign(x) and math.abs(p.Center.Z - z) < 18 then
				return false
			end
		end
		return true
	end
	for z = -10, M.GateZ[1] - 10, 20 do
		local side = if (z // 20) % 2 == 0 then 1 else -1
		local x = side * (M.PathHalfWidth + 1.5)
		if clearOfPlots(x, z) then
			lamp(Vector3.new(x, 0, z))
		end
	end
	-- trees on whichever side of the path has no plot at that Z
	for i, p in M.Plots do
		local opposite = Vector3.new(-p.Center.X, 0, p.Center.Z)
		tree(opposite + Vector3.new(-6 * math.sign(opposite.X), 0, -10), decorRng:NextNumber(9, 13), CANOPY[(i % #CANOPY) + 1])
		tree(opposite + Vector3.new(10 * math.sign(opposite.X), 0, 12), decorRng:NextNumber(8, 12), CANOPY[((i + 1) % #CANOPY) + 1])
	end
	sign(CFrame.lookAt(Vector3.new(14, 0, M.GateZ[1] - 8), Vector3.new(14, 0, M.GateZ[1] - 20)), "THE WILDS")
	sign(CFrame.lookAt(Vector3.new(-14, 0, 30), Vector3.new(-14, 0, 10)), "RANCH ROW")
end

local function buildWilds(): { Spawner }
	local spawners: { Spawner } = {}
	for i = 1, 12 do
		local x = decorRng:NextNumber(-55, 55)
		local z = decorRng:NextNumber(M.WildZ[1] + 15, M.EndZ - 15)
		local top = tree(Vector3.new(x, 0, z), decorRng:NextNumber(9, 14), CANOPY[(i % 2) + 1])
		table.insert(spawners, { Position = top - Vector3.new(0, 2, 0), Kind = "Berry" })
	end
	for _ = 1, 9 do
		local x = decorRng:NextNumber(-55, 55)
		local z = decorRng:NextNumber(M.WildZ[1] + 15, M.EndZ - 15)
		part({
			Name = "RootPatch",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 7, 7),
			CFrame = CFrame.new(x, 0.1, z) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(140, 100, 75),
			Material = Enum.Material.Ground,
			CastShadow = false,
		})
		for k = 1, 3 do
			part({
				Name = "Sprout",
				Size = Vector3.new(0.3, 1.4, 0.8),
				CFrame = CFrame.new(x + (k - 2) * 1.6, 1, z) * CFrame.Angles(0, decorRng:NextNumber(0, 3), 0.3),
				Color = Color3.fromRGB(110, 210, 110),
				CanCollide = false,
				CastShadow = false,
			})
		end
		table.insert(spawners, { Position = Vector3.new(x, 2, z), Kind = "Root" })
	end
	return spawners
end

function MapBuilder.build(): MapRefs
	local old = workspace:FindFirstChild("RanchMap")
	if old then
		old:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "RanchMap"
	mapFolder.Parent = workspace

	setupLighting()
	if M.BuildTerrain then
		buildTerrain()
	end
	-- invisible bounds so jetpacks can't hop the cliffs out of the valley
	local length = M.EndZ - M.SeaEdgeZ + 200
	local midZ = (M.EndZ + M.SeaEdgeZ) / 2
	for _, side in { -1, 1 } do
		part({ Name = "Bound", Size = Vector3.new(4, 400, length), Position = Vector3.new(side * (M.HalfWidth + 24), 150, midZ), Transparency = 1, CanQuery = false, CastShadow = false })
	end
	part({ Name = "Bound", Size = Vector3.new(2 * M.HalfWidth + 60, 400, 4), Position = Vector3.new(0, 150, M.SeaEdgeZ - 80), Transparency = 1, CanQuery = false, CastShadow = false })
	part({ Name = "Bound", Size = Vector3.new(2 * M.HalfWidth + 60, 400, 4), Position = Vector3.new(0, 150, M.EndZ + 15), Transparency = 1, CanQuery = false, CastShadow = false })

	local intake, board, exchangePrompt, workshopPrompt = buildHub()
	buildRanchDecor()
	local spawners = buildWilds()

	return {
		Spawners = spawners,
		Intake = intake,
		ExchangeBoard = board,
		ExchangePrompt = exchangePrompt,
		WorkshopPrompt = workshopPrompt,
		ExchangePosition = M.GemExchange.Position,
		WorkshopPosition = M.Workshop.Position,
	}
end

return MapBuilder
