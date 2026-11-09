--!strict
-- Hold jump while airborne to thrust. Fuel is per level (Config.Jetpack) and
-- only drains while actually pushing you up, so max climb matches the
-- server's Reach numbers. Flames are shown for everyone via a server attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local J = Config.Jetpack
local player = Players.LocalPlayer
local JetRemote = Remotes.event("Jet")

local Jetpack = {}

local fuel = 0
local airTime = 0
local thrusting = false
local sentOn = false

local function level(): number
	local snap = ClientState.Data
	return if snap then snap.Jetpack or 0 else 0
end

local function setFlames(model: Instance)
	local on = model:GetAttribute("JetOn") == true
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = on
		end
	end
end

local function decorate(model: Instance)
	for _, att in model:GetDescendants() do
		if att:IsA("Attachment") and att.Name == "Flame" and not att:FindFirstChildOfClass("ParticleEmitter") then
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/fire_main.dds"
			e.EmissionDirection = Enum.NormalId.Left -- thruster's local -X is down
			e.Speed = NumberRange.new(10, 14)
			e.Lifetime = NumberRange.new(0.12, 0.22)
			e.SpreadAngle = Vector2.new(8, 8)
			e.Rate = 60
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) })
			e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 120, 60))
			e.LightEmission = 1
			e.Enabled = false
			e.Parent = att
		end
	end
	model:GetAttributeChangedSignal("JetOn"):Connect(function()
		setFlames(model)
	end)
	setFlames(model)
end

local function watchCharacter(char: Model)
	local jp = char:FindFirstChild("Jetpack")
	if jp then
		decorate(jp)
	end
	char.ChildAdded:Connect(function(c)
		if c.Name == "Jetpack" then
			task.wait() -- let the thruster parts replicate in
			decorate(c)
		end
	end)
end

local function setThrust(on: boolean)
	if on == thrusting then
		return
	end
	thrusting = on
	if on ~= sentOn then
		sentOn = on
		JetRemote:FireServer(on)
	end
end

function Jetpack.init()
	local function hookPlayer(p: Player)
		if p.Character then
			watchCharacter(p.Character)
		end
		p.CharacterAdded:Connect(watchCharacter)
	end
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	-- runs right after the ControlModule writes Humanoid.Jump for this frame,
	-- which works the same for keyboard, gamepad and the mobile jump button
	RunService:BindToRenderStep("Jetpack", Enum.RenderPriority.Input.Value + 1, function(dt)
		local lv = level()
		local maxFuel = J.Fuel[lv] or 0
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if lv <= 0 or not hum or not root or hum.Health <= 0 then
			setThrust(false)
			Hud.setFuel(0, false)
			return
		end

		local airborne = hum.FloorMaterial == Enum.Material.Air
		if airborne then
			airTime += dt
		else
			airTime = 0
			fuel = math.min(maxFuel, fuel + J.RechargeRate * dt)
		end

		local v = root.AssemblyLinearVelocity
		local wants = airborne and airTime > 0.12 and hum.Jump and fuel > 0
		if wants and v.Y < J.Thrust then
			-- ease into full thrust instead of snapping (feels like engines spooling)
			local newY = v.Y + (J.Thrust - v.Y) * math.min(1, dt * 12)
			root.AssemblyLinearVelocity = Vector3.new(v.X, newY, v.Z)
			fuel = math.max(0, fuel - dt)
			setThrust(true)
		elseif not wants then
			setThrust(false)
		end
		Hud.setFuel(if maxFuel > 0 then fuel / maxFuel else 0, true)
	end)
end

return Jetpack
