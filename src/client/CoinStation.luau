--!strict
-- Physical Slime Coins at the money station next to each corral.
--
--  * Coins stack up on the station as uncollected money grows.
--  * When the owner collects, the whole pile hops up and streams into them
--    with sparkles and a rising coin jingle.
--
-- Hook-up (server side, in whatever script runs the money station):
--   Tag the station's top/pad part "CoinStation".
--   Keep station:SetAttribute("Stored", <uncollected amount>) up to date.
--   On collect:  station:SetAttribute("CollectedBy", player.UserId)
--                station:SetAttribute("CollectCount", (station:GetAttribute("CollectCount") or 0) + 1)
--                station:SetAttribute("Stored", 0)
-- Coin model: put the imported SlimeCoin MeshPart at
--   ReplicatedStorage.Assets.SlimeCoin  (faces +/-Z, like the OBJ in assets/coin).
-- Without it a simple purple disc is used.
--
-- Purely cosmetic and client-side: max 30 coins per station, only stations
-- within 150 studs are drawn.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(script.Parent.Sounds)

local TAG = "CoinStation"
local MAX_COINS = 30
local DRAW_RANGE = 150
local COIN_SIZE = 1.7

type Station = { Part: BasePart, Coins: { BasePart }, Folder: Folder, Count: number }

local CoinStation = {}
local stations: { [BasePart]: Station } = {}
local templateCache: BasePart? = nil

local function template(): (BasePart, CFrame)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local mesh = assets and assets:FindFirstChild("SlimeCoin")
	if mesh and mesh:IsA("BasePart") then
		return mesh, CFrame.Angles(math.pi / 2, 0, 0) -- mesh faces Z: lay it flat
	end
	if not templateCache then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.4, COIN_SIZE, COIN_SIZE)
		p.Color = Color3.fromRGB(165, 70, 235)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.15
		templateCache = p
	end
	return templateCache :: BasePart, CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> vertical
end

local function wanted(stored: number): number
	if stored <= 0 then
		return 0
	end
	return math.clamp(math.floor(math.sqrt(stored) * 0.8), 1, MAX_COINS)
end

-- coins go in 5 little stacks across the pad
local function slotCFrame(st: Station, i: number, flat: CFrame): CFrame
	local stack = (i - 1) % 5
	local level = math.floor((i - 1) / 5)
	local offsets = { Vector3.new(0, 0, 0), Vector3.new(1.9, 0, 0.4), Vector3.new(-1.8, 0, 0.6), Vector3.new(0.5, 0, -1.8), Vector3.new(-0.6, 0, 1.9) }
	local top = st.Part.CFrame * CFrame.new(0, st.Part.Size.Y / 2, 0)
	local jitter = CFrame.Angles(0, (i * 1.7) % (math.pi * 2), 0)
	return top * CFrame.new(offsets[stack + 1] + Vector3.new(0, 0.22 + level * 0.36, 0)) * jitter * flat
end

local function addCoin(st: Station)
	local tpl, flat = template()
	local c = tpl:Clone()
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	local i = #st.Coins + 1
	local target = slotCFrame(st, i, flat)
	local fullSize = c.Size
	c.Size = fullSize * 0.2
	c.CFrame = target + Vector3.new(0, 2.5, 0)
	c.Parent = st.Folder
	table.insert(st.Coins, c)
	TweenService:Create(c, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { CFrame = target, Size = fullSize }):Play()
end

local function sync(st: Station)
	local stored = st.Part:GetAttribute("Stored")
	local n = wanted(if typeof(stored) == "number" then stored else 0)
	local cam = Workspace.CurrentCamera
	if cam and (cam.CFrame.Position - st.Part.Position).Magnitude > DRAW_RANGE then
		n = 0
	end
	while #st.Coins < n do
		addCoin(st)
	end
	while #st.Coins > n do
		local c = table.remove(st.Coins) :: BasePart
		c:Destroy()
	end
end

-- the satisfying bit: every coin hops and streams into the collector
local function collect(st: Station)
	local userId = st.Part:GetAttribute("CollectedBy")
	local who = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local char = who and who.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local coins = st.Coins
	st.Coins = {}
	if not root then
		for _, c in coins do
			c:Destroy()
		end
		return
	end
	local isMe = who == Players.LocalPlayer
	for i, c in coins do
		task.delay((i - 1) * 0.035, function()
			if not c.Parent then
				return
			end
			local from = c.Position
			local startSize = c.Size
			local spinAxis = CFrame.Angles(math.random() * 6, math.random() * 6, 0)
			local t0 = os.clock()
			local dur = 0.45 + math.random() * 0.15
			local conn: RBXScriptConnection
			conn = RunService.RenderStepped:Connect(function()
				local a = math.min(1, (os.clock() - t0) / dur)
				local to = if root.Parent then root.Position else from
				local e = a * a * (3 - 2 * a)
				local arc = Vector3.new(0, math.sin(a * math.pi) * 5, 0)
				c.CFrame = CFrame.new(from:Lerp(to, e) + arc) * spinAxis * CFrame.Angles(0, a * 14, 0)
				c.Size = startSize * (1 - 0.4 * e)
				if a >= 1 then
					conn:Disconnect()
					c:Destroy()
				end
			end)
			-- jingle that climbs in pitch as the pile drains (rate-limited)
			if i % 3 == 1 then
				if isMe then
					Sounds.play("Coin", 0.7, 1 + math.min(i, 30) * 0.02)
				else
					Sounds.at("Coin", from, 0.5, 1 + math.min(i, 30) * 0.02, 60)
				end
			end
		end)
	end
end

local function track(part: Instance)
	if not part:IsA("BasePart") or stations[part] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Coins"
	folder.Parent = Workspace.CurrentCamera or Workspace
	local st: Station = { Part = part, Coins = {}, Folder = folder, Count = 0 }
	st.Count = (part:GetAttribute("CollectCount") or 0) :: number
	stations[part] = st
	part:GetAttributeChangedSignal("Stored"):Connect(function()
		-- a collect sets Stored = 0 too; wait a beat so the fly-to-player
		-- animation grabs the pile before sync would just delete it
		if part:GetAttribute("Stored") == 0 then
			task.delay(0.15, sync, st)
		else
			sync(st)
		end
	end)
	part:GetAttributeChangedSignal("CollectCount"):Connect(function()
		local c = (part:GetAttribute("CollectCount") or 0) :: number
		if c > st.Count then
			st.Count = c
			collect(st)
		end
	end)
	part.Destroying:Connect(function()
		folder:Destroy()
		stations[part] = nil
	end)
	sync(st)
end

function CoinStation.init()
	for _, p in CollectionService:GetTagged(TAG) do
		track(p)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	-- stations coming in/out of draw range
	task.spawn(function()
		while true do
			task.wait(1)
			for _, st in stations do
				sync(st)
			end
		end
	end)
end

return CoinStation
