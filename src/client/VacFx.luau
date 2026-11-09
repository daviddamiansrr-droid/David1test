--!strict
-- Visual + audio feedback for every vac in the server (yours and other players'),
-- plus the world Fx events the server fires (gem pops, largos, sells, etc).
-- Nothing here affects gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(script.Parent.Sounds)
local Hud = require(script.Parent.Hud)
local PlotFx = require(script.Parent.PlotFx)

local player = Players.LocalPlayer
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type ToolFx = {
	Tool: Tool,
	Nozzle: BasePart,
	Rotor: Weld?,
	RotorBase: CFrame,
	Angle: number,
	Spin: number,
	Suction: { ParticleEmitter },
	Burst: ParticleEmitter,
	Loop: Sound?,
	On: boolean,
}

local VacFx = {}
local tools: { [Tool]: ToolFx } = {}

-- hooks the controller sets for local-only juice
VacFx.onLocalAbsorb = nil :: ((id: string) -> ())?

local function camDistance(pos: Vector3): number
	local cam = Workspace.CurrentCamera
	return if cam then (cam.CFrame.Position - pos).Magnitude else 0
end

local function burstAt(pos: Vector3, color: Color3, count: number, speed: number?, texture: string?, size: number?)
	if camDistance(pos) > 160 then
		return
	end
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	a.WorldPosition = pos
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture or SPARKLE
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = 0.8
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.7), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.35, 0.7)
	e.Speed = NumberRange.new((speed or 10) * 0.5, speed or 10)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 4
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	task.delay(1.2, function()
		a:Destroy()
	end)
end
VacFx.burstAt = burstAt

-- a little ball that zips from A to B and shrinks: the "slurp"
local function ghost(from: Vector3, toPart: BasePart?, toPos: Vector3?, color: Color3, size: number, duration: number)
	if camDistance(from) > 140 then
		return
	end
	local g = Instance.new("Part")
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.one * size
	g.Color = color
	g.Material = Enum.Material.Neon
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.CanTouch = false
	g.CastShadow = false
	g.Position = from
	g.Parent = Workspace.Terrain
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.min(1, (os.clock() - t0) / duration)
		local target = if toPart and toPart.Parent then toPart.Position else toPos or from
		local e = a * a -- accelerate into the nozzle
		local arc = Vector3.new(0, math.sin(a * math.pi) * size * 0.8, 0)
		g.Position = from:Lerp(target, e) + arc
		g.Size = Vector3.one * math.max(0.05, size * (1 - e * 0.85))
		if a >= 1 then
			conn:Disconnect()
			g:Destroy()
		end
	end)
end
VacFx.ghost = ghost

