--!strict
-- Every tunable number lives here. Server and client both read this module,
-- but only the server's copy matters for anything that affects gameplay.

local Config = {}

----------------------------------------------------------------------
-- World / performance caps (these are what keep mobile playable)
----------------------------------------------------------------------
Config.MaxPlots = 5 -- also set Server Size = 5 in Game Settings > Places
Config.World = {
	MaxSlimes = 150, -- hard cap across the whole server (corrals + wilds + loose)
	MaxItems = 140, -- food + gems that physically exist
	LooseLifetime = 150, -- seconds before food/gems lying outside corrals despawn
	LooseSlimeLifetime = 240, -- slimes outside any corral and outside the wilds
}

----------------------------------------------------------------------
-- Map layout. Long Z axis, narrow X axis. Ground top is Y = 0.
----------------------------------------------------------------------
Config.Map = {
	Seed = 7311,
	BuildTerrain = true, -- WIPES workspace.Terrain and regenerates it. Set false once you've saved the generated terrain into the place.
	SpawnPoint = Vector3.new(0, 3, -40),
	HalfWidth = 78, -- cliffs start here (inner face wobbles +-6)
	SeaEdgeZ = -150,
	HubZ = { -110, 40 },
	RanchZ = { 40, 440 },
	GateZ = { 440, 475 },
	WildZ = { 475, 900 },
	EndZ = 900,
	PathHalfWidth = 9,
	-- plot centres + which way the gate faces (always toward the centre path)
	Plots = {
		{ Center = Vector3.new(38, 0, 100), Facing = Vector3.new(-1, 0, 0) },
		{ Center = Vector3.new(-38, 0, 170), Facing = Vector3.new(1, 0, 0) },
		{ Center = Vector3.new(38, 0, 240), Facing = Vector3.new(-1, 0, 0) },
		{ Center = Vector3.new(-38, 0, 310), Facing = Vector3.new(1, 0, 0) },
		{ Center = Vector3.new(38, 0, 380), Facing = Vector3.new(-1, 0, 0) },
	},
	GemExchange = CFrame.lookAt(Vector3.new(30, 0, -55), Vector3.new(0, 0, -55)),
	Workshop = CFrame.lookAt(Vector3.new(-30, 0, -20), Vector3.new(0, 0, -20)),
	RanchHouse = CFrame.lookAt(Vector3.new(-36, 0, -78), Vector3.new(0, 0, -60)),
}

----------------------------------------------------------------------
-- Plots
----------------------------------------------------------------------
Config.Plot = {
	Size = 48, -- interior is Size x Size studs
	FloorTop = 1.2, -- slab height above ground
	SegmentMax = 12, -- max wall panel width between posts
	GateWidth = 10,
	EjectCheckInterval = 0.4,
	AlarmCooldown = 20,
	GemCap = 40, -- physical gems allowed to sit in one corral
	FeederInterval = 25,
	FeederFoodCap = 6,
}

-- Security track. Each tier must be bought in order.
-- WallHeight is in studs above the corral floor.
Config.SecurityTiers = {
	{ Name = "Starter Corral", WallHeight = 4, AirNet = false, LockSeconds = 30, Price = 0,
		Desc = "Low walls. Anyone can hop in, and hungry slimes hop out." },
	{ Name = "High Walls", WallHeight = 9, AirNet = false, LockSeconds = 45, Price = 750,
		Desc = "Too tall to jump. Slimes stay put. Jetpacks still clear it." },
	{ Name = "Reinforced Walls", WallHeight = 14, AirNet = false, LockSeconds = 60, Price = 3000, Alarm = true,
		Desc = "Beats a basic jetpack. Alerts you when someone walks in." },
	{ Name = "Air Net", WallHeight = 14, AirNet = true, LockSeconds = 75, Price = 8000, Alarm = true,
		Desc = "Honeycomb roof. Nobody gets in over the top while locked." },
	{ Name = "Fortress Field", WallHeight = 18, AirNet = true, LockSeconds = 90, Price = 20000, Alarm = true,
		TagThieves = true, Desc = "Max walls, longest lock. Thieves get slowed when they steal." },
}

