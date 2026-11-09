--!strict
-- Local-only plot juice:
--   * walls/posts/net rise in a ripple when security is upgraded
--   * lock barrier fades in, gate caps flash
--   * owner-only prompts are hidden for everyone else
--   * alarm flash when someone walks into your ranch

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer
local PlotFx = {}

local lastHeight: { [Model]: number } = {}

local function sparkle(pos: Vector3, color: Color3, count: number)
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	a.WorldPosition = pos
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(4, 9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	task.delay(1.5, function()
		a:Destroy()
	end)
end
PlotFx.sparkle = sparkle

local function rise(model: Model, delta: number)
	task.wait() -- let the new sizes replicate alongside the attribute
	local center = model:GetPivot().Position
	local risers: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Riser") then
			table.insert(risers, d)
		end
	end
	-- ripple: stagger by angle around the corral
	table.sort(risers, function(a, b)
		local pa, pb = a.Position - center, b.Position - center
		return math.atan2(pa.Z, pa.X) < math.atan2(pb.Z, pb.X)
	end)
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i, p in risers do
		local finalCF, finalSize = p.CFrame, p.Size
		if p:GetAttribute("Riser") == "Grow" then
			p.Size = Vector3.new(finalSize.X, math.max(0.05, finalSize.Y - delta), finalSize.Z)
			p.CFrame = finalCF - Vector3.new(0, delta / 2, 0)
		else
			p.CFrame = finalCF - Vector3.new(0, delta, 0)
		end
		task.delay((i / #risers) * 0.6, function()
			TweenService:Create(p, info, { CFrame = finalCF, Size = finalSize }):Play()
			if p.Name == "Cap" then
				task.delay(0.8, sparkle, finalCF.Position, Config.Fence.Color, 6)
			end
		end)
	end
	local dist = (Workspace.CurrentCamera.CFrame.Position - center).Magnitude
	if dist < 120 then
		Sounds.at("Upgrade", center, 0.8, 0.8)
		task.delay(0.4, Sounds.at, "Upgrade", center, 0.6, 1.1)
	end
end

local function refreshPrompts(model: Model)
	local mine = model:GetAttribute("OwnerUserId") == player.UserId
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("OwnerOnly") then
			d.Enabled = mine
		end
	end
end

local function watch(model: Model)
	lastHeight[model] = (model:GetAttribute("WallHeight") or 0) :: number
	model:GetAttributeChangedSignal("WallHeight"):Connect(function()
		local new = (model:GetAttribute("WallHeight") or 0) :: number
		local old = lastHeight[model] or new
		lastHeight[model] = new
		if new > old then
			task.spawn(rise, model, new - old)
		end
	end)
	model:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		refreshPrompts(model)
	end)
	model.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			refreshPrompts(model)
		elseif d.Name == "LockBarrier" and d:IsA("BasePart") then
			local target = d.Transparency
			d.Transparency = 1
			TweenService:Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Transparency = target }):Play()
		elseif d.Name == "AirNet" and d:IsA("BasePart") then
			sparkle(d.Position, Config.Fence.Color, 30)
		end
	end)
	refreshPrompts(model)
end

function PlotFx.plotModel(index: number): Model?
	local root = Workspace:FindFirstChild("RanchPlots")
	return root and root:FindFirstChild(`Plot{index}`) :: Model?
end

function PlotFx.flashCaps(index: number, color: Color3)
	local model = PlotFx.plotModel(index)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Cap" then
			local original = d.Color
			d.Color = color
			TweenService:Create(d, TweenInfo.new(0.8), { Color = original }):Play()
		end
	end
end

function PlotFx.upgradeBurst(index: number)
	local model = PlotFx.plotModel(index)
	if model then
		sparkle(model:GetPivot().Position + Vector3.new(0, 4, 0), Color3.fromRGB(255, 230, 140), 40)
	end
end

function PlotFx.init()
	local root = Workspace:WaitForChild("RanchPlots")
	for _, m in root:GetChildren() do
		if m:IsA("Model") then
			watch(m)
		end
	end
	root.ChildAdded:Connect(function(m)
		if m:IsA("Model") then
			watch(m)
		end
	end)
end

return PlotFx
