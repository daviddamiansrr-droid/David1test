--!strict
-- Client-only honeycomb look for corral walls, Air Nets and lock barriers.
-- The server just makes translucent panels tagged with a "Honeycomb" attribute;
-- all the pattern work happens here so nothing extra replicates.
--
-- Two modes:
--   Config.Fence.HexTexture set -> tiled Texture on both faces (cheap, recommended)
--   empty                       -> honeycomb drawn with GUI frames, only for
--                                  walls near the camera (LOD), rebuilt per height

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local F = Config.Fence
local SQRT3 = math.sqrt(3)
local useTexture = F.HexTexture ~= ""

type Entry = { Kind: string, Guis: { SurfaceGui }, Key: string? }

local Honeycomb = {}
local entries: { [BasePart]: Entry } = {}
local templates: { [string]: Frame } = {}

local function facesFor(kind: string): { Enum.NormalId }
	if kind == "Net" then
		return { Enum.NormalId.Top, Enum.NormalId.Bottom }
	end
	return { Enum.NormalId.Front, Enum.NormalId.Back }
end

local function colorFor(kind: string): Color3
	return if kind == "Barrier" then F.LockColor else F.Color
end

local function faceSize(p: BasePart, face: Enum.NormalId): Vector2
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return Vector2.new(p.Size.X, p.Size.Z)
	end
	return Vector2.new(p.Size.X, p.Size.Y)
end

-- soft glow that's brightest along the top edge of each wall
local function glowGui(p: BasePart, kind: string, face: Enum.NormalId): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "HexGlow"
	g.Face = face
	g.LightInfluence = 0
	g.Brightness = 1.5
	g.MaxDistance = 220
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 4
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colorFor(kind)
	fill.BorderSizePixel = 0
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = if kind == "Net"
		then NumberSequence.new(0.8)
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.25, 0.75),
			NumberSequenceKeypoint.new(1, 0.92),
		})
	grad.Parent = fill
	fill.Parent = g
	g.Parent = p
	return g
end

local function buildFrames(w: number, h: number, side: number, color: Color3): Frame
	local pps = F.PixelsPerStud
	local container = Instance.new("Frame")
	container.Name = "Hex"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromOffset(w * pps, h * pps)
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.fromScale(0, 1) -- bottom-anchored: walls grow upward
	local s = side * pps
	local dx, dy = 1.5 * s, SQRT3 * s
	local cols = math.ceil(w * pps / dx) + 1
	local rows = math.ceil(h * pps / dy) + 1
	for c = 0, cols do
		for r = 0, rows do
			local cx = c * dx
			local cy = h * pps - (r * dy + (if c % 2 == 1 then dy / 2 else 0))
			-- edges k=0,1,2 of every hex cover each shared edge exactly once
			for k = 0, 2 do
				local a1, a2 = math.rad(60 * k), math.rad(60 * (k + 1))
				local x1, y1 = cx + s * math.cos(a1), cy - s * math.sin(a1)
				local x2, y2 = cx + s * math.cos(a2), cy - s * math.sin(a2)
				local e = Instance.new("Frame")
				e.BorderSizePixel = 0
				e.BackgroundColor3 = color
				e.BackgroundTransparency = 0.12
				e.AnchorPoint = Vector2.new(0.5, 0.5)
				e.Size = UDim2.fromOffset(s + F.LineThickness, F.LineThickness)
				e.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
				e.Rotation = math.deg(math.atan2(y2 - y1, x2 - x1))
				e.Parent = container
			end
		end
	end
	return container
end

local function template(w: number, h: number, kind: string): Frame
	local side = F.HexSide * (if kind == "Net" then 2.2 else 1.3)
	local key = `{kind}:{math.round(w)}x{math.round(h)}`
	local t = templates[key]
	if not t then
		t = buildFrames(w, h, side, Color3.new(1, 1, 1):Lerp(colorFor(kind), 0.55))
		templates[key] = t
	end
	return t
end

local function clearGuis(e: Entry)
	for _, g in e.Guis do
		g:Destroy()
	end
	e.Guis = {}
	e.Key = nil
end

local function wallHeightOf(p: BasePart): number
	local model = p.Parent
	local h = model and model:GetAttribute("WallHeight")
	return if typeof(h) == "number" then h else p.Size.Y
end

local function ensureFrames(p: BasePart, e: Entry)
	local faces = facesFor(e.Kind)
	local size = faceSize(p, faces[1])
	local h = if e.Kind == "Net" then size.Y else wallHeightOf(p)
	local key = `{math.round(size.X)}x{math.round(h)}`
	if e.Key == key then
		return
	end
	clearGuis(e)
	e.Key = key
	local t = template(size.X, h, e.Kind)
	for _, face in faces do
		local g = Instance.new("SurfaceGui")
		g.Name = "HexPattern"
		g.Face = face
		g.LightInfluence = 0
		g.Brightness = 1.8
		g.MaxDistance = F.PatternDistance
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = F.PixelsPerStud
		g.ClipsDescendants = true
		t:Clone().Parent = g
		g.Parent = p
		table.insert(e.Guis, g)
	end
end

local function track(p: BasePart)
	local kind = p:GetAttribute("Honeycomb")
	if typeof(kind) ~= "string" or entries[p] then
		return
	end
	local e: Entry = { Kind = kind, Guis = {}, Key = nil }
	entries[p] = e
	if p:FindFirstChild("HexGlow") then
		return -- re-parented net/barrier: decorations are still on it
	end
	for _, face in facesFor(kind) do
		glowGui(p, kind, face)
		if useTexture then
			local tex = Instance.new("Texture")
			tex.Face = face
			tex.Texture = F.HexTexture
			local side = F.HexSide * (if kind == "Net" then 1.6 else 1)
			tex.StudsPerTileU = 3 * side
			tex.StudsPerTileV = SQRT3 * side
			tex.Color3 = Color3.new(1, 1, 1):Lerp(colorFor(kind), 0.45)
			tex.Transparency = 0.05
			tex.Parent = p
		end
	end
	p.Destroying:Connect(function()
		entries[p] = nil
	end)
end

function Honeycomb.init()
	local root = Workspace:WaitForChild("RanchPlots")
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			track(d)
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			track(d)
		end
	end)
	root.DescendantRemoving:Connect(function(d)
		local e = entries[d :: BasePart]
		if e and not useTexture then
			-- barrier/net get unparented and re-parented; rebuild on return
			clearGuis(e)
			entries[d :: BasePart] = nil
		end
	end)

	if useTexture then
		return
	end
	-- frame mode: LOD loop
	task.spawn(function()
		while true do
			task.wait(0.5)
			local cam = Workspace.CurrentCamera
			if not cam then
				continue
			end
			local camPos = cam.CFrame.Position
			for p, e in entries do
				if not p.Parent then
					continue
				end
				local reach = F.PatternDistance + math.max(p.Size.X, p.Size.Z) / 2
				if (p.Position - camPos).Magnitude <= reach then
					ensureFrames(p, e)
				elseif #e.Guis > 0 then
					clearGuis(e)
				end
			end
		end
	end)
end

return Honeycomb
