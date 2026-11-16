--!strict
-- Purely cosmetic: nearby slimes do a quick squish-pop when they land, and
-- make small quiet sounds (soft boing on landing, the odd squeak while idle).
-- Uses Model:ScaleTo locally (server never sees it). Capped per frame, and
-- voices are rate-limited globally and per slime so a full corral never
-- turns into noise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(script.Parent.Sounds)

local VOICE = Config.SlimeVoice
local lastVoice = 0
local lastVoiceBy: { [Model]: number } = {}

-- bigger slimes (largos) sound lower
local function pitchOf(root: BasePart): number
	return math.clamp(2.8 / root.Size.Y, 0.75, 1.25)
end

local function voice(model: Model, root: BasePart, kind: string, cameraPos: Vector3): boolean
	local t = os.clock()
	if t - lastVoice < VOICE.GlobalGap or t - (lastVoiceBy[model] or 0) < VOICE.PerSlimeGap then
		return false
	end
	if (root.Position - cameraPos).Magnitude > VOICE.Range then
		return false
	end
	lastVoice = t
	lastVoiceBy[model] = t
	Sounds.at(kind, root.Position, 1, pitchOf(root), VOICE.Range + 10)
	return true
end

local RANGE = 70
local MAX_PER_FRAME = 4

local SlimeJuice = {}
local lastVy: { [Model]: number } = {}
local busy: { [Model]: boolean } = {}

local function squish(model: Model)
	busy[model] = true
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			conn:Disconnect()
			busy[model] = nil
			return
		end
		local a = (os.clock() - t0) / 0.22
		if a >= 1 then
			pcall(model.ScaleTo, model, 1)
			conn:Disconnect()
			busy[model] = nil
			return
		end
		-- overshoot then settle
		local s = 1 + math.sin(a * math.pi) * 0.14 * (1 - a)
		pcall(model.ScaleTo, model, s)
	end)
end

function SlimeJuice.init()
	local folder = Workspace:WaitForChild("Slimes")

	-- idle chatter: every half second, maybe one nearby slime squeaks
	task.spawn(function()
		while true do
			task.wait(0.5)
			local cam = Workspace.CurrentCamera
			if not cam then
				continue
			end
			local camPos = cam.CFrame.Position
			for _, m in folder:GetChildren() do
				local model = m :: Model
				local root = model.PrimaryPart
				if root and math.random() < VOICE.Chance and voice(model, root, "SlimeSqueak", camPos) then
					break
				end
			end
		end
	end)
	folder.ChildRemoved:Connect(function(m)
		lastVy[m :: Model] = nil
		busy[m :: Model] = nil
		lastVoiceBy[m :: Model] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		local fired = 0
		for _, m in folder:GetChildren() do
			local model = m :: Model
			local root = model.PrimaryPart
			if not root then
				continue
			end
			if (root.Position - camPos).Magnitude > RANGE then
				lastVy[model] = nil
				continue
			end
			local vy = root.AssemblyLinearVelocity.Y
			local prev = lastVy[model]
			lastVy[model] = vy
			if prev and prev < -10 and vy > -2 and not busy[model] and fired < MAX_PER_FRAME then
				fired += 1
				squish(model)
				if math.random() < 0.35 then
					voice(model, root, "SlimeBoing", camPos)
				end
			end
		end
	end)
end

return SlimeJuice