Config.PlotUpgrades = {
	Collector = { Name = "Gem Collector", Price = 1200,
		Desc = "Auto-collects gems in your corral into your Gem Bank." },
	MusicBox = { Name = "Music Box", Price = 1500,
		Desc = "Happier slimes: +25% gem rate and they stay calm longer." },
	Feeder = { Name = "Auto Feeder", Price = 2000,
		Desc = "Drops food into your corral every 25s." },
}

Config.Capacity = {
	Levels = { 12, 18, 24 }, -- slimes saved + producing per corral
	Prices = { 0, 1500, 5000 },
}

----------------------------------------------------------------------
-- Vac tool
----------------------------------------------------------------------
Config.Vac = {
	ToolName = "Vac",
	ConeHalfAngle = 32, -- degrees
	CloseGrabRadius = 4, -- inside this distance, cone angle is ignored
	AbsorbDistance = 3.2,
	AbsorbInterval = 0.12, -- min time between absorbs (gives the pop-pop-pop rhythm)
	ShootCooldown = 0.16,
	ShootSpeed = 72,
	ReVacImmunity = 0.4, -- shooter can't instantly re-suck what they just fired
	AimRate = 20, -- max aim packets/sec accepted
	ServerTick = 1 / 20,
	MaxNozzleOffset = 8, -- sanity: tool nozzle must be this close to the head
}

Config.VacUpgrades = {
	Tank = { Name = "Tank Booster", Values = { 20, 30, 45, 60 }, Prices = { 0, 400, 1500, 4000 },
		Desc = "More of each item per slot." },
	Slots = { Name = "Extra Tank", Values = { 3, 4, 5 }, Prices = { 0, 1000, 4000 },
		Desc = "Carry more item types at once." },
	Power = { Name = "Vac Power", Values = { 14, 18, 23 }, Pull = { 30, 38, 46 }, Prices = { 0, 800, 3000 },
		Desc = "Longer range, stronger pull." },
	Jetpack = { Name = "Jetpack", Values = { 0, 1, 2 }, Prices = { 0, 2500, 9000 },
		Desc = "Hold jump in the air to fly. Level 2 burns longer." },
}

-- Jetpack: fuel seconds per level and how high (studs above takeoff ground)
-- a legit player can reach. Server uses Reach to decide who is allowed
-- inside a locked corral, so keep these in sync with Thrust/Fuel.
Config.Jetpack = {
	Thrust = 18, -- upward velocity while thrusting
	Fuel = { [0] = 0, [1] = 0.3, [2] = 0.8 },
	RechargeRate = 0.5, -- fuel seconds regained per second on the ground
	-- jump (7.2 at default JumpHeight) + thrust * fuel + coast. Change these if
	-- you change JumpHeight/JumpPower, or locked-corral ejects will misfire.
	Reach = { [0] = 7.2, [1] = 12.6, [2] = 21.6 },
}

----------------------------------------------------------------------
-- Slimes, food, gems
----------------------------------------------------------------------
Config.SlimeOrder = { "Bubble", "Pebble", "Fizz", "Glow", "Ember" }

Config.Slimes = {
	Bubble = { Display = "Bubble", Color = Color3.fromRGB(255, 140, 190), Diet = { Berry = true, Root = true }, GemValue = 8 },
	Pebble = { Display = "Pebble", Color = Color3.fromRGB(150, 160, 185), Diet = { Root = true }, GemValue = 14 },
	Fizz = { Display = "Fizz", Color = Color3.fromRGB(90, 205, 255), Diet = { Berry = true }, GemValue = 20 },
	Glow = { Display = "Glow", Color = Color3.fromRGB(185, 120, 255), Diet = { Berry = true }, GemValue = 32 },
	Ember = { Display = "Ember", Color = Color3.fromRGB(255, 135, 60), Diet = { Root = true }, GemValue = 48 },
}

