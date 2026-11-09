--!strict
-- Builds the physical slimes / food / gems. All server-owned (SetNetworkOwner(nil))
-- so an exploiter can't fling or teleport them by claiming physics ownership.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)

local ItemFactory = {}

local slimesFolder = Instance.new("Folder")
slimesFolder.Name = "Slimes"
slimesFolder.Parent = workspace
local itemsFolder = Instance.new("Folder")
itemsFolder.Name = "Items"
itemsFolder.Parent = workspace

ItemFactory.Slimes = slimesFolder
ItemFactory.Items = itemsFolder

local function decor(props: { [string]: any }, root: BasePart): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = root.Parent
	return p
end

local function claimServerOwnership(p: BasePart)
	-- can only be called once it's in workspace and unanchored
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
end

function ItemFactory.slime(a: string, b: string?, cf: CFrame): Model
	local radius = if b then Config.Slime.LargoRadius else Config.Slime.Radius
	local colorA = Config.Slimes[a].Color
	local id = ItemIds.slime(a, b)

	local model = Instance.new("Model")
	model.Name = "Slime"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.one * radius * 2
	root.CFrame = CFrame.new()
	root.Color = colorA
	root.Material = Enum.Material.SmoothPlastic
	root.Reflectance = 0.06
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.9, 0.2, 1, 1)
	root.CollisionGroup = "Slimes"
	root:SetAttribute("Kind", "slime")
	root:SetAttribute("Id", id)
	root:SetAttribute("A", a)
	if b then
		root:SetAttribute("B", b)
	end
	root.Parent = model
	model.PrimaryPart = root

	-- face: two glossy eyes
	for _, side in { -1, 1 } do
		local eyePos = Vector3.new(side * radius * 0.34, radius * 0.2, -radius * 0.82)
		decor({
			Name = "Eye",
			Size = Vector3.one * radius * 0.34,
			CFrame = CFrame.new(eyePos),
			Color = Color3.fromRGB(30, 25, 40),
		}, root)
		decor({
			Name = "Shine",
			Size = Vector3.one * radius * 0.12,
			CFrame = CFrame.new(eyePos + Vector3.new(-radius * 0.05, radius * 0.07, -radius * 0.13)),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
		}, root)
	end
	-- largo: "ears" in the second type's colour
	if b then
		local colorB = Config.Slimes[b].Color
		for _, side in { -1, 1 } do
			decor({
				Name = "Ear",
				Size = Vector3.one * radius * 0.6,
				CFrame = CFrame.new(side * radius * 0.55, radius * 0.72, radius * 0.1),
				Color = colorB,
			}, root)
		end
	end

	-- keep it upright so the face doesn't roll into the dirt
	local att = Instance.new("Attachment")
	att.Name = "Align"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 1e6
	align.Responsiveness = 22
	align.CFrame = CFrame.new()
	align.Parent = root

	model:PivotTo(cf)
	model.Parent = slimesFolder
	claimServerOwnership(root)
	return model
end

local function item(kind: string, id: string, p: Part, pos: Vector3, velocity: Vector3?): Part
	p.Position = pos
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Items"
	p.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.6, 0.35, 1, 1)
	p.CastShadow = false
	p:SetAttribute("Kind", kind)
	p:SetAttribute("Id", id)
	p:SetAttribute("SpawnedAt", os.clock())
	p.Parent = itemsFolder
	if velocity then
		p.AssemblyLinearVelocity = velocity
	end
	claimServerOwnership(p)
	return p
end

function ItemFactory.food(name: string, pos: Vector3, velocity: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Color = Config.Foods[name].Color
	if name == "Berry" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 1.3
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.1
	else
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(1.8, 0.9, 0.9)
	end
	return item("food", ItemIds.food(name), p, pos, velocity)
end

function ItemFactory.gem(t: string, pos: Vector3, velocity: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = "Gem"
	p.Size = Vector3.one * 1.05
	p.Color = Config.Slimes[t].Color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.05
	p.CFrame = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	return item("gem", ItemIds.gem(t), p, pos, velocity)
end

-- Spawn whatever an id describes (used when shooting items out of the vac).
function ItemFactory.fromId(id: string, pos: Vector3, velocity: Vector3): Instance?
	local parsed = ItemIds.parse(id)
	if not parsed then
		return nil
	end
	if parsed.Kind == "slime" then
		local m = ItemFactory.slime(parsed.A, parsed.B, CFrame.new(pos))
		local root = m.PrimaryPart :: BasePart
		root.AssemblyLinearVelocity = velocity
		return m
	elseif parsed.Kind == "food" then
		return ItemFactory.food(parsed.A, pos, velocity)
	else
		return ItemFactory.gem(parsed.A, pos, velocity)
	end
end

function ItemFactory.slimeCount(): number
	return #slimesFolder:GetChildren()
end

function ItemFactory.itemCount(): number
	return #itemsFolder:GetChildren()
end

-- The object the vac/AI deals with: slime root part or the item part itself.
function ItemFactory.objectOf(p: BasePart): Instance
	if p:GetAttribute("Kind") == "slime" then
		return p.Parent :: Instance
	end
	return p
end

return ItemFactory