local function floatText(pos: Vector3, text: string, color: Color3)
	if camDistance(pos) > 120 then
		return
	end
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	a.WorldPosition = pos
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 44)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = a
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.3
	l.Text = text
	l.Parent = bb
	bb.Parent = a
	TweenService:Create(a, TweenInfo.new(1, Enum.EasingStyle.Quad), { WorldPosition = pos + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.05, function()
		a:Destroy()
	end)
end

----------------------------------------------------------------------
-- per-tool effects
----------------------------------------------------------------------
local function setupTool(tool: Tool)
	if tools[tool] then
		return
	end
	local nozzle = tool:WaitForChild("Nozzle", 5) :: BasePart?
	if not nozzle then
		return
	end
	local rotorPart = tool:FindFirstChild("Rotor")
	local rotorWeld = rotorPart and rotorPart:FindFirstChild("RotorWeld") :: Weld?

	-- converging streams: 6 sources in a ring ahead of the nozzle, each aimed
	-- at the mouth, locked to the part so they follow your aim
	local suction: { ParticleEmitter } = {}
	local ahead, ring, life = 7, 2.4, 0.32
	for k = 0, 5 do
		local ang = k * math.pi / 3
		local src = Vector3.new(math.cos(ang) * ring, math.sin(ang) * ring, -ahead)
		local att = Instance.new("Attachment")
		att.Name = "SuctionSrc"
		att.CFrame = CFrame.lookAt(src, Vector3.zero)
		att.Parent = nozzle
		local e = Instance.new("ParticleEmitter")
		e.Texture = SPARKLE
		e.EmissionDirection = Enum.NormalId.Front
		e.LockedToPart = true
		e.Speed = NumberRange.new(src.Magnitude / life)
		e.Lifetime = NumberRange.new(life)
		e.SpreadAngle = Vector2.new(6, 6)
		e.Rate = 16
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 0.05) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 0.5) })
		e.Color = ColorSequence.new(Color3.fromRGB(200, 245, 255), Config.Fence.Color)
		e.LightEmission = 0.9
		e.Enabled = false
		e.Parent = att
		table.insert(suction, e)
	end
	-- soft swirl of air in the middle of the cone
	local mid = Instance.new("Attachment")
	mid.CFrame = CFrame.lookAt(Vector3.new(0, 0, -5.5), Vector3.zero)
	mid.Parent = nozzle
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = SMOKE
	swirl.EmissionDirection = Enum.NormalId.Front
	swirl.LockedToPart = true
	swirl.Speed = NumberRange.new(16)
	swirl.Lifetime = NumberRange.new(0.33)
	swirl.SpreadAngle = Vector2.new(25, 25)
	swirl.Rotation = NumberRange.new(0, 360)
	swirl.RotSpeed = NumberRange.new(-400, 400)
	swirl.Rate = 18
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.3) })
	swirl.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) })
	swirl.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	swirl.Enabled = false
	swirl.Parent = mid
	table.insert(suction, swirl)

	-- muzzle burst for shooting
	local mouth = nozzle:FindFirstChild("Mouth") :: Attachment?
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = SPARKLE
	burst.EmissionDirection = Enum.NormalId.Front
	burst.Speed = NumberRange.new(10, 22)
	burst.Lifetime = NumberRange.new(0.15, 0.3)
	burst.SpreadAngle = Vector2.new(28, 28)
	burst.Drag = 6
	burst.Rate = 0
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	burst.LightEmission = 1
	burst.Parent = mouth or nozzle

	local loop = Sounds.loop("VacLoop", nozzle, 0)
	local fx: ToolFx = {
		Tool = tool,
		Nozzle = nozzle,
		Rotor = rotorWeld,
		RotorBase = if rotorWeld then rotorWeld.C0 else CFrame.new(),
		Angle = 0,
		Spin = 1.5,
		Suction = suction,
		Burst = burst,
		Loop = loop,
		On = false,
	}
	tools[tool] = fx

	local function apply()
		local on = tool:GetAttribute("VacOn") == true
		fx.On = on
		for _, e in fx.Suction do
			e.Enabled = on
		end
		if loop then
			if on then
				loop.PlaybackSpeed = 0.55
				loop.Volume = 0.45
				if not loop.IsPlaying then
					loop:Play()
				end
				TweenService:Create(loop, TweenInfo.new(0.35), { PlaybackSpeed = 0.85 }):Play()
			else
				local tw = TweenService:Create(loop, TweenInfo.new(0.2), { PlaybackSpeed = 0.4, Volume = 0 })
				tw:Play()
				tw.Completed:Connect(function()
					if not fx.On then
						loop:Stop()
					end
				end)
			end
		end
	end
	tool:GetAttributeChangedSignal("VacOn"):Connect(apply)
	apply()
	tool.Destroying:Connect(function()
		tools[tool] = nil
	end)
end

function VacFx.toolOf(p: Player): ToolFx?
	local char = p.Character
	local tool = char and char:FindFirstChild(Config.Vac.ToolName)
	return if tool and tool:IsA("Tool") then tools[tool] else nil
end

function VacFx.muzzle(fx: ToolFx, color: Color3)
	fx.Burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	fx.Burst:Emit(16)
	-- rotor flash
	local rotor = fx.Tool:FindFirstChild("Rotor") :: BasePart?
	if rotor then
		rotor.Color = Color3.new(1, 1, 1)
		TweenService:Create(rotor, TweenInfo.new(0.25), { Color = Config.Fence.Color }):Play()
	end
	fx.Spin = 30
end

