--!strict
-- Smooth, connected portal swirl (client-only visual).
--
-- Replaces "lots of square blocks spinning around". Each arm of the spiral is
-- a chain of Beams that share attachments, so it's one continuous ribbon with
-- no gaps; the whole thing rotates as one piece.
--
-- Setup in Studio:
--   1. Delete the old spinning blocks inside the portal.
--   2. Tag the portal's flat surface part "PortalSwirl" (Tag Editor / Properties > Tags).
--      The thinnest axis of that part is treated as the portal's facing.
--   3. Optional attributes on that part:
--        Color1 (Color3)  main swirl colour      default light cyan
--        Color2 (Color3)  deep centre colour     default blue
--        Arms   (number)  spiral arms            default 3
--        Speed  (number)  radians/sec            default 1.6
--
-- Only portals near the camera animate (mobile friendly).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TAG = "PortalSwirl"
local ANIMATE_RANGE = 220
local POINTS = 16 -- attachments per arm

type Swirl = { Source: BasePart, Front: BasePart, Back: BasePart, Base: CFrame, Angle: number, Speed: number, Folder: Folder }

local PortalSwirl = {}
local swirls: { [BasePart]: Swirl } = {}

-- portal centre frame with local Z = the portal's normal
local function frameOf(part: BasePart): (CFrame, number)
	local s = part.Size
	local cf = part.CFrame
	if s.X <= s.Y and s.X <= s.Z then
		return cf * CFrame.Angles(0, math.pi / 2, 0), math.min(s.Y, s.Z) / 2
	elseif s.Y <= s.X and s.Y <= s.Z then
		return cf * CFrame.Angles(math.pi / 2, 0, 0), math.min(s.X, s.Z) / 2
	end
	return cf, math.min(s.X, s.Y) / 2
end

local function holder(name: string, cf: CFrame, folder: Folder): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = cf
	p.Parent = folder
	return p
end

local function disc(name: string, cf: CFrame, radius: number, thickness: number, color: Color3, transparency: number, folder: Folder)
	local d = Instance.new("Part")
	d.Name = name
	d.Shape = Enum.PartType.Cylinder
	d.Size = Vector3.new(thickness, radius * 2, radius * 2)
	d.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) onto the normal
	d.Material = Enum.Material.Neon
	d.Color = color
	d.Transparency = transparency
	d.Anchored = true
	d.CanCollide = false
	d.CanQuery = false
	d.CanTouch = false
	d.CastShadow = false
	d.Parent = folder
end

-- one spiral arm = attachments along a curve + beams between neighbours
local function arm(onto: BasePart, radius: number, startAngle: number, turns: number, width: number, c1: Color3, c2: Color3, alpha: number, z: number)
	local atts: { Attachment } = {}
	for i = 0, POINTS do
		local t = i / POINTS
		local r = radius * (1 - t) ^ 0.85 + radius * 0.04
		local a = startAngle + t * turns * math.pi * 2
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(math.cos(a) * r, math.sin(a) * r, z)
		att.Parent = onto
		atts[i] = att
	end
	for i = 0, POINTS - 1 do
		local t0, t1 = i / POINTS, (i + 1) / POINTS
		local b = Instance.new("Beam")
		b.Attachment0 = atts[i]
		b.Attachment1 = atts[i + 1]
		b.FaceCamera = true
		b.Segments = 3
		-- thick at the rim, thin at the centre; overlap a touch so joints never gap
		b.Width0 = width * (1 - t0 * 0.8) * 1.04
		b.Width1 = width * (1 - t1 * 0.8) * 1.04
		b.Color = ColorSequence.new(c1:Lerp(c2, t0), c1:Lerp(c2, t1))
		b.Transparency = NumberSequence.new(alpha + (1 - alpha) * t0 * 0.5, alpha + (1 - alpha) * t1 * 0.5)
		b.LightEmission = 0.9
		b.LightInfluence = 0
		b.Parent = onto
	end
end