Config.Foods = {
	Berry = { Display = "Puffberry", Color = Color3.fromRGB(235, 55, 120) },
	Root = { Display = "Carrot Root", Color = Color3.fromRGB(255, 150, 40) },
}

Config.Slime = {
	Radius = 1.4, -- normal slime collider radius
	LargoRadius = 1.95,
	ThinkMin = 1.2,
	ThinkMax = 3.2,
	HopHeight = 2.6,
	AgitatedHopHeight = 6, -- clears Starter Corral walls (4) but not High Walls (9)
	HopSpeed = 9,
	HungerDelay = 25, -- seconds after eating before it looks for food again
	AgitateAfter = 180, -- seconds unfed in a corral before it starts trying to escape
	SeekRadius = 16,
	EatDistance = 2.4,
	PassiveInterval = 75, -- seconds per passive gem in a claimed corral
	MusicBoxMultiplier = 1.25,
}

Config.Wild = {
	MaxSlimes = 30,
	SpawnInterval = 3,
	-- Z bands inside the wilds with spawn weights per slime type
	Bands = {
		{ ZMin = 475, ZMax = 620, Weights = { Bubble = 6, Pebble = 4, Fizz = 1 } },
		{ ZMin = 620, ZMax = 760, Weights = { Pebble = 3, Fizz = 4, Glow = 2 } },
		{ ZMin = 760, ZMax = 895, Weights = { Fizz = 2, Glow = 3, Ember = 3 } },
	},
	ProduceInterval = 8, -- fruit trees / root patches attempt a drop every N seconds
	ProduceChance = 0.45,
	SpawnerItemCap = 3, -- don't drop if this many items already near the spawner
}

----------------------------------------------------------------------
-- Market (fluctuating prices + saturation, refreshed while you play)
----------------------------------------------------------------------
Config.Market = {
	SaturationPerGem = 0.006, -- each gem sold lowers that gem's multiplier by this
	MinMultiplier = 0.35,
	DriftInterval = 10,
	RecoverRate = 0.06, -- fraction of the gap to target closed each drift tick
	TargetRerollInterval = 300,
	TargetRange = { 0.75, 1.35 },
}

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
Config.Data = {
	StoreName = "SlimeRanch_v1",
	StartingCoins = 250,
	AutosaveInterval = 120,
	SessionLockTimeout = 600, -- a lock older than this is treated as stale
	LoadAttempts = 5,
}

----------------------------------------------------------------------
-- Client visuals
----------------------------------------------------------------------
Config.Fence = {
	Color = Color3.fromRGB(110, 205, 255),
	LockColor = Color3.fromRGB(255, 120, 90),
	PanelTransparency = 0.72,
	-- Upload assets/honeycomb.png to Roblox and paste "rbxassetid://<id>" here.
	-- With it set, fences use cheap tiled Textures. Left empty, the client draws
	-- the honeycomb with GUI frames (heavier, so it only does nearby walls).
	HexTexture = "",
	HexSide = 1.6, -- studs
	PixelsPerStud = 12,
	LineThickness = 2,
	PatternDistance = 140, -- honeycomb SurfaceGuis only exist within this range of the camera
}

-- Sound ids. The rbxasset:// ones ship with every Roblox client so they always
-- load, but they're generic. Swap in Creator Store sounds for a better feel.
Config.Sounds = {
	VacLoop = "rbxasset://sounds/swoosh.wav",
	Absorb = "rbxasset://sounds/electronicpingshort.wav",
	Shoot = "rbxasset://sounds/action_jump.mp3",
	Pop = "rbxasset://sounds/action_jump_land.mp3",
	Full = "rbxasset://sounds/clickfast.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Upgrade = "rbxasset://sounds/electronicpingshort.wav",
	Button = "rbxasset://sounds/button.wav",
	Splash = "rbxasset://sounds/impact_water.mp3",
}

return Config