----------------------------------------------------------------------
-- server events
----------------------------------------------------------------------
local function onFx(kind: string, ...: any)
	local args = { ... }
	if kind == "absorb" then
		local who: Player, id: string, pos: Vector3 = args[1], args[2], args[3]
		local fx = VacFx.toolOf(who)
		local color = (ItemIds.colors(id))
		local parsed = ItemIds.parse(id)
		local size = if parsed and parsed.Kind == "slime" then 2.4 else 1.1
		ghost(pos, fx and fx.Nozzle, pos, color, size, 0.13)
		if fx then
			task.delay(0.12, function()
				burstAt(fx.Nozzle.Position, color, 8, 6, nil, 0.45)
			end)
		end
		if who == player then
			if VacFx.onLocalAbsorb then
				VacFx.onLocalAbsorb(id)
			end
		else
			Sounds.at("Absorb", pos, 0.35, 1.2 + math.random() * 0.3)
		end
	elseif kind == "shoot" then
		local who: Player, id: string = args[1], args[2]
		if who ~= player then
			local fx = VacFx.toolOf(who)
			if fx then
				VacFx.muzzle(fx, (ItemIds.colors(id)))
				Sounds.at("Shoot", fx.Nozzle.Position, 0.4, 1.4)
			end
		end
	elseif kind == "gem" then
		local pos: Vector3, color: Color3 = args[1], args[2]
		burstAt(pos, color, 10, 8)
		if camDistance(pos) < 70 then
			Sounds.at("Pop", pos, 0.5, 1.7 + math.random() * 0.3)
		end
	elseif kind == "eat" then
		local pos: Vector3, color: Color3 = args[1], args[2]
		burstAt(pos, color, 8, 5)
		if camDistance(pos) < 60 then
			Sounds.at("Pop", pos, 0.45, 0.9)
		end
	elseif kind == "largo" then
		local pos: Vector3, color: Color3 = args[1], args[2]
		burstAt(pos, color, 40, 16, nil, 1.1)
		burstAt(pos, Color3.new(1, 1, 1), 20, 10, SMOKE, 2)
		Sounds.at("Upgrade", pos, 0.6, 0.7)
		floatText(pos + Vector3.new(0, 3, 0), "LARGO!", color)
	elseif kind == "collect" then
		local from: Vector3, to: Vector3, color: Color3 = args[1], args[2], args[3]
		ghost(from, nil, to, color, 1, 0.45)
		task.delay(0.45, burstAt, to, color, 6, 4, nil, 0.4)
	elseif kind == "poof" then
		local pos: Vector3, color: Color3 = args[1], args[2]
		burstAt(pos, color, 16, 6, SMOKE, 2)
	elseif kind == "feed" then
		burstAt(args[1], Color3.fromRGB(255, 220, 140), 10, 6)
	elseif kind == "sell" then
		local pos: Vector3, amount: number, userId: number = args[1], args[2], args[3]
		burstAt(pos, Color3.fromRGB(255, 215, 90), 14, 10)
		floatText(pos + Vector3.new(0, 2, 0), `+{amount}`, Color3.fromRGB(255, 220, 110))
		if userId == player.UserId then
			Hud.coinPop(amount)
		end
	elseif kind == "coins" then
		Hud.coinPop(args[1])
	elseif kind == "lock" then
		local index: number, locked: boolean = args[1], args[2]
		PlotFx.flashCaps(index, if locked then Config.Fence.LockColor else Color3.fromRGB(120, 255, 170))
		local model = PlotFx.plotModel(index)
		if model then
			Sounds.at("Upgrade", model:GetPivot().Position, 0.5, if locked then 0.6 else 1.2)
		end
	elseif kind == "upgrade" then
		PlotFx.upgradeBurst(args[1])
	elseif kind == "alarm" then
		PlotFx.flashCaps(args[1], Color3.fromRGB(255, 60, 60))
		for k = 0, 2 do
			task.delay(k * 0.18, Sounds.play, "Full", 0.6, 1.6)
		end
	elseif kind == "full" then
		Sounds.play("Full", 0.4, 0.8)
		Hud.toast("Tank full for that item", "warn")
	end
end

function VacFx.init()
	Remotes.event("Fx").OnClientEvent:Connect(onFx)
	Remotes.event("Notify").OnClientEvent:Connect(function(text, kind)
		Hud.toast(text, kind)
	end)

	-- find vac tools as characters equip them
	local function scanCharacter(char: Model)
		for _, c in char:GetChildren() do
			if c:IsA("Tool") and c.Name == Config.Vac.ToolName then
				task.spawn(setupTool, c)
			end
		end
		char.ChildAdded:Connect(function(c)
			if c:IsA("Tool") and c.Name == Config.Vac.ToolName then
				task.spawn(setupTool, c)
			end
		end)
	end
	local function hookPlayer(p: Player)
		if p.Character then
			scanCharacter(p.Character)
		end
		p.CharacterAdded:Connect(scanCharacter)
	end
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	-- rotor spin (local only)
	RunService.RenderStepped:Connect(function(dt)
		for tool, fx in tools do
			if not fx.Rotor or not tool.Parent then
				continue
			end
			local target = if fx.On then 28 else 1.5
			fx.Spin += (target - fx.Spin) * math.min(1, dt * 6)
			fx.Angle = (fx.Angle + fx.Spin * dt) % (math.pi * 2)
			fx.Rotor.C0 = fx.RotorBase * CFrame.Angles(fx.Angle, 0, 0)
		end
	end)
end

return VacFx