local function rimParticles(onto: BasePart, radius: number, color: Color3)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local src = Vector3.new(math.cos(a) * radius, math.sin(a) * radius, -0.1)
		local att = Instance.new("Attachment")
		att.CFrame = CFrame.lookAt(src, Vector3.new(0, 0, -0.1))
		att.Parent = onto
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.EmissionDirection = Enum.NormalId.Front
		e.LockedToPart = true
		e.Lifetime = NumberRange.new(0.9)
		e.Speed = NumberRange.new(radius / 0.9)
		e.SpreadAngle = Vector2.new(8, 8)
		e.Rate = 3
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.08), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.2, 1)
		e.Color = ColorSequence.new(color)
		e.LightEmission = 1
		e.Parent = att
	end
end

local function build(part: BasePart)
	if swirls[part] or not part:IsDescendantOf(Workspace) then
		return
	end
	local c1 = part:GetAttribute("Color1")
	local c2 = part:GetAttribute("Color2")
	local col1 = if typeof(c1) == "Color3" then c1 else Color3.fromRGB(190, 245, 255)
	local col2 = if typeof(c2) == "Color3" then c2 else Color3.fromRGB(40, 130, 255)
	local arms = math.clamp(tonumber(part:GetAttribute("Arms")) or 3, 1, 6)
	local speed = tonumber(part:GetAttribute("Speed")) or 1.6

	local base, radius = frameOf(part)
	radius *= 0.94
	local folder = Instance.new("Folder")
	folder.Name = "Swirl"
	-- keep it out of the server's hierarchy so nothing replicates or collides
	folder.Parent = Workspace.CurrentCamera or Workspace

	-- depth: dark centre, glowing ring of colour around it
	-- discs sit in the middle; arms go on both faces so it reads from either side
	-- stepped thickness so no two faces are coplanar (no z-fighting from any side)
	disc("Back", base, radius, 0.04, col2:Lerp(Color3.new(0, 0, 0), 0.35), 0.05, folder)
	disc("Glow", base, radius * 0.62, 0.07, col1:Lerp(col2, 0.4), 0.35, folder)
	disc("Core", base, radius * 0.2, 0.1, Color3.new(1, 1, 1), 0.2, folder)

	local front = holder("Front", base, folder)
	for i = 0, arms - 1 do
		for _, z in { -0.08, 0.08 } do
			arm(front, radius, i / arms * math.pi * 2, 1.15, radius * 0.34, col1, Color3.new(1, 1, 1), 0.15, z)
		end
	end
	rimParticles(front, radius, col1)
	-- fainter, wider layer turning the other way for depth
	local back = holder("BackLayer", base, folder)
	for i = 0, arms - 1 do
		arm(back, radius * 0.95, (i + 0.5) / arms * math.pi * 2, -0.8, radius * 0.5, col2:Lerp(col1, 0.5), col1, 0.55, -0.04)
	end

	swirls[part] = { Source = part, Front = front, Back = back, Base = base, Angle = 0, Speed = speed, Folder = folder }
	part.Destroying:Connect(function()
		local s = swirls[part]
		if s then
			s.Folder:Destroy()
			swirls[part] = nil
		end
	end)
end

function PortalSwirl.init()
	for _, p in CollectionService:GetTagged(TAG) do
		if p:IsA("BasePart") then
			task.spawn(build, p)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(p)
		if p:IsA("BasePart") then
			build(p)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(p)
		local s = swirls[p :: BasePart]
		if s then
			s.Folder:Destroy()
			swirls[p :: BasePart] = nil
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		for _, s in swirls do
			if (s.Base.Position - camPos).Magnitude > ANIMATE_RANGE then
				continue
			end
			s.Angle = (s.Angle + s.Speed * dt) % (math.pi * 2)
			s.Front.CFrame = s.Base * CFrame.Angles(0, 0, -s.Angle)
			s.Back.CFrame = s.Base * CFrame.Angles(0, 0, s.Angle * 0.55)
		end
	end)
end

return PortalSwirl
